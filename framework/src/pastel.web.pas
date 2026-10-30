(* Pastel - HTTP server for web APIs and sites.

    Web := TWebServer.Create(8080);
    Web.Get('/hello', @Hello);
    Web.Get('/users/:id', @GetUser);
    Web.Post('/users', @CreateUser);
    Web.Static('/', 'public');           // files: public/index.html, public/app.css, ...
    Web.Health('/health', AppVersion);
    Web.Start;                           // serves in the background until Web.Stop

    procedure GetUser(Req: TWebRequest; Res: TWebResponse);
    var
      User: TJSONObject;
    begin
      User := FindUser(Req.ParamInt('id'));
      if User = nil then
        raise EWebError.Create(404, 'no user with this id');
      Res.Json(User);
    end;

  Requests are handled at the same time in several threads: what handlers
  share must be protected (TCriticalSection) or be read-only.
  Errors become JSON answers: EWebError(404, 'no user') -> 404
  {"error": "no user"}; a bad JSON body -> 400; any other exception -> 500,
  logged, with the message in the answer only in debug builds.
  Part of the Pastel project, MIT License. *)
unit Pastel.Web;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, fphttpserver, httpdefs, Pastel.Service, Pastel.Config;

type
  // Raise it in a handler to answer with this status and {"error": Message}
  EWebError = class(Exception)
  public
    Status: Integer;
    constructor Create(AStatus: Integer; const AMessage: string);
    constructor CreateFmt(AStatus: Integer; const Fmt: string; const Args: array of const);
  end;

  { The server could not start (port in use, no permission, ...). }
  EWebServerError = class(Exception);

  TWebRequest = class
  private
    FReq: TFPHTTPConnectionRequest;
    FParams: TStringList;
    FJson: TJSONData;
    FPath, FBody: string;
  public
    constructor Create(AReq: TFPHTTPConnectionRequest; const APath: string);
    destructor Destroy; override;
    function Method: string;
    { the path without the query: /users/42 }
    property Path: string read FPath;
    { the request body as text }
    property Body: string read FBody;
    function ClientIP: string;
    { a part of the path: Param('id') for the route /users/:id }
    function Param(const Name: string): string;
    { ... as a number; 400 Bad Request when it is not one }
    function ParamInt(const Name: string): Int64;
    { ?page=2 }
    function Query(const Name: string; const Default: string = ''): string;
    function QueryInt(const Name: string; Default: Int64): Int64;
    function HasQuery(const Name: string): Boolean;
    function Header(const Name: string): string;
    { a field of a submitted HTML form (application/x-www-form-urlencoded) }
    function Form(const Name: string; const Default: string = ''): string;
    { the body as JSON; 400 when it is missing or not JSON. Owned by the request. }
    function Json: TJSONData;
    // the same, and it must be a JSON object
    function JsonObject: TJSONObject;
    { the route's parameters, name=value }
    property Params: TStringList read FParams;
  end;

  TWebResponse = class
  private
    FRes: TFPHTTPConnectionResponse;
    FStatus: Integer;
    FSent: Boolean;
    FBodyLength: Int64;
    procedure SetBody(const S, ContentType: string; AStatus: Integer);
  public
    constructor Create(ARes: TFPHTTPConnectionResponse);
    procedure SetHeader(const Name, Value: string);
    procedure Text(const S: string; AStatus: Integer = 200);
    procedure Html(const S: string; AStatus: Integer = 200);
    { sends Data and frees it }
    procedure Json(Data: TJSONData; AStatus: Integer = 200);
    procedure JsonText(const S: string; AStatus: Integer = 200);
    // answers {"error": Message}
    procedure Error(AStatus: Integer; const Message: string);
    procedure SendFile(const FileName: string; const ContentType: string = '');
    procedure Redirect(const Url: string; AStatus: Integer = 302);
    { 204, no body }
    procedure NoContent;
    property Status: Integer read FStatus write FStatus;
    { something was answered already }
    property Sent: Boolean read FSent;
  end;

  TWebHandler = procedure(Req: TWebRequest; Res: TWebResponse) of object;
  TWebHandlerProc = procedure(Req: TWebRequest; Res: TWebResponse);

  TWebRoute = class
  public
    Method: string;
    Pattern: string;
    Parts: TStringArray;
    Handler: TWebHandler;
    Proc: TWebHandlerProc;
    StaticFolder: string;
  end;

  TWebServerThread = class;

  TWebServer = class
  private
    FPort: Integer;
    FAddress: string;
    FRoutes: TList;
    FHttp: TFPCustomHttpServer;
    FThread: TWebServerThread;
    FAccessLog: Boolean;
    FStarted: TDateTime;
    FHealthVersion: string;
    FRequests: Int64;
    FLock: TCriticalSection;
    function AddRoute(const Method, Pattern: string): TWebRoute;
    procedure OnRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
    procedure DispatchRequest(Req: TWebRequest; Res: TWebResponse);
    procedure ServeStatic(Route: TWebRoute; Req: TWebRequest; Res: TWebResponse);
    procedure HealthHandler(Req: TWebRequest; Res: TWebResponse);
    function GetRequests: Int64;
  public
    { Address: '' or '0.0.0.0' for every network, '127.0.0.1' for this computer only }
    constructor Create(APort: Integer = 8080; const AAddress: string = '');
    destructor Destroy; override;
    procedure Get(const Pattern: string; Handler: TWebHandler);
    procedure Get(const Pattern: string; Handler: TWebHandlerProc);
    procedure Post(const Pattern: string; Handler: TWebHandler);
    procedure Post(const Pattern: string; Handler: TWebHandlerProc);
    procedure Put(const Pattern: string; Handler: TWebHandler);
    procedure Put(const Pattern: string; Handler: TWebHandlerProc);
    procedure Patch(const Pattern: string; Handler: TWebHandler);
    procedure Patch(const Pattern: string; Handler: TWebHandlerProc);
    procedure Delete(const Pattern: string; Handler: TWebHandler);
    procedure Delete(const Pattern: string; Handler: TWebHandlerProc);
    { the files of Folder under UrlPrefix: Static('/assets', 'public/assets') }
    procedure Static(const UrlPrefix, Folder: string);
    // GET Path answers {"status":"ok","version":...,"uptime_seconds":...}
    procedure Health(const Path: string = '/health'; const Version: string = '');
    { starts listening; EWebServerError when that is not possible }
    procedure Start;
    { stops accepting, lets running requests finish }
    procedure Stop;
    function Running: Boolean;
    { http://localhost:8080 }
    function Url: string;
    property Port: Integer read FPort;
    property Address: string read FAddress;
    { a log line for every request (default on) }
    property AccessLog: Boolean read FAccessLog write FAccessLog;
    property Requests: Int64 read GetRequests;
  end;

  TWebServerThread = class(TThread)
  public
    Server: TFPCustomHttpServer;
    Error: string;
    Listening: Boolean;
    { accepting connections: set by the server's idle callback }
    Ready: Boolean;
    procedure Idle(Sender: TObject);
    procedure Execute; override;
  end;

  { A service with a web server: settings server.port (8080) and
    server.address; routes are added in Routes. }
  TWebService = class(TService)
  private
    FWeb: TWebServer;
  protected
    procedure Configure(C: TConfig); override;
    { add the routes here: Web.Get('/users/:id', @GetUser) }
    procedure Routes(Web: TWebServer); virtual;
    procedure Started; override;
    procedure Stopping; override;
  public
    destructor Destroy; override;
    property Server: TWebServer read FWeb;
  end;

{ 'application/json' for 'x.json', ... }
function ContentTypeOf(const FileName: string): string;
function UrlDecode(const S: string): string;

implementation

uses
  DateUtils, ssockets, Pastel.Json, Pastel.Log;

type
  { publishes Address, which TFPHttpServer hides in FPC 3.2.2 }
  TPastelHttpServer = class(TFPCustomHttpServer)
  public
    property Address;
    property Port;
    property Threaded;
    property OnRequest;
    property AcceptIdleTimeout;
    property OnAcceptIdle;
    property Active;
    property QueueSize;
  end;

{ ---------------- helpers ---------------- }

function UrlDecode(const S: string): string;
var
  I: Integer;
  H: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) and TryStrToInt('$' + Copy(S, I + 1, 2), H) then
    begin
      Result := Result + Chr(H);
      Inc(I, 3);
    end
    else
    begin
      if S[I] = '+' then
        Result := Result + ' '
      else
        Result := Result + S[I];
      Inc(I);
    end;
  end;
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

function SplitPath(const Path: string): TStringArray;
var
  P: string;
  Parts: TStringArray;
begin
  Result := nil;
  Parts := Path.Split(['/']);
  for P in Parts do
    if P <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := P;
    end;
end;

function ContentTypeOf(const FileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  case Ext of
    '.html', '.htm': Result := 'text/html; charset=utf-8';
    '.css': Result := 'text/css; charset=utf-8';
    '.js', '.mjs': Result := 'text/javascript; charset=utf-8';
    '.json', '.map': Result := 'application/json';
    '.txt', '.md': Result := 'text/plain; charset=utf-8';
    '.csv': Result := 'text/csv; charset=utf-8';
    '.xml': Result := 'application/xml';
    '.svg': Result := 'image/svg+xml';
    '.png': Result := 'image/png';
    '.jpg', '.jpeg': Result := 'image/jpeg';
    '.gif': Result := 'image/gif';
    '.webp': Result := 'image/webp';
    '.ico': Result := 'image/x-icon';
    '.pdf': Result := 'application/pdf';
    '.zip': Result := 'application/zip';
    '.wasm': Result := 'application/wasm';
    '.woff': Result := 'font/woff';
    '.woff2': Result := 'font/woff2';
    '.mp4': Result := 'video/mp4';
    '.mp3': Result := 'audio/mpeg';
  else
    Result := 'application/octet-stream';
  end;
end;

function HttpDate(T: TDateTime): string;
const
  Days: array[1..7] of string = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
  Months: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec');
begin
  Result := Format('%s, %.2d %s %d %s GMT', [Days[DayOfWeek(T)], DayOf(T), Months[MonthOf(T)],
    YearOf(T), FormatDateTime('hh:nn:ss', T)]);
end;

{ ---------------- EWebError ---------------- }

constructor EWebError.Create(AStatus: Integer; const AMessage: string);
begin
  inherited Create(AMessage);
  Status := AStatus;
end;

constructor EWebError.CreateFmt(AStatus: Integer; const Fmt: string; const Args: array of const);
begin
  inherited CreateFmt(Fmt, Args);
  Status := AStatus;
end;

{ ---------------- TWebRequest ---------------- }

constructor TWebRequest.Create(AReq: TFPHTTPConnectionRequest; const APath: string);
begin
  inherited Create;
  FReq := AReq;
  FPath := APath;
  FBody := AReq.Content;
  SetCodePage(RawByteString(FBody), CP_UTF8, False);
  FParams := TStringList.Create;
end;

destructor TWebRequest.Destroy;
begin
  FParams.Free;
  FJson.Free;
  inherited Destroy;
end;

function TWebRequest.Method: string;
begin
  Result := UpperCase(FReq.Method);
end;

function TWebRequest.ClientIP: string;
begin
  Result := FReq.RemoteAddress;
end;

function TWebRequest.Param(const Name: string): string;
begin
  Result := FParams.Values[Name];
end;

function TWebRequest.ParamInt(const Name: string): Int64;
begin
  if not TryStrToInt64(Param(Name), Result) then
    raise EWebError.CreateFmt(400, '%s must be a whole number, not "%s"', [Name, Param(Name)]);
end;

function TWebRequest.HasQuery(const Name: string): Boolean;
begin
  { "?all" has no value }
  Result := (FReq.QueryFields.IndexOfName(Name) >= 0) or (FReq.QueryFields.IndexOf(Name) >= 0);
end;

function TWebRequest.Query(const Name: string; const Default: string): string;
begin
  if not HasQuery(Name) then
    Exit(Default);
  Result := FReq.QueryFields.Values[Name];
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

function TWebRequest.QueryInt(const Name: string; Default: Int64): Int64;
begin
  if not HasQuery(Name) then
    Exit(Default);
  if not TryStrToInt64(Query(Name), Result) then
    raise EWebError.CreateFmt(400, '%s must be a whole number, not "%s"', [Name, Query(Name)]);
end;

function TWebRequest.Header(const Name: string): string;
begin
  Result := FReq.GetFieldByName(Name);
  if Result = '' then
    Result := FReq.GetCustomHeader(Name);
end;

function TWebRequest.Form(const Name: string; const Default: string): string;
begin
  if FReq.ContentFields.IndexOfName(Name) < 0 then
    Exit(Default);
  Result := FReq.ContentFields.Values[Name];
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

function TWebRequest.Json: TJSONData;
begin
  if FJson = nil then
  begin
    if Trim(FBody) = '' then
      raise EWebError.Create(400, 'the request needs a JSON body');
    try
      FJson := ParseJson(FBody);
    except
      on E: Exception do
        raise EWebError.Create(400, 'the body is not valid JSON: ' + E.Message);
    end;
  end;
  Result := FJson;
end;

function TWebRequest.JsonObject: TJSONObject;
begin
  if not (Json is TJSONObject) then
    raise EWebError.Create(400, 'the body must be a JSON object {...}');
  Result := TJSONObject(Json);
end;

{ ---------------- TWebResponse ---------------- }

constructor TWebResponse.Create(ARes: TFPHTTPConnectionResponse);
begin
  inherited Create;
  FRes := ARes;
  FStatus := 200;
end;

procedure TWebResponse.SetHeader(const Name, Value: string);
begin
  FRes.SetCustomHeader(Name, Value);
end;

procedure TWebResponse.SetBody(const S, ContentType: string; AStatus: Integer);
begin
  FStatus := AStatus;
  FRes.ContentType := ContentType;
  if FRes.ContentStream <> nil then
  begin
    if FRes.FreeContentStream then
      FRes.ContentStream.Free;
    FRes.ContentStream := nil;
  end;
  { Content would add a line break; a stream sends the bytes as they are }
  FRes.ContentStream := TStringStream.Create(S);
  FRes.FreeContentStream := True;
  FBodyLength := Length(S);
  FSent := True;
end;

procedure TWebResponse.Text(const S: string; AStatus: Integer);
begin
  SetBody(S, 'text/plain; charset=utf-8', AStatus);
end;

procedure TWebResponse.Html(const S: string; AStatus: Integer);
begin
  SetBody(S, 'text/html; charset=utf-8', AStatus);
end;

procedure TWebResponse.Json(Data: TJSONData; AStatus: Integer);
begin
  try
    SetBody(ToJson(Data), 'application/json; charset=utf-8', AStatus);
  finally
    Data.Free;
  end;
end;

procedure TWebResponse.JsonText(const S: string; AStatus: Integer);
begin
  SetBody(S, 'application/json; charset=utf-8', AStatus);
end;

procedure TWebResponse.Error(AStatus: Integer; const Message: string);
begin
  Json(JObject(['error', Message]), AStatus);
end;

procedure TWebResponse.SendFile(const FileName: string; const ContentType: string);
var
  F: TFileStream;
begin
  if not FileExists(FileName) then
    raise EWebError.Create(404, 'not found');
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  FStatus := 200;
  if ContentType <> '' then
    FRes.ContentType := ContentType
  else
    FRes.ContentType := ContentTypeOf(FileName);
  FRes.ContentStream := F;
  FRes.FreeContentStream := True;
  FBodyLength := F.Size;
  SetHeader('Last-Modified', HttpDate(LocalTimeToUniversal(FileDateToDateTime(FileAge(FileName)))));
  FSent := True;
end;

procedure TWebResponse.Redirect(const Url: string; AStatus: Integer);
begin
  SetHeader('Location', Url);
  SetBody('', 'text/plain; charset=utf-8', AStatus);
end;

procedure TWebResponse.NoContent;
begin
  SetBody('', 'text/plain; charset=utf-8', 204);
end;

{ ---------------- TWebServerThread ---------------- }

procedure TWebServerThread.Idle(Sender: TObject);
begin
  Ready := True;
end;

procedure TWebServerThread.Execute;
begin
  try
    Listening := True;
    TPastelHttpServer(Server).Active := True;      { returns when the server stops }
  except
    on E: Exception do
    begin
      Error := E.Message;
      Listening := False;
    end;
  end;
  Listening := False;
end;

{ ---------------- TWebServer ---------------- }

constructor TWebServer.Create(APort: Integer; const AAddress: string);
begin
  inherited Create;
  FPort := APort;
  FAddress := AAddress;
  FRoutes := TList.Create;
  FAccessLog := True;
  FLock := TCriticalSection.Create;
end;

destructor TWebServer.Destroy;
var
  I: Integer;
begin
  Stop;
  for I := 0 to FRoutes.Count - 1 do
    TObject(FRoutes[I]).Free;
  FRoutes.Free;
  FLock.Free;
  inherited Destroy;
end;

function TWebServer.AddRoute(const Method, Pattern: string): TWebRoute;
var
  P: string;
begin
  if (Pattern = '') or (Pattern[1] <> '/') then
    raise EArgumentException.CreateFmt('route "%s" must start with /', [Pattern]);
  Result := TWebRoute.Create;
  Result.Method := Method;
  Result.Pattern := Pattern;
  Result.Parts := SplitPath(Pattern);
  for P in Result.Parts do
    if (P = '*') and (P <> Result.Parts[High(Result.Parts)]) then
      raise EArgumentException.CreateFmt('route "%s": * can only be the last part', [Pattern]);
  FRoutes.Add(Result);
end;

procedure TWebServer.Get(const Pattern: string; Handler: TWebHandler);
begin
  AddRoute('GET', Pattern).Handler := Handler;
end;

procedure TWebServer.Get(const Pattern: string; Handler: TWebHandlerProc);
begin
  AddRoute('GET', Pattern).Proc := Handler;
end;

procedure TWebServer.Post(const Pattern: string; Handler: TWebHandler);
begin
  AddRoute('POST', Pattern).Handler := Handler;
end;

procedure TWebServer.Post(const Pattern: string; Handler: TWebHandlerProc);
begin
  AddRoute('POST', Pattern).Proc := Handler;
end;

procedure TWebServer.Put(const Pattern: string; Handler: TWebHandler);
begin
  AddRoute('PUT', Pattern).Handler := Handler;
end;

procedure TWebServer.Put(const Pattern: string; Handler: TWebHandlerProc);
begin
  AddRoute('PUT', Pattern).Proc := Handler;
end;

procedure TWebServer.Patch(const Pattern: string; Handler: TWebHandler);
begin
  AddRoute('PATCH', Pattern).Handler := Handler;
end;

procedure TWebServer.Patch(const Pattern: string; Handler: TWebHandlerProc);
begin
  AddRoute('PATCH', Pattern).Proc := Handler;
end;

procedure TWebServer.Delete(const Pattern: string; Handler: TWebHandler);
begin
  AddRoute('DELETE', Pattern).Handler := Handler;
end;

procedure TWebServer.Delete(const Pattern: string; Handler: TWebHandlerProc);
begin
  AddRoute('DELETE', Pattern).Proc := Handler;
end;

procedure TWebServer.Static(const UrlPrefix, Folder: string);
var
  R: TWebRoute;
  Prefix: string;
begin
  Prefix := UrlPrefix;
  while (Length(Prefix) > 1) and (Prefix[Length(Prefix)] = '/') do
    SetLength(Prefix, Length(Prefix) - 1);
  if Prefix = '/' then
    R := AddRoute('GET', '/*')
  else
    R := AddRoute('GET', Prefix + '/*');
  R.StaticFolder := IncludeTrailingPathDelimiter(ExpandFileName(Folder));
end;

procedure TWebServer.Health(const Path, Version: string);
begin
  FHealthVersion := Version;
  Get(Path, @HealthHandler);
end;

procedure TWebServer.HealthHandler(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Json(JObject(['status', 'ok', 'version', FHealthVersion,
    'uptime_seconds', SecondsBetween(Now, FStarted), 'requests', Requests]));
end;

function TWebServer.GetRequests: Int64;
begin
  FLock.Acquire;
  try
    Result := FRequests;
  finally
    FLock.Release;
  end;
end;

{ /users/42 against /users/:id; Params gets id=42 }
function Matches(Route: TWebRoute; const Parts: TStringArray; Params: TStrings): Boolean;
var
  I, J: Integer;
  Rest: string;
begin
  Params.Clear;
  for I := 0 to High(Route.Parts) do
  begin
    if Route.Parts[I] = '*' then
    begin
      Rest := '';
      for J := I to High(Parts) do
      begin
        if Rest <> '' then
          Rest := Rest + '/';
        Rest := Rest + Parts[J];
      end;
      Params.Values['*'] := Rest;
      Exit(True);
    end;
    if I > High(Parts) then
      Exit(False);
    if (Route.Parts[I] <> '') and (Route.Parts[I][1] = ':') then
      Params.Values[Copy(Route.Parts[I], 2, MaxInt)] := Parts[I]
    else if Route.Parts[I] <> Parts[I] then
      Exit(False);
  end;
  Result := Length(Parts) = Length(Route.Parts);
end;

procedure TWebServer.ServeStatic(Route: TWebRoute; Req: TWebRequest; Res: TWebResponse);
var
  Rel, Full, P: string;
begin
  Rel := Req.Param('*');
  for P in Rel.Split(['/']) do
    if (P = '..') or (P = '.') or (Pos('\', P) > 0) or (Pos(':', P) > 0) then
      raise EWebError.Create(404, 'not found');
  Full := Route.StaticFolder + SetDirSeparators(Rel);
  if DirectoryExists(Full) then
    Full := IncludeTrailingPathDelimiter(Full) + 'index.html';
  if not FileExists(Full) then
    raise EWebError.Create(404, 'not found');
  Res.SendFile(Full);
end;

procedure TWebServer.DispatchRequest(Req: TWebRequest; Res: TWebResponse);
var
  Parts: TStringArray;
  I: Integer;
  Route, Found: TWebRoute;
  Allowed, Method: string;
  Params: TStringList;
begin
  Parts := SplitPath(Req.Path);
  for I := 0 to High(Parts) do
    Parts[I] := UrlDecode(Parts[I]);
  Method := Req.Method;
  if Method = 'HEAD' then
    Method := 'GET';
  Found := nil;
  Allowed := '';
  Params := TStringList.Create;
  try
    for I := 0 to FRoutes.Count - 1 do
    begin
      Route := TWebRoute(FRoutes[I]);
      if not Matches(Route, Parts, Params) then
        Continue;
      if Route.Method = Method then
      begin
        { a static folder does not hide the routes after it when the file is missing }
        if (Route.StaticFolder <> '') and
           not FileExists(Route.StaticFolder + SetDirSeparators(Params.Values['*'])) and
           not FileExists(IncludeTrailingPathDelimiter(Route.StaticFolder +
             SetDirSeparators(Params.Values['*'])) + 'index.html') then
          Continue;
        Found := Route;
        Req.Params.Assign(Params);
        Break;
      end;
      if Pos(Route.Method, Allowed) = 0 then
      begin
        if Allowed <> '' then
          Allowed := Allowed + ', ';
        Allowed := Allowed + Route.Method;
      end;
    end;
  finally
    Params.Free;
  end;

  if Found = nil then
  begin
    if Allowed <> '' then
    begin
      Res.SetHeader('Allow', Allowed);
      Res.Error(405, Format('%s is not allowed for %s; use %s', [Req.Method, Req.Path, Allowed]));
    end
    else
      Res.Error(404, Format('no route for %s %s', [Req.Method, Req.Path]));
    Exit;
  end;

  if Found.StaticFolder <> '' then
    ServeStatic(Found, Req, Res)
  else if Assigned(Found.Proc) then
    Found.Proc(Req, Res)
  else
    Found.Handler(Req, Res);
  if not Res.Sent then
    Res.NoContent;
end;

procedure TWebServer.OnRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  Req: TWebRequest;
  Res: TWebResponse;
  Path: string;
  T0: QWord;
begin
  T0 := GetTickCount64;
  if FThread <> nil then
    FThread.Ready := True;
  Path := ARequest.URI;
  if Pos('?', Path) > 0 then
    SetLength(Path, Pos('?', Path) - 1);
  Req := TWebRequest.Create(ARequest, Path);
  Res := TWebResponse.Create(AResponse);
  try
    try
      DispatchRequest(Req, Res);
    except
      on E: EWebError do
        Res.Error(E.Status, E.Message);
      on E: EJsonError do
        Res.Error(400, 'the body is not valid JSON: ' + E.Message);
      on E: Exception do
      begin
        Log.Error(E, Req.Method + ' ' + Req.Path);
        {$IFDEF PASTEL_DEBUG}
        Res.Error(500, 'internal error: ' + E.Message + ' (' + E.ClassName + '; shown in debug builds only)');
        {$ELSE}
        Res.Error(500, 'internal error');
        {$ENDIF}
      end;
    end;
    AResponse.Code := Res.Status;
    AResponse.CodeText := GetStatusCode(Res.Status);
    if Req.Method = 'HEAD' then
    begin
      if AResponse.FreeContentStream then
        AResponse.ContentStream.Free;
      AResponse.ContentStream := nil;
    end;
    FLock.Acquire;
    Inc(FRequests);
    FLock.Release;
    if FAccessLog then
      Log.Fields(['status', Res.Status, 'ms', GetTickCount64 - T0]).Info(Req.Method + ' ' + Req.Path);
  finally
    Req.Free;
    Res.Free;
  end;
end;

procedure TWebServer.Start;
var
  H: TPastelHttpServer;
  Waited: Integer;
  Error: string;
begin
  if Running then
    Exit;
  H := TPastelHttpServer.Create(nil);
  H.Port := FPort;
  if FAddress <> '' then
    H.Address := FAddress;
  H.Threaded := True;
  H.QueueSize := 64;
  H.AcceptIdleTimeout := 50;      { so Stop is noticed quickly, and Start knows it listens }
  H.OnRequest := @OnRequest;
  FHttp := H;
  FStarted := Now;
  FThread := TWebServerThread.Create(True);
  FThread.Server := FHttp;
  FThread.FreeOnTerminate := False;
  H.OnAcceptIdle := @FThread.Idle;
  FThread.Start;
  { binding happens in the thread: wait until it accepts, or failed }
  Waited := 0;
  while (Waited < 5000) and not FThread.Ready and (FThread.Error = '') do
  begin
    Sleep(5);
    Inc(Waited, 5);
  end;
  if FThread.Error <> '' then
  begin
    Error := FThread.Error;
    FThread.WaitFor;
    FreeAndNil(FThread);
    FreeAndNil(FHttp);
    raise EWebServerError.CreateFmt('cannot listen on port %d (is another program using it, ' +
      'or is the port below 1024 and this not root?): %s', [FPort, Error]);
  end;
end;

procedure TWebServer.Stop;
begin
  if FThread = nil then
    Exit;
  TPastelHttpServer(FHttp).Active := False;
  FThread.WaitFor;
  FreeAndNil(FThread);
  FreeAndNil(FHttp);     { waits for requests still being answered }
end;

function TWebServer.Running: Boolean;
begin
  Result := (FThread <> nil) and FThread.Listening and (FThread.Error = '');
end;

function TWebServer.Url: string;
begin
  if (FAddress = '') or (FAddress = '0.0.0.0') then
    Result := Format('http://localhost:%d', [FPort])
  else
    Result := Format('http://%s:%d', [FAddress, FPort]);
end;

{ ---------------- TWebService ---------------- }

procedure TWebService.Configure(C: TConfig);
begin
  inherited Configure(C);
  C.SetDefault('server.port', '8080');
  C.SetDefault('server.address', '');
end;

procedure TWebService.Routes(Web: TWebServer);
begin
end;

procedure TWebService.Started;
begin
  inherited Started;
  FWeb := TWebServer.Create(Config.GetInt('server.port'), Config.Get('server.address'));
  Routes(FWeb);
  FWeb.Start;
  Log.Info('listening on %s', [FWeb.Url]);
end;

procedure TWebService.Stopping;
begin
  if FWeb <> nil then
    FWeb.Stop;
  inherited Stopping;
end;

destructor TWebService.Destroy;
begin
  FreeAndNil(FWeb);
  inherited Destroy;
end;

end.
