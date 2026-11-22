{ Pastel - WebSockets: a connection that stays open, messages both ways (chat,
  live updates, notifications from the server).

  On a server (Pastel.Web):
    Chat := TWebSockets.Create;
    Chat.OnMessage := @ChatMessage;
    Web.WebSocket('/chat', Chat);           // behind RequireJwt, RateLimit... like routes

    procedure TApi.ChatMessage(Socket: TWebSocket; const Text: string);
    begin
      Chat.Broadcast(Socket.Claim('name') + ': ' + Text);
    end;

  In an app, or a program talking to a server:
    Client := TWebSocketClient.Create;
    Client.OnMessage := @Received;          // on the app's thread, like a button's click
    Client.BearerToken := Token;
    Client.Connect('wss://api.example.com/chat');
    Client.Send('hello');

  Text messages are UTF-8 strings; binary ones TBytes (OnBinary). Pings keep
  the connection alive through proxies and find dead ones. A server's
  handlers run on the connection's own thread (one per client), like routes:
  what they share must be protected.
  Part of the Pastel project, MIT License. }
unit Pastel.WebSocket;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, Pastel.Http;

type
  EWebSocketError = class(Exception);

  TWebSocket = class;
  TWebSocketEvent = procedure(Socket: TWebSocket) of object;
  TWebSocketMessageEvent = procedure(Socket: TWebSocket; const Text: string) of object;
  TWebSocketBinaryEvent = procedure(Socket: TWebSocket; const Data: TBytes) of object;

  { one connection: a client of a server's TWebSockets, or TWebSocketClient }
  TWebSocket = class
  private
    FConn: TNetConnection;
    FWriteLock: TCriticalSection;
    FIsClient: Boolean;
    FCloseSent, FStopping, FPingSent: Boolean;
    FLastHeard: QWord;
    FId: Int64;
    FPath: string;
    FParams, FQuery, FValues: TStringList;
    FClaims: TJSONObject;
    FCloseCode: Integer;
    FCloseReason: string;
    function Fill(var Buf: RawByteString; N: Integer; AtStart: Boolean): Boolean;
    procedure SendFrame(Opcode: Byte; const Data: RawByteString);
  protected
    MaxMessageSize: Int64;
    PingInterval: Integer;
    { the next message; False when the connection is closed }
    function ReadMessage(out Data: RawByteString; out Binary: Boolean): Boolean;
    procedure Attach(AConn: TNetConnection);
  public
    constructor Create(AConn: TNetConnection; AIsClient: Boolean);
    destructor Destroy; override;
    { a text message; EWebSocketError when the connection is gone }
    procedure Send(const Text: string);
    procedure SendBinary(const Data: TBytes);
    { sends Data as JSON text and frees it }
    procedure SendJson(Data: TJSONData);
    { ends the connection (1000: normal; 1008: not allowed; 1011: an error) }
    procedure Close(Code: Integer = 1000; const Reason: string = '');
    function Open: Boolean;
    { a number for this connection, given by the server }
    property Id: Int64 read FId;
    { the address it connected to: /chat/42 }
    property Path: string read FPath;
    { the route's parameters (/rooms/:room -> Params.Values['room']) and ?query }
    property Params: TStringList read FParams;
    property Query: TStringList read FQuery;
    { what the program keeps about it ('user', 'room'): also what filters set in Req.Values }
    property Values: TStringList read FValues;
    { the JWT's claims (RequireJwt); nil without one }
    property Claims: TJSONObject read FClaims;
    function Claim(const Name: string): string;
    { why it closed: 1000 normal, 1001 going away, 1006 the connection broke }
    property CloseCode: Integer read FCloseCode;
    property CloseReason: string read FCloseReason;
    { internal: what the server knows of the request that opened it }
    procedure Prepare(const APath: string; AParams, AQuery, AValues: TStrings; AClaims: TJSONObject);
  end;

  { the clients connected to one address of a server (TWebServer.WebSocket) }
  TWebSockets = class
  private
    FList: TList;
    FLock: TCriticalSection;
    FNextId: Int64;
  public
    OnOpen: TWebSocketEvent;
    OnClose: TWebSocketEvent;
    OnMessage: TWebSocketMessageEvent;
    OnBinary: TWebSocketBinaryEvent;
    { a longer message closes the connection (1009); default 1 MB }
    MaxMessageSize: Int64;
    { seconds without a word before a ping; twice as long: the client is gone. Default 30 }
    PingInterval: Integer;
    constructor Create;
    destructor Destroy; override;
    { to every client (but Except_) }
    procedure Broadcast(const Text: string; Except_: TWebSocket = nil);
    { to the clients whose Values[Key] is Value (a user's devices, a room); how many got it }
    function SendTo(const Key, Value, Text: string): Integer;
    { to the client with this Id; False when it is not connected }
    function SendToId(AId: Int64; const Text: string): Boolean;
    function Count: Integer;
    { ends every connection (the server stops) }
    procedure CloseAll(Code: Integer = 1001; const Reason: string = 'the server stops');
    { internal: TWebServer's connection thread runs the connection here until it closes }
    procedure Serve(Socket: TWebSocket);
  end;

  TWebSocketClientEvent = procedure(Sender: TObject; const Text: string) of object;
  TWebSocketClientBinaryEvent = procedure(Sender: TObject; const Data: TBytes) of object;

  TWebSocketReader = class;

  { a connection to a WebSocket server: ws:// or wss:// }
  TWebSocketClient = class(TWebSocket)
  private
    FReader: TWebSocketReader;
    FInbox: TList;
    FInboxLock: TCriticalSection;
    FClosedNoted: Boolean;
    procedure Deliver;
    procedure Arrived(Kind: Integer; const Data: RawByteString);
  public
    { 'Name: value' lines sent with the handshake }
    Headers: TStringArray;
    { "Authorization: Bearer <token>" (RequireJwt) }
    BearerToken: string;
    OnMessage: TWebSocketClientEvent;
    OnBinary: TWebSocketClientBinaryEvent;
    { the connection ended (Close, the server, the network): CloseCode says how }
    OnClose: TNotifyEvent;
    { True (default): events on the app's thread (forms can be used); False: on the reading thread }
    EventsOnAppThread: Boolean;
    { milliseconds for connecting; default 30000 }
    Timeout: Integer;
    { Leave on. Off accepts any certificate (tests only). }
    VerifyCertificates: Boolean;
    constructor Create;
    destructor Destroy; override;
    { connects and does the handshake; EWebSocketError with the reason }
    procedure Connect(const Url: string);
  end;

  TWebSocketReader = class(TThread)
  private
    FClient: TWebSocketClient;
  public
    constructor Create(AClient: TWebSocketClient);
    procedure Execute; override;
  end;

{ Sec-WebSocket-Accept for a Sec-WebSocket-Key }
function WebSocketAccept(const Key: string): string;

implementation

uses
  base64, Pastel.Crypto, Pastel.Json, Pastel.Log;

const
  OpText = 1;
  OpBinary = 2;
  OpClose = 8;
  OpPing = 9;
  OpPong = 10;

function WebSocketAccept(const Key: string): string;
begin
  Result := EncodeStringBase64(Sha1(Trim(Key) + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'));
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then
    Move(S[1], Result[0], Length(S));
end;

{ ---------------- TWebSocket ---------------- }

constructor TWebSocket.Create(AConn: TNetConnection; AIsClient: Boolean);
begin
  inherited Create;
  FConn := AConn;
  FIsClient := AIsClient;
  FWriteLock := TCriticalSection.Create;
  FParams := TStringList.Create;
  FQuery := TStringList.Create;
  FValues := TStringList.Create;
  MaxMessageSize := 1024 * 1024;
  PingInterval := 30;
  FLastHeard := GetTickCount64;
  FCloseCode := 1006;
end;

destructor TWebSocket.Destroy;
begin
  FConn.Free;
  FClaims.Free;
  FValues.Free;
  FQuery.Free;
  FParams.Free;
  FWriteLock.Free;
  inherited Destroy;
end;

procedure TWebSocket.Attach(AConn: TNetConnection);
begin
  FConn := AConn;
  FCloseSent := False;
  FStopping := False;
  FCloseCode := 1006;
  FCloseReason := '';
  FLastHeard := GetTickCount64;
end;

procedure TWebSocket.Prepare(const APath: string; AParams, AQuery, AValues: TStrings; AClaims: TJSONObject);
begin
  FPath := APath;
  FParams.Assign(AParams);
  FQuery.Assign(AQuery);
  FValues.Assign(AValues);
  FreeAndNil(FClaims);
  if AClaims <> nil then
    FClaims := TJSONObject(AClaims.Clone);
end;

function TWebSocket.Open: Boolean;
begin
  Result := (FConn <> nil) and not FCloseSent and not FStopping;
end;

function TWebSocket.Claim(const Name: string): string;
begin
  Result := '';
  if (FClaims <> nil) and (FClaims.IndexOfName(Name) >= 0) then
    Result := FClaims.Get(Name, '');
end;

procedure TWebSocket.SendFrame(Opcode: Byte; const Data: RawByteString);
var
  H, P: RawByteString;
  N: QWord;
  I: Integer;
  Mask: RawByteString;
begin
  if FConn = nil then
    raise EWebSocketError.Create('the WebSocket is not connected');
  N := Length(Data);
  H := Chr($80 or Opcode);
  if N < 126 then
    H := H + Chr(N or (Ord(FIsClient) shl 7))
  else if N < 65536 then
    H := H + Chr(126 or (Ord(FIsClient) shl 7)) + Chr(N shr 8) + Chr(N and $FF)
  else
  begin
    H := H + Chr(127 or (Ord(FIsClient) shl 7));
    for I := 7 downto 0 do
      H := H + Chr((N shr (I * 8)) and $FF);
  end;
  P := Data;
  if FIsClient then
  begin
    { a client masks what it sends }
    Mask := RandomBytes(4);
    H := H + Mask;
    UniqueString(P);
    for I := 1 to Length(P) do
      P[I] := Chr(Ord(P[I]) xor Ord(Mask[((I - 1) and 3) + 1]));
  end;
  FWriteLock.Enter;
  try
    try
      FConn.WriteText(H + P);
    except
      on E: ENetError do
      begin
        FStopping := True;
        raise EWebSocketError.Create('the WebSocket connection is gone');
      end;
    end;
  finally
    FWriteLock.Leave;
  end;
end;

procedure TWebSocket.Send(const Text: string);
begin
  if FCloseSent then
    raise EWebSocketError.Create('the WebSocket is closed');
  SendFrame(OpText, Text);
end;

procedure TWebSocket.SendBinary(const Data: TBytes);
var
  S: RawByteString;
begin
  if FCloseSent then
    raise EWebSocketError.Create('the WebSocket is closed');
  SetLength(S, Length(Data));
  if Length(Data) > 0 then
    Move(Data[0], S[1], Length(Data));
  SendFrame(OpBinary, S);
end;

procedure TWebSocket.SendJson(Data: TJSONData);
begin
  try
    Send(Data.AsJSON);
  finally
    Data.Free;
  end;
end;

procedure TWebSocket.Close(Code: Integer; const Reason: string);
begin
  if FCloseSent or (FConn = nil) then
    Exit;
  FCloseSent := True;
  try
    SendFrame(OpClose, Chr(Code shr 8) + Chr(Code and $FF) + Copy(Reason, 1, 120));
  except
    { gone already }
  end;
end;

{ exactly N bytes; False when the connection ended (or is dead, or stops) }
function TWebSocket.Fill(var Buf: RawByteString; N: Integer; AtStart: Boolean): Boolean;
var
  Got, R: Integer;
  Idle: QWord;
begin
  SetLength(Buf, N);
  Got := 0;
  while Got < N do
  begin
    try
      R := FConn.Read(Buf[Got + 1], N - Got);
    except
      on E: ENetError do
        R := 0;
    end;
    if R > 0 then
    begin
      Inc(Got, R);
      FLastHeard := GetTickCount64;
      FPingSent := False;
      Continue;
    end;
    if R = 0 then
      Exit(False);
    { nothing came within the read timeout }
    if FStopping then
      Exit(False);
    Idle := GetTickCount64 - FLastHeard;
    if AtStart and (Got = 0) and (PingInterval > 0) then
    begin
      if (Idle > QWord(PingInterval) * 1000) and not FPingSent then
      begin
        FPingSent := True;
        try
          SendFrame(OpPing, '');
        except
          Exit(False);
        end;
      end;
      if Idle > QWord(PingInterval) * 2000 then
        Exit(False);
    end
    else if Idle > 30000 then
      Exit(False);
  end;
  Result := True;
end;

function TWebSocket.ReadMessage(out Data: RawByteString; out Binary: Boolean): Boolean;
var
  H, X, Mask, Payload, Msg: RawByteString;
  Fin, Masked: Boolean;
  Op, MsgOp: Byte;
  Len: QWord;
  I: Integer;
begin
  Result := False;
  Data := '';
  Binary := False;
  Msg := '';
  MsgOp := 0;
  while not FStopping do
  begin
    if not Fill(H, 2, Msg = '') then
      Exit;
    Fin := (Ord(H[1]) and $80) <> 0;
    Op := Ord(H[1]) and $0F;
    Masked := (Ord(H[2]) and $80) <> 0;
    Len := Ord(H[2]) and $7F;
    if Masked = FIsClient then
    begin
      { clients mask, servers do not }
      Close(1002, 'protocol error');
      Exit;
    end;
    if Len = 126 then
    begin
      if not Fill(X, 2, False) then
        Exit;
      Len := (QWord(Ord(X[1])) shl 8) or Ord(X[2]);
    end
    else if Len = 127 then
    begin
      if not Fill(X, 8, False) then
        Exit;
      Len := 0;
      for I := 1 to 8 do
        Len := (Len shl 8) or Ord(X[I]);
    end;
    if Len + QWord(Length(Msg)) > QWord(MaxMessageSize) then
    begin
      Close(1009, 'message too big');
      Exit;
    end;
    Mask := '';
    if Masked and not Fill(Mask, 4, False) then
      Exit;
    Payload := '';
    if (Len > 0) and not Fill(Payload, Len, False) then
      Exit;
    if Masked then
      for I := 1 to Length(Payload) do
        Payload[I] := Chr(Ord(Payload[I]) xor Ord(Mask[((I - 1) and 3) + 1]));
    case Op of
      OpClose:
        begin
          if Length(Payload) >= 2 then
          begin
            FCloseCode := (Ord(Payload[1]) shl 8) or Ord(Payload[2]);
            FCloseReason := Copy(Payload, 3, MaxInt);
          end
          else
            FCloseCode := 1005;
          if not FCloseSent then
          begin
            FCloseSent := True;
            try
              SendFrame(OpClose, Copy(Payload, 1, 2));
            except
            end;
          end;
          Exit;
        end;
      OpPing:
        try
          SendFrame(OpPong, Payload);
        except
          Exit;
        end;
      OpPong:
        FPingSent := False;
      0, OpText, OpBinary:
        begin
          if Op <> 0 then
            MsgOp := Op;
          Msg := Msg + Payload;
          if Fin then
          begin
            Data := Msg;
            SetCodePage(Data, CP_UTF8, False);
            Binary := MsgOp = OpBinary;
            Exit(True);
          end;
        end;
    else
      Close(1002, 'protocol error');
      Exit;
    end;
  end;
end;

{ ---------------- TWebSockets ---------------- }

constructor TWebSockets.Create;
begin
  inherited Create;
  FList := TList.Create;
  FLock := TCriticalSection.Create;
  MaxMessageSize := 1024 * 1024;
  PingInterval := 30;
end;

destructor TWebSockets.Destroy;
begin
  CloseAll;
  FLock.Free;
  FList.Free;
  inherited Destroy;
end;

function TWebSockets.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FList.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSockets.Broadcast(const Text: string; Except_: TWebSocket);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to FList.Count - 1 do
      if TWebSocket(FList[I]) <> Except_ then
      try
        TWebSocket(FList[I]).Send(Text);
      except
        on E: EWebSocketError do ;     { that one is going }
      end;
  finally
    FLock.Leave;
  end;
end;

function TWebSockets.SendTo(const Key, Value, Text: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    for I := 0 to FList.Count - 1 do
      if TWebSocket(FList[I]).Values.Values[Key] = Value then
      try
        TWebSocket(FList[I]).Send(Text);
        Inc(Result);
      except
        on E: EWebSocketError do ;
      end;
  finally
    FLock.Leave;
  end;
end;

function TWebSockets.SendToId(AId: Int64; const Text: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    for I := 0 to FList.Count - 1 do
      if TWebSocket(FList[I]).Id = AId then
      try
        TWebSocket(FList[I]).Send(Text);
        Exit(True);
      except
        on E: EWebSocketError do
          Exit(False);
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSockets.CloseAll(Code: Integer; const Reason: string);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to FList.Count - 1 do
    begin
      TWebSocket(FList[I]).Close(Code, Reason);
      TWebSocket(FList[I]).FStopping := True;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSockets.Serve(Socket: TWebSocket);
var
  Data: RawByteString;
  Binary: Boolean;
begin
  Socket.MaxMessageSize := MaxMessageSize;
  Socket.PingInterval := PingInterval;
  FLock.Enter;
  try
    Inc(FNextId);
    Socket.FId := FNextId;
    FList.Add(Socket);
  finally
    FLock.Leave;
  end;
  try
    try
      if Assigned(OnOpen) then
        OnOpen(Socket);
      while Socket.ReadMessage(Data, Binary) do
      try
        if Binary then
        begin
          if Assigned(OnBinary) then
            OnBinary(Socket, BytesOf(Data));
        end
        else if Assigned(OnMessage) then
          OnMessage(Socket, Data);
      except
        on E: Exception do
          Log.Error(E, 'WebSocket ' + Socket.Path);
      end;
    except
      on E: Exception do
      begin
        Log.Error(E, 'WebSocket ' + Socket.Path);
        Socket.Close(1011, 'error');
      end;
    end;
  finally
    FLock.Enter;
    try
      FList.Remove(Socket);
    finally
      FLock.Leave;
    end;
    try
      if Assigned(OnClose) then
        OnClose(Socket);
    except
      on E: Exception do
        Log.Error(E, 'WebSocket ' + Socket.Path);
    end;
    try
      Socket.FConn.Shutdown;
    except
    end;
  end;
end;

{ ---------------- TWebSocketClient ---------------- }

type
  TInboxItem = class
    Kind: Integer;           { 1 text, 2 binary, 0 closed }
    Data: RawByteString;
  end;

constructor TWebSocketReader.Create(AClient: TWebSocketClient);
begin
  FClient := AClient;
  inherited Create(False);
end;

procedure TWebSocketReader.Execute;
var
  Data: RawByteString;
  Binary: Boolean;
begin
  try
    while FClient.ReadMessage(Data, Binary) do
      FClient.Arrived(1 + Ord(Binary), Data);
  except
  end;
  FClient.FStopping := True;
  FClient.Arrived(0, '');
end;

constructor TWebSocketClient.Create;
begin
  inherited Create(nil, True);
  FInbox := TList.Create;
  FInboxLock := TCriticalSection.Create;
  EventsOnAppThread := True;
  Timeout := 30000;
  VerifyCertificates := True;
  PingInterval := 0;     { the server pings; a client answers }
end;

destructor TWebSocketClient.Destroy;
var
  I: Integer;
begin
  if FReader <> nil then
  begin
    Close(1001, 'going away');
    FStopping := True;
    try
      FConn.Shutdown;
    except
    end;
    FReader.WaitFor;
    TThread.RemoveQueuedEvents(FReader);
    FreeAndNil(FReader);
  end;
  for I := 0 to FInbox.Count - 1 do
    TObject(FInbox[I]).Free;
  FInbox.Free;
  FInboxLock.Free;
  inherited Destroy;
end;

procedure TWebSocketClient.Arrived(Kind: Integer; const Data: RawByteString);
var
  Item: TInboxItem;
begin
  Item := TInboxItem.Create;
  Item.Kind := Kind;
  Item.Data := Data;
  FInboxLock.Enter;
  try
    FInbox.Add(Item);
  finally
    FInboxLock.Leave;
  end;
  if EventsOnAppThread then
    TThread.Queue(FReader, @Deliver)
  else
    Deliver;
end;

procedure TWebSocketClient.Deliver;
var
  Item: TInboxItem;
begin
  repeat
    FInboxLock.Enter;
    try
      if FInbox.Count = 0 then
        Exit;
      Item := TInboxItem(FInbox[0]);
      FInbox.Delete(0);
    finally
      FInboxLock.Leave;
    end;
    try
      case Item.Kind of
        1: if Assigned(OnMessage) then OnMessage(Self, Item.Data);
        2: if Assigned(OnBinary) then OnBinary(Self, BytesOf(Item.Data));
      else
        if not FClosedNoted then
        begin
          FClosedNoted := True;
          if Assigned(OnClose) then
            OnClose(Self);
        end;
      end;
    finally
      Item.Free;
    end;
  until False;
end;

procedure TWebSocketClient.Connect(const Url: string);
var
  U, Host, PathQ, Key, Req, Line, Accept, H: string;
  Port, I, Code: Integer;
  Tls: Boolean;
  C: TNetConnection;
begin
  if FReader <> nil then
  begin
    if Open then
      raise EWebSocketError.Create('the WebSocket is connected already');
    { connected before: that connection is over }
    FReader.WaitFor;
    TThread.RemoveQueuedEvents(FReader);
    FreeAndNil(FReader);
    FreeAndNil(FConn);
  end;
  U := Url;
  if SameText(Copy(U, 1, 6), 'wss://') then
  begin
    Tls := True;
    Delete(U, 1, 6);
    Port := 443;
  end
  else if SameText(Copy(U, 1, 5), 'ws://') then
  begin
    Tls := False;
    Delete(U, 1, 5);
    Port := 80;
  end
  else if SameText(Copy(U, 1, 8), 'https://') then
  begin
    Tls := True;
    Delete(U, 1, 8);
    Port := 443;
  end
  else if SameText(Copy(U, 1, 7), 'http://') then
  begin
    Tls := False;
    Delete(U, 1, 7);
    Port := 80;
  end
  else
    raise EWebSocketError.CreateFmt('"%s" is not a WebSocket address (ws://host/path or wss://...)', [Url]);
  I := Pos('/', U);
  if I = 0 then
  begin
    Host := U;
    PathQ := '/';
  end
  else
  begin
    Host := Copy(U, 1, I - 1);
    PathQ := Copy(U, I, MaxInt);
  end;
  H := Host;
  I := LastDelimiter(':', Host);
  if (I > 0) and (Pos(']', Host) < I) then
  begin
    Port := StrToIntDef(Copy(Host, I + 1, MaxInt), Port);
    SetLength(Host, I - 1);
  end;
  try
    C := NetConnect(Host, Port, Tls, nil, Timeout, VerifyCertificates, Timeout);
  except
    on E: ENetError do
      raise EWebSocketError.Create(E.Message);
  end;
  try
    Key := EncodeStringBase64(RandomBytes(16));
    Req := 'GET ' + PathQ + ' HTTP/1.1'#13#10 +
      'Host: ' + H + #13#10 +
      'Upgrade: websocket'#13#10 +
      'Connection: Upgrade'#13#10 +
      'Sec-WebSocket-Key: ' + Key + #13#10 +
      'Sec-WebSocket-Version: 13'#13#10 +
      'User-Agent: Pastel'#13#10;
    if BearerToken <> '' then
      Req := Req + 'Authorization: Bearer ' + BearerToken + #13#10;
    for Line in Headers do
      Req := Req + Line + #13#10;
    C.WriteText(Req + #13#10);
    { the answer's lines, up to the empty one }
    Line := C.ReadLine;
    Code := StrToIntDef(Copy(Line, Pos(' ', Line) + 1, 3), 0);
    Accept := '';
    repeat
      H := C.ReadLine;
      if SameText(Copy(H, 1, 21), 'Sec-WebSocket-Accept:') then
        Accept := Trim(Copy(H, 22, MaxInt));
    until H = '';
    if Code <> 101 then
      raise EWebSocketError.CreateFmt('%s answered "%s", not a WebSocket', [Url, Trim(Copy(Line, Pos(' ', Line) + 1, MaxInt))]);
    if Accept <> WebSocketAccept(Key) then
      raise EWebSocketError.CreateFmt('%s did not do the WebSocket handshake right', [Url]);
  except
    on E: ENetError do
    begin
      C.Free;
      raise EWebSocketError.CreateFmt('%s: %s', [Url, E.Message]);
    end;
    on E: Exception do
    begin
      C.Free;
      raise;
    end;
  end;
  FPath := PathQ;
  FClosedNoted := False;
  C.SetReadTimeout(0);     { the reader waits for the server }
  Attach(C);
  FReader := TWebSocketReader.Create(Self);
end;

end.
