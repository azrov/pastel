# Pastel.Background

Work that goes on when the app is not on the screen.

  Background work: the app keeps running, with a notification, while it does
  something the user started (plays music, records a route, uploads photos).
  Its Pascal code goes on as before: timers, threads, the network.

    StartBackgroundWork('Uploading photos', '3 of 20', bkDataSync);
    UpdateBackgroundWork('7 of 20');
    StopBackgroundWork;

  Background jobs: a function Android runs from time to time - also when the
  app is closed, and after the phone restarted (sync, reminders, a backup).
  It is registered in a unit's initialization, runs on a thread of its own
  without the app's window (no forms: data, files, HTTP) and answers True
  when it was done (False: again later).

    function SyncNow: Boolean;
    begin
      Result := Store.Sync(ServerUrl);
    end;

    initialization
      RegisterBackgroundJob('sync', @SyncNow);
    ...
    ScheduleBackgroundJob('sync', 60);         // about every hour, when there is a network

  pastel.toml says what the app does in the background:
    [package.android] background = ["data_sync"]   # media_playback, location, connected_device
  On computers apps run as long as they are open: background work does
  nothing, scheduled jobs run with a timer while the app is open.

`uses Pastel.Background;` · source: [framework/src/pastel.background.pas](../../framework/src/pastel.background.pas)

**Contents:** [TBackgroundKind](#tbackgroundkind) · [StartBackgroundWork](#startbackgroundwork) · [UpdateBackgroundWork](#updatebackgroundwork) · [StopBackgroundWork](#stopbackgroundwork) · [BackgroundWorkRunning](#backgroundworkrunning) · [RegisterBackgroundJob](#registerbackgroundjob) · [ScheduleBackgroundJob](#schedulebackgroundjob) · [CancelBackgroundJob](#cancelbackgroundjob) · [RunBackgroundJob](#runbackgroundjob) · [InBackgroundJob](#inbackgroundjob)

## Types

### TBackgroundKind

```pascal
type TBackgroundKind = (bkDataSync, bkMediaPlayback, bkLocation, bkConnectedDevice)
```

- `bkDataSync`
- `bkMediaPlayback`
- `bkLocation`
- `bkConnectedDevice`
## Other types

| | |
|---|---|
| `type TBackgroundJob = function: Boolean` | a background job: True when done, False when it should be tried again later |

## Routines

### StartBackgroundWork

```pascal
procedure StartBackgroundWork(const Title: string; const Text: string; Kind: TBackgroundKind = bkDataSync)
```

The app keeps running with a notification (Title, Text) until StopBackgroundWork.
Kind must be in pastel.toml's [package.android] background.

### UpdateBackgroundWork

```pascal
procedure UpdateBackgroundWork(const Text: string)
```

A new text for its notification.

### StopBackgroundWork

```pascal
procedure StopBackgroundWork
```

### BackgroundWorkRunning

```pascal
function BackgroundWorkRunning: Boolean
```

### RegisterBackgroundJob

```pascal
procedure RegisterBackgroundJob(const Name: string; Job: TBackgroundJob)
```

A job by name; in a unit's initialization, so it is there when Android starts the app for it.

### ScheduleBackgroundJob

```pascal
function ScheduleBackgroundJob(const Name: string; EveryMinutes: Integer = 60; NeedsNetwork: Boolean = True): Boolean
```

Runs it about every EveryMinutes (15 at least), when there is a network if
NeedsNetwork; also after the phone restarted. False when it could not be planned.

### CancelBackgroundJob

```pascal
procedure CancelBackgroundJob(const Name: string)
```

### RunBackgroundJob

```pascal
function RunBackgroundJob(const Name: string): Boolean
```

Runs a registered job now (tests, a "Sync now" button); its answer.

### InBackgroundJob

```pascal
function InBackgroundJob: Boolean
```

True inside a job Android started without the app's window.

