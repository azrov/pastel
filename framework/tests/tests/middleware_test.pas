unit Middleware_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.Testing, Pastel.Web, Pastel.Http, Pastel.Json,
  Pastel.Jwt, Pastel.Log;

type
  TMiddlewareTests = class(TTestSuite)
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ApiKeyIsRequired;
    procedure WrongApiKeyIsRefused;
    procedure ApiKeyInEitherHeader;
    procedure OtherRoutesStayOpen;
    procedure JwtGivesClaims;
    procedure BadJwtIsRefused;
    procedure FiltersPassValuesOn;
    procedure FiltersCanAnswer;
    procedure RateLimitAnswers429;
    procedure CorsForAllowedOrigins;
    procedure CorsPreflight;
    procedure ClientIPBehindAProxy;
    procedure ValidationListsEveryProblem;
    procedure ValidationChecksTypesAndRanges;
    procedure ValidRequestPasses;
  end;

implementation

const
  Key = 'k-0123456789abcdef-test';
  Secret = 'jwt-secret-0123456789-0123456789-abc';

var
  Server: TWebServer = nil;
  Base: string;
  Maintenance: Boolean = False;

procedure Ok(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text('ok ' + Req.Values.Values['auth']);
end;

procedure Me(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text(Req.Claim('sub') + ' ' + Req.Claim('role'));
end;

procedure Tagged(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text(Req.Values.Values['tag']);
end;

procedure AddTag(Req: TWebRequest; Res: TWebResponse);
begin
  Req.Values.Values['tag'] := 'from the filter';
end;

procedure MaybeClosed(Req: TWebRequest; Res: TWebResponse);
begin
  if Maintenance then
    Res.Error(503, 'closed for maintenance');
end;

procedure WhoAmI(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text(Req.ClientIP);
end;

procedure Register(Req: TWebRequest; Res: TWebResponse);
var
  V: TValidator;
  Name, Email, Plan: string;
  Age: Int64;
  News: Boolean;
begin
  V := Req.Validate;
  Name := V.Str('name', 2, 50);
  Email := V.Email('email');
  Age := V.OptInt('age', 0, 0, 150);
  Plan := V.Choice('plan', ['free', 'pro']);
  News := V.OptBool('news', False);
  V.Check;
  Res.Json(JObject(['name', Name, 'email', Email, 'age', Age, 'plan', Plan, 'news', News]), 201);
end;

procedure StartServer;
var
  Port: Integer;
begin
  if Server <> nil then
    Exit;
  Port := 22000 + Random(20000);
  Base := Format('http://127.0.0.1:%d', [Port]);
  Server := TWebServer.Create(Port, '127.0.0.1');
  Server.AccessLog := False;
  Server.RequireApiKey('/keyed', [Key, 'k-second-key-0123456789']);
  Server.RequireJwt('/me', Secret);
  Server.Use('/tagged', @AddTag);
  Server.Use('/', @MaybeClosed);
  Server.RateLimit('/limited', 3, 60);
  Server.Cors(['https://app.example.com']);
  Server.Get('/keyed/data', @Ok);
  Server.Get('/keyedless', @Ok);
  Server.Get('/open', @Ok);
  Server.Get('/me', @Me);
  Server.Get('/tagged', @Tagged);
  Server.Get('/limited', @Ok);
  Server.Get('/whoami', @WhoAmI);
  Server.Post('/register', @Register);
  Server.Start;
end;

procedure TMiddlewareTests.SetUp;
begin
  StartServer;
  Log.Console := False;
end;

procedure TMiddlewareTests.TearDown;
begin
  Log.Console := True;
end;

function GetWith(const Path: string; const Headers: array of string): THttpResponse;
var
  C: THttpClient;
  I: Integer;
begin
  C := THttpClient.Create(Base);
  try
    SetLength(C.Headers, Length(Headers));
    for I := 0 to High(Headers) do
      C.Headers[I] := Headers[I];
    Result := C.Get(Path);
  finally
    C.Free;
  end;
end;

procedure TMiddlewareTests.ApiKeyIsRequired;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/keyed/data');
  AssertEquals(401, R.Status);
  AssertContains('an API key is required', R.Body);
  AssertEquals('Bearer', R.Header('WWW-Authenticate'));
end;

procedure TMiddlewareTests.WrongApiKeyIsRefused;
var
  R: THttpResponse;
begin
  R := GetWith('/keyed/data', ['X-API-Key: k-0123456789abcdef-tesT']);
  AssertEquals(401, R.Status);
  AssertContains('the API key is not valid', R.Body);
end;

procedure TMiddlewareTests.ApiKeyInEitherHeader;
begin
  AssertEquals('ok api-key', GetWith('/keyed/data', ['X-API-Key: ' + Key]).Body);
  AssertEquals('ok api-key', GetWith('/keyed/data', ['Authorization: Bearer k-second-key-0123456789']).Body);
end;

procedure TMiddlewareTests.OtherRoutesStayOpen;
begin
  AssertEquals('ok ', HttpGetText(Base + '/open'));
  { "/keyed" protects /keyed and /keyed/..., not /keyedless }
  AssertEquals('ok ', HttpGetText(Base + '/keyedless'));
end;

procedure TMiddlewareTests.JwtGivesClaims;
var
  Token: string;
begin
  Token := JwtSign(JObject(['sub', 'ayşe', 'role', 'admin']), Secret, 60);
  AssertEquals('ayşe admin', GetWith('/me', ['Authorization: Bearer ' + Token]).Body);
end;

procedure TMiddlewareTests.BadJwtIsRefused;
var
  R: THttpResponse;
begin
  R := HttpGet(Base + '/me');
  AssertEquals(401, R.Status);
  AssertContains('a token is required', R.Body);
  R := GetWith('/me', ['Authorization: Bearer ' +
    JwtSign(JObject(['sub', 'x']), 'some-other-secret-0123456789-0123456789', 60)]);
  AssertEquals(401, R.Status);
  AssertContains('the JWT signature is wrong', R.Body);
  R := GetWith('/me', ['Authorization: Bearer not.a.token']);
  AssertEquals(401, R.Status);
end;

procedure TMiddlewareTests.FiltersPassValuesOn;
begin
  AssertEquals('from the filter', HttpGetText(Base + '/tagged'));
end;

procedure TMiddlewareTests.FiltersCanAnswer;
var
  R: THttpResponse;
begin
  Maintenance := True;
  try
    R := HttpGet(Base + '/open');
    AssertEquals(503, R.Status);
    AssertContains('closed for maintenance', R.Body);
  finally
    Maintenance := False;
  end;
end;

procedure TMiddlewareTests.RateLimitAnswers429;
var
  R: THttpResponse;
  I: Integer;
begin
  for I := 1 to 3 do
  begin
    R := HttpGet(Base + '/limited');
    AssertEquals(200, R.Status, R.Body);
    AssertEquals(IntToStr(3 - I), R.Header('RateLimit-Remaining'));
  end;
  R := HttpGet(Base + '/limited');
  AssertEquals(429, R.Status);
  AssertContains('too many requests', R.Body);
  AssertTrue(StrToIntDef(R.Header('Retry-After'), 0) > 0);
  AssertEquals(200, HttpGet(Base + '/open').Status, 'other routes are not limited');
end;

procedure TMiddlewareTests.CorsForAllowedOrigins;
begin
  AssertEquals('https://app.example.com',
    GetWith('/open', ['Origin: https://app.example.com']).Header('Access-Control-Allow-Origin'));
  AssertEquals('', GetWith('/open', ['Origin: https://evil.example']).Header('Access-Control-Allow-Origin'));
  AssertEquals('', HttpGet(Base + '/open').Header('Access-Control-Allow-Origin'));
end;

procedure TMiddlewareTests.CorsPreflight;
var
  C: THttpClient;
  R: THttpResponse;
begin
  C := THttpClient.Create(Base);
  try
    C.Headers := ['Origin: https://app.example.com', 'Access-Control-Request-Method: POST',
      'Access-Control-Request-Headers: content-type'];
    R := C.Request('OPTIONS', '/register', '', '');
    AssertEquals(204, R.Status);
    AssertEquals('POST', R.Header('Access-Control-Allow-Methods'));
    AssertEquals('content-type', R.Header('Access-Control-Allow-Headers'));
    AssertEquals('https://app.example.com', R.Header('Access-Control-Allow-Origin'));
  finally
    C.Free;
  end;
end;

procedure TMiddlewareTests.ClientIPBehindAProxy;
begin
  AssertEquals('127.0.0.1', GetWith('/whoami', ['X-Forwarded-For: 203.0.113.9']).Body);
  Server.TrustProxy := True;
  try
    AssertEquals('203.0.113.9', GetWith('/whoami', ['X-Forwarded-For: 203.0.113.9, 10.0.0.1']).Body);
  finally
    Server.TrustProxy := False;
  end;
end;

procedure TMiddlewareTests.ValidationListsEveryProblem;
var
  R: THttpResponse;
  D: TJSONData;
begin
  R := HttpPostJson(Base + '/register', '{"name": "A", "plan": "gold"}');
  AssertEquals(422, R.Status);
  D := R.Json;
  try
    AssertEquals('3 fields are not right', JStr(D, 'error'));
    AssertEquals('must be at least 2 characters', JStr(D, 'fields.name'));
    AssertEquals('is required', JStr(D, 'fields.email'));
    AssertEquals('must be one of: free, pro', JStr(D, 'fields.plan'));
  finally
    D.Free;
  end;
end;

procedure TMiddlewareTests.ValidationChecksTypesAndRanges;
var
  R: THttpResponse;
  D: TJSONData;
begin
  R := HttpPostJson(Base + '/register',
    '{"name": 42, "email": "ali@", "age": 200, "plan": "pro", "news": "yes"}');
  AssertEquals(422, R.Status);
  D := R.Json;
  try
    AssertEquals('must be text', JStr(D, 'fields.name'));
    AssertEquals('must be an email address', JStr(D, 'fields.email'));
    AssertEquals('must be between 0 and 150', JStr(D, 'fields.age'));
    AssertEquals('must be true or false', JStr(D, 'fields.news'));
  finally
    D.Free;
  end;
  R := HttpPostJson(Base + '/register', '{"name": "Ali", "email": "ali@example.com", "age": 2.5, "plan": "pro"}');
  AssertEquals('{"error":"age must be a whole number","fields":{"age":"must be a whole number"}}', R.Body);
end;

procedure TMiddlewareTests.ValidRequestPasses;
var
  R: THttpResponse;
begin
  R := HttpPostJson(Base + '/register',
    '{"name": "  Çiğdem ", "email": "cigdem@example.com", "plan": "free", "news": true}');
  AssertEquals(201, R.Status);
  AssertEquals('{"name":"Çiğdem","email":"cigdem@example.com","age":0,"plan":"free","news":true}', R.Body);
end;

initialization
  RegisterTests(TMiddlewareTests);
end.
