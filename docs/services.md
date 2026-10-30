# Services: programs that keep running

A service starts, does its work for days or months, and stops cleanly when
told to: a file watcher, a job that syncs data every five minutes, a
backup at night, later a web API. `Pastel.Service` takes care of the parts
every such program needs; you write the work.

```sh
pastel new service file-watch
cd file-watch
pastel run            # runs until Ctrl+C; put files into inbox/ and watch the log
```

## A service

```pascal
uses Pastel.Service, Pastel.Config, Pastel.Log, AppInfo;

type
  TSyncService = class(TService)
  protected
    procedure Configure(C: TConfig); override;
    procedure Started; override;
    procedure Stopping; override;
  public
    procedure Sync;
    procedure Cleanup;
  end;

procedure TSyncService.Configure(C: TConfig);
begin
  C.SetDefault('sync.interval', '300');      { seconds }
end;

procedure TSyncService.Started;
begin
  { open connections, files, ... }
end;

procedure TSyncService.Stopping;
begin
  { close them }
end;

var
  Service: TSyncService;
begin
  Service := TSyncService.Create(AppName, AppVersion);
  try
    Service.Every(Service.Config.GetFloat('sync.interval'), @Service.Sync, 'sync', True);
    Service.DailyAt('03:30', @Service.Cleanup, 'cleanup');
    ExitCode := Service.Run;
  finally
    Service.Free;
  end;
end.
```

`Run` does, in order:

1. read the settings: `Configure` gives the defaults, then `/etc/<name>/config.toml`, `~/.config/<name>/config.toml`, `./config.toml` and the environment ([data.md](data.md)). A mistake in them ends the start with exit code 1 and the reason.
2. call `Started`. An exception there ends the service with exit code 1 (and is logged).
3. run the jobs when they are due, until the service is told to stop
4. call `Stopping`, log "stopped", return 0

## Jobs

| | |
|---|---|
| `Every(Seconds, @Job, 'name')` | Every so many seconds (fractions are fine), the first time after one interval |
| `Every(Seconds, @Job, 'name', True)` | The same, and once right at the start |
| `DailyAt('03:30', @Job, 'name')` | Once a day, local time |

A job can be a method of the service (`@Service.Sync`) or a plain procedure.

- Jobs run one after the other, in the main thread, so they never run at the same time and need no locks.
- A job that raises is logged with its name (`sync failed: connection refused`) and runs again next time; the service goes on.
- The next run is planned from when a job starts, so a slow job does not pile up runs.
- A long job should check `IsStopping` now and then, and wait with `Wait(Ms)` instead of `Sleep`: `Wait` returns `False` at once when the service is told to stop.

## Stopping, reloading

| | |
|---|---|
| Ctrl+C, `kill`, `systemctl stop`, `docker stop` (SIGINT, SIGTERM) | Finishes the running job, calls `Stopping`, ends with 0 |
| A second Ctrl+C | Ends at once |
| `systemctl reload`, `kill -HUP` (SIGHUP) | Reads the settings again; then calls `Reloaded` |
| `Service.Stop`, `Service.Reload` | The same from code (a job, a thread, a test) |

When the new settings have a mistake, the old ones stay and the reason is logged. Settings in `[log]` (`level`, `format`) take effect at once:

```toml
[log]
level = "debug"     # debug, info, warn, error
format = "json"     # text, json or journal
```

On Windows, Ctrl+C and closing the console window stop the service cleanly; there is no reload (restart it instead). Running as a real Windows service (the Services control panel) is planned.

## Under systemd

`pastel new service` writes `deploy/<name>.service` and `deploy/README.md` with the steps to install it on a server. The unit uses:

- `Type=notify`: Pastel tells systemd when the service is ready, reloading and stopping, so `systemctl start` waits until `Started` is done and reports a failed start.
- `ExecReload=/bin/kill -HUP $MAINPID`: `systemctl reload` applies new settings.
- `WatchdogSec=60` (commented out): when set, Pastel tells systemd every half interval that it is alive; if the main loop hangs (a job stuck longer than that), systemd restarts the service.
- `DynamicUser=yes` and `StateDirectory=<name>`: the service runs as its own user and may write only to `/var/lib/<name>`. In code that folder is `Service.StateDir` (`./data` while developing).

Logs go to the journal with their level, so `journalctl -u <name> -p err` shows only errors.

The settings file on the server is `/etc/<name>/config.toml`; every setting can also be given as an environment variable in the unit (`Environment=FILE_WATCH_CHECK_INTERVAL=30` for `check.interval`).

## While developing

- `pastel run --watch` rebuilds and restarts the service whenever you save (with SIGTERM, so `Stopping` runs).
- `./config.toml` in the project holds the settings for development; `config.example.toml` is the one that goes to servers (`[package] include`).
- Put the work in units under `src/services/` and test them there; the template's `inbox.pas` with `tests/inbox_test.pas` shows how. The service itself can be tested too: run it with short intervals and stop it from a job (`Service.Stop`).

## When something goes wrong

Every Pastel program, not only services, ends an uncaught exception with a short message and exit code 1:

```
error: setting "check.interval" must be a number, got "often" (from config.toml)
```

Debug builds add where it happened (file and line). Under systemd, `Restart=on-failure` starts the service again after such an end.
