# Web APIs and sites: `Pastel.Web`

An HTTP server for JSON APIs, small web sites and health checks, in the
same program as the rest of your code. `examples/notes-api` is a complete
example: an API with a web page, run as a service.

## A web service

```pascal
uses Pastel.Service, Pastel.Web, Pastel.Json, fpjson, AppInfo;

type
  TApi = class(TWebService)
  protected
    procedure Routes(Web: TWebServer); override;
  public
    procedure Hello(Req: TWebRequest; Res: TWebResponse);
    procedure GetUser(Req: TWebRequest; Res: TWebResponse);
  end;

procedure TApi.Routes(Web: TWebServer);
begin
  Web.Get('/hello', @Hello);
  Web.Get('/users/:id', @GetUser);
  Web.Health('/health', AppVersion);
end;

procedure TApi.Hello(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Text('Hello, ' + Req.Query('name', 'world'));
end;

procedure TApi.GetUser(Req: TWebRequest; Res: TWebResponse);
begin
  if Req.ParamInt('id') <> 1 then
    raise EWebError.Create(404, 'no user with this id');
  Res.Json(JObject(['id', 1, 'name', 'Ayşe']));
end;

var
  Api: TApi;
begin
  Api := TApi.Create(AppName, AppVersion);
  try
    ExitCode := Api.Run;
  finally
    Api.Free;
  end;
end.
```

`TWebService` is a [service](services.md): it reads its settings, starts the
server in `Started`, stops it cleanly on Ctrl+C or `systemctl stop`, and
under systemd says when it is ready. The settings:

```toml
[server]
port = 8080             # or MYAPP_SERVER_PORT=9000
address = "127.0.0.1"   # only this computer; leave out (or "0.0.0.0") for every network
```

Without a service, the server works on its own too:

```pascal
Web := TWebServer.Create(8080);
Web.Get('/hello', @Hello);
Web.Start;          { in the background }
...
Web.Stop;
```

## Routes

| | |
|---|---|
| `Web.Get('/users', @List)` | also `Post`, `Put`, `Patch`, `Delete` |
| `/users/:id` | `:id` matches one part of the path: `Req.Param('id')` |
| `/files/*` | `*` matches the rest: `Req.Param('*')` is `a/b/c.txt` |
| `Web.Static('/', 'public')` | the files in a folder: `/app.css` → `public/app.css`, `/` → `public/index.html` |
| `Web.Health('/health', AppVersion)` | `{"status":"ok","version":"1.0.0","uptime_seconds":..., "requests":...}` |

Routes are tried in the order they were added. A static folder only answers
when the file exists, so routes added after `Static('/', ...)` still work.
Paths in a static folder cannot leave it (`..` gives 404). `HEAD` requests
are answered like `GET`, without the body.

A path that matches no route gets **404** `{"error": "no route for GET /x"}`;
one that matches with another method gets **405** with an `Allow` header.

## The request: `TWebRequest`

| | |
|---|---|
| `Req.Method`, `Req.Path`, `Req.Body`, `Req.ClientIP` | |
| `Req.Param('id')`, `Req.ParamInt('id')` | parts of the path |
| `Req.Query('q', Default)`, `Req.QueryInt('page', 1)`, `Req.HasQuery('all')` | `?q=...&page=2&all` |
| `Req.Header('Authorization')` | any request header |
| `Req.Json`, `Req.JsonObject` | the body as JSON (it belongs to the request: do not free it) |
| `Req.Form('name')` | a field of a submitted HTML form |

`ParamInt`, `QueryInt`, `Json` and `JsonObject` answer **400** with a clear
message by themselves when the client sends something wrong:
`{"error": "id must be a whole number, not \"abc\""}`.

## The response: `TWebResponse`

| | |
|---|---|
| `Res.Json(Data, 201)` | sends a `TJSONData` and frees it |
| `Res.JsonText('{"ok":true}')` | JSON you already have as text |
| `Res.Text(S)`, `Res.Html(S)` | UTF-8 text |
| `Res.SendFile(FileName)` | a file, with its content type and `Last-Modified` |
| `Res.Redirect('/new', 301)` | |
| `Res.NoContent` | 204; also what a handler that sends nothing answers |
| `Res.Error(422, 'title is required')` | `{"error": "title is required"}` |
| `Res.SetHeader(Name, Value)` | |

The status is 200 unless given.

## Errors

| In the handler | The client gets |
|---|---|
| `raise EWebError.Create(404, 'no user with this id')` | 404 `{"error": "no user with this id"}` |
| a bad number, bad JSON | 400 with the reason |
| any other exception | 500 `{"error": "internal error"}`, and the exception in the log |

In debug builds (`pastel run`) the 500 answer also contains the exception's
message, which helps while developing; release builds never show it to
clients.

## Threads

Requests are answered at the same time, each in its own thread. Anything
handlers share must be safe for that: read-only data, or a lock around it
(`TCriticalSection` from `SyncObjs`), as `TNoteStore` in `examples/notes-api`
does. Logging with `Pastel.Log` is safe.

## The log

Every request is logged with its status and time:

```
2026-10-30 18:36:21.419 INFO  POST /api/notes status=201 ms=0
```

`Web.AccessLog := False` turns it off. With `[log] format = "json"` the lines
are JSON for log collectors.

## In production

- Put a reverse proxy in front for HTTPS and the domain name: nginx or Caddy (`reverse_proxy localhost:8080`). The server itself speaks plain HTTP.
- Listen on `127.0.0.1` when the proxy runs on the same machine.
- `/health` is for monitoring and load balancers.
- Run it as a systemd service: [services.md](services.md).

## Limits today

- No HTTPS in the server itself (use a reverse proxy).
- Every connection is closed after one request (no keep-alive); behind a proxy this does not matter.
- The whole request body is read into memory: keep uploads small, or limit them in the proxy (`client_max_body_size` in nginx).
- No middleware yet (authentication, CORS, rate limits): planned for the next part.
