# Pastel.CrashReport

Crash reports: what went wrong on users' machines, sent to you.

    EnableCrashReports('https://api.example.com/crashes', '1.4.2');
    ...
    try
      Sync;
    except
      on E: Exception do
        ReportError(E, 'sync');          // a caught error worth knowing about
    end;

  An exception nobody caught is written into a file before the program ends
  (with the place it happened, the version, the system); the next start sends
  the waiting reports as JSON (POST, on a thread of its own) and removes them.
  Release builds have no names of functions in them: the report has the
  addresses, which a debug build of the same version can name.

`uses Pastel.CrashReport;` · source: [framework/src/pastel.crashreport.pas](../../framework/src/pastel.crashreport.pas)

## Routines

### EnableCrashReports

```pascal
procedure EnableCrashReports(const Url: string; const AppVersion: string = '')
```

Turns them on; also sends the reports of earlier crashes.

### ReportError

```pascal
procedure ReportError(E: Exception; const Where: string = '')
```

Sends a report of a caught exception (at once, on a thread).

### CrashReportDir

```pascal
function CrashReportDir: string
```

The folder the waiting reports are in.

### CrashReportJson

```pascal
function CrashReportJson(Obj: TObject; Addr: CodePointer; FrameCount: Longint; Frame: PCodePointer; const Where: string): string
```

The report of an exception as JSON (what is sent).

### SendCrashReports

```pascal
function SendCrashReports: Integer
```

Sends the waiting reports now and waits (tests); how many went.

