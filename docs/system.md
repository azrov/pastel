# Files, programs, HTTP and the environment

| Unit | For |
|---|---|
| `Pastel.Files` | Reading and writing files, folders, paths, sizes |
| `Pastel.Process` | Running other programs and reading their output |
| `Pastel.Http` | HTTP and HTTPS requests, JSON APIs, downloads |
| `Pastel.Env` | Environment variables in UTF-8 on every system |

All text is UTF-8, and errors say in plain words what went wrong and with which file, program or address.

## Files: `Pastel.Files`

```pascal
uses Pastel.Files;

Text := ReadText('notes.txt');
WriteText('out/report.txt', Text);              // creates out/ when needed
AppendText('logs/app.log', 'started' + LineEnding);
for Line in ReadLines('list.txt') do ...
WriteLines('names.txt', ['Ali', 'Ayşe']);

for F in ListFiles('photos', '*.jpg', True) do  // True: also in sub-folders
  WriteLn(F, '  ', FormatSize(FileSize(F)));    // photos/a.jpg  1.4 MB
```

`WriteText` never leaves a half-written file: it writes a temporary file and puts it in place at the end, so a crash or a full disk keeps the old content.

| | |
|---|---|
| `ReadText`, `WriteText`, `AppendText` | Whole files as text (a UTF-8 byte order mark is dropped) |
| `ReadLines`, `WriteLines` | Line by line |
| `ReadBytes`, `WriteBytes` | Binary data (`TBytes`) |
| `ListFiles(Dir, Pattern, Recursive)` | Full paths, sorted |
| `ListDirs(Dir)` | Sub-folders, sorted |
| `EnsureDir(Dir)` | Creates the folder and its parents |
| `CopyFile(Src, Dest)`, `MoveFile(Src, Dest)` | Create the destination folder; keep the time of the file |
| `DeleteFileIfExists(Name)`, `DeleteDir(Dir)` | `DeleteDir` removes everything inside |
| `FileSize`, `FileModified` | |
| `JoinPath(['data', 'users', 'ali.json'])` | With `/` or `\` for the system |
| `RelativePath(File, BaseDir)` | |
| `AppDir`, `HomeDir`, `MakeTempDir` | The program's folder, the user's folder, a new empty temporary folder |
| `FormatSize(1536)` | `'1.5 KB'` |

Errors raise `EFileError`: `cannot read "config.txt": cannot open it (does it exist, and may this program read it?)`.

## Programs: `Pastel.Process`

```pascal
uses Pastel.Process;

Branch := RunOutput('git', ['rev-parse', '--abbrev-ref', 'HEAD']);

R := Run('tar', ['czf', 'backup.tgz', 'data']);
if not R.Ok then
  WriteLn('tar failed: ', R.Errors);

Code := RunLive('apt-get', ['update']);    // its output goes straight to the terminal
R := Shell('ls *.log | wc -l');            // a shell command line
if Which('ffmpeg') = '' then
  WriteLn('please install ffmpeg');
```

Arguments are passed exactly as given, one by one: spaces, quotes, `*` and `$` need no escaping and are not interpreted. Only `Shell` goes through the system shell (`/bin/sh`, or `cmd.exe` on Windows) for pipes, wildcards and redirections.

| | |
|---|---|
| `Run(Exe, Args)` | Waits, returns `TRunResult` |
| `RunOutput(Exe, Args)` | The output without the last line break; raises `EProcessError` with the program's error text when it fails |
| `RunLive(Exe, Args)` | Shares this program's terminal, returns the exit code |
| `Shell(CommandLine)` | Like `Run`, through the shell |
| `Which(Name)` | Full path of a program on `PATH`, or `''` |

`TRunResult` has `ExitCode`, `Output`, `Errors`, `TimedOut`, `Duration` (ms), `Ok`, `Text` (the output without the final line break) and `Lines`.

Options:

```pascal
Opts := Default(TRunOptions);
Opts.Dir := '/srv/app';                   // working folder
Opts.Input := 'yes' + LineEnding;         // sent to its standard input
Opts.Env := ['LANG=C', 'APP_MODE=test'];  // added to the environment
Opts.Timeout := 30000;                    // ms; the program is stopped after that
Opts.MergeErrors := True;                 // standard error into Output too
R := Run('./migrate', ['--all'], Opts);
```

A failure reads like `"git" failed (exit code 128): fatal: not a git repository`. A missing program: `program "ffmpeg" was not found (is it installed and on PATH?)`.

## HTTP: `Pastel.Http`

```pascal
uses Pastel.Http, Pastel.Json;

R := HttpGet('https://api.example.com/users/1');
if R.Ok then
  WriteLn(R.Body);

Doc := HttpGetJson('https://api.example.com/users');   // raises unless 2xx
try
  for User in JArray(Doc, 'items') do
    WriteLn(JStr(User, 'name'));
finally
  Doc.Free;
end;

HttpDownload('https://example.com/file.zip', 'downloads/file.zip');
```

For an API you call often, use a client:

```pascal
Api := THttpClient.Create('https://api.example.com/v1');
try
  Api.BearerToken := Config.Require('api.token');
  Api.Timeout := 10000;
  Api.Headers := ['Accept-Language: tr'];

  R := Api.Get('/orders', ['status', 'open', 'page', '2']);   // /orders?status=open&page=2
  R.RaiseForStatus;
  R := Api.PostJson('/orders', '{"item": 42, "count": 1}');
  R := Api.PostForm('/login', ['user', 'ali', 'pass', Secret]);
  R := Api.Delete('/orders/7');
finally
  Api.Free;
end;
```

| `THttpClient` | |
|---|---|
| `Get(Path)`, `Get(Path, Query)`, `Head`, `Delete` | |
| `Post`, `Put`, `Patch(Path, Body, ContentType)` | |
| `PostJson`, `PutJson(Path, Json)` | Text or a `TJSONData` |
| `PostForm(Path, ['name', 'value', ...])` | Like an HTML form |
| `Request(Method, Path, Body, ContentType)` | Any method |
| `Download(Path, FileName)` | Streams to the file; nothing is left behind when it fails |
| `BaseUrl`, `Headers`, `BearerToken`, `UserName`/`Password` | Sent with every request |
| `Timeout` | Milliseconds for connecting and for each read (default 30000) |
| `FollowRedirects` | Default on |
| `OnProgress` | `procedure(Done, Total: Int64)` while the answer arrives |
| `Proxy` | `'http://host:port'`, or `'none'` |

`THttpResponse` has `Status`, `StatusText`, `Body`, `Headers`, `Url` (after redirects), `Duration`, and:

- `Ok`: status 200–299. Error statuses (404, 500, …) are normal answers, not exceptions.
- `Header('content-type')`: a header by name, any case.
- `Json`: the body parsed (you free it).
- `RaiseForStatus`: `EHttpError` unless `Ok`, with the start of the body: `GET https://api.example.com/x: 404 Not Found: no such user`.

When no answer comes at all, `EHttpError` says why:

```
cannot find server "api.exmaple.com" (check the address and the network)
cannot connect to "localhost" (is the server running, and is the port right?)
certificate of "test.local" is not trusted: self-signed certificate
the proxy 10.0.0.1 wants a user name and password (http://user:pass@host:port)
```

### HTTPS

Certificates are checked, including that they belong to the host name, just like a browser. Free Pascal 3.2.2 on its own does not do this, nor does it find OpenSSL 3 (what current Linux systems ship) or go through a proxy for HTTPS; `Pastel.Http` takes care of all three.

- **Linux**: needs `libssl3` (or 1.1), installed on nearly every system. `pastel doctor` checks it.
- **Windows**: put `libssl-3-x64.dll` and `libcrypto-3-x64.dll` next to your program, and `cacert.pem` (from [curl.se/ca](https://curl.se/ca/cacert.pem)) for the list of trusted certificates.
- **Own certificates** (a company CA, a test server): `SSL_CERT_FILE=/path/ca.pem`.
- `VerifyCertificates := False` turns the check off. Only for tests: anyone in between could read and change the traffic.

### Proxies

`HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY` are followed like curl does (`NO_PROXY=.internal,localhost`). `localhost` never goes through a proxy.

### Limits

Addresses are looked up as IPv4; a server reachable only over IPv6 cannot be used yet (a limit of Free Pascal 3.2.2's sockets). Each request opens its own connection.

## Environment: `Pastel.Env`

```pascal
Port := GetEnv('PORT', '8080');
if HasEnv('CI') then ...
SetEnv('APP_MODE', 'test');     // also seen by programs started afterwards
for S in EnvList do WriteLn(S);  // NAME=value
```

On Windows, Free Pascal's `GetEnvironmentVariable` turns letters outside the old code page into `?` or plain letters (`şeker` becomes `seker`). `GetEnv` gives the real text. All Pastel units use it.
