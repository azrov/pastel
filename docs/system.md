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
- **Windows**: nothing to install: `Pastel.Http` uses Windows' own HTTP (WinINet), with Windows' certificates and proxy settings. (`PASTEL_HTTP=fpc` uses Free Pascal's instead, which needs `libssl-3-x64.dll`, `libcrypto-3-x64.dll` and `cacert.pem` next to the program.)
- **Android**: the phone's own HTTP, also without OpenSSL ([android.md](android.md)).
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

## Serial ports: `Pastel.Serial`

Scales, barcode readers, cash drawers, receipt printers, Arduino boards:

```pascal
Port := TSerialPort.Create;
try
  Port.Open('/dev/ttyUSB0', 9600);         // Windows: 'COM3'; ListSerialPorts: the ones there
  Port.WriteText('W'#13);
  Weight := Port.ReadLine(2000);           // a line, 2 seconds at most ('' when none came)
finally
  Port.Free;
end;
```

`DataBits`, `StopBits`, `Parity`, `Flow` (none, hardware, software) before `Open`; `Read`, `Write`, `SetDTR`,
`SetRTS`, `Flush`. On Linux the user must be in the `dialout` group (`sudo usermod -aG dialout $USER`).

## Long work without a frozen window: `RunInBackground`

```pascal
uses Pastel.Workers;

RunInBackground(@LoadRows, @RowsLoaded, Job);       // Job: what the work needs, and its results

procedure TMainForm.LoadRows(Sender: TObject);      // a thread of its own: no controls here
begin
  TJob(TBackgroundTask(Sender).Data).Rows := Db.Query('select ...', []);
end;

procedure TMainForm.RowsLoaded(Sender: TObject);    // the main thread, after it
begin
  with TBackgroundTask(Sender) do
    if Error <> '' then ShowMessage(Error) else ShowRows(TJob(Data).Rows);
  TBackgroundTask(Sender).Data.Free;
end;
```

The window goes on painting and answering meanwhile. `Cancel` (before Done): Done is not called and `Data` is
freed; the work itself runs to its end. A `TDatabase` may be used from such threads (each takes a connection
of its pool).

## Crash reports: `Pastel.CrashReport`

```pascal
EnableCrashReports('https://api.example.com/crashes', '1.4.2');     // at the start
...
except
  on E: Exception do
    ReportError(E, 'sync');         // a caught error worth knowing about
end;
```

An exception nobody caught is written into a file before the program ends; the next start sends the waiting
reports to the address (a JSON `POST`: app, version, system, error, message, where, stack) on a thread of its
own and removes them.

An exception that an event handler of a window app does not catch does not end the app: Pastel shows its
message and the app goes on (as in Delphi), and with crash reports on it is reported too (`where`: `event`).
`Application.OnException` does something else with it (a status line, a log); `Abort` is quiet:

```pascal
Application.OnException := @AppError;

procedure TMainForm.AppError(Sender: TObject; E: Exception);
begin
  StatusLabel.Text := E.Message;
end;
```

## Updating itself: `Pastel.Updater`

```pascal
if CheckForUpdate('https://example.com/shop/update.json', '1.4.2', Update) then
  if Confirm('Version ' + Update.Version + ' is there. Update now?') then
  begin
    InstallUpdate(DownloadUpdate(Update));       // checked against its SHA-256
    Application.Terminate;
  end;
```

`pastel update-manifest https://example.com/shop/ "What is new"` writes `dist/update.json` from the packages in
`dist/` (the setup `.exe`, the `.AppImage`, the `.apk`, each with its SHA-256); put it and the packages at that
address. Windows runs the installer silently (it starts the app again), an AppImage replaces itself, Android asks
the user to install the `.apk` (`[package.android] permissions = ["install_updates"]`; apps of Google Play update
through Play).
