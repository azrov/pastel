# Pastel.Process

Running other programs.

    Version := RunOutput('git', ['describe', '--tags']);   // raises with git's own message on failure

    R := Run('tar', ['czf', 'backup.tgz', 'data']);
    if not R.Ok then
      WriteLn('tar failed: ', R.Errors);

    Opts := Default(TRunOptions);
    Opts.Dir := '/srv/app';
    Opts.Timeout := 30000;                 // milliseconds; the program is stopped after that
    Opts.Input := 'yes' + LineEnding;      // sent to its standard input
    Opts.Env := ['LANG=C', 'APP_MODE=test'];
    R := Run('./migrate', [], Opts);

    Code := RunLive('apt-get', ['update']);  // output goes straight to the terminal
    R := Shell('ls *.log | wc -l');          // through /bin/sh (cmd.exe on Windows)
    if Which('ffmpeg') = '' then ...

  Arguments are passed as they are: no quoting is needed and nothing is
  interpreted by a shell, except with Shell.

`uses Pastel.Process;` · source: [framework/src/pastel.process.pas](../../framework/src/pastel.process.pas)

**Contents:** [EProcessError](#eprocesserror) · [TRunOptions](#trunoptions) · [TRunResult](#trunresult) · [Run](#run) · [Run](#run) · [RunOutput](#runoutput) · [RunOutput](#runoutput) · [RunLive](#runlive) · [Shell](#shell) · [Shell](#shell) · [Which](#which)

## Types

### EProcessError

```pascal
type EProcessError = class(Exception)
```

### TRunOptions

```pascal
type TRunOptions = record
```

| | |
|---|---|
| `Dir: string` | working folder; '' = the current one |
| `Input: string` | text sent to standard input |
| `Env: array of string` | 'NAME=value' added to (or replacing in) the environment |
| `Timeout: Integer` | milliseconds, 0 = wait forever |
| `MergeErrors: Boolean` | standard error goes into Output too |

### TRunResult

```pascal
type TRunResult = record
```

| | |
|---|---|
| `ExitCode: Integer` |  |
| `Output: string` |  |
| `Errors: string` |  |
| `TimedOut: Boolean` |  |
| `Duration: Integer` | milliseconds |
| `function Ok: Boolean` |  |
| `function Text: string` | Output without the final line break |
| `function Lines: TStringArray` |  |

## Routines

### Run

```pascal
function Run(const Exe: string; const Args: array of string): TRunResult
```

### Run

```pascal
function Run(const Exe: string; const Args: array of string; const Opts: TRunOptions): TRunResult
```

### RunOutput

```pascal
function RunOutput(const Exe: string; const Args: array of string): string
```

The output, or EProcessError when the program fails.

### RunOutput

```pascal
function RunOutput(const Exe: string; const Args: array of string; const Opts: TRunOptions): string
```

### RunLive

```pascal
function RunLive(const Exe: string; const Args: array of string; const Dir: string = ''): Integer
```

Runs with this program's terminal; returns the exit code.

### Shell

```pascal
function Shell(const CommandLine: string): TRunResult
```

A command line for the system shell: pipes, wildcards, redirections.

### Shell

```pascal
function Shell(const CommandLine: string; const Opts: TRunOptions): TRunResult
```

### Which

```pascal
function Which(const Name: string): string
```

Full path of a program found on PATH, or ''.

