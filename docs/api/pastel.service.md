# Pastel.Service

Long-running programs (services, daemons).

    type
      TBackup = class(TService)
      protected
        procedure Configure(C: TConfig); override;
        procedure Started; override;
        procedure Stopping; override;
      public
        procedure CheckDisk;
        procedure Nightly;
      end;

    procedure TBackup.Configure(C: TConfig);
    begin
      C.SetDefault('check.interval', '60');
    end;
    ...
    begin
      Service := TBackup.Create(AppName, AppVersion);
      Service.Every(Service.Config.GetFloat('check.interval'), @Service.CheckDisk, 'check disk');
      Service.DailyAt('03:30', @Service.Nightly, 'nightly backup');
      ExitCode := Service.Run;
      Service.Free;
    end.

  Run loads the settings (Pastel.Config), calls Started, runs the jobs
  until the service is told to stop, then calls Stopping:
  - SIGTERM (systemctl stop, docker stop) and Ctrl+C stop it cleanly; a
    second Ctrl+C ends it at once.
  - SIGHUP (systemctl reload) reads the settings again and calls Reloaded.
  - Under systemd with Type=notify it reports when it is ready and when it
    stops, and keeps WatchdogSec= happy.
  A job that raises is logged and runs again next time; the service goes on.

`uses Pastel.Service;` · source: [framework/src/pastel.service.pas](../../framework/src/pastel.service.pas)

## Types

### TServiceJob

```pascal
type TServiceJob = class
```

### TService

```pascal
type TService = class
```

| | |
|---|---|
| `constructor Create(const AName: string; const AVersion: string = '')` |  |
| `destructor Destroy` |  |
| `function Run: Integer` | Runs until stopped; the exit code for the program. |
| `procedure Every(Seconds: Double; Job: TJobMethod; const JobName: string = ''; RunAtStart: Boolean = False)` | A job every Seconds; the first run after Seconds, or right at the start. |
| `procedure Every(Seconds: Double; Job: TJobProc; const JobName: string = ''; RunAtStart: Boolean = False)` |  |
| `procedure DailyAt(const Time: string; Job: TJobMethod; const JobName: string = '')` | A job once a day at Time ('03:30', local time). |
| `procedure DailyAt(const Time: string; Job: TJobProc; const JobName: string = '')` |  |
| `procedure Stop` | Asks the service to stop (from a job, a worker thread, a test). |
| `procedure Reload` | Asks it to read the settings again, as SIGHUP does. |
| `function Wait(Ms: Integer): Boolean` | Sleeps up to Ms milliseconds; returns False at once when the service is stopping. Long jobs use it instead of Sleep. |
| `property Name: string` |  |
| `property Version: string` |  |
| `property Config: TConfig` |  |
| `property IsStopping: Boolean` |  |
| `property StateDir: string` | A folder for the service's own files: $STATE_DIRECTORY under systemd (StateDirectory=), else ./data. Created when first used. |

## Other types

| | |
|---|---|
| `type TJobMethod = procedure` |  |
| `type TJobProc = procedure` |  |

## Routines

### NextDailyRun

```pascal
function NextDailyRun(const Time: string; Now: TDateTime): TDateTime
```

When a daily job at Time ('HH:MM') runs next, seen from Now.

### NotifySystemd

```pascal
procedure NotifySystemd(const Message: string)
```

Tells systemd about the service ("READY=1", "STOPPING=1", "STATUS=...").
Does nothing outside systemd.

