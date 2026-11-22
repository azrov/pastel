unit Service_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Pastel.Testing, Pastel.Service, Pastel.Config, Pastel.Log,
  Pastel.Files, Pastel.Env;

type
  TServiceTests = class(TTestSuite)
  private
    procedure BadTime;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure RunsJobsUntilStopped;
    procedure CallsStartedAndStopping;
    procedure FailingJobIsLoggedAndRunsAgain;
    procedure FailingStartIsAnError;
    procedure JobsCanRunAtStart;
    procedure PlansDailyJobs;
    procedure RejectsBadTimes;
    procedure ReloadReadsSettingsAgain;
    procedure BrokenSettingsKeepTheOldOnes;
    procedure WaitReturnsWhenStopping;
    procedure StateDirFollowsSystemd;
  end;

implementation

type
  TTestService = class(TService)
  protected
    procedure Configure(C: TConfig); override;
    procedure Started; override;
    procedure Stopping; override;
    procedure Reloaded; override;
  public
    Events: TStringList;
    Ticks, Fails: Integer;
    FailStart: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Tick;
    procedure Broken;
  end;

var
  LogLines: TStringList;
  Dir, OldDir: string;

type
  TCapture = class
    procedure Line(Level: TLogLevel; const Text: string);
  end;

procedure TCapture.Line(Level: TLogLevel; const Text: string);
begin
  LogLines.Add(Text);
end;

var
  Capture: TCapture;

constructor TTestService.Create;
begin
  Events := TStringList.Create;
  inherited Create('svctest', '1.2.3');
end;

destructor TTestService.Destroy;
begin
  inherited Destroy;
  Events.Free;
end;

procedure TTestService.Configure(C: TConfig);
begin
  C.SetDefault('greeting', 'default');
end;

procedure TTestService.Started;
begin
  Events.Add('started ' + Config.Get('greeting'));
  if FailStart then
    raise Exception.Create('database not reachable');
end;

procedure TTestService.Stopping;
begin
  Events.Add('stopping');
end;

procedure TTestService.Reloaded;
begin
  Events.Add('reloaded ' + Config.Get('greeting'));
end;

procedure TTestService.Tick;
begin
  Inc(Ticks);
  if Ticks = 3 then
    Stop;
end;

procedure TTestService.Broken;
begin
  Inc(Fails);
  if Fails = 2 then
    Stop;
  raise Exception.Create('disk full');
end;

function Joined(L: TStrings): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to L.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + L[I];
  end;
end;

procedure TServiceTests.SetUp;
begin
  LogLines.Clear;
  Log.OnLine := @Capture.Line;
  Log.Console := False;
  Dir := MakeTempDir('svctest');
  OldDir := GetCurrentDir;
  SetCurrentDir(Dir);     { ./config.toml is read from here }
end;

procedure TServiceTests.TearDown;
begin
  SetCurrentDir(OldDir);
  DeleteDir(Dir);
  Log.OnLine := nil;
  Log.Console := True;
end;

procedure TServiceTests.RunsJobsUntilStopped;
var
  S: TTestService;
  Start: QWord;
begin
  S := TTestService.Create;
  try
    S.Every(0.02, @S.Tick, 'tick');
    Start := GetTickCount64;
    AssertEquals(0, S.Run);
    AssertEquals(3, S.Ticks);
    AssertTrue(GetTickCount64 - Start < 2000, 'took too long');
  finally
    S.Free;
  end;
end;

procedure TServiceTests.CallsStartedAndStopping;
var
  S: TTestService;
begin
  S := TTestService.Create;
  try
    S.Every(0.01, @S.Tick);
    S.Run;
    AssertEquals('started default,stopping', Joined(S.Events));
    AssertContains('svctest 1.2.3 starting', LogLines.Text);
    AssertContains('svctest stopped', LogLines.Text);
  finally
    S.Free;
  end;
end;

procedure TServiceTests.FailingJobIsLoggedAndRunsAgain;
var
  S: TTestService;
begin
  S := TTestService.Create;
  try
    S.Every(0.01, @S.Broken, 'cleanup');
    AssertEquals(0, S.Run);
    AssertEquals(2, S.Fails);
    AssertContains('cleanup failed: disk full', LogLines.Text);
  finally
    S.Free;
  end;
end;

procedure TServiceTests.FailingStartIsAnError;
var
  S: TTestService;
begin
  S := TTestService.Create;
  try
    S.FailStart := True;
    S.Every(0.01, @S.Tick);
    AssertEquals(1, S.Run);
    AssertEquals(0, S.Ticks);
    AssertContains('could not start svctest: database not reachable', LogLines.Text);
  finally
    S.Free;
  end;
end;

procedure TServiceTests.JobsCanRunAtStart;
var
  S: TTestService;
begin
  S := TTestService.Create;
  try
    S.Every(3600, @S.Tick, 'hourly', True);
    S.Every(0.01, @S.Stop, 'stopper');
    S.Run;
    AssertEquals(1, S.Ticks);
  finally
    S.Free;
  end;
end;

procedure TServiceTests.PlansDailyJobs;
var
  Now: TDateTime;
begin
  Now := EncodeDateTime(2026, 10, 30, 2, 0, 0, 0);
  AssertEquals('2026-10-30 03:30', FormatDateTime('yyyy-mm-dd hh:nn', NextDailyRun('03:30', Now)));
  Now := EncodeDateTime(2026, 10, 30, 4, 0, 0, 0);
  AssertEquals('2026-10-31 03:30', FormatDateTime('yyyy-mm-dd hh:nn', NextDailyRun('03:30', Now)));
  Now := EncodeDateTime(2026, 12, 31, 23, 59, 0, 0);
  AssertEquals('2027-01-01 00:00', FormatDateTime('yyyy-mm-dd hh:nn', NextDailyRun('0:00', Now)));
end;

procedure TServiceTests.BadTime;
begin
  NextDailyRun('25:00', SysUtils.Now);
end;

procedure TServiceTests.RejectsBadTimes;
begin
  AssertRaises(EConvertError, @BadTime);
end;

type
  TReloader = class
    Service: TTestService;
    Step: Integer;
    procedure Go;
  end;

procedure TReloader.Go;
begin
  Inc(Step);
  case Step of
    1:
      begin
        WriteText('config.toml', 'greeting = "changed"' + LineEnding);
        Service.Reload;
      end;
    3:
      Service.Stop;
  end;
end;

procedure TServiceTests.ReloadReadsSettingsAgain;
var
  S: TTestService;
  R: TReloader;
begin
  WriteText('config.toml', 'greeting = "first"' + LineEnding);
  S := TTestService.Create;
  R := TReloader.Create;
  try
    R.Service := S;
    S.Every(0.02, @R.Go);
    S.Run;
    AssertEquals('started first,reloaded changed,stopping', Joined(S.Events));
    AssertEquals('changed', S.Config.Get('greeting'));
    AssertContains('settings reloaded', LogLines.Text);
  finally
    R.Free;
    S.Free;
  end;
end;

type
  TBreaker = class
    Service: TTestService;
    Step: Integer;
    procedure Go;
  end;

procedure TBreaker.Go;
begin
  Inc(Step);
  case Step of
    1:
      begin
        WriteText('config.toml', 'greeting = changed without quotes' + LineEnding);
        Service.Reload;
      end;
    3:
      Service.Stop;
  end;
end;

procedure TServiceTests.BrokenSettingsKeepTheOldOnes;
var
  S: TTestService;
  B: TBreaker;
begin
  WriteText('config.toml', 'greeting = "first"' + LineEnding);
  S := TTestService.Create;
  B := TBreaker.Create;
  try
    B.Service := S;
    S.Every(0.02, @B.Go);
    S.Run;
    AssertEquals('first', S.Config.Get('greeting'));
    AssertContains('keeping the old settings', LogLines.Text);
    AssertContains('config.toml, line 1', LogLines.Text);
  finally
    B.Free;
    S.Free;
  end;
end;

type
  TWaiter = class
    Service: TTestService;
    Waited: QWord;
    Result: Boolean;
    procedure Go;
  end;

procedure TWaiter.Go;
var
  T: QWord;
begin
  T := GetTickCount64;
  Service.Stop;
  Result := Service.Wait(10000);
  Waited := GetTickCount64 - T;
end;

procedure TServiceTests.WaitReturnsWhenStopping;
var
  S: TTestService;
  W: TWaiter;
begin
  S := TTestService.Create;
  W := TWaiter.Create;
  try
    W.Service := S;
    S.Every(0.01, @W.Go);
    S.Run;
    AssertFalse(W.Result);
    AssertTrue(W.Waited < 1000);
  finally
    W.Free;
    S.Free;
  end;
end;

procedure TServiceTests.StateDirFollowsSystemd;
var
  S: TTestService;
begin
  SetEnv('STATE_DIRECTORY', Dir + 'state');
  S := TTestService.Create;
  try
    AssertEquals(IncludeTrailingPathDelimiter(Dir + 'state'), S.StateDir);
    AssertTrue(DirectoryExists(Dir + 'state'));
  finally
    S.Free;
    UnsetEnv('STATE_DIRECTORY');
  end;
  S := TTestService.Create;
  try
    AssertEquals(IncludeTrailingPathDelimiter(ExpandFileName('data')), S.StateDir);
  finally
    S.Free;
  end;
end;

initialization
  LogLines := TStringList.Create;
  Capture := TCapture.Create;
  RegisterTests(TServiceTests);
end.
