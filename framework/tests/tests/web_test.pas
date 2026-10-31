unit Web_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, ssockets, Pastel.Testing, Pastel.Web, Pastel.Http, Pastel.Json,
  Pastel.Files, Pastel.Log;

type
  TWebTests = class(TTestSuite)
  private
    procedure StartTwice;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AnswersText;
    procedure RouteParameters;
    procedure ParametersAreDecoded;
    procedure QueryValues;
    procedure BadNumbersAre400;
    procedure ReadsAndWritesJson;
    procedure BadJsonIs400;
    procedure ErrorsBecomeJson;
    procedure CrashesAre500AndLogged;
    procedure UnknownRoutesAre404;
    procedure WrongMethodIs405;
    procedure HeadersBothWays;
    procedure NoContentByDefault;
    procedure Redirects;
    procedure ServesStaticFiles;
    procedure StaticFilesStayInTheirFolder;
    procedure RoutesBeatMissingStaticFiles;
    procedure ReportsHealth;
    procedure ManyRequestsAtOnce;
    procedure PortInUseIsExplained;
    procedure StopsAndFreesThePort;
    procedure TooLargeBodiesAre413;
    procedure TooLargeHeadersAre431;
    procedure SlowClientsAre408;
    procedure TooManyConnectionsAre503;
    procedure AnswersSayNoSniff;
  end;

implementation

var
  Server: TWebServer = nil;
  Port: Integer;
  Base: string;
  Folder: string;
  LastError: string;
  Counter: Integer = 0;
  CounterLock: TCriticalSection;

type
  TCapture = class
    procedure Line(Level: TLogLevel; const Text: string);
  end;

procedure TCapture.Line(Level: TLogLevel; const Text: string);
begin
  if Level = llError then
    LastError := Text;
end;

var
  Capture: TCapture;

procedure Hello(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text('merhaba dünya');
end;

procedure GetUser(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Json(JObject(['id', Req.ParamInt('id'), 'name', 'Ayşe']));
end;

procedure GetFile(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text(Req.Param('folder') + '|' + Req.Param('name'));
end;

procedure Search(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text(Req.Query('q', '-') + '|' + IntToStr(Req.QueryInt('page', 1)) + '|' +
    BoolToStr(Req.HasQuery('all'), 'all', 'some'));
end;

procedure CreateUser(Req: TWebRequest; Res: TWebResponse);
var
  Body: TJSONObject;
begin
  Body := Req.JsonObject;
  if JStr(Body, 'name') = '' then
    raise EWebError.Create(422, 'name is required');
  Res.Json(JObject(['id', 7, 'name', JStr(Body, 'name')]), 201);
end;

procedure Crash(Req: TWebRequest; Res: TWebResponse);
begin
  raise EConvertError.Create('the disk is on fire');
end;

procedure Echo(Req: TWebRequest; Res: TWebResponse);
begin
  Res.SetHeader('X-Answer', 'yes ' + Req.Header('X-Question'));
  Res.Text(Req.Header('User-Agent'));
end;

procedure Nothing(Req: TWebRequest; Res: TWebResponse);
begin
end;

procedure Old(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Redirect('/hello', 301);
end;

procedure Count(Req: TWebRequest; Res: TWebResponse);
begin
  Sleep(20);
  CounterLock.Acquire;
  try
    Inc(Counter);
  finally
    CounterLock.Release;
  end;
  Res.Text('ok');
end;

procedure StartServer;
begin
  if Server <> nil then
    Exit;
  Folder := MakeTempDir('pastel-web-test');
  WriteText(Folder + 'index.html', '<h1>Ana sayfa</h1>');
  WriteText(JoinPath([Folder, 'css', 'app.css']), 'body { color: red }');
  WriteText(JoinPath([Folder, 'docs', 'index.html']), 'docs');
  WriteText(Folder + '..' + PathDelim + 'pastel-web-secret.txt', 'secret');
  Port := 21000 + Random(20000);
  Base := Format('http://127.0.0.1:%d', [Port]);
  Server := TWebServer.Create(Port, '127.0.0.1');
  Server.AccessLog := False;
  Server.Get('/hello', @Hello);
  Server.Get('/users/:id', @GetUser);
  Server.Post('/users', @CreateUser);
  Server.Get('/files/:folder/:name', @GetFile);
  Server.Get('/search', @Search);
  Server.Get('/crash', @Crash);
  Server.Get('/echo', @Echo);
  Server.Get('/nothing', @Nothing);
  Server.Get('/old', @Old);
  Server.Get('/count', @Count);
  Server.Health('/health', '1.0.0');
  Server.Static('/', Folder);
  Server.Get('/api/version', @Hello);
  Server.MaxBodySize := 4096;
  Server.MaxHeaderSize := 8192;
  Server.RequestTimeout := 2;
  Server.Start;
end;

{ sends Data as it is (Pause ms before the rest after a first part), returns the whole answer }
function RawRequest(APort: Integer; const Data: string; Pause: Integer = 0; const Rest: string = ''): string;
var
  S: TInetSocket;
  Buf: array[0..4095] of Char;
  N: Integer;
begin
  Result := '';
  S := TInetSocket.Create('127.0.0.1', APort);
  try
    S.IOTimeout := 5000;
    if Data <> '' then
      S.WriteBuffer(Data[1], Length(Data));
    if Pause > 0 then
      Sleep(Pause);
    if Rest <> '' then
    try
      S.WriteBuffer(Rest[1], Length(Rest));
    except
      { the server may have closed already }
    end;
    repeat
      N := S.Read(Buf, SizeOf(Buf));
      if N > 0 then
        Result := Result + Copy(Buf, 0, N);
    until N <= 0;
  finally
    S.Free;
  end;
end;

procedure TWebTests.SetUp;
begin
  StartServer;
  Log.OnLine := @Capture.Line;
  Log.Console := False;
end;

procedure TWebTests.TearDown;
begin
  Log.OnLine := nil;
  Log.Console := True;
end;

procedure TWebTests.AnswersText;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/hello');
  AssertEquals(200, R.Status);
  AssertEquals('merhaba dünya', R.Body);
  AssertContains('text/plain; charset=utf-8', R.Header('Content-Type'));
end;

procedure TWebTests.RouteParameters;
var
  D: TJSONData;
begin
  D := HttpGetJson(Base + '/users/42');
  try
    AssertEquals(42, JInt(D, 'id'));
    AssertEquals('Ayşe', JStr(D, 'name'));
  finally
    D.Free;
  end;
  AssertEquals('a|b.txt', HttpGetText(Base + '/files/a/b.txt'));
  AssertEquals(200, HttpGet(Base + '/hello/').Status);
end;

procedure TWebTests.ParametersAreDecoded;
begin
  AssertEquals('my docs|çay.txt', HttpGetText(Base + '/files/my%20docs/' + UrlEncode('çay.txt')));
end;

procedure TWebTests.QueryValues;
begin
  AssertEquals('ağaç ev|3|some', HttpGetText(Base + '/search?' + QueryString(['q', 'ağaç ev', 'page', '3'])));
  AssertEquals('-|1|all', HttpGetText(Base + '/search?all'));
end;

procedure TWebTests.BadNumbersAre400;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/users/abc');
  AssertEquals(400, R.Status);
  AssertContains('id must be a whole number, not \"abc\"', R.Body);
  AssertEquals(400, HttpGet(Base + '/search?page=x').Status);
end;

procedure TWebTests.ReadsAndWritesJson;
var
  R: THttpResponse;
begin
  R := HttpPostJson(Base + '/users', '{"name": "Çiğdem"}');
  AssertEquals(201, R.Status);
  AssertEquals('{"id":7,"name":"Çiğdem"}', R.Body);
  AssertContains('application/json', R.Header('Content-Type'));
end;

procedure TWebTests.BadJsonIs400;
var
  R: THttpResponse;
begin
  R := HttpPostJson(Base + '/users', '{"name": ');
  AssertEquals(400, R.Status);
  AssertContains('not valid JSON', R.Body);
  AssertEquals(400, HttpPostJson(Base + '/users', '[1, 2]').Status);
  AssertEquals(400, HttpPost(Base + '/users', '', 'application/json').Status);
end;

procedure TWebTests.ErrorsBecomeJson;
var
  R: THttpResponse;
begin
  R := HttpPostJson(Base + '/users', '{}');
  AssertEquals(422, R.Status);
  AssertEquals('{"error":"name is required"}', R.Body);
end;

procedure TWebTests.CrashesAre500AndLogged;
var
  R: THttpResponse;
begin
  LastError := '';
  R := HttpGet(Base + '/crash');
  AssertEquals(500, R.Status);
  AssertContains('internal error: the disk is on fire', R.Body);   { a debug build }
  AssertContains('GET /crash: the disk is on fire', LastError);
end;

procedure TWebTests.UnknownRoutesAre404;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/nowhere/at/all');
  AssertEquals(404, R.Status);
  AssertEquals('{"error":"no route for GET /nowhere/at/all"}', R.Body);
end;

procedure TWebTests.WrongMethodIs405;
var
  C: THttpClient;
  R: THttpResponse;
begin
  C := THttpClient.Create(Base);
  try
    R := C.Delete('/users/1');
    AssertEquals(405, R.Status);
    AssertEquals('GET', R.Header('Allow'));
    AssertContains('DELETE is not allowed for /users/1; use GET', R.Body);
  finally
    C.Free;
  end;
end;

procedure TWebTests.HeadersBothWays;
var
  C: THttpClient;
  R: THttpResponse;
begin
  C := THttpClient.Create(Base);
  try
    C.Headers := ['X-Question: çay?'];
    C.UserAgent := 'pastel-test';
    R := C.Get('/echo');
    AssertEquals('pastel-test', R.Body);
    AssertEquals('yes çay?', R.Header('X-Answer'));
  finally
    C.Free;
  end;
end;

procedure TWebTests.NoContentByDefault;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/nothing');
  AssertEquals(204, R.Status);
  AssertEquals('', R.Body);
end;

procedure TWebTests.Redirects;
var
  C: THttpClient;
begin
  AssertEquals('merhaba dünya', HttpGetText(Base + '/old'));
  C := THttpClient.Create(Base);
  try
    C.FollowRedirects := False;
    AssertEquals(301, C.Get('/old').Status);
    AssertEquals('/hello', C.Get('/old').Header('Location'));
  finally
    C.Free;
  end;
end;

procedure TWebTests.ServesStaticFiles;
var
  R: THttpResponse;
begin
  AssertEquals('<h1>Ana sayfa</h1>', HttpGetText(Base + '/'));
  R := HttpGet(Base + '/css/app.css');
  AssertEquals('body { color: red }', R.Body);
  AssertContains('text/css', R.Header('Content-Type'));
  AssertContains('GMT', R.Header('Last-Modified'));
  AssertEquals('docs', HttpGetText(Base + '/docs'));
  AssertEquals(404, HttpGet(Base + '/css/missing.css').Status);
end;

procedure TWebTests.StaticFilesStayInTheirFolder;
begin
  AssertEquals(404, HttpGet(Base + '/../pastel-web-secret.txt').Status);
  AssertEquals(404, HttpGet(Base + '/css/%2e%2e/%2e%2e/pastel-web-secret.txt').Status);
  AssertEquals(404, HttpGet(Base + '/%2e%2e%2fpastel-web-secret.txt').Status);
  AssertEquals(404, HttpGet(Base + '/index.html%00.png').Status);
  AssertEquals(404, HttpGet(Base + '/..%5cpastel-web-secret.txt').Status);
end;

procedure TWebTests.TooLargeBodiesAre413;
var
  Body: string;
begin
  Body := '{"name": "' + StringOfChar('a', 5000) + '"}';
  AssertContains('HTTP/1.1 413', RawRequest(Port, 'POST /users HTTP/1.1'#13#10'Host: x'#13#10 +
    'Content-Type: application/json'#13#10'Content-Length: ' + IntToStr(Length(Body)) + #13#10#13#10 + Body));
  { claiming a huge body does not make the server reserve it }
  AssertContains('HTTP/1.1 413', RawRequest(Port, 'POST /users HTTP/1.1'#13#10'Content-Length: 99999999999'#13#10#13#10));
  AssertEquals(201, HttpPostJson(Base + '/users', '{"name": "Ayşe"}').Status, 'small ones still work');
end;

procedure TWebTests.TooLargeHeadersAre431;
begin
  AssertContains('HTTP/1.1 431', RawRequest(Port, 'GET /hello HTTP/1.1'#13#10'X-Big: ' + StringOfChar('a', 10000) +
    #13#10#13#10));
  AssertContains('HTTP/1.1 431', RawRequest(Port, 'GET /hello HTTP/1.1'#13#10 + StringOfChar('a', 20000)));
end;

procedure TWebTests.SlowClientsAre408;
var
  T: QWord;
begin
  T := GetTickCount64;
  { half a request, then silence }
  AssertContains('HTTP/1.1 408', RawRequest(Port, 'GET /hello HTTP/1.1'#13#10'Host: x'#13#10));
  AssertTrue(GetTickCount64 - T < 4000, 'within the timeout');
  AssertEquals('merhaba dünya', HttpGetText(Base + '/hello'), 'the server is fine');
end;

procedure TWebTests.TooManyConnectionsAre503;
var
  Small: TWebServer;
  P, I: Integer;
  Idle: array[0..2] of TInetSocket;
begin
  P := Port + 1;
  Small := TWebServer.Create(P, '127.0.0.1');
  try
    Small.AccessLog := False;
    Small.MaxConnections := 3;
    Small.Get('/hello', @Hello);
    Small.Start;
    for I := 0 to 2 do
    begin
      Idle[I] := TInetSocket.Create('127.0.0.1', P);
      Idle[I].WriteBuffer('GET', 3);     { started, not finished }
    end;
    Sleep(200);
    try
      AssertContains('HTTP/1.1 503', RawRequest(P, 'GET /hello HTTP/1.1'#13#10#13#10));
    finally
      for I := 0 to 2 do
        Idle[I].Free;
    end;
    Sleep(200);
    AssertContains('merhaba', RawRequest(P, 'GET /hello HTTP/1.1'#13#10#13#10), 'free again');
  finally
    Small.Stop;
    Small.Free;
  end;
end;

procedure TWebTests.AnswersSayNoSniff;
begin
  AssertEquals('nosniff', HttpGet(Base + '/hello').Header('X-Content-Type-Options'));
end;

procedure TWebTests.RoutesBeatMissingStaticFiles;
begin
  AssertEquals('merhaba dünya', HttpGetText(Base + '/api/version'));
end;

procedure TWebTests.ReportsHealth;
var
  D: TJSONData;
begin
  D := HttpGetJson(Base + '/health');
  try
    AssertEquals('ok', JStr(D, 'status'));
    AssertEquals('1.0.0', JStr(D, 'version'));
    AssertTrue(JInt(D, 'requests') > 0);
  finally
    D.Free;
  end;
end;

type
  TCaller = class(TThread)
    Failures: Integer;
    procedure Execute; override;
  end;

procedure TCaller.Execute;
var
  I: Integer;
begin
  for I := 1 to 10 do
  try
    if HttpGetText(Base + '/count') <> 'ok' then
      Inc(Failures);
  except
    Inc(Failures);
  end;
end;

procedure TWebTests.ManyRequestsAtOnce;
var
  Callers: array[1..8] of TCaller;
  I, Failures: Integer;
  Start: QWord;
begin
  Counter := 0;
  Start := GetTickCount64;
  for I := Low(Callers) to High(Callers) do
    Callers[I] := TCaller.Create(False);
  Failures := 0;
  for I := Low(Callers) to High(Callers) do
  begin
    Callers[I].WaitFor;
    Inc(Failures, Callers[I].Failures);
    Callers[I].Free;
  end;
  AssertEquals(0, Failures);
  AssertEquals(80, Counter);
  { 80 requests of 20 ms each, answered side by side }
  AssertTrue(GetTickCount64 - Start < 1600, Format('took %d ms', [GetTickCount64 - Start]));
end;

procedure TWebTests.StartTwice;
var
  Second: TWebServer;
begin
  Second := TWebServer.Create(Port, '127.0.0.1');
  try
    Second.Start;
  finally
    Second.Free;
  end;
end;

procedure TWebTests.PortInUseIsExplained;
begin
  try
    StartTwice;
    Fail('no exception');
  except
    on E: EWebServerError do
      AssertContains(Format('cannot listen on port %d', [Port]), E.Message);
  end;
end;

procedure TWebTests.StopsAndFreesThePort;
var
  S: TWebServer;
  P: Integer;
begin
  P := Port + 1;
  S := TWebServer.Create(P, '127.0.0.1');
  try
    S.AccessLog := False;
    S.Get('/hello', @Hello);
    S.Start;
    AssertTrue(S.Running);
    AssertEquals('merhaba dünya', HttpGetText(Format('http://127.0.0.1:%d/hello', [P])));
    S.Stop;
    AssertFalse(S.Running);
    try
      HttpGet(Format('http://127.0.0.1:%d/hello', [P]));
      Fail('still answering');
    except
      on E: EHttpError do
        AssertContains('cannot connect', E.Message);
    end;
    S.Start;     { the port is free again }
    AssertEquals('merhaba dünya', HttpGetText(Format('http://127.0.0.1:%d/hello', [P])));
  finally
    S.Free;
  end;
end;

initialization
  CounterLock := TCriticalSection.Create;
  Capture := TCapture.Create;
  RegisterTests(TWebTests);
end.
