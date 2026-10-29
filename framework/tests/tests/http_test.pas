unit Http_Test;

{ A small HTTP server runs inside the test program, so these tests need no
  network. Set PASTEL_NET_TESTS=1 to also try a real HTTPS site. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.Testing, Pastel.Http, Pastel.Json, Pastel.Files;

type
  THttpTests = class(TTestSuite)
  private
    procedure GetMissingHost;
    procedure GetClosedPort;
    procedure GetNotFound;
    procedure GetSlow;
  public
    procedure SetUp; override;
  published
    procedure GetsText;
    procedure ReadsHeaders;
    procedure GetsJson;
    procedure PostsJsonAndHeaders;
    procedure PostsForm;
    procedure BuildsUrlsFromBaseAndQuery;
    procedure SendsBearerToken;
    procedure OtherMethods;
    procedure ErrorStatusIsAnAnswer;
    procedure RaiseForStatusExplains;
    procedure FollowsRedirects;
    procedure CanStopAtRedirects;
    procedure DownloadsFiles;
    procedure ReportsProgress;
    procedure UnknownHostIsExplained;
    procedure ClosedPortIsExplained;
    procedure TimesOut;
    procedure UsesHttpProxy;
    procedure EncodesUrls;
    procedure RealHttps;
  end;

implementation

uses
  fphttpserver, httpdefs;

type
  TServerThread = class(TThread)
  public
    Server: TFPHttpServer;
    procedure Handle(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
    procedure Execute; override;
  end;

  TProgressCounter = class
    Calls: Integer;
    Last: Int64;
    procedure Progress(Done, Total: Int64);
  end;

var
  ServerThread: TServerThread = nil;
  Port: Integer;

function Base: string;
begin
  Result := 'http://127.0.0.1:' + IntToStr(Port);
end;

procedure TProgressCounter.Progress(Done, Total: Int64);
begin
  Inc(Calls);
  Last := Done;
end;

procedure TServerThread.Handle(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  Path, Body: string;
begin
  Body := '';
  Path := ARequest.URI;
  if Pos('?', Path) > 0 then
    SetLength(Path, Pos('?', Path) - 1);
  AResponse.ContentType := 'text/plain; charset=utf-8';
  AResponse.Code := 200;
  if Path.StartsWith('http://') then
    Body := 'proxied ' + ARequest.URI
  else if Path = '/hello' then
  begin
    AResponse.SetCustomHeader('X-Server', 'pastel-test');
    Body := 'merhaba dünya';
  end
  else if Path = '/json' then
  begin
    AResponse.ContentType := 'application/json';
    Body := '{"name": "Ayşe", "n": 2}';
  end
  else if Path = '/echo' then
    Body := ARequest.Method + '|' + ARequest.QueryString + '|' +
      ARequest.ContentType + '|' + ARequest.Content + '|' +
      ARequest.GetCustomHeader('X-Test') + '|' + ARequest.Authorization
  else if Path = '/missing' then
  begin
    AResponse.Code := 404;
    AResponse.CodeText := 'Not Found';
    Body := 'no such thing';
  end
  else if Path = '/redirect' then
  begin
    AResponse.Code := 302;
    AResponse.CodeText := 'Found';
    AResponse.Location := '/hello';
    Body := 'go away';
  end
  else if Path = '/big' then
    Body := StringOfChar('x', 500000)
  else if Path = '/slow' then
  begin
    Sleep(1500);
    Body := 'late';
  end
  else
  begin
    AResponse.Code := 404;
    AResponse.CodeText := 'Not Found';
  end;
  { Content would add a line break }
  AResponse.ContentStream := TStringStream.Create(Body);
  AResponse.FreeContentStream := True;
end;

procedure TServerThread.Execute;
begin
  try
    Server.Active := True;
  except
    on E: Exception do
      WriteLn(StdErr, 'test server: ', E.Message);
  end;
end;

procedure StartServer;
var
  I: Integer;
begin
  if ServerThread <> nil then
    Exit;
  Port := 20000 + Random(20000);
  ServerThread := TServerThread.Create(True);
  ServerThread.FreeOnTerminate := False;
  ServerThread.Server := TFPHttpServer.Create(nil);
  ServerThread.Server.Port := Port;
  ServerThread.Server.Threaded := True;
  ServerThread.Server.OnRequest := @ServerThread.Handle;
  ServerThread.Start;
  for I := 1 to 100 do
  begin
    if ServerThread.Server.Active then
      Break;
    Sleep(10);
  end;
  Sleep(50);
end;

procedure THttpTests.SetUp;
begin
  StartServer;
end;

procedure THttpTests.GetsText;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/hello');
  AssertEquals(200, R.Status);
  AssertTrue(R.Ok);
  AssertEquals('merhaba dünya', R.Body);
  AssertEquals('merhaba dünya', HttpGetText(Base + '/hello'));
end;

procedure THttpTests.ReadsHeaders;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/hello');
  AssertEquals('pastel-test', R.Header('x-server'));
  AssertContains('text/plain', R.Header('Content-Type'));
  AssertEquals('', R.Header('X-Nothing'));
end;

procedure THttpTests.GetsJson;
var
  D: TJSONData;
begin
  D := HttpGetJson(Base + '/json');
  try
    AssertEquals('Ayşe', JStr(D, 'name'));
    AssertEquals(2, JInt(D, 'n'));
  finally
    D.Free;
  end;
end;

procedure THttpTests.PostsJsonAndHeaders;
var
  C: THttpClient;
  R: THttpResponse;
begin
  C := THttpClient.Create(Base);
  try
    C.Headers := ['X-Test: çay'];
    R := C.PostJson('/echo', '{"a": 1}');
    AssertEquals('POST||application/json|{"a": 1}|çay|', R.Body);
  finally
    C.Free;
  end;
end;

procedure THttpTests.PostsForm;
var
  C: THttpClient;
begin
  C := THttpClient.Create(Base);
  try
    AssertEquals('POST||application/x-www-form-urlencoded|user=ali&note=a%20b%26c||',
      C.PostForm('/echo', ['user', 'ali', 'note', 'a b&c']).Body);
  finally
    C.Free;
  end;
end;

procedure THttpTests.BuildsUrlsFromBaseAndQuery;
var
  C: THttpClient;
begin
  C := THttpClient.Create(Base + '/');
  try
    AssertEquals('GET|q=%C3%A7ay&page=2||||', C.Get('/echo', ['q', 'çay', 'page', '2']).Body);
    AssertEquals('GET|x=1&y=2||||', C.Get('echo?x=1', ['y', '2']).Body);
    AssertEquals('merhaba dünya', C.Get(Base + '/hello').Body);
  finally
    C.Free;
  end;
end;

procedure THttpTests.SendsBearerToken;
var
  C: THttpClient;
begin
  C := THttpClient.Create(Base);
  try
    C.BearerToken := 'abc123';
    AssertEquals('GET|||||Bearer abc123', C.Get('/echo').Body);
  finally
    C.Free;
  end;
end;

procedure THttpTests.OtherMethods;
var
  C: THttpClient;
begin
  C := THttpClient.Create(Base);
  try
    AssertEquals('PUT||application/json|{}||', C.PutJson('/echo', '{}').Body);
    AssertEquals('PATCH||text/plain; charset=utf-8|x||', C.Patch('/echo', 'x').Body);
    AssertEquals('DELETE|||||', C.Delete('/echo').Body);
    AssertEquals(200, C.Head('/hello').Status);
  finally
    C.Free;
  end;
end;

procedure THttpTests.ErrorStatusIsAnAnswer;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/missing');
  AssertEquals(404, R.Status);
  AssertFalse(R.Ok);
  AssertEquals('Not Found', R.StatusText);
  AssertEquals('no such thing', R.Body);
end;

procedure THttpTests.GetNotFound;
begin
  HttpGetText(Base + '/missing');
end;

procedure THttpTests.RaiseForStatusExplains;
begin
  try
    GetNotFound;
    Fail('no exception');
  except
    on E: EHttpError do
    begin
      AssertEquals('GET ' + Base + '/missing: 404 Not Found: no such thing', E.Message);
      AssertEquals(404, E.Status);
    end;
  end;
end;

procedure THttpTests.FollowsRedirects;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/redirect');
  AssertEquals(200, R.Status);
  AssertEquals('merhaba dünya', R.Body);
  AssertEquals(Base + '/hello', R.Url);
end;

procedure THttpTests.CanStopAtRedirects;
var
  C: THttpClient;
  R: THttpResponse;
begin
  C := THttpClient.Create(Base);
  try
    C.FollowRedirects := False;
    R := C.Get('/redirect');
    AssertEquals(302, R.Status);
    AssertEquals('/hello', R.Header('Location'));
  finally
    C.Free;
  end;
end;

procedure THttpTests.DownloadsFiles;
var
  Dir: string;
begin
  Dir := MakeTempDir('pastel-http-test');
  try
    HttpDownload(Base + '/big', Dir + 'sub/big.txt');
    AssertEquals(500000, FileSize(Dir + 'sub/big.txt'));
    AssertFalse(FileExists(Dir + 'sub/big.txt.part'));
    try
      HttpDownload(Base + '/missing', Dir + 'm.txt');
      Fail('no exception');
    except
      on E: EHttpError do
        AssertEquals(404, E.Status);
    end;
    AssertFalse(FileExists(Dir + 'm.txt'));
    AssertFalse(FileExists(Dir + 'm.txt.part'));
  finally
    DeleteDir(Dir);
  end;
end;

procedure THttpTests.ReportsProgress;
var
  C: THttpClient;
  P: TProgressCounter;
begin
  C := THttpClient.Create(Base);
  P := TProgressCounter.Create;
  try
    C.OnProgress := @P.Progress;
    C.Get('/big');
    AssertTrue(P.Calls > 0);
    AssertEquals(500000, P.Last);
  finally
    P.Free;
    C.Free;
  end;
end;

procedure THttpTests.GetMissingHost;
begin
  HttpGet('http://no-such-host.invalid/x');
end;

procedure THttpTests.UnknownHostIsExplained;
begin
  try
    GetMissingHost;
    Fail('no exception');
  except
    on E: EHttpError do
      AssertContains('cannot find server "no-such-host.invalid"', E.Message);
  end;
end;

procedure THttpTests.GetClosedPort;
begin
  HttpGet('http://127.0.0.1:1/x');
end;

procedure THttpTests.ClosedPortIsExplained;
begin
  try
    GetClosedPort;
    Fail('no exception');
  except
    on E: EHttpError do
    begin
      AssertContains('cannot connect to "127.0.0.1"', E.Message);
      AssertEquals(0, E.Status);
    end;
  end;
end;

procedure THttpTests.GetSlow;
var
  C: THttpClient;
begin
  C := THttpClient.Create(Base);
  try
    C.Timeout := 300;
    C.Get('/slow');
  finally
    C.Free;
  end;
end;

procedure THttpTests.TimesOut;
var
  Start: QWord;
begin
  Start := GetTickCount64;
  AssertRaises(EHttpError, @GetSlow);
  AssertTrue(GetTickCount64 - Start < 1400, 'did not stop waiting');
end;

procedure THttpTests.UsesHttpProxy;
var
  C: THttpClient;
begin
  C := THttpClient.Create;
  try
    C.Proxy := Base;
    AssertEquals('proxied http://example.invalid/page', C.Get('http://example.invalid/page').Body);
  finally
    C.Free;
  end;
end;

procedure THttpTests.EncodesUrls;
begin
  AssertEquals('a%20b%26c', UrlEncode('a b&c'));
  AssertEquals('%C3%A7', UrlEncode('ç'));
  AssertEquals('safe-_.~', UrlEncode('safe-_.~'));
  AssertEquals('q=1&w=a%2Fb', QueryString(['q', '1', 'w', 'a/b']));
end;

procedure THttpTests.RealHttps;
var
  R: THttpResponse;
begin
  if GetEnvironmentVariable('PASTEL_NET_TESTS') = '' then
    Skip('set PASTEL_NET_TESTS=1 to test a real HTTPS site');
  R := HttpGet('https://pypi.org/simple/pip/');
  AssertEquals(200, R.Status);
  AssertContains('pip', R.Body);
end;

initialization
  RegisterTests(THttpTests);
end.
