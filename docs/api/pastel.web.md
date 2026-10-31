# Pastel.Web

HTTP server for web APIs and sites.

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

`uses Pastel.Web;` · source: [framework/src/pastel.web.pas](../../framework/src/pastel.web.pas)

**Contents:** [EWebError](#eweberror) · [TValidator](#tvalidator) · [EWebServerError](#ewebservererror) · [TWebRequest](#twebrequest) · [TWebResponse](#twebresponse) · [TWebRoute](#twebroute) · [TWebServer](#twebserver) · [TWebServerThread](#twebserverthread) · [TWebService](#twebservice) · [ContentTypeOf](#contenttypeof) · [UrlDecode](#urldecode)

## Types

### EWebError

```pascal
type EWebError = class(Exception)
```

Raise it in a handler to answer with this status and {"error": Message}

| | |
|---|---|
| `constructor Create(AStatus: Integer; const AMessage: string)` |  |
| `constructor CreateFmt(AStatus: Integer; const Fmt: string; const Args: array of const)` |  |
| `destructor Destroy` |  |

### TValidator

```pascal
type TValidator = class
```

Checks the fields of a JSON request and collects every problem:

V := Req.Validate;
Title := V.Str('title', 1, 200);
Age := V.OptInt('age', 0, 0, 150);
V.Check;      // 422 {"error": "...", "fields": {"title": "is required"}}

| | |
|---|---|
| `constructor Create(AData: TJSONObject)` | Data is not owned |
| `destructor Destroy` |  |
| `function Str(const Name: string; MinLength: Integer = 1; MaxLength: Integer = MaxInt): string` | required text, MinLength..MaxLength characters (after trimming spaces) |
| `function OptStr(const Name: string; const Default: string; MaxLength: Integer = MaxInt): string` |  |
| `function Int(const Name: string; Min: Int64 = Low (Int64); Max: Int64 = High (Int64)): Int64` |  |
| `function OptInt(const Name: string; Default: Int64; Min: Int64 = Low (Int64); Max: Int64 = High (Int64)): Int64` |  |
| `function Float(const Name: string; Min: Double = -1e308; Max: Double = 1e308): Double` |  |
| `function OptFloat(const Name: string; Default: Double; Min: Double = -1e308; Max: Double = 1e308): Double` |  |
| `function Bool(const Name: string): Boolean` |  |
| `function OptBool(const Name: string; Default: Boolean): Boolean` |  |
| `function Choice(const Name: string; const Choices: array of string): string` | required; one of Choices |
| `function Email(const Name: string): string` | required; a plausible e-mail address |
| `procedure AddError(const Name: string; const Message: string)` | for your own rules: V.AddError('end', 'must be after start') |
| `function Ok: Boolean` |  |
| `procedure Check` | 422 with every problem, unless Ok |

### EWebServerError

```pascal
type EWebServerError = class(Exception)
```

The server could not start (port in use, no permission, ...).

### TWebRequest

```pascal
type TWebRequest = class
```

| | |
|---|---|
| `constructor Create(AReq: TFPHTTPConnectionRequest; const APath: string; ATrustProxy: Boolean = False)` |  |
| `destructor Destroy` |  |
| `function Method: string` |  |
| `property Path: string` | the path without the query: /users/42 |
| `property Body: string` | the request body as text |
| `function ClientIP: string` | the client's address; with TrustProxy the first one in X-Forwarded-For |
| `function Param(const Name: string): string` | a part of the path: Param('id') for the route /users/:id |
| `function ParamInt(const Name: string): Int64` | ... as a number; 400 Bad Request when it is not one |
| `function Query(const Name: string; const Default: string = ''): string` | ?page=2 |
| `function QueryInt(const Name: string; Default: Int64): Int64` |  |
| `function HasQuery(const Name: string): Boolean` |  |
| `function Header(const Name: string): string` |  |
| `function Form(const Name: string; const Default: string = ''): string` | a field of a submitted HTML form (application/x-www-form-urlencoded) |
| `function Json: TJSONData` | the body as JSON; 400 when it is missing or not JSON. Owned by the request. |
| `function JsonObject: TJSONObject` | the same, and it must be a JSON object |
| `function Validate: TValidator` | checks the JSON body's fields; owned by the request |
| `function Claim(const Name: string): string` | a claim of the JWT checked by RequireJwt: Claim('sub') |
| `property Params: TStringList` | the route's parameters, name=value |
| `property Values: TStringList` | for filters to pass things on to handlers: Req.Values['user'] := ... |
| `property Claims: TJSONObject` | the claims of the JWT checked by RequireJwt (nil without one) |

### TWebResponse

```pascal
type TWebResponse = class
```

| | |
|---|---|
| `constructor Create(ARes: TFPHTTPConnectionResponse)` |  |
| `procedure SetHeader(const Name: string; const Value: string)` |  |
| `procedure Text(const S: string; AStatus: Integer = 200)` |  |
| `procedure Html(const S: string; AStatus: Integer = 200)` |  |
| `procedure Json(Data: TJSONData; AStatus: Integer = 200)` | sends Data and frees it |
| `procedure JsonText(const S: string; AStatus: Integer = 200)` |  |
| `procedure Error(AStatus: Integer; const Message: string)` | answers {"error": Message} |
| `procedure SendFile(const FileName: string; const ContentType: string = '')` |  |
| `procedure Redirect(const Url: string; AStatus: Integer = 302)` |  |
| `procedure NoContent` | 204, no body |
| `property Status: Integer` |  |
| `property Sent: Boolean` | something was answered already |

### TWebRoute

```pascal
type TWebRoute = class
```

### TWebServer

```pascal
type TWebServer = class
```

| | |
|---|---|
| `constructor Create(APort: Integer = 8080; const AAddress: string = '')` | Address: '' or '0.0.0.0' for every network, '127.0.0.1' for this computer only |
| `destructor Destroy` |  |
| `procedure Get(const Pattern: string; Handler: TWebHandler)` |  |
| `procedure Get(const Pattern: string; Handler: TWebHandlerProc)` |  |
| `procedure Post(const Pattern: string; Handler: TWebHandler)` |  |
| `procedure Post(const Pattern: string; Handler: TWebHandlerProc)` |  |
| `procedure Put(const Pattern: string; Handler: TWebHandler)` |  |
| `procedure Put(const Pattern: string; Handler: TWebHandlerProc)` |  |
| `procedure Patch(const Pattern: string; Handler: TWebHandler)` |  |
| `procedure Patch(const Pattern: string; Handler: TWebHandlerProc)` |  |
| `procedure Delete(const Pattern: string; Handler: TWebHandler)` |  |
| `procedure Delete(const Pattern: string; Handler: TWebHandlerProc)` |  |
| `procedure Static(const UrlPrefix: string; const Folder: string)` | the files of Folder under UrlPrefix: Static('/assets', 'public/assets') |
| `procedure Health(const Path: string = '/health'; const Version: string = '')` | GET Path answers {"status":"ok","version":...,"uptime_seconds":...} |
| `procedure Use(const Prefix: string; Filter: TWebHandler)` | Runs Filter before the handler of every route under Prefix ('/api' covers /api and /api/...). A filter stops the request by raising EWebError or by answering (Res.Error, ...). In the order added. |
| `procedure Use(const Prefix: string; Filter: TWebHandlerProc)` |  |
| `procedure RequireApiKey(const Prefix: string; const Keys: array of string)` | "Authorization: Bearer <key>" or "X-API-Key: <key>" must hold one of Keys |
| `procedure RequireJwt(const Prefix: string; const Secret: string)` | "Authorization: Bearer <JWT>" signed with Secret; the claims go to Req.Claims |
| `procedure RateLimit(const Prefix: string; Count: Integer; Seconds: Integer)` | at most Count requests in Seconds from one client address; then 429 |
| `procedure Cors(const Origins: array of string; AllowCredentials: Boolean = False)` | lets web pages from these origins call the API ('https://app.example.com', or '*') |
| `property TrustProxy: Boolean` | behind nginx/Caddy: take the client address from X-Forwarded-For |
| `procedure Start` | starts listening; EWebServerError when that is not possible |
| `procedure Stop` | stops accepting, lets running requests finish |
| `function Running: Boolean` |  |
| `function Url: string` | http://localhost:8080 |
| `property Port: Integer` |  |
| `property Address: string` |  |
| `property AccessLog: Boolean` | a log line for every request (default on) |
| `property Requests: Int64` |  |

### TWebServerThread

```pascal
type TWebServerThread = class(TThread)
```

| | |
|---|---|
| `procedure Idle(Sender: TObject)` |  |
| `procedure Execute` |  |

### TWebService

```pascal
type TWebService = class(TService)
```

A service with a web server: settings server.port (8080) and
server.address; routes are added in Routes.

| | |
|---|---|
| `destructor Destroy` |  |
| `property Server: TWebServer` |  |

## Other types

| | |
|---|---|
| `type TWebHandler = procedure(Req: TWebRequest; Res: TWebResponse)` |  |
| `type TWebHandlerProc = procedure(Req: TWebRequest; Res: TWebResponse)` |  |

## Routines

### ContentTypeOf

```pascal
function ContentTypeOf(const FileName: string): string
```

'application/json' for 'x.json', ...

### UrlDecode

```pascal
function UrlDecode(const S: string): string
```

