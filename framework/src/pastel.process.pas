(* Pastel - running other programs.

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
  Part of the Pastel project, MIT License. *)
unit Pastel.Process;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Pastel.Env;

type
  EProcessError = class(Exception)
  public
    ExitCode: Integer;
    Errors: string;
  end;

  TRunOptions = record
    Dir: string;               // working folder; '' = the current one
    Input: string;             // text sent to standard input
    Env: array of string;      // 'NAME=value' added to (or replacing in) the environment
    Timeout: Integer;          // milliseconds, 0 = wait forever
    MergeErrors: Boolean;      // standard error goes into Output too
  end;

  TRunResult = record
    ExitCode: Integer;
    Output: string;
    Errors: string;
    TimedOut: Boolean;
    Duration: Integer;         // milliseconds
    function Ok: Boolean;
    { Output without the final line break }
    function Text: string;
    function Lines: TStringArray;
  end;

function Run(const Exe: string; const Args: array of string): TRunResult;
function Run(const Exe: string; const Args: array of string; const Opts: TRunOptions): TRunResult;
{ The output, or EProcessError when the program fails. }
function RunOutput(const Exe: string; const Args: array of string): string;
function RunOutput(const Exe: string; const Args: array of string; const Opts: TRunOptions): string;
{ Runs with this program's terminal; returns the exit code. }
function RunLive(const Exe: string; const Args: array of string; const Dir: string = ''): Integer;
{ A command line for the system shell: pipes, wildcards, redirections. }
function Shell(const CommandLine: string): TRunResult;
function Shell(const CommandLine: string; const Opts: TRunOptions): TRunResult;
{ Full path of a program found on PATH, or ''. }
function Which(const Name: string): string;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Process, Pipes;

{ The exit code as the shell reports it: 128 + signal number when the
  program was killed. }
function ExitCodeOf(P: TProcess): Integer;
begin
  {$IFDEF UNIX}
  if wifexited(P.ExitStatus) then
    Result := wexitstatus(P.ExitStatus)
  else if wifsignaled(P.ExitStatus) then
    Result := 128 + wtermsig(P.ExitStatus)
  else
    Result := P.ExitStatus;
  {$ELSE}
  Result := P.ExitStatus;
  {$ENDIF}
end;

function ShellQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

{ Windows passes one command line; this quotes an argument so that the
  program's own parsing (the CommandLineToArgvW rules) gets it back
  unchanged. }
function WinQuote(const S: string): string;
var
  I, Slashes: Integer;
begin
  if (S <> '') and (S.IndexOfAny([' ', #9, #10, '"']) < 0) then
    Exit(S);
  Result := '"';
  Slashes := 0;
  for I := 1 to Length(S) do
    if S[I] = '\' then
      Inc(Slashes)
    else
    begin
      if S[I] = '"' then
        Result := Result + StringOfChar('\', Slashes * 2 + 1)
      else
        Result := Result + StringOfChar('\', Slashes);
      Slashes := 0;
      Result := Result + S[I];
    end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

{ Sets program and arguments.
  Unix: Free Pascal's TProcess cannot pass an empty argument (it ends the
  list there), so in that rare case the program is started through
  /bin/sh with every argument quoted.
  Windows: TProcess's quoting breaks arguments that contain quotes, so the
  command line is built here. RawTail is added as it is (for cmd.exe). }
procedure SetCommand(P: TProcess; const Path: string; const Args: array of string;
  const RawTail: string);
var
  I: Integer;
  Line: string;
  {$IFDEF UNIX}
  J: Integer;
  {$ENDIF}
begin
  {$IFDEF UNIX}
  for I := 0 to High(Args) do
    if Args[I] = '' then
    begin
      Line := 'exec ' + ShellQuote(Path);
      for J := 0 to High(Args) do
        Line := Line + ' ' + ShellQuote(Args[J]);
      P.Executable := '/bin/sh';
      P.Parameters.Add('-c');
      P.Parameters.Add(Line);
      Exit;
    end;
  P.Executable := Path;
  for I := 0 to High(Args) do
    P.Parameters.Add(Args[I]);
  if RawTail <> '' then
    P.Parameters.Add(RawTail);
  {$ELSE}
  Line := WinQuote(Path);
  for I := 0 to High(Args) do
    Line := Line + ' ' + WinQuote(Args[I]);
  if RawTail <> '' then
    Line := Line + ' ' + RawTail;
  {$push}{$warn symbol_deprecated off}
  P.CommandLine := Line;
  {$pop}
  {$ENDIF}
end;

function TRunResult.Ok: Boolean;
begin
  Result := (ExitCode = 0) and not TimedOut;
end;

function TRunResult.Text: string;
begin
  Result := Output;
  while (Result <> '') and (Result[Length(Result)] in [#10, #13]) do
    SetLength(Result, Length(Result) - 1);
end;

function TRunResult.Lines: TStringArray;
var
  L: TStringList;
  I: Integer;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.Text := Output;
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
      Result[I] := L[I];
  finally
    L.Free;
  end;
end;

function Which(const Name: string): string;
var
  Dirs: TStringArray;
  D: string;
  Ext: string = '';
  {$IFDEF WINDOWS}
  Exts: TStringArray;
  {$ENDIF}
begin
  Result := '';
  if Name = '' then
    Exit;
  if (Pos('/', Name) > 0) {$IFDEF WINDOWS} or (Pos('\', Name) > 0) {$ENDIF} then
  begin
    if FileExists(Name) then
      Result := ExpandFileName(Name)
    {$IFDEF WINDOWS}
    else if FileExists(Name + '.exe') then
      Result := ExpandFileName(Name + '.exe')
    {$ENDIF};
    Exit;
  end;
  Dirs := GetEnv('PATH').Split([PathSeparator]);
  {$IFDEF WINDOWS}
  if ExtractFileExt(Name) <> '' then
    Exts := ['']
  else
    Exts := ['.exe', '.com', '.bat', '.cmd'];
  {$ENDIF}
  for D in Dirs do
  begin
    if D = '' then
      Continue;
    {$IFDEF WINDOWS}
    for Ext in Exts do
    {$ELSE}
    Ext := '';
    {$ENDIF}
      if FileExists(IncludeTrailingPathDelimiter(D) + Name + Ext) then
        Exit(IncludeTrailingPathDelimiter(D) + Name + Ext);
  end;
end;

procedure SetupEnv(P: TProcess; const Extra: array of string);
var
  I, J: Integer;
  Name: string;
begin
  if Length(Extra) = 0 then
    Exit;
  for Name in EnvList do
    P.Environment.Add(Name);
  for I := 0 to High(Extra) do
  begin
    Name := Copy(Extra[I], 1, Pos('=', Extra[I]) - 1);
    if Name = '' then
      raise EProcessError.CreateFmt('environment entry "%s" must look like NAME=value', [Extra[I]]);
    for J := P.Environment.Count - 1 downto 0 do
      if {$IFDEF WINDOWS}SameText{$ELSE}SameStr{$ENDIF}(
         Copy(P.Environment[J], 1, Pos('=', P.Environment[J]) - 1), Name) then
        P.Environment.Delete(J);
    P.Environment.Add(Extra[I]);
  end;
end;

function Drain(S: TInputPipeStream; var Into: string): Boolean;
var
  N, Got: Integer;
  Buf: string;
begin
  Result := False;
  if S = nil then
    Exit;
  N := S.NumBytesAvailable;
  while N > 0 do
  begin
    SetLength(Buf, N);
    Got := S.Read(Buf[1], N);
    if Got <= 0 then
      Break;
    Into := Into + Copy(Buf, 1, Got);
    Result := True;
    N := S.NumBytesAvailable;
  end;
end;

{ Reads what is left after the program ended: NumBytesAvailable can be 0
  while data is still in the pipe on some systems. }
procedure DrainRest(S: TInputPipeStream; var Into: string);
var
  Buf: array[0..4095] of Char;
  Got: LongInt;
begin
  Buf[0] := #0;
  if S = nil then
    Exit;
  repeat
    Got := S.Read(Buf, SizeOf(Buf));
    if Got > 0 then
      Into := Into + Copy(Buf, 0, Got);
  until Got <= 0;
end;

function RunWith(const Exe: string; const Args: array of string; const RawTail: string;
  const Opts: TRunOptions): TRunResult;
var
  P: TProcess;
  Path, Pending: string;
  Sent, Chunk: Integer;
  Start: QWord;
  Busy: Boolean;
begin
  Result := Default(TRunResult);
  Path := Which(Exe);
  if Path = '' then
    raise EProcessError.CreateFmt('program "%s" was not found (is it installed and on PATH?)', [Exe]);
  if (Opts.Dir <> '') and not DirectoryExists(Opts.Dir) then
    raise EProcessError.CreateFmt('cannot run "%s": folder "%s" does not exist', [Exe, Opts.Dir]);
  P := TProcess.Create(nil);
  try
    SetCommand(P, Path, Args, RawTail);
    P.CurrentDirectory := Opts.Dir;
    SetupEnv(P, Opts.Env);
    P.Options := [poUsePipes, poNoConsole];
    if Opts.MergeErrors then
      P.Options := P.Options + [poStderrToOutPut];
    P.PipeBufferSize := 16384;
    Start := GetTickCount64;
    try
      P.Execute;
    except
      on E: Exception do
        raise EProcessError.CreateFmt('cannot run "%s": %s', [Exe, E.Message]);
    end;

    Pending := Opts.Input;
    Sent := 0;
    if Pending = '' then
      P.CloseInput;
    while True do
    begin
      Busy := False;
      if Sent < Length(Pending) then
      begin
        Chunk := Length(Pending) - Sent;
        if Chunk > 4096 then
          Chunk := 4096;
        try
          P.Input.WriteBuffer(Pending[Sent + 1], Chunk);
          Inc(Sent, Chunk);
        except
          Sent := Length(Pending);    // the program closed its input
        end;
        if Sent >= Length(Pending) then
          P.CloseInput;
        Busy := True;
      end;
      if Drain(P.Output, Result.Output) then
        Busy := True;
      if not Opts.MergeErrors and Drain(P.Stderr, Result.Errors) then
        Busy := True;
      if not P.Running then
        Break;
      if (Opts.Timeout > 0) and (GetTickCount64 - Start > QWord(Opts.Timeout)) then
      begin
        Result.TimedOut := True;
        P.Terminate(124);
        Break;
      end;
      if not Busy then
        Sleep(2);
    end;
    P.WaitOnExit;
    DrainRest(P.Output, Result.Output);
    if not Opts.MergeErrors then
      DrainRest(P.Stderr, Result.Errors);
    Result.Duration := GetTickCount64 - Start;
    if Result.TimedOut then
      Result.ExitCode := 124
    else
      Result.ExitCode := ExitCodeOf(P);
  finally
    P.Free;
  end;
  SetCodePage(RawByteString(Result.Output), CP_UTF8, False);
  SetCodePage(RawByteString(Result.Errors), CP_UTF8, False);
end;

function Run(const Exe: string; const Args: array of string): TRunResult;
begin
  Result := RunWith(Exe, Args, '', Default(TRunOptions));
end;

function Run(const Exe: string; const Args: array of string; const Opts: TRunOptions): TRunResult;
begin
  Result := RunWith(Exe, Args, '', Opts);
end;

function Failure(const Exe: string; const R: TRunResult; const Opts: TRunOptions): EProcessError;
var
  Msg, Detail: string;
begin
  if R.TimedOut then
    Msg := Format('"%s" did not finish within %d ms and was stopped', [Exe, Opts.Timeout])
  else
    Msg := Format('"%s" failed (exit code %d)', [Exe, R.ExitCode]);
  Detail := Trim(R.Errors);
  if (Detail = '') and Opts.MergeErrors then
    Detail := Trim(R.Output);
  if Detail <> '' then
    Msg := Msg + ': ' + Detail;
  Result := EProcessError.Create(Msg);
  Result.ExitCode := R.ExitCode;
  Result.Errors := R.Errors;
end;

function RunOutput(const Exe: string; const Args: array of string): string;
begin
  Result := RunOutput(Exe, Args, Default(TRunOptions));
end;

function RunOutput(const Exe: string; const Args: array of string; const Opts: TRunOptions): string;
var
  R: TRunResult;
begin
  R := Run(Exe, Args, Opts);
  if not R.Ok then
    raise Failure(Exe, R, Opts);
  Result := R.Text;
end;

function RunLive(const Exe: string; const Args: array of string; const Dir: string): Integer;
var
  P: TProcess;
  Path: string;
begin
  Path := Which(Exe);
  if Path = '' then
    raise EProcessError.CreateFmt('program "%s" was not found (is it installed and on PATH?)', [Exe]);
  P := TProcess.Create(nil);
  try
    SetCommand(P, Path, Args, '');
    P.CurrentDirectory := Dir;
    P.Options := [poWaitOnExit];
    try
      P.Execute;
    except
      on E: Exception do
        raise EProcessError.CreateFmt('cannot run "%s": %s', [Exe, E.Message]);
    end;
    Result := ExitCodeOf(P);
  finally
    P.Free;
  end;
end;

function Shell(const CommandLine: string): TRunResult;
begin
  Result := Shell(CommandLine, Default(TRunOptions));
end;

function Shell(const CommandLine: string; const Opts: TRunOptions): TRunResult;
begin
  {$IFDEF WINDOWS}
  { cmd.exe has its own rules: with /s /c "..." it runs exactly what is
    between the outer quotes }
  Result := RunWith(GetEnv('ComSpec', 'cmd.exe'), [], '/d /s /c "' + CommandLine + '"', Opts);
  {$ELSE}
  Result := Run('/bin/sh', ['-c', CommandLine], Opts);
  {$ENDIF}
end;

end.
