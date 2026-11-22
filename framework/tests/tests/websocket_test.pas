{ Tests of Pastel.WebSocket: a TWebServer with WebSockets and TWebSocketClient. }
unit websocket_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, Pastel.Testing, Pastel.Web, Pastel.WebSocket, Pastel.Http, Pastel.Jwt;

type
  TWebSocketTests = class(TTestSuite)
  private
    FServer: TWebServer;
    FHub, FPrivate: TWebSockets;
    FPort: Integer;
    FLock: TCriticalSection;
    FGot: TStringList;
    FClosed: Integer;
    FServerClosed: Integer;
    FOnAppThread: Boolean;
    procedure HubOpen(Socket: TWebSocket);
    procedure HubMessage(Socket: TWebSocket; const Text: string);
    procedure HubBinary(Socket: TWebSocket; const Data: TBytes);
    procedure HubClose(Socket: TWebSocket);
    procedure PrivateMessage(Socket: TWebSocket; const Text: string);
    procedure ClientMessage(Sender: TObject; const Text: string);
    procedure ClientBinary(Sender: TObject; const Data: TBytes);
    procedure ClientClosed(Sender: TObject);
    function Url(const Path: string): string;
    function NewClient: TWebSocketClient;
    function WaitFor(Count: Integer; Ms: Integer = 3000): Boolean;
    function Got(I: Integer): string;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EchoAndBroadcast;
    procedure LongAndBinaryMessages;
    procedure EventsOnTheAppThread;
    procedure FiltersGuardWebSockets;
    procedure PlainRequestsGetAnAnswer;
    procedure ClosingFromBothSides;
    procedure ServerStopEndsConnections;
  end;

implementation

const
  Secret = 'a-test-secret-that-is-long-enough-123';

procedure TWebSocketTests.SetUp;
begin
  FLock := TCriticalSection.Create;
  FGot := TStringList.Create;
  FClosed := 0;
  FServerClosed := 0;
  FHub := TWebSockets.Create;
  FHub.OnOpen := @HubOpen;
  FHub.OnMessage := @HubMessage;
  FHub.OnBinary := @HubBinary;
  FHub.OnClose := @HubClose;
  FPrivate := TWebSockets.Create;
  FPrivate.OnMessage := @PrivateMessage;
  FPort := 21000 + Random(20000);
  FServer := TWebServer.Create(FPort, '127.0.0.1');
  FServer.AccessLog := False;
  FServer.RequestTimeout := 2;
  FServer.WebSocket('/chat/:room', FHub);
  FServer.RequireJwt('/private', Secret);
  FServer.WebSocket('/private/feed', FPrivate);
  FServer.Start;
end;

procedure TWebSocketTests.TearDown;
begin
  FServer.Free;
  FPrivate.Free;
  FHub.Free;
  FGot.Free;
  FLock.Free;
end;

procedure TWebSocketTests.HubOpen(Socket: TWebSocket);
begin
  Socket.Values.Values['room'] := Socket.Params.Values['room'];
  Socket.Send('welcome to ' + Socket.Params.Values['room'] + ' #' + IntToStr(Socket.Id) + ' ' + Socket.Query.Values['name']);
end;

procedure TWebSocketTests.HubMessage(Socket: TWebSocket; const Text: string);
begin
  if Text = 'all' then
    FHub.Broadcast('to all from #' + IntToStr(Socket.Id))
  else if Text = 'room' then
    FHub.SendTo('room', Socket.Values.Values['room'], 'to ' + Socket.Values.Values['room'])
  else if Text = 'bye' then
    Socket.Close(4000, 'asked to')
  else if Text = 'crash' then
    raise Exception.Create('a handler failed')
  else
    Socket.Send('echo: ' + Text);
end;

procedure TWebSocketTests.HubBinary(Socket: TWebSocket; const Data: TBytes);
var
  B: TBytes;
  I: Integer;
begin
  B := Copy(Data);
  for I := 0 to High(B) do
    B[I] := 255 - B[I];
  Socket.SendBinary(B);
end;

procedure TWebSocketTests.HubClose(Socket: TWebSocket);
begin
  FLock.Enter;
  Inc(FServerClosed);
  FLock.Leave;
end;

procedure TWebSocketTests.PrivateMessage(Socket: TWebSocket; const Text: string);
begin
  Socket.Send('hello ' + Socket.Claim('sub'));
end;

procedure TWebSocketTests.ClientMessage(Sender: TObject; const Text: string);
begin
  FLock.Enter;
  try
    if FOnAppThread and (GetCurrentThreadID <> MainThreadID) then
      FGot.Add('not on the app thread')
    else
      FGot.Add(Text);
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketTests.ClientBinary(Sender: TObject; const Data: TBytes);
var
  S: string;
  B: Byte;
begin
  S := 'bytes';
  for B in Data do
    S := S + ' ' + IntToStr(B);
  ClientMessage(Sender, S);
end;

procedure TWebSocketTests.ClientClosed(Sender: TObject);
begin
  FLock.Enter;
  Inc(FClosed);
  FLock.Leave;
end;

function TWebSocketTests.Url(const Path: string): string;
begin
  Result := Format('ws://127.0.0.1:%d%s', [FPort, Path]);
end;

function TWebSocketTests.NewClient: TWebSocketClient;
begin
  Result := TWebSocketClient.Create;
  Result.EventsOnAppThread := False;
  Result.OnMessage := @ClientMessage;
  Result.OnBinary := @ClientBinary;
  Result.OnClose := @ClientClosed;
end;

function TWebSocketTests.WaitFor(Count: Integer; Ms: Integer): Boolean;
var
  Until_: QWord;
begin
  Until_ := GetTickCount64 + QWord(Ms);
  repeat
    FLock.Enter;
    try
      if FGot.Count >= Count then
        Exit(True);
    finally
      FLock.Leave;
    end;
    if FOnAppThread then
      CheckSynchronize(10)
    else
      Sleep(10);
  until GetTickCount64 > Until_;
  Result := False;
end;

function TWebSocketTests.Got(I: Integer): string;
begin
  FLock.Enter;
  try
    if I < FGot.Count then
      Result := FGot[I]
    else
      Result := '(nothing)';
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketTests.EchoAndBroadcast;
var
  A, B: TWebSocketClient;
begin
  A := NewClient;
  B := NewClient;
  try
    A.Connect(Url('/chat/red?name=ali'));
    AssertTrue(WaitFor(1), 'welcome');
    AssertEquals('welcome to red #1 ali', Got(0));
    B.Connect(Url('/chat/blue'));
    AssertTrue(WaitFor(2));
    AssertEquals(2, FHub.Count);
    A.Send('merhaba dünya');
    AssertTrue(WaitFor(3));
    AssertEquals('echo: merhaba dünya', Got(2));
    A.Send('all');
    AssertTrue(WaitFor(5), 'both got it');
    AssertEquals('to all from #1', Got(3));
    AssertEquals('to all from #1', Got(4));
    B.Send('room');
    AssertTrue(WaitFor(6));
    Sleep(100);
    AssertEquals(6, FGot.Count);
    AssertEquals('to blue', Got(5));
    { an error of a handler is logged; the connection stays }
    A.Send('crash');
    A.Send('still here');
    AssertTrue(WaitFor(7));
    AssertEquals('echo: still here', Got(6));
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TWebSocketTests.LongAndBinaryMessages;
var
  A: TWebSocketClient;
  Long: string;
begin
  A := NewClient;
  try
    A.Connect(Url('/chat/x'));
    AssertTrue(WaitFor(1));
    Long := StringOfChar('a', 300);
    A.Send(Long);
    Long := StringOfChar('b', 70000);
    A.Send(Long);
    A.SendBinary(TBytes.Create(0, 1, 254));
    AssertTrue(WaitFor(4));
    AssertEquals('echo: ' + StringOfChar('a', 300), Got(1));
    AssertEquals('echo: ' + Long, Got(2));
    AssertEquals('bytes 255 254 1', Got(3));
    { too long for the server: it closes }
    FHub.MaxMessageSize := 1000;
  finally
    A.Free;
  end;
  A := NewClient;
  try
    A.Connect(Url('/chat/x'));
    AssertTrue(WaitFor(5));
    A.Send(StringOfChar('c', 2000));
    Sleep(300);
    AssertEquals(2, FClosed, 'closed (the first client, and this one)');
    AssertEquals(1009, A.CloseCode);
    AssertFalse(A.Open);
  finally
    A.Free;
  end;
end;

procedure TWebSocketTests.EventsOnTheAppThread;
var
  A: TWebSocketClient;
begin
  FOnAppThread := True;
  A := NewClient;
  try
    A.EventsOnAppThread := True;
    A.Connect(Url('/chat/x'));
    Sleep(100);
    AssertEquals(0, FGot.Count, 'not before the app thread takes it');
    AssertTrue(WaitFor(1));
    A.Send('hi');
    AssertTrue(WaitFor(2));
    AssertEquals('echo: hi', Got(1));
  finally
    A.Free;
    FOnAppThread := False;
  end;
end;

procedure TWebSocketTests.FiltersGuardWebSockets;
var
  A: TWebSocketClient;
  Msg: string;
  C: TJSONObject;
begin
  A := NewClient;
  try
    Msg := '';
    try
      A.Connect(Url('/private/feed'));
    except
      on E: EWebSocketError do
        Msg := E.Message;
    end;
    AssertTrue(Pos('401', Msg) > 0, Msg);
    C := TJSONObject.Create(['sub', 'ayse']);
    A.BearerToken := JwtSign(C, Secret);      { frees C }
    A.Connect(Url('/private/feed'));
    A.Send('who am I');
    AssertTrue(WaitFor(1));
    AssertEquals('hello ayse', Got(0));
  finally
    A.Free;
  end;
end;

procedure TWebSocketTests.PlainRequestsGetAnAnswer;
var
  R: THttpResponse;
  A: TWebSocketClient;
  Msg: string;
begin
  R := HttpGet(Format('http://127.0.0.1:%d/chat/x', [FPort]));
  AssertEquals(426, R.Status);
  AssertTrue(Pos('WebSocket', R.Body) > 0, R.Body);
  A := NewClient;
  try
    Msg := '';
    try
      A.Connect(Url('/nothing/here'));
    except
      on E: EWebSocketError do
        Msg := E.Message;
    end;
    AssertTrue(Pos('404', Msg) > 0, Msg);
    Msg := '';
    try
      A.Connect(Format('ws://127.0.0.1:%d/x', [FPort + 1]));
    except
      on E: EWebSocketError do
        Msg := E.Message;
    end;
    AssertTrue(Pos('cannot connect', Msg) > 0, Msg);
  finally
    A.Free;
  end;
end;

procedure TWebSocketTests.ClosingFromBothSides;
var
  A: TWebSocketClient;
begin
  A := NewClient;
  try
    A.Connect(Url('/chat/x'));
    AssertTrue(WaitFor(1));
    A.Send('bye');
    Sleep(300);
    AssertEquals(1, FClosed);
    AssertEquals(4000, A.CloseCode);
    AssertEquals('asked to', A.CloseReason);
    AssertEquals(1, FServerClosed);
    { again, with the same object; this time the client closes }
    A.Connect(Url('/chat/x'));
    AssertTrue(WaitFor(2));
    AssertEquals(1, FHub.Count);
    A.Close;
    Sleep(300);
    AssertEquals(2, FServerClosed);
    AssertEquals(0, FHub.Count);
    AssertEquals(2, FClosed);
  finally
    A.Free;
  end;
end;

procedure TWebSocketTests.ServerStopEndsConnections;
var
  A: TWebSocketClient;
  T0: QWord;
begin
  A := NewClient;
  try
    A.Connect(Url('/chat/x'));
    AssertTrue(WaitFor(1));
    T0 := GetTickCount64;
    FServer.Stop;
    AssertTrue(GetTickCount64 - T0 < 3000, 'the server did not wait for the client');
    Sleep(200);
    AssertEquals(1, FClosed);
    AssertEquals(1001, A.CloseCode);
  finally
    A.Free;
  end;
end;

initialization
  RegisterTests(TWebSocketTests);

end.
