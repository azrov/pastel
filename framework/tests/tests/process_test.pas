unit Process_Test;

{ The tests start this same test program again as the "other program",
  with PASTEL_PROCESS_HELPER telling it what to do. That works the same
  on every system, without depending on sh, cat or cmd.exe. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Process, Pastel.Text, Pastel.Env, Pastel.Args;

type
  TProcessTests = class(TTestSuite)
  private
    procedure RunMissing;
    procedure RunFailing;
  published
    procedure CapturesOutputAndExitCode;
    procedure PassesArgumentsUnchanged;
    procedure SendsInput;
    procedure SendsLargeInput;
    procedure SeparatesErrors;
    procedure MergesErrors;
    procedure AddsEnvironment;
    procedure RunsInFolder;
    procedure StopsAfterTimeout;
    procedure RunOutputRaisesWithMessage;
    procedure MissingProgramGivesClearError;
    procedure RunsShellCommands;
    procedure FindsProgramsOnPath;
  end;

implementation

function Helper(const Mode: string; const Args: array of string; Opts: TRunOptions): TRunResult;
begin
  Opts.Env := Concat(Opts.Env, ['PASTEL_PROCESS_HELPER=' + Mode]);
  Result := Run(ParamStr(0), Args, Opts);
end;

function Helper(const Mode: string; const Args: array of string): TRunResult;
begin
  Result := Helper(Mode, Args, Default(TRunOptions));
end;

procedure TProcessTests.CapturesOutputAndExitCode;
var
  R: TRunResult;
begin
  R := Helper('exit', ['3']);
  AssertEquals(3, R.ExitCode);
  AssertFalse(R.Ok);
  AssertEquals('exiting with 3', R.Text);
  R := Helper('exit', ['0']);
  AssertTrue(R.Ok);
end;

procedure TProcessTests.PassesArgumentsUnchanged;
var
  R: TRunResult;
begin
  R := Helper('args', ['a b', '"quoted"', '', 'ağaç', '*.txt', '$HOME']);
  AssertEquals('[a b]["quoted"][][ağaç][*.txt][$HOME]', R.Text);
end;

procedure TProcessTests.SendsInput;
var
  Opts: TRunOptions;
  R: TRunResult;
begin
  Opts := Default(TRunOptions);
  Opts.Input := 'merhaba' + LineEnding + 'dünya' + LineEnding;
  R := Helper('upper', [], Opts);
  AssertEquals('MERHABA' + LineEnding + 'DÜNYA', R.Text);
  AssertEquals(2, Length(R.Lines));
end;

procedure TProcessTests.SendsLargeInput;
var
  Opts: TRunOptions;
  R: TRunResult;
begin
  Opts := Default(TRunOptions);
  Opts.Input := StringOfChar('x', 300000);
  R := Helper('count', [], Opts);
  AssertEquals('300000', R.Text);
end;

procedure TProcessTests.SeparatesErrors;
var
  R: TRunResult;
begin
  R := Helper('both', []);
  AssertEquals('to output', R.Text);
  AssertEquals('to errors', Trim(R.Errors));
end;

procedure TProcessTests.MergesErrors;
var
  Opts: TRunOptions;
  R: TRunResult;
begin
  Opts := Default(TRunOptions);
  Opts.MergeErrors := True;
  R := Helper('both', [], Opts);
  AssertContains('to output', R.Output);
  AssertContains('to errors', R.Output);
  AssertEquals('', R.Errors);
end;

procedure TProcessTests.AddsEnvironment;
var
  Opts: TRunOptions;
begin
  Opts := Default(TRunOptions);
  Opts.Env := ['PASTEL_TEST_VALUE=şeker'];
  AssertEquals('şeker', Helper('env', ['PASTEL_TEST_VALUE'], Opts).Text);
  { the rest of the environment is still there }
  AssertNotEquals('', Helper('env', ['PATH'], Opts).Text);
end;

procedure TProcessTests.RunsInFolder;
var
  Opts: TRunOptions;
  Dir: string;
begin
  Dir := ExcludeTrailingPathDelimiter(GetTempDir(False));
  Opts := Default(TRunOptions);
  Opts.Dir := Dir;
  AssertEquals(ExpandFileName(Dir), ExpandFileName(Helper('pwd', [], Opts).Text));
end;

procedure TProcessTests.StopsAfterTimeout;
var
  Opts: TRunOptions;
  R: TRunResult;
begin
  Opts := Default(TRunOptions);
  Opts.Timeout := 300;
  R := Helper('sleep', ['10000'], Opts);
  AssertTrue(R.TimedOut);
  AssertFalse(R.Ok);
  AssertTrue(R.Duration < 5000, 'took ' + IntToStr(R.Duration) + ' ms');
end;

procedure TProcessTests.RunFailing;
var
  Opts: TRunOptions;
begin
  Opts := Default(TRunOptions);
  Opts.Env := ['PASTEL_PROCESS_HELPER=both-fail'];
  RunOutput(ParamStr(0), [], Opts);
end;

procedure TProcessTests.RunOutputRaisesWithMessage;
begin
  try
    RunFailing;
    Fail('no exception');
  except
    on E: EProcessError do
    begin
      AssertContains('exit code 5', E.Message);
      AssertContains('to errors', E.Message);
      AssertEquals(5, E.ExitCode);
    end;
  end;
end;

procedure TProcessTests.RunMissing;
begin
  Run('pastel-no-such-program', []);
end;

procedure TProcessTests.MissingProgramGivesClearError;
begin
  try
    RunMissing;
    Fail('no exception');
  except
    on E: EProcessError do
      AssertContains('"pastel-no-such-program" was not found', E.Message);
  end;
end;

procedure TProcessTests.RunsShellCommands;
var
  R: TRunResult;
begin
  R := Shell('echo one&& echo two');
  AssertTrue(R.Ok, R.Errors);
  AssertTrue(R.Ok);
  AssertEquals(2, Length(R.Lines));
  AssertEquals('one', Trim(R.Lines[0]));
end;

procedure TProcessTests.FindsProgramsOnPath;
begin
  {$IFDEF WINDOWS}
  AssertNotEquals('', Which('cmd'));
  {$ELSE}
  AssertNotEquals('', Which('sh'));
  {$ENDIF}
  AssertEquals('', Which('pastel-no-such-program'));
  AssertEquals(ExpandFileName(ParamStr(0)), Which(ParamStr(0)));
end;

{ ---- the helper side ---- }

procedure RunHelper(const Mode: string);
var
  S, All: string;
  I: Integer;
begin
  case Mode of
    'exit':
      begin
        WriteLn('exiting with ', ParamStr(1));
        Halt(StrToInt(ParamStr(1)));
      end;
    'args':
      begin
        { CommandLineWords: the RTL's ParamStr does not follow the Windows
          rules for quotes and is not UTF-8 there }
        for S in CommandLineWords do
          Write('[', S, ']');
        WriteLn;
      end;
    'upper':
      while not EOF(Input) do
      begin
        ReadLn(S);
        WriteLn(Upper(S));
      end;
    'count':
      begin
        All := '';
        while not EOF(Input) do
        begin
          ReadLn(S);
          All := All + S;
        end;
        WriteLn(Length(All));
      end;
    'both':
      begin
        WriteLn('to output');
        WriteLn(StdErr, 'to errors');
      end;
    'both-fail':
      begin
        WriteLn('to output');
        WriteLn(StdErr, 'to errors');
        Halt(5);
      end;
    'env':
      WriteLn(GetEnv(ParamStr(1)));
    'pwd':
      WriteLn(GetCurrentDir);
    'sleep':
      Sleep(StrToInt(ParamStr(1)));
  end;
  Halt(0);
end;

initialization
  if GetEnv('PASTEL_PROCESS_HELPER') <> '' then
    RunHelper(GetEnv('PASTEL_PROCESS_HELPER'));
  RegisterTests(TProcessTests);
end.
