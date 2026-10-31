# Pastel.Workers

Background work: a thread-safe queue and a pool of worker threads.

    Mail := TWorkerPool.Create('mail', 4, @SendMail);     // 4 threads
    Mail.Submit(JObject(['to', 'ayse@example.com']).AsJSON);
    ...
    Mail.Free;       // takes no new work, finishes what is queued, then stops

    procedure TApi.SendMail(const Msg: string);
    begin
      ...                     // runs in one of the worker threads
    end;

  Messages are strings (often JSON), so nothing is shared between threads
  by accident. An exception in a handler is logged and counted; the worker
  goes on with the next message. TMessageQueue on its own passes messages
  between any threads.

`uses Pastel.Workers;` · source: [framework/src/pastel.workers.pas](../../framework/src/pastel.workers.pas)

## Types

### TMessageQueue

```pascal
type TMessageQueue = class
```

First in, first out; any number of threads may push and pop.

| | |
|---|---|
| `constructor Create(MaxCount: Integer = 0)` | MaxCount 0: no limit |
| `destructor Destroy` |  |
| `function Push(const Msg: string): Boolean` | False when the queue is closed or full |
| `function Pop(out Msg: string; TimeoutMs: Integer = -1): Boolean` | waits up to TimeoutMs (-1: until there is a message or the queue is closed); False after the time, or when closed and empty |
| `procedure Close` | no new messages; Pop still returns the ones queued |
| `function Count: Integer` |  |
| `property Closed: Boolean` |  |

### TWorkerPool

```pascal
type TWorkerPool = class
```

| | |
|---|---|
| `constructor Create(const AName: string; Count: Integer; Handler: TWorkHandler; MaxQueue: Integer = 0)` |  |
| `constructor Create(const AName: string; Count: Integer; Handler: TWorkHandlerProc; MaxQueue: Integer = 0)` |  |
| `destructor Destroy` | Stop, then free |
| `function Submit(const Msg: string): Boolean` | queue a message; False after Stop or when the queue is full |
| `procedure Stop(WarnAfterMs: Integer = 30000)` | no new work; waits until the queued work is done (a warning in the log when it takes longer than WarnAfterMs) |
| `function WaitIdle(TimeoutMs: Integer = 30000): Boolean` | waits until the queue is empty and no worker is busy; False after TimeoutMs |
| `property Name: string` |  |
| `property Pending: Integer` |  |
| `property Processed: Integer` |  |
| `property Failed: Integer` |  |

## Other types

| | |
|---|---|
| `type TWorkHandler = procedure(Msg: string)` |  |
| `type TWorkHandlerProc = procedure(Msg: string)` |  |

