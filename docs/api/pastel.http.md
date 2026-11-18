# Pastel.Http

HTTP and HTTPS client.

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

`uses Pastel.Http;` · source: [framework/src/pastel.http.pas](../../framework/src/pastel.http.pas)

**Contents:** [EHttpError](#ehttperror) · [THttpResponse](#thttpresponse) · [THttpClient](#thttpclient) · [TNetConnection](#tnetconnection) · [ENetError](#eneterror) · [NetConnect](#netconnect) · [HttpGet](#httpget) · [HttpGetText](#httpgettext) · [HttpGetJson](#httpgetjson) · [HttpPost](#httppost) · [HttpPostJson](#httppostjson) · [HttpDownload](#httpdownload) · [UrlEncode](#urlencode) · [QueryString](#querystring)

## Types

### EHttpError

```pascal
type EHttpError = class(Exception)
```

### THttpResponse

```pascal
type THttpResponse = record
```

| | |
|---|---|
| `Status: Integer` | 200, 404, ... |
| `StatusText: string` | 'OK', 'Not Found' |
| `Body: string` |  |
| `Headers: TStringArray` | 'Name: value' |
| `Url: string` | the final address, after redirects |
| `Method: string` |  |
| `Duration: Integer` | milliseconds |
| `function Ok: Boolean` | 200-299 |
| `function Header(const Name: string): string` | A header value by name, any case; '' when missing |
| `function Json: TJSONData` | The body as JSON; the caller frees it. |
| `procedure RaiseForStatus` | Raises EHttpError unless Ok. |

### THttpClient

```pascal
type THttpClient = class
```

| | |
|---|---|
| `constructor Create(const ABaseUrl: string = '')` |  |
| `function Get(const Path: string): THttpResponse` |  |
| `function Get(const Path: string; const Query: array of string): THttpResponse` |  |
| `function Delete(const Path: string): THttpResponse` |  |
| `function Head(const Path: string): THttpResponse` |  |
| `function Post(const Path: string; const Body: string; const ContentType: string = 'text/plain; charset=utf-8'): THttpResponse` |  |
| `function Put(const Path: string; const Body: string; const ContentType: string = 'text/plain; charset=utf-8'): THttpResponse` |  |
| `function Patch(const Path: string; const Body: string; const ContentType: string = 'text/plain; charset=utf-8'): THttpResponse` |  |
| `function PostJson(const Path: string; const Json: string): THttpResponse` |  |
| `function PostJson(const Path: string; Json: TJSONData): THttpResponse` |  |
| `function PutJson(const Path: string; const Json: string): THttpResponse` |  |
| `function PostForm(const Path: string; const Fields: array of string): THttpResponse` | Fields in turn: name, value, name, value |
| `function Request(const Method: string; const Path: string; const Body: string; const ContentType: string): THttpResponse` |  |
| `procedure Download(const Path: string; const FileName: string)` | Streams into FileName (through a temporary file); raises unless 2xx. |
| `property BaseUrl: string` |  |

### TNetConnection

```pascal
type TNetConnection = class
```

A connection of another protocol than HTTP (SMTP, WebSocket): bytes both
ways, TLS or not. Read and Write may run on two threads at once.

| | |
|---|---|
| `function Read(var Buffer; Count: Integer): Integer` | up to Count bytes; 0 when the connection is closed; ENetError when it broke |
| `procedure Write(const Buffer; Count: Integer)` | all of them, or ENetError |
| `procedure WriteText(const S: RawByteString)` |  |
| `function ReadLine: string` | a line without its CR LF; ENetError when the connection closes first |
| `procedure Shutdown` | ends the connection; a Read waiting on another thread returns 0 |
| `procedure SetReadTimeout(Ms: Integer)` | milliseconds a Read waits; 0: until something comes |

### ENetError

```pascal
type ENetError = class(Exception)
```

## Other types

| | |
|---|---|
| `type THttpProgressEvent = procedure(Done: Int64; Total: Int64)` |  |
| `type TBeforeTlsEvent = function(Conn: TNetConnection): string` | the plain part of a connection before TLS starts (SMTP's STARTTLS): lines with WriteText/ReadLine; '' when TLS can start, else what went wrong |

## Routines

### NetConnect

```pascal
function NetConnect(const Host: string; Port: Integer; Tls: Boolean; BeforeTls: TBeforeTlsEvent = nil; Timeout: Integer = 30000; Verify: Boolean = True; ReadTimeout: Integer = 30000): TNetConnection
```

A TCP connection to Host:Port; Tls: TLS, its certificate checked like HTTPS's
(Verify False accepts any: tests only). BeforeTls talks plain first, then TLS
starts (Tls must be True). Timeout: milliseconds for connecting; ReadTimeout:
for a Read, 0 for none. ENetError with the reason when it fails. On Android
Android's own sockets and TLS (dev.pastel.PastelSocket).

### HttpGet

```pascal
function HttpGet(const Url: string): THttpResponse
```

### HttpGetText

```pascal
function HttpGetText(const Url: string): string
```

The body; raises EHttpError unless 2xx.

### HttpGetJson

```pascal
function HttpGetJson(const Url: string): TJSONData
```

Parsed JSON (the caller frees it); raises EHttpError unless 2xx.

### HttpPost

```pascal
function HttpPost(const Url: string; const Body: string; const ContentType: string): THttpResponse
```

### HttpPostJson

```pascal
function HttpPostJson(const Url: string; const Json: string): THttpResponse
```

### HttpDownload

```pascal
procedure HttpDownload(const Url: string; const FileName: string)
```

### UrlEncode

```pascal
function UrlEncode(const S: string): string
```

'a b&c' -> 'a%20b%26c'

### QueryString

```pascal
function QueryString(const Pairs: array of string): string
```

['q', 'çay', 'n', '2'] -> 'q=%C3%A7ay&n=2'

