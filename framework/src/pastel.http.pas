(* Pastel - HTTP and HTTPS client.

    R := HttpGet('https://api.example.com/users/1');
    if R.Ok then
      WriteLn(R.Body);

    Doc := HttpGetJson('https://api.example.com/users');   // raises unless 2xx
    R := HttpPostJson('https://api.example.com/users', '{"name": "Ali"}');
    HttpDownload('https://example.com/big.iso', 'big.iso');

    Client := THttpClient.Create('https://api.example.com/v1');
    Client.BearerToken := Token;
    Client.Timeout := 10000;
    Client.Headers := ['Accept-Language: tr'];
    R := Client.Get('/orders', ['status', 'open', 'page', '2']);   // ?status=open&page=2
    R := Client.PostForm('/login', ['user', 'ali', 'pass', 'x']);
    Client.Free;

  HTTPS certificates are checked (with the host name), like a browser does.
  HTTPS_PROXY, HTTP_PROXY and NO_PROXY are followed, including HTTPS
  through a proxy. OpenSSL 3 and 1.1 both work.
  Errors raise EHttpError with a message that says what went wrong:
    cannot find server "api.exmaple.com" (check the address and the network)
    certificate of "self-signed.badssl.com" is not trusted: self-signed certificate
    GET https://api.example.com/x: 404 Not Found
  Part of the Pastel project, MIT License. *)
unit Pastel.Http;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, fpjson, {$IFNDEF ANDROID}fphttpclient, ssockets, sslsockets, opensslsockets,{$ENDIF} Pastel.Env;

type
  EHttpError = class(Exception)
  public
    { HTTP status for an error response; 0 when no answer came }
    Status: Integer;
    Body: string;
  end;

  THttpResponse = record
    Status: Integer;          // 200, 404, ...
    StatusText: string;       // 'OK', 'Not Found'
    Body: string;
    Headers: TStringArray;    // 'Name: value'
    Url: string;              // the final address, after redirects
    Method: string;
    Duration: Integer;        // milliseconds
    { 200-299 }
    function Ok: Boolean;
    { A header value by name, any case; '' when missing }
    function Header(const Name: string): string;
    { The body as JSON; the caller frees it. }
    function Json: TJSONData;
    { Raises EHttpError unless Ok. }
    procedure RaiseForStatus;
  end;

  THttpProgressEvent = procedure(Done, Total: Int64) of object;

  THttpClient = class
  private
    FBaseUrl: string;
    procedure Fill(Client: TObject);
    function MakeUrl(const Path: string; const Query: array of string): string;
    function Send(const Method, Url: string; Body: TStream; const ContentType: string;
      Output: TStream): THttpResponse;
  public
    { Sent with every request: 'Name: value' }
    Headers: TStringArray;
    BearerToken: string;
    UserName, Password: string;
    UserAgent: string;
    { milliseconds for connecting and for every read; default 30000 }
    Timeout: Integer;
    FollowRedirects: Boolean;
    { Leave on. Off accepts any certificate (only for testing!). }
    VerifyCertificates: Boolean;
    { 'http://host:port'; default from HTTPS_PROXY / HTTP_PROXY.
      Set to 'none' to never use one. }
    Proxy: string;
    OnProgress: THttpProgressEvent;
    constructor Create(const ABaseUrl: string = '');
    function Get(const Path: string): THttpResponse;
    function Get(const Path: string; const Query: array of string): THttpResponse;
    function Delete(const Path: string): THttpResponse;
    function Head(const Path: string): THttpResponse;
    function Post(const Path, Body: string; const ContentType: string = 'text/plain; charset=utf-8'): THttpResponse;
    function Put(const Path, Body: string; const ContentType: string = 'text/plain; charset=utf-8'): THttpResponse;
    function Patch(const Path, Body: string; const ContentType: string = 'text/plain; charset=utf-8'): THttpResponse;
    function PostJson(const Path, Json: string): THttpResponse;
    function PostJson(const Path: string; Json: TJSONData): THttpResponse;
    function PutJson(const Path, Json: string): THttpResponse;
    { Fields in turn: name, value, name, value }
    function PostForm(const Path: string; const Fields: array of string): THttpResponse;
    function Request(const Method, Path, Body, ContentType: string): THttpResponse;
    { The same, the answer's body written into Output as it arrives (Body of
      the result stays empty): answers that come in parts (server-sent
      events, a long download); an answer that is not 2xx goes there too.
      Android: all of it at the end. }
    function RequestTo(const Method, Path, Body, ContentType: string; Output: TStream): THttpResponse;
    { Streams into FileName (through a temporary file); raises unless 2xx. }
    procedure Download(const Path, FileName: string);
    property BaseUrl: string read FBaseUrl write FBaseUrl;
  end;

  { A connection of another protocol than HTTP (SMTP, WebSocket): bytes both
    ways, TLS or not. Read and Write may run on two threads at once. }
  TNetConnection = class
  public
    { up to Count bytes; 0 when the connection is closed; ENetError when it broke }
    function Read(var Buffer; Count: Integer): Integer; virtual; abstract;
    { all of them, or ENetError }
    procedure Write(const Buffer; Count: Integer); virtual; abstract;
    procedure WriteText(const S: RawByteString);
    { a line without its CR LF; ENetError when the connection closes first }
    function ReadLine: string;
    { ends the connection; a Read waiting on another thread returns 0 }
    procedure Shutdown; virtual; abstract;
    { milliseconds a Read waits; 0: until something comes }
    procedure SetReadTimeout(Ms: Integer); virtual;
  end;

  ENetError = class(Exception);

  { the plain part of a connection before TLS starts (SMTP's STARTTLS): lines
    with WriteText/ReadLine; '' when TLS can start, else what went wrong }
  TBeforeTlsEvent = function(Conn: TNetConnection): string of object;

{ A TCP connection to Host:Port; Tls: TLS, its certificate checked like HTTPS's
  (Verify False accepts any: tests only). BeforeTls talks plain first, then TLS
  starts (Tls must be True). Timeout: milliseconds for connecting; ReadTimeout:
  for a Read, 0 for none. ENetError with the reason when it fails. On Android
  Android's own sockets and TLS (dev.pastel.PastelSocket). }
function NetConnect(const Host: string; Port: Integer; Tls: Boolean; BeforeTls: TBeforeTlsEvent = nil;
  Timeout: Integer = 30000; Verify: Boolean = True; ReadTimeout: Integer = 30000): TNetConnection;

function HttpGet(const Url: string): THttpResponse;
{ The body; raises EHttpError unless 2xx. }
function HttpGetText(const Url: string): string;
{ Parsed JSON (the caller frees it); raises EHttpError unless 2xx. }
function HttpGetJson(const Url: string): TJSONData;
function HttpPost(const Url, Body, ContentType: string): THttpResponse;
function HttpPostJson(const Url, Json: string): THttpResponse;
procedure HttpDownload(const Url, FileName: string);

{ 'a b&c' -> 'a%20b%26c' }
function UrlEncode(const S: string): string;
{ ['q', 'çay', 'n', '2'] -> 'q=%C3%A7ay&n=2' }
function QueryString(const Pairs: array of string): string;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  base64, Pastel.Json, Pastel.Files,
  { Android: the phone's own HTTP (OpenSSL cannot be loaded there) }
  {$IFDEF ANDROID}Pastel.Android, Pastel.Java{$ELSE}Sockets, DynLibs, ctypes, openssl, fpopenssl{$ENDIF};

{$IFNDEF ANDROID}
type
  TPastelSSLHandler = class;

  { fphttpclient with: HTTPS through a proxy (CONNECT), certificate and host
    name checks, a clear reason when TLS fails, and progress. }
  TPastelHttpClient = class(TFPHTTPClient)
  private
    FTunnelHost, FTunnelAuth: string;
    FTunnelPort: Word;
    FTargetHost: string;
    FLastUrl: string;
    FProxyUrl: string;
    FVerify: Boolean;
    FFailure: string;
    FOutput: TStream;
    FOnProgressCb: THttpProgressEvent;
    procedure GetHandler(Sender: TObject; const UseSSL: Boolean; out AHandler: TSocketHandler);
    procedure Redirected(Sender: TObject; const ASrc: string; var ADest: string);
    procedure DataReceived(Sender: TObject; const ContentLength, CurrentPos: Int64);
  protected
    procedure DoMethod(const AMethod, AURL: string; Stream: TStream;
      const AllowedResponseCodes: array of Integer); override;
    procedure ConnectToServer(const AHost: string; APort: Integer; UseSSL: Boolean = False); override;
  end;

  TPastelSSLHandler = class(TOpenSSLSocketHandler)
  private
    FOwner: TPastelHttpClient;
    FBeforeTls: TBeforeTlsEvent;
    function OpenTunnel: Boolean;
    function PlainStep: Boolean;
  protected
    function InitContext(NeedCertificate: Boolean): Boolean; override;
  public
    function Connect: Boolean; override;
  end;

  TSetHostFunc = function(ssl: PSSL; const host: PAnsiChar): cint; cdecl;
  TCtxFunc = function(ctx: PSSL_CTX): cint; cdecl;
  TGetCtxFunc = function(ssl: PSSL): PSSL_CTX; cdecl;
  TVerifyStringFunc = function(n: clong): PAnsiChar; cdecl;

{ ---------------- proxy settings from the environment ---------------- }

function EnvAny(const Names: array of string): string;
var
  N: string;
begin
  for N in Names do
  begin
    Result := GetEnv(N);
    if Result <> '' then
      Exit;
  end;
  Result := '';
end;

function BypassProxy(const Host: string): Boolean;
var
  Item, Entry, H: string;
begin
  H := LowerCase(Host);
  if (H = 'localhost') or (H = '127.0.0.1') or (H = '::1') or H.EndsWith('.localhost') then
    Exit(True);
  for Item in LowerCase(EnvAny(['NO_PROXY', 'no_proxy'])).Split([',', ' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    Entry := Item;
    if Entry = '*' then
      Exit(True);
    if Entry.StartsWith('*.') then
      System.Delete(Entry, 1, 1);
    if Entry[1] = '.' then
    begin
      if H.EndsWith(Entry) or (H = Copy(Entry, 2, MaxInt)) then
        Exit(True);
    end
    else if (H = Entry) or H.EndsWith('.' + Entry) then
      Exit(True);
  end;
  Result := False;
end;

{ 'http://user:pass@host:port/' -> parts }
procedure SplitProxy(const Url: string; out Host: string; out Port: Word; out User, Pass: string);
var
  S, Auth: string;
  I: Integer;
begin
  S := Url;
  I := Pos('://', S);
  if I > 0 then
    Delete(S, 1, I + 2);
  I := Pos('/', S);
  if I > 0 then
    SetLength(S, I - 1);
  User := '';
  Pass := '';
  I := LastDelimiter('@', S);
  if I > 0 then
  begin
    Auth := Copy(S, 1, I - 1);
    Delete(S, 1, I);
    I := Pos(':', Auth);
    if I > 0 then
    begin
      User := Copy(Auth, 1, I - 1);
      Pass := Copy(Auth, I + 1, MaxInt);
    end
    else
      User := Auth;
  end;
  I := LastDelimiter(':', S);
  if I > 0 then
  begin
    Host := Copy(S, 1, I - 1);
    Port := StrToIntDef(Copy(S, I + 1, MaxInt), 8080);
  end
  else
  begin
    Host := S;
    Port := 8080;
  end;
end;

function HostOf(const Url: string; out IsHttps: Boolean): string;
var
  S: string;
  I: Integer;
begin
  S := Url;
  IsHttps := LowerCase(Copy(S, 1, 8)) = 'https://';
  I := Pos('://', S);
  if I > 0 then
    Delete(S, 1, I + 2);
  I := Pos('/', S);
  if I > 0 then
    SetLength(S, I - 1);
  I := Pos('?', S);
  if I > 0 then
    SetLength(S, I - 1);
  I := LastDelimiter('@', S);
  if I > 0 then
    Delete(S, 1, I);
  I := LastDelimiter(':', S);
  if I > 0 then
    SetLength(S, I - 1);
  Result := S;
end;

{ ---------------- the client ---------------- }

procedure TPastelHttpClient.GetHandler(Sender: TObject; const UseSSL: Boolean; out AHandler: TSocketHandler);
var
  H: TPastelSSLHandler;
begin
  AHandler := nil;
  if UseSSL then
  begin
    H := TPastelSSLHandler.Create;
    H.FOwner := Self;
    H.SendHostAsSNI := False;     // the socket's host may be the proxy
    H.VerifyPeerCert := FVerify;
    AHandler := H;
  end;
end;

procedure TPastelHttpClient.Redirected(Sender: TObject; const ASrc: string; var ADest: string);
begin
  { the body of the redirect answer is not part of the result }
  if FOutput <> nil then
  begin
    FOutput.Size := 0;
    FOutput.Position := 0;
  end;
end;

procedure TPastelHttpClient.DataReceived(Sender: TObject; const ContentLength, CurrentPos: Int64);
begin
  if Assigned(FOnProgressCb) then
    FOnProgressCb(CurrentPos, ContentLength);
end;

procedure TPastelHttpClient.DoMethod(const AMethod, AURL: string; Stream: TStream;
  const AllowedResponseCodes: array of Integer);
var
  Host, PHost, PUser, PPass, ProxyUrl: string;
  PPort: Word;
  IsHttps: Boolean;
begin
  { decided again for every address, since a redirect can go anywhere }
  Host := HostOf(AURL, IsHttps);
  FTargetHost := Host;
  FLastUrl := AURL;
  FTunnelHost := '';
  Proxy.Host := '';
  Proxy.Port := 0;
  ProxyUrl := FProxyUrl;
  if ProxyUrl = '' then
    if IsHttps then
      ProxyUrl := EnvAny(['HTTPS_PROXY', 'https_proxy', 'ALL_PROXY', 'all_proxy'])
    else
      ProxyUrl := EnvAny(['HTTP_PROXY', 'http_proxy', 'ALL_PROXY', 'all_proxy']);
  if (ProxyUrl <> '') and (LowerCase(ProxyUrl) <> 'none') and not BypassProxy(Host) then
  begin
    SplitProxy(ProxyUrl, PHost, PPort, PUser, PPass);
    if IsHttps then
    begin
      FTunnelHost := PHost;
      FTunnelPort := PPort;
      FTunnelAuth := '';
      if PUser <> '' then
        FTunnelAuth := EncodeStringBase64(PUser + ':' + PPass);
    end
    else
    begin
      Proxy.Host := PHost;
      Proxy.Port := PPort;
      Proxy.UserName := PUser;
      Proxy.Password := PPass;
    end;
  end;
  inherited DoMethod(AMethod, AURL, Stream, AllowedResponseCodes);
end;

procedure TPastelHttpClient.ConnectToServer(const AHost: string; APort: Integer; UseSSL: Boolean);
begin
  FFailure := '';
  if UseSSL and (FTunnelHost <> '') then
  begin
    { connect to the proxy; the handler asks it for a tunnel to AHost }
    if APort = 0 then
      APort := 443;
    FTargetHost := AHost + ':' + IntToStr(APort);
    inherited ConnectToServer(FTunnelHost, FTunnelPort, True);
  end
  else
    inherited ConnectToServer(AHost, APort, UseSSL);
end;

{ ---------------- TLS ---------------- }

var
  SetHostProc: TSetHostFunc = nil;
  DefaultPathsProc: TCtxFunc = nil;
  GetCtxProc: TGetCtxFunc = nil;
  VerifyStringProc: TVerifyStringFunc = nil;
  ExtraLoaded: Boolean = False;

procedure LoadExtra;
begin
  if ExtraLoaded then
    Exit;
  ExtraLoaded := True;
  if SSLLibHandle <> 0 then
  begin
    Pointer(SetHostProc) := GetProcedureAddress(SSLLibHandle, 'SSL_set1_host');
    Pointer(GetCtxProc) := GetProcedureAddress(SSLLibHandle, 'SSL_get_SSL_CTX');
    Pointer(DefaultPathsProc) := GetProcedureAddress(SSLLibHandle, 'SSL_CTX_set_default_verify_paths');
  end;
  if SSLUtilHandle <> 0 then
    Pointer(VerifyStringProc) := GetProcedureAddress(SSLUtilHandle, 'X509_verify_cert_error_string');
end;

function PlainHost(const HostPort: string): string;
var
  I: Integer;
begin
  Result := HostPort;
  I := LastDelimiter(':', Result);
  if I > 0 then
    SetLength(Result, I - 1);
end;

function FileFromEnvOrNear(out FileName: string): Boolean;
begin
  FileName := GetEnv('SSL_CERT_FILE');
  if (FileName <> '') and FileExists(FileName) then
    Exit(True);
  { Windows has no OpenSSL certificate store: a cacert.pem next to the
    program (https://curl.se/ca/cacert.pem) is used when present. }
  FileName := ExtractFilePath(ParamStr(0)) + 'cacert.pem';
  Result := FileExists(FileName);
end;

function TPastelSSLHandler.InitContext(NeedCertificate: Boolean): Boolean;
var
  Host, CaFile: string;
  Ctx: PSSL_CTX;
begin
  if VerifyPeerCert and FileFromEnvOrNear(CaFile) then
    CertificateData.CertCA.FileName := CaFile;
  Result := inherited InitContext(NeedCertificate);
  if not Result or (SSL = nil) then
    Exit;
  LoadExtra;
  Host := PlainHost(FOwner.FTargetHost);
  if VerifyPeerCert and Assigned(GetCtxProc) and Assigned(DefaultPathsProc) then
  begin
    Ctx := GetCtxProc(SSL.SSL);
    if Ctx <> nil then
      DefaultPathsProc(Ctx);
  end;
  if Host <> '' then
  begin
    SSL.Ctrl(SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, PAnsiChar(AnsiString(Host)));
    if VerifyPeerCert and Assigned(SetHostProc) then
      SetHostProc(SSL.SSL, PAnsiChar(AnsiString(Host)));
  end;
end;

function SendAll(H: THandle; const S: string): Boolean;
var
  Done, N: Integer;
begin
  Done := 0;
  while Done < Length(S) do
  begin
    N := fpSend(H, @S[Done + 1], Length(S) - Done, 0);
    if N <= 0 then
      Exit(False);
    Inc(Done, N);
  end;
  Result := True;
end;

function TPastelSSLHandler.OpenTunnel: Boolean;
var
  Req, Answer, Line: string;
  C: Char;
  N, Code: Integer;
begin
  Req := 'CONNECT ' + FOwner.FTargetHost + ' HTTP/1.1'#13#10 +
         'Host: ' + FOwner.FTargetHost + #13#10;
  if FOwner.FTunnelAuth <> '' then
    Req := Req + 'Proxy-Authorization: Basic ' + FOwner.FTunnelAuth + #13#10;
  Req := Req + #13#10;
  if not SendAll(Socket.Handle, Req) then
  begin
    FOwner.FFailure := 'the proxy closed the connection';
    Exit(False);
  end;
  { read the proxy's answer byte by byte, up to the empty line, so that
    nothing of the TLS data after it is taken away }
  Answer := '';
  repeat
    N := fpRecv(Socket.Handle, @C, 1, 0);
    if N <= 0 then
      Break;
    Answer := Answer + C;
  until (Length(Answer) > 16384) or Answer.EndsWith(#13#10#13#10);
  Line := Copy(Answer, 1, Pos(#13, Answer + #13) - 1);
  { 'HTTP/1.1 200 Connection established' }
  Code := StrToIntDef(Copy(Line, Pos(' ', Line) + 1, 3), 0);
  Result := (Code >= 200) and (Code < 300);
  if not Result then
    if Line = '' then
      FOwner.FFailure := Format('the proxy %s did not answer', [FOwner.FTunnelHost])
    else if Code = 407 then
      FOwner.FFailure := Format('the proxy %s wants a user name and password (http://user:pass@host:port)', [FOwner.FTunnelHost])
    else
      FOwner.FFailure := Format('the proxy %s refused the connection to %s: %s',
        [FOwner.FTunnelHost, FOwner.FTargetHost, Line]);
end;

function TPastelSSLHandler.Connect: Boolean;
var
  V: clong;
  Why: string;
begin
  if FOwner.FTunnelHost <> '' then
    if not OpenTunnel then
      Exit(False);
  if Assigned(FBeforeTls) then
    if not PlainStep then
      Exit(False);
  Result := inherited Connect;
  if not Result and (FOwner.FFailure = '') then
  begin
    V := 0;
    if SSL <> nil then
      V := SSLGetVerifyResult(SSL.SSL);
    LoadExtra;
    if (V <> 0) and VerifyPeerCert then
    begin
      if Assigned(VerifyStringProc) then
        Why := string(VerifyStringProc(V))
      else
        Why := 'error ' + IntToStr(V);
      FOwner.FFailure := Format('certificate of "%s" is not trusted: %s', [PlainHost(FOwner.FTargetHost), Why]);
      {$IFDEF WINDOWS}
      if V = 20 then
        FOwner.FFailure := FOwner.FFailure + ' (put cacert.pem from https://curl.se/ca/cacert.pem next to the program, or set SSL_CERT_FILE)';
      {$ENDIF}
    end
    else
    begin
      Why := Trim(SSLLastErrorString);
      if Why = '' then
        Why := 'the server closed the connection';
      FOwner.FFailure := Format('secure connection to "%s" failed: %s', [PlainHost(FOwner.FTargetHost), Why]);
    end;
  end;
end;

{$ENDIF}

{ ---------------- connections of other protocols ---------------- }

procedure TNetConnection.SetReadTimeout(Ms: Integer);
begin
end;

procedure TNetConnection.WriteText(const S: RawByteString);
begin
  if S <> '' then
    Write(S[1], Length(S));
end;

function TNetConnection.ReadLine: string;
var
  C: Char;
begin
  Result := '';
  repeat
    if Read(C, 1) <> 1 then
      raise ENetError.Create('the connection was closed');
    if C = #10 then
      Break;
    if C <> #13 then
      Result := Result + C;
    if Length(Result) > 65536 then
      raise ENetError.Create('a line too long came');
  until False;
end;

{$IFNDEF ANDROID}
type
  { a plain socket's handle, before TLS }
  TPlainConnection = class(TNetConnection)
  private
    FHandle: THandle;
  public
    function Read(var Buffer; Count: Integer): Integer; override;
    procedure Write(const Buffer; Count: Integer); override;
    procedure Shutdown; override;
  end;

  TSocketConnection = class(TNetConnection)
  private
    FSocket: TSocketStream;
    FOwner: TPastelHttpClient;
  public
    destructor Destroy; override;
    function Read(var Buffer; Count: Integer): Integer; override;
    procedure Write(const Buffer; Count: Integer); override;
    procedure Shutdown; override;
    procedure SetReadTimeout(Ms: Integer); override;
  end;

procedure TSocketConnection.SetReadTimeout(Ms: Integer);
begin
  FSocket.IOTimeout := Ms;
end;

function TPlainConnection.Read(var Buffer; Count: Integer): Integer;
begin
  Result := fpRecv(FHandle, @Buffer, Count, 0);
  if Result < 0 then
    raise ENetError.Create('the connection broke');
end;

procedure TPlainConnection.Write(const Buffer; Count: Integer);
var
  Done, N: Integer;
begin
  Done := 0;
  while Done < Count do
  begin
    N := fpSend(FHandle, PByte(@Buffer) + Done, Count - Done, 0);
    if N <= 0 then
      raise ENetError.Create('the connection broke');
    Inc(Done, N);
  end;
end;

procedure TPlainConnection.Shutdown;
begin
  fpShutdown(FHandle, 2);
end;

function TPastelSSLHandler.PlainStep: Boolean;
var
  C: TPlainConnection;
begin
  C := TPlainConnection.Create;
  try
    C.FHandle := Socket.Handle;
    try
      FOwner.FFailure := FBeforeTls(C);
    except
      on E: Exception do
        FOwner.FFailure := E.Message;
    end;
    Result := FOwner.FFailure = '';
  finally
    C.Free;
  end;
end;

destructor TSocketConnection.Destroy;
begin
  FSocket.Free;
  FOwner.Free;
  inherited Destroy;
end;

function TSocketConnection.Read(var Buffer; Count: Integer): Integer;
begin
  Result := FSocket.Read(Buffer, Count);
  if Result < 0 then
    raise ENetError.Create('the connection broke');
end;

procedure TSocketConnection.Write(const Buffer; Count: Integer);
var
  Done, N: Integer;
begin
  Done := 0;
  while Done < Count do
  begin
    N := FSocket.Write((PByte(@Buffer) + Done)^, Count - Done);
    if N <= 0 then
      raise ENetError.Create('the connection broke');
    Inc(Done, N);
  end;
end;

procedure TSocketConnection.Shutdown;
begin
  fpShutdown(FSocket.Handle, 2);
end;
{$ENDIF}

{$IFDEF ANDROID}
type
  { Android's own sockets and TLS (dev.pastel.PastelSocket): bytes as ISO-8859-1 strings }
  TJavaConnection = class(TNetConnection)
  private
    FObj: TJavaObject;
  public
    function Read(var Buffer; Count: Integer): Integer; override;
    procedure Write(const Buffer; Count: Integer); override;
    procedure Shutdown; override;
    procedure SetReadTimeout(Ms: Integer); override;
  end;

const
  SocketClass = 'dev.pastel.PastelSocket';

function TJavaConnection.Read(var Buffer; Count: Integer): Integer;
var
  R: TJavaObject;
  W: UnicodeString;
  I: Integer;
begin
  if Count > 65536 then
    Count := 65536;
  try
    R := JavaCallO(FObj, SocketClass, 'read', '(I)Ljava/lang/String;', [Count]);
  except
    on E: EJavaError do
      raise ENetError.Create('the connection broke: ' + E.Message);
  end;
  if R.IsNull then
    Exit(0);
  W := UTF8Decode(R.ToString);
  if W = '' then
    Exit(-1);         { nothing within the read timeout }
  for I := 1 to Length(W) do
    PByte(@Buffer)[I - 1] := Ord(W[I]);
  Result := Length(W);
end;

procedure TJavaConnection.Write(const Buffer; Count: Integer);
var
  W: UnicodeString;
  I: Integer;
begin
  SetLength(W, Count);
  for I := 1 to Count do
    W[I] := WideChar(PByte(@Buffer)[I - 1]);
  try
    JavaCall(FObj, SocketClass, 'write', '(Ljava/lang/String;)V', [UTF8Encode(W)]);
  except
    on E: EJavaError do
      raise ENetError.Create('the connection broke: ' + E.Message);
  end;
end;

procedure TJavaConnection.Shutdown;
begin
  try
    JavaCall(FObj, SocketClass, 'close', '()V', []);
  except
  end;
end;

procedure TJavaConnection.SetReadTimeout(Ms: Integer);
begin
  JavaCall(FObj, SocketClass, 'setReadTimeout', '(I)V', [Ms]);
end;

{ "java.net.UnknownHostException: x" -> what it means }
function JavaNetReason(const Msg, Host: string; Port: Integer): string;
begin
  if Pos('UnknownHost', Msg) > 0 then
    Result := Format('cannot find server "%s" (check the address and the network)', [Host])
  else if (Pos('ConnectException', Msg) > 0) or (Pos('SocketTimeout', Msg) > 0) then
    Result := Format('cannot connect to %s:%d (is the server running? is the port right?)', [Host, Port])
  else
  begin
    Result := Msg;
    { "PastelSocket.open: java.io.IOException: certificate of ..." -> "certificate of ..." }
    if Pos('IOException: ', Result) > 0 then
      Result := Copy(Result, Pos('IOException: ', Result) + 13, MaxInt);
  end;
end;
{$ENDIF}

function NetConnect(const Host: string; Port: Integer; Tls: Boolean; BeforeTls: TBeforeTlsEvent;
  Timeout: Integer; Verify: Boolean; ReadTimeout: Integer): TNetConnection;
var
  Why: string;
  {$IFDEF ANDROID}
  J: TJavaConnection;
  {$ELSE}
  C: TSocketConnection;
  H: TPastelSSLHandler;
  {$ENDIF}
begin
  {$IFDEF ANDROID}
  if Assigned(BeforeTls) and not Tls then
    raise ENetError.Create('BeforeTls is for a connection that becomes TLS');
  J := TJavaConnection.Create;
  try
    try
      J.FObj := JavaStaticO(SocketClass, 'open', '(Ljava/lang/String;IZZI)Ldev/pastel/PastelSocket;',
        [Host, Port, Tls and not Assigned(BeforeTls), Verify, Timeout]);
    except
      on E: EJavaError do
        raise ENetError.Create(JavaNetReason(E.Message, Host, Port));
    end;
    if Assigned(BeforeTls) then
    begin
      Why := BeforeTls(J);
      if Why <> '' then
        raise ENetError.Create(Why);
      try
        JavaCall(J.FObj, SocketClass, 'startTls', '()V', []);
      except
        on E: EJavaError do
          raise ENetError.Create(JavaNetReason(E.Message, Host, Port));
      end;
    end;
    J.SetReadTimeout(ReadTimeout);
    Result := J;
  except
    J.Shutdown;
    J.Free;
    raise;
  end;
  {$ELSE}
  if Assigned(BeforeTls) and not Tls then
    raise ENetError.Create('BeforeTls is for a connection that becomes TLS');
  {$IFDEF UNIX}
  { a peer that went away must be an error of a write, not the end of the program (TLS writes cannot say MSG_NOSIGNAL) }
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}
  C := TSocketConnection.Create;
  try
    H := nil;
    if Tls then
    begin
      C.FOwner := TPastelHttpClient.Create(nil);
      C.FOwner.FTargetHost := Host;
      C.FOwner.FVerify := Verify;
      H := TPastelSSLHandler.Create;
      H.FOwner := C.FOwner;
      H.FBeforeTls := BeforeTls;
      H.SendHostAsSNI := False;     // set by InitContext
      H.VerifyPeerCert := Verify;
    end;
    try
      C.FSocket := TInetSocket.Create(Host, Port, Timeout, H);
      { with a handler the socket waits for Connect }
      C.FSocket.IOTimeout := ReadTimeout;     { also for BeforeTls' plain lines }
      if H <> nil then
        TInetSocket(C.FSocket).Connect;
    except
      on E: Exception do
      begin
        Why := E.Message;
        if (C.FOwner <> nil) and (C.FOwner.FFailure <> '') then
          Why := C.FOwner.FFailure
        else if Pos('resolve', LowerCase(Why)) > 0 then
          Why := Format('cannot find server "%s" (check the address and the network)', [Host])
        else if Pos('connect', LowerCase(Why)) > 0 then
          Why := Format('cannot connect to %s:%d (is the server running? is the port right?)', [Host, Port]);
        raise ENetError.Create(Why);
      end;
    end;
    Result := C;
  except
    C.Free;
    raise;
  end;
  {$ENDIF}
end;

{ ---------------- THttpResponse ---------------- }

function THttpResponse.Ok: Boolean;
begin
  Result := (Status >= 200) and (Status < 300);
end;

function THttpResponse.Header(const Name: string): string;
var
  H: string;
  I: Integer;
begin
  for H in Headers do
  begin
    I := Pos(':', H);
    if (I > 0) and SameText(Trim(Copy(H, 1, I - 1)), Name) then
      Exit(Trim(Copy(H, I + 1, MaxInt)));
  end;
  Result := '';
end;

function THttpResponse.Json: TJSONData;
begin
  try
    Result := ParseJson(Body);
  except
    on E: Exception do
      raise EHttpError.CreateFmt('%s %s: the answer is not valid JSON (%s)', [Method, Url, E.Message]);
  end;
end;

procedure THttpResponse.RaiseForStatus;
var
  E: EHttpError;
  Snippet: string;
begin
  if Ok then
    Exit;
  Snippet := Trim(Body);
  if Length(Snippet) > 200 then
    Snippet := Copy(Snippet, 1, 200) + '...';
  if Snippet <> '' then
    Snippet := ': ' + StringReplace(StringReplace(Snippet, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  E := EHttpError.CreateFmt('%s %s: %d %s%s', [Method, Url, Status, StatusText, Snippet]);
  E.Status := Status;
  E.Body := Body;
  raise E;
end;

{ ---------------- THttpClient ---------------- }

constructor THttpClient.Create(const ABaseUrl: string);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
  Timeout := 30000;
  FollowRedirects := True;
  VerifyCertificates := True;
  UserAgent := 'Pastel/1.0';
end;

function UrlEncode(const S: string): string;
const
  Safe = ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'];
var
  C: Char;
begin
  Result := '';
  for C in S do
    if C in Safe then
      Result := Result + C
    else
      Result := Result + '%' + IntToHex(Ord(C), 2);
end;

function QueryString(const Pairs: array of string): string;
var
  I: Integer;
begin
  if Odd(Length(Pairs)) then
    raise EHttpError.Create('QueryString needs names and values in pairs');
  Result := '';
  I := 0;
  while I < High(Pairs) do
  begin
    if Result <> '' then
      Result := Result + '&';
    Result := Result + UrlEncode(Pairs[I]) + '=' + UrlEncode(Pairs[I + 1]);
    Inc(I, 2);
  end;
end;

function THttpClient.MakeUrl(const Path: string; const Query: array of string): string;
var
  Q: string;
begin
  if (FBaseUrl = '') or (Pos('://', Path) > 0) then
    Result := Path
  else if Path = '' then
    Result := FBaseUrl
  else if FBaseUrl.EndsWith('/') and Path.StartsWith('/') then
    Result := FBaseUrl + Copy(Path, 2, MaxInt)
  else if FBaseUrl.EndsWith('/') or Path.StartsWith('/') or Path.StartsWith('?') then
    Result := FBaseUrl + Path
  else
    Result := FBaseUrl + '/' + Path;
  Q := QueryString(Query);
  if Q <> '' then
    if Pos('?', Result) > 0 then
      Result := Result + '&' + Q
    else
      Result := Result + '?' + Q;
end;

{$IFNDEF ANDROID}
procedure THttpClient.Fill(Client: TObject);
var
  C: TPastelHttpClient;
  H: string;
  I: Integer;
begin
  C := TPastelHttpClient(Client);
  C.OnGetSocketHandler := @C.GetHandler;
  C.OnRedirect := @C.Redirected;
  {$IFDEF WINDOWS}
  { Free Pascal's connect-with-timeout on Windows never notices a refused
    connection and waits the whole time; the system's own limit is used. }
  C.ConnectTimeout := 0;
  {$ELSE}
  C.ConnectTimeout := Timeout;
  {$ENDIF}
  C.IOTimeout := Timeout;
  C.AllowRedirect := FollowRedirects;
  C.MaxRedirects := 10;
  C.FVerify := VerifyCertificates;
  C.FProxyUrl := Proxy;
  C.FOnProgressCb := OnProgress;
  if Assigned(OnProgress) then
    C.OnDataReceived := @C.DataReceived;
  C.AddHeader('User-Agent', UserAgent);
  if BearerToken <> '' then
    C.AddHeader('Authorization', 'Bearer ' + BearerToken);
  C.UserName := UserName;
  C.Password := Password;
  for H in Headers do
  begin
    I := Pos(':', H);
    if I = 0 then
      raise EHttpError.CreateFmt('header "%s" must look like "Name: value"', [H]);
    C.AddHeader(Trim(Copy(H, 1, I - 1)), Trim(Copy(H, I + 1, MaxInt)));
  end;
end;

function Explain(E: Exception; const Method, Url, Failure: string): string;
var
  IsHttps: Boolean;
  Host: string;
begin
  Host := HostOf(Url, IsHttps);
  if Failure <> '' then
    Result := Failure
  else if E is ESocketError then
    case ESocketError(E).Code of
      seHostNotFound:
        Result := Format('cannot find server "%s" (check the address and the network)', [Host]);
      seConnectTimeOut:
        Result := Format('server "%s" did not answer in time', [Host]);
      seConnectFailed:
        Result := Format('cannot connect to "%s" (is the server running, and is the port right?)', [Host]);
    else
      Result := E.Message;
    end
  else if (E is EInOutError) and (Pos('OpenSSL', E.Message) > 0) then
    Result := 'HTTPS needs the OpenSSL library, which was not found' +
      {$IFDEF WINDOWS}' (put libssl-3-x64.dll and libcrypto-3-x64.dll next to the program)'
      {$ELSE}' (install it, for example: sudo apt install libssl3)'{$ENDIF}
  else if (E is EHTTPClient) and (Pos('socket', LowerCase(E.Message)) > 0) then
    Result := Format('the connection to "%s" was interrupted or timed out', [Host])
  else
    Result := E.Message;
  Result := Format('%s %s: %s', [Method, Url, Result]);
end;
{$ELSE}
procedure THttpClient.Fill(Client: TObject);
begin
end;
{$ENDIF}

{$IFDEF ANDROID}
{ Android: the phone's own HTTP and HTTPS (its certificates and proxy), through Pastel's
  activity; apps cannot load OpenSSL there. }
function AndroidSend(Client: THttpClient; const Method, Url: string; Body: TStream; const ContentType: string;
  Output: TStream): THttpResponse;
var
  Head, H, Answer, Data: RawByteString;
  Lines: TStringArray;
  M: string;
  I, P, Start: Integer;
  Started: QWord;
begin
  Result := Default(THttpResponse);
  Result.Method := Method;
  Result.Url := Url;
  Head := 'User-Agent: ' + Client.UserAgent + #10;
  if Client.BearerToken <> '' then
    Head := Head + 'Authorization: Bearer ' + Client.BearerToken + #10;
  if Client.UserName <> '' then
    Head := Head + 'Authorization: Basic ' + EncodeStringBase64(Client.UserName + ':' + Client.Password) + #10;
  for H in Client.Headers do
  begin
    if Pos(':', H) = 0 then
      raise EHttpError.CreateFmt('header "%s" must look like "Name: value"', [H]);
    Head := Head + H + #10;
  end;
  if (Body <> nil) and (ContentType <> '') then
    Head := Head + 'Content-Type: ' + ContentType + #10;
  { Android's HTTP has no PATCH: POST that says so (Pastel's web server understands it) }
  M := UpperCase(Method);
  if M = 'PATCH' then
  begin
    M := 'POST';
    Head := Head + 'X-HTTP-Method-Override: PATCH' + #10;
  end;
  Data := '';
  if Body <> nil then
  begin
    SetLength(Data, Body.Size - Body.Position);
    if Data <> '' then
      Body.ReadBuffer(Data[1], Length(Data));
  end;
  Started := GetTickCount64;
  Answer := AndroidHttp(M, Url, Head, Data, Body <> nil, Client.Timeout, Client.FollowRedirects,
    Client.VerifyCertificates);
  Result.Duration := GetTickCount64 - Started;
  { the head: status, its text, the final address, the headers, an empty line }
  P := Pos(#10#10, Answer);
  if P = 0 then
    P := Length(Answer) + 1;
  Lines := string(Copy(Answer, 1, P - 1)).Split([#10]);
  Start := P + 2;
  if (Length(Lines) < 1) or (StrToIntDef(Lines[0], 0) = 0) then
  begin
    if Length(Lines) > 1 then
      raise EHttpError.Create(Format('%s %s: %s', [Method, Url, Lines[1]]));
    raise EHttpError.Create(Format('%s %s: no answer', [Method, Url]));
  end;
  Result.Status := StrToInt(Lines[0]);
  if Length(Lines) > 1 then
    Result.StatusText := Trim(Lines[1]);
  if (Length(Lines) > 2) and (Lines[2] <> '') then
    Result.Url := Lines[2];
  for I := 3 to High(Lines) do
    Result.Headers := Concat(Result.Headers, [Lines[I]]);
  Data := Copy(Answer, Start, MaxInt);
  if Output <> nil then
  begin
    if Data <> '' then
      Output.WriteBuffer(Data[1], Length(Data));
    if Assigned(Client.OnProgress) then
      Client.OnProgress(Length(Data), Length(Data));
  end
  else
  begin
    Result.Body := Data;
    SetCodePage(RawByteString(Result.Body), CP_UTF8, False);
  end;
end;
{$ENDIF}

{$IFDEF WINDOWS}
{ Windows: the system's own HTTP and HTTPS (WinINet): its certificates, its
  proxy settings, no OpenSSL DLLs next to the program. }
const
  WinInetDll = 'wininet.dll';
  INTERNET_OPEN_TYPE_PRECONFIG = 0;
  INTERNET_OPEN_TYPE_PROXY = 3;
  INTERNET_SERVICE_HTTP = 3;
  INTERNET_OPTION_CONNECT_TIMEOUT = 2;
  INTERNET_OPTION_SEND_TIMEOUT = 5;
  INTERNET_OPTION_RECEIVE_TIMEOUT = 6;
  INTERNET_OPTION_SECURITY_FLAGS = 31;
  INTERNET_OPTION_URL = 34;
  INTERNET_FLAG_RELOAD = $80000000;
  INTERNET_FLAG_NO_CACHE_WRITE = $04000000;
  INTERNET_FLAG_SECURE = $00800000;
  INTERNET_FLAG_NO_AUTO_REDIRECT = $00200000;
  INTERNET_FLAG_NO_COOKIES = $00080000;
  INTERNET_FLAG_NO_UI = $00000200;
  INTERNET_FLAG_IGNORE_CERT_CN_INVALID = $00001000;
  INTERNET_FLAG_IGNORE_CERT_DATE_INVALID = $00002000;
  SECURITY_FLAG_IGNORE_UNKNOWN_CA = $00000100;
  SECURITY_FLAG_IGNORE_REVOCATION = $00000080;
  HTTP_QUERY_STATUS_CODE = 19;
  HTTP_QUERY_STATUS_TEXT = 20;
  HTTP_QUERY_RAW_HEADERS_CRLF = 22;
  HTTP_QUERY_CONTENT_LENGTH = 5;
  HTTP_QUERY_FLAG_NUMBER = $20000000;

type
  HINTERNET = Pointer;

function InternetOpenW(Agent: PWideChar; AccessType: LongWord; Proxy, Bypass: PWideChar; Flags: LongWord): HINTERNET;
  stdcall; external WinInetDll;
function InternetConnectW(H: HINTERNET; Server: PWideChar; Port: Word; User, Password: PWideChar; Service, Flags: LongWord;
  Context: PtrUInt): HINTERNET; stdcall; external WinInetDll;
function HttpOpenRequestW(H: HINTERNET; Verb, ObjectName, Version, Referrer: PWideChar; AcceptTypes: Pointer;
  Flags: LongWord; Context: PtrUInt): HINTERNET; stdcall; external WinInetDll;
function HttpSendRequestW(H: HINTERNET; Headers: PWideChar; HeadersLength: LongWord; Optional: Pointer;
  OptionalLength: LongWord): LongBool; stdcall; external WinInetDll;
function HttpQueryInfoW(H: HINTERNET; Level: LongWord; Buffer: Pointer; var BufferLength: LongWord;
  Index: PLongWord): LongBool; stdcall; external WinInetDll;
function InternetReadFile(H: HINTERNET; Buffer: Pointer; ToRead: LongWord; var Read: LongWord): LongBool;
  stdcall; external WinInetDll;
function InternetSetOptionW(H: HINTERNET; Option: LongWord; Buffer: Pointer; BufferLength: LongWord): LongBool;
  stdcall; external WinInetDll;
function InternetQueryOptionW(H: HINTERNET; Option: LongWord; Buffer: Pointer; var BufferLength: LongWord): LongBool;
  stdcall; external WinInetDll;
function InternetCloseHandle(H: HINTERNET): LongBool; stdcall; external WinInetDll;
function WinGetLastError: LongWord; stdcall; external 'kernel32.dll' name 'GetLastError';

function WinInetQuery(H: HINTERNET; Level: LongWord): string;
var
  Buf: UnicodeString;
  Len: LongWord;
begin
  Result := '';
  Len := 0;
  HttpQueryInfoW(H, Level, nil, Len, nil);
  if Len = 0 then
    Exit;
  SetLength(Buf, Len div 2 + 1);
  if HttpQueryInfoW(H, Level, @Buf[1], Len, nil) then
  begin
    SetLength(Buf, Len div 2);
    Result := UTF8Encode(Buf);
  end;
end;

function WinInetError(Code: LongWord; const Host: string): string;
begin
  case Code of
    12007: Result := Format('cannot find server "%s" (check the address and the network)', [Host]);
    12002: Result := Format('server "%s" did not answer in time', [Host]);
    12029, 12030, 12031: Result := Format('cannot connect to "%s" (is the server running, and is the port right?)', [Host]);
    12037, 12038, 12044, 12045, 12057, 12169, 12175:
      Result := Format('the certificate of "%s" is not trusted (VerifyCertificates := False only for your own test servers)', [Host]);
  else
    Result := Format('Windows'' HTTP error %d', [Code]);
  end;
end;

function WinSend(Client: THttpClient; const Method, Url: string; Body: TStream; const ContentType: string;
  Output: TStream): THttpResponse;
var
  Inet, Conn, Req: HINTERNET;
  IsHttps: Boolean;
  Scheme, Rest, HostPort, Host, Path, Head, H, Data, Raw, Agent: string;
  Port, Slash, Colon, I: Integer;
  Flags, Sec, Len, Ms, Got, Code, Status: LongWord;
  Buf: array[0..65535] of Byte;
  Total, Done: Int64;
  Started: QWord;
  Lines: TStringArray;
  UrlBuf: UnicodeString;
  WHead, WMethod, WPath, WHost, WAgent, WProxy: UnicodeString;
  Own: TStringStream;
begin
  Result := Default(THttpResponse);
  Result.Method := Method;
  Result.Url := Url;
  I := Pos('://', Url);
  Scheme := LowerCase(Copy(Url, 1, I - 1));
  Rest := Copy(Url, I + 3, MaxInt);
  IsHttps := Scheme = 'https';
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    HostPort := Rest;
    Path := '/';
  end
  else
  begin
    HostPort := Copy(Rest, 1, Slash - 1);
    Path := Copy(Rest, Slash, MaxInt);
  end;
  if Pos('?', HostPort) > 0 then
  begin
    Path := '/' + Copy(HostPort, Pos('?', HostPort), MaxInt);
    HostPort := Copy(HostPort, 1, Pos('?', HostPort) - 1);
  end;
  Colon := LastDelimiter(':]', HostPort);
  if (Colon > 0) and (HostPort[Colon] = ':') then
  begin
    Host := Copy(HostPort, 1, Colon - 1);
    Port := StrToIntDef(Copy(HostPort, Colon + 1, MaxInt), 0);
  end
  else
  begin
    Host := HostPort;
    if IsHttps then Port := 443 else Port := 80;
  end;
  Host := StringReplace(StringReplace(Host, '[', '', []), ']', '', []);
  Agent := Client.UserAgent;
  WAgent := UTF8Decode(Agent);
  if Client.Proxy <> '' then
  begin
    WProxy := UTF8Decode(StringReplace(StringReplace(Client.Proxy, 'http://', '', []), '/', '', [rfReplaceAll]));
    Inet := InternetOpenW(PWideChar(WAgent), INTERNET_OPEN_TYPE_PROXY, PWideChar(WProxy), nil, 0);
  end
  else
    Inet := InternetOpenW(PWideChar(WAgent), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Inet = nil then
    raise EHttpError.CreateFmt('%s %s: Windows'' HTTP could not start (%d)', [Method, Url, WinGetLastError]);
  Conn := nil;
  Req := nil;
  Own := nil;
  try
    Ms := Client.Timeout;
    InternetSetOptionW(Inet, INTERNET_OPTION_CONNECT_TIMEOUT, @Ms, 4);
    InternetSetOptionW(Inet, INTERNET_OPTION_SEND_TIMEOUT, @Ms, 4);
    InternetSetOptionW(Inet, INTERNET_OPTION_RECEIVE_TIMEOUT, @Ms, 4);
    WHost := UTF8Decode(Host);
    Conn := InternetConnectW(Inet, PWideChar(WHost), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    if Conn = nil then
      raise EHttpError.CreateFmt('%s %s: %s', [Method, Url, WinInetError(WinGetLastError, Host)]);
    Flags := INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_NO_COOKIES or INTERNET_FLAG_NO_UI;
    if IsHttps then
      Flags := Flags or INTERNET_FLAG_SECURE;
    if not Client.FollowRedirects then
      Flags := Flags or INTERNET_FLAG_NO_AUTO_REDIRECT;
    if IsHttps and not Client.VerifyCertificates then
      Flags := Flags or INTERNET_FLAG_IGNORE_CERT_CN_INVALID or INTERNET_FLAG_IGNORE_CERT_DATE_INVALID;
    WMethod := UTF8Decode(UpperCase(Method));
    WPath := UTF8Decode(Path);
    Req := HttpOpenRequestW(Conn, PWideChar(WMethod), PWideChar(WPath), nil, nil, nil, Flags, 0);
    if Req = nil then
      raise EHttpError.CreateFmt('%s %s: %s', [Method, Url, WinInetError(WinGetLastError, Host)]);
    if IsHttps and not Client.VerifyCertificates then
    begin
      Len := 4;
      Sec := 0;
      InternetQueryOptionW(Req, INTERNET_OPTION_SECURITY_FLAGS, @Sec, Len);
      Sec := Sec or SECURITY_FLAG_IGNORE_UNKNOWN_CA or SECURITY_FLAG_IGNORE_REVOCATION;
      InternetSetOptionW(Req, INTERNET_OPTION_SECURITY_FLAGS, @Sec, 4);
    end;
    Head := '';
    if Client.BearerToken <> '' then
      Head := Head + 'Authorization: Bearer ' + Client.BearerToken + #13#10;
    if Client.UserName <> '' then
      Head := Head + 'Authorization: Basic ' + EncodeStringBase64(Client.UserName + ':' + Client.Password) + #13#10;
    for H in Client.Headers do
    begin
      if Pos(':', H) = 0 then
        raise EHttpError.CreateFmt('header "%s" must look like "Name: value"', [H]);
      Head := Head + H + #13#10;
    end;
    if (Body <> nil) and (ContentType <> '') then
      Head := Head + 'Content-Type: ' + ContentType + #13#10;
    Data := '';
    if Body <> nil then
    begin
      SetLength(Data, Body.Size - Body.Position);
      if Data <> '' then
        Body.ReadBuffer(Data[1], Length(Data));
    end;
    WHead := UTF8Decode(Head);
    Started := GetTickCount64;
    if not HttpSendRequestW(Req, PWideChar(WHead), Length(WHead), Pointer(Data), Length(Data)) then
    begin
      Code := WinGetLastError;
      raise EHttpError.CreateFmt('%s %s: %s', [Method, Url, WinInetError(Code, Host)]);
    end;
    Status := 0;
    Len := 4;
    HttpQueryInfoW(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Status, Len, nil);
    Result.Status := Status;
    Result.StatusText := Trim(WinInetQuery(Req, HTTP_QUERY_STATUS_TEXT));
    Raw := WinInetQuery(Req, HTTP_QUERY_RAW_HEADERS_CRLF);
    Lines := Raw.Split([#13#10], TStringSplitOptions.ExcludeEmpty);
    for I := 1 to High(Lines) do
      Result.Headers := Concat(Result.Headers, [Lines[I]]);
    SetLength(UrlBuf, 4096);
    Len := Length(UrlBuf) * 2;
    if InternetQueryOptionW(Req, INTERNET_OPTION_URL, @UrlBuf[1], Len) then
      Result.Url := UTF8Encode(Copy(UrlBuf, 1, Len div 2));
    Total := StrToInt64Def(Result.Header('Content-Length'), 0);
    if Output = nil then
    begin
      Own := TStringStream.Create('');
      Output := Own;
    end;
    Done := 0;
    repeat
      Got := 0;
      if not InternetReadFile(Req, @Buf[0], SizeOf(Buf), Got) then
        raise EHttpError.CreateFmt('%s %s: the connection to "%s" was interrupted or timed out', [Method, Url, Host]);
      if Got > 0 then
      begin
        Output.WriteBuffer(Buf[0], Got);
        Inc(Done, Got);
        if Assigned(Client.OnProgress) and (Own = nil) then
          Client.OnProgress(Done, Total);
      end;
    until Got = 0;
    Result.Duration := GetTickCount64 - Started;
    if Own <> nil then
    begin
      Result.Body := Own.DataString;
      SetCodePage(RawByteString(Result.Body), CP_UTF8, False);
    end;
  finally
    Own.Free;
    if Req <> nil then
      InternetCloseHandle(Req);
    if Conn <> nil then
      InternetCloseHandle(Conn);
    InternetCloseHandle(Inet);
  end;
end;
{$ENDIF}

{$IFDEF ANDROID}
function THttpClient.Send(const Method, Url: string; Body: TStream; const ContentType: string;
  Output: TStream): THttpResponse;
begin
  if not (LowerCase(Url).StartsWith('http://') or LowerCase(Url).StartsWith('https://')) then
    raise EHttpError.CreateFmt('"%s" is not an http:// or https:// address', [Url]);
  Result := AndroidSend(Self, Method, Url, Body, ContentType, Output);
end;
{$ELSE}
function THttpClient.Send(const Method, Url: string; Body: TStream; const ContentType: string;
  Output: TStream): THttpResponse;
var
  C: TPastelHttpClient;
  Own: TStringStream;
  Start: QWord;
  I: Integer;
begin
  Result := Default(THttpResponse);
  Result.Method := Method;
  Result.Url := Url;
  if not (LowerCase(Url).StartsWith('http://') or LowerCase(Url).StartsWith('https://')) then
    raise EHttpError.CreateFmt('"%s" is not an http:// or https:// address', [Url]);
  {$IFDEF WINDOWS}
  { Windows' own HTTP (PASTEL_HTTP=fpc: Free Pascal's, with OpenSSL's DLLs) }
  if not SameText(SysUtils.GetEnvironmentVariable('PASTEL_HTTP'), 'fpc') then
    Exit(WinSend(Self, Method, Url, Body, ContentType, Output));
  {$ENDIF}
  Own := nil;
  C := TPastelHttpClient.Create(nil);
  try
    Fill(C);
    if Output = nil then
    begin
      Own := TStringStream.Create('');
      Output := Own;
    end;
    C.FOutput := Output;
    if Body <> nil then
    begin
      C.RequestBody := Body;
      if ContentType <> '' then
        C.AddHeader('Content-Type', ContentType);
    end;
    Start := GetTickCount64;
    try
      C.HTTPMethod(Method, Url, Output, []);
    except
      on E: EHttpError do
        raise;
      on E: Exception do
        raise EHttpError.Create(Explain(E, Method, Url, C.FFailure));
    end;
    Result.Duration := GetTickCount64 - Start;
    Result.Status := C.ResponseStatusCode;
    Result.StatusText := Trim(C.ResponseStatusText);
    SetLength(Result.Headers, C.ResponseHeaders.Count);
    for I := 0 to C.ResponseHeaders.Count - 1 do
      Result.Headers[I] := C.ResponseHeaders[I];
    if Own <> nil then
    begin
      Result.Body := Own.DataString;
      SetCodePage(RawByteString(Result.Body), CP_UTF8, False);
    end;
    { the address the answer finally came from }
    Result.Url := C.FLastUrl;
  finally
    C.RequestBody := nil;
    C.Free;
    Own.Free;
  end;
end;

{$ENDIF}

function THttpClient.Request(const Method, Path, Body, ContentType: string): THttpResponse;
var
  S: TStringStream;
begin
  if (Body = '') and (ContentType = '') then
    Exit(Send(Method, MakeUrl(Path, []), nil, '', nil));
  S := TStringStream.Create(Body);
  try
    Result := Send(Method, MakeUrl(Path, []), S, ContentType, nil);
  finally
    S.Free;
  end;
end;

function THttpClient.RequestTo(const Method, Path, Body, ContentType: string; Output: TStream): THttpResponse;
var
  S: TStringStream;
begin
  if (Body = '') and (ContentType = '') then
    Exit(Send(Method, MakeUrl(Path, []), nil, '', Output));
  S := TStringStream.Create(Body);
  try
    Result := Send(Method, MakeUrl(Path, []), S, ContentType, Output);
  finally
    S.Free;
  end;
end;

function THttpClient.Get(const Path: string): THttpResponse;
begin
  Result := Send('GET', MakeUrl(Path, []), nil, '', nil);
end;

function THttpClient.Get(const Path: string; const Query: array of string): THttpResponse;
begin
  Result := Send('GET', MakeUrl(Path, Query), nil, '', nil);
end;

function THttpClient.Delete(const Path: string): THttpResponse;
begin
  Result := Send('DELETE', MakeUrl(Path, []), nil, '', nil);
end;

function THttpClient.Head(const Path: string): THttpResponse;
begin
  Result := Send('HEAD', MakeUrl(Path, []), nil, '', nil);
end;

function THttpClient.Post(const Path, Body, ContentType: string): THttpResponse;
begin
  Result := Request('POST', Path, Body, ContentType);
end;

function THttpClient.Put(const Path, Body, ContentType: string): THttpResponse;
begin
  Result := Request('PUT', Path, Body, ContentType);
end;

function THttpClient.Patch(const Path, Body, ContentType: string): THttpResponse;
begin
  Result := Request('PATCH', Path, Body, ContentType);
end;

function THttpClient.PostJson(const Path, Json: string): THttpResponse;
begin
  Result := Request('POST', Path, Json, 'application/json');
end;

function THttpClient.PostJson(const Path: string; Json: TJSONData): THttpResponse;
begin
  Result := Request('POST', Path, Json.AsJSON, 'application/json');
end;

function THttpClient.PutJson(const Path, Json: string): THttpResponse;
begin
  Result := Request('PUT', Path, Json, 'application/json');
end;

function THttpClient.PostForm(const Path: string; const Fields: array of string): THttpResponse;
begin
  Result := Request('POST', Path, QueryString(Fields), 'application/x-www-form-urlencoded');
end;

procedure THttpClient.Download(const Path, FileName: string);
var
  F: TFileStream;
  Tmp, Url: string;
  R: THttpResponse;
begin
  Url := MakeUrl(Path, []);
  if ExtractFileDir(ExpandFileName(FileName)) <> '' then
    EnsureDir(ExtractFileDir(ExpandFileName(FileName)));
  Tmp := FileName + '.part';
  F := TFileStream.Create(Tmp, fmCreate);
  try
    try
      R := Send('GET', Url, nil, '', F);
    finally
      F.Free;
    end;
    R.RaiseForStatus;
  except
    SysUtils.DeleteFile(Tmp);
    raise;
  end;
  if FileExists(FileName) then
    SysUtils.DeleteFile(FileName);
  if not RenameFile(Tmp, FileName) then
    raise EHttpError.CreateFmt('cannot write "%s"', [FileName]);
end;

{ ---------------- shortcuts ---------------- }

function HttpGet(const Url: string): THttpResponse;
var
  C: THttpClient;
begin
  C := THttpClient.Create;
  try
    Result := C.Get(Url);
  finally
    C.Free;
  end;
end;

function HttpGetText(const Url: string): string;
var
  R: THttpResponse;
begin
  R := HttpGet(Url);
  R.RaiseForStatus;
  Result := R.Body;
end;

function HttpGetJson(const Url: string): TJSONData;
var
  R: THttpResponse;
begin
  R := HttpGet(Url);
  R.RaiseForStatus;
  Result := R.Json;
end;

function HttpPost(const Url, Body, ContentType: string): THttpResponse;
var
  C: THttpClient;
begin
  C := THttpClient.Create;
  try
    Result := C.Post(Url, Body, ContentType);
  finally
    C.Free;
  end;
end;

function HttpPostJson(const Url, Json: string): THttpResponse;
begin
  Result := HttpPost(Url, Json, 'application/json');
end;

procedure HttpDownload(const Url, FileName: string);
var
  C: THttpClient;
begin
  C := THttpClient.Create;
  try
    C.Download(Url, FileName);
  finally
    C.Free;
  end;
end;

initialization
  { Free Pascal 3.2.2 does not know OpenSSL 3 yet, which is what current
    systems ship. Look for it first. }
  {$IFNDEF ANDROID}
  {$IFDEF WINDOWS}
  {$IFDEF WIN64}
  DLLSSLName := 'libssl-3-x64.dll';
  DLLUtilName := 'libcrypto-3-x64.dll';
  {$ELSE}
  DLLSSLName := 'libssl-3.dll';
  DLLUtilName := 'libcrypto-3.dll';
  {$ENDIF}
  {$ELSE}
  {$IFDEF DARWIN}
  DLLVersions[2] := '.3';
  DLLVersions[3] := '.1.1';
  {$ELSE}
  DLLVersions[19] := DLLVersions[1];
  DLLVersions[1] := '.3';
  {$ENDIF}
  {$ENDIF}
  {$ENDIF}
end.
