(* Pastel - long-running programs (services, daemons).

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
  Part of the Pastel project, MIT License. *)
unit Pastel.Service;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Config, Pastel.Log;

type
  TJobMethod = procedure of object;
  TJobProc = procedure;

  TServiceJob = class
  public
    Name: string;
    Method: TJobMethod;
    Proc: TJobProc;
    Interval: Double;        { seconds; 0 for a daily job }
    DailyTime: string;       { 'HH:MM' }
    NextRun: TDateTime;
    Runs, Failures: Integer;
  end;

  TService = class
  private
    FName, FVersion: string;
    FConfig: TConfig;
    FJobs: TList;
    FStateDir: string;
    FRunning: Boolean;
    function LoadConfig(out Error: string): TConfig;
    procedure ApplyLogSettings;
    procedure RunDueJobs;
    procedure DoReload;
    function GetStopping: Boolean;
    function AddJob(const JobName: string): TServiceJob;
    function AddInterval(Seconds: Double; const JobName: string; RunAtStart: Boolean): TServiceJob;
    function AddDaily(const Time, JobName: string): TServiceJob;
    function GetStateDir: string;
  protected
    { Defaults for the settings; called before each load (start and reload). }
    procedure Configure(C: TConfig); virtual;
    { After the settings are loaded: open connections, start workers. An
      exception here ends the service with exit code 1. }
    procedure Started; virtual;
    { The service is ending: close what Started opened. Called once. }
    procedure Stopping; virtual;
    { After SIGHUP, with the new settings in Config. }
    procedure Reloaded; virtual;
  public
    constructor Create(const AName: string; const AVersion: string = '');
    destructor Destroy; override;
    { Runs until stopped; the exit code for the program. }
    function Run: Integer;
    { A job every Seconds; the first run after Seconds, or right at the start. }
    procedure Every(Seconds: Double; Job: TJobMethod; const JobName: string = '';
      RunAtStart: Boolean = False);
    procedure Every(Seconds: Double; Job: TJobProc; const JobName: string = '';
      RunAtStart: Boolean = False);
    { A job once a day at Time ('03:30', local time). }
    procedure DailyAt(const Time: string; Job: TJobMethod; const JobName: string = '');
    procedure DailyAt(const Time: string; Job: TJobProc; const JobName: string = '');
    { Asks the service to stop (from a job, a worker thread, a test). }
    procedure Stop;
    { Asks it to read the settings again, as SIGHUP does. }
    procedure Reload;
    { Sleeps up to Ms milliseconds; returns False at once when the service is
      stopping. Long jobs use it instead of Sleep. }
    function Wait(Ms: Integer): Boolean;
    property Name: string read FName;
    property Version: string read FVersion;
    property Config: TConfig read FConfig;
    property IsStopping: Boolean read GetStopping;
    { A folder for the service's own files: $STATE_DIRECTORY under systemd
      (StateDirectory=), else ./data. Created when first used. }
    property StateDir: string read GetStateDir;
  end;

{ When a daily job at Time ('HH:MM') runs next, seen from Now. }
function NextDailyRun(const Time: string; Now: TDateTime): TDateTime;

{ Tells systemd about the service ("READY=1", "STOPPING=1", "STATUS=...").
  Does nothing outside systemd. }
procedure NotifySystemd(const Message: string);

implementation

uses
  DateUtils, Pastel.Env, Pastel.Files
  {$IFDEF UNIX}, BaseUnix, Sockets{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

var
  StopRequested: Boolean = False;
  ReloadRequested: Boolean = False;

{$IFDEF UNIX}
procedure OnSignal(Sig: cint); cdecl;
begin
  case Sig of
    SIGHUP:
      ReloadRequested := True;
  else
    if StopRequested and (Sig = SIGINT) then
      fpExit(130);       { a second Ctrl+C: the user means it }
    StopRequested := True;
  end;
end;

procedure CatchSignals;
begin
  fpSignal(SIGTERM, signalhandler(@OnSignal));
  fpSignal(SIGINT, signalhandler(@OnSignal));
  fpSignal(SIGHUP, signalhandler(@OnSignal));
end;

procedure NotifySystemd(const Message: string);
var
  Path: string;
  Addr: sockaddr_un;
  S: cint;
begin
  Path := GetEnv('NOTIFY_SOCKET');
  if (Path = '') or (Length(Path) >= SizeOf(Addr.sun_path)) or (Message = '') then
    Exit;
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sun_family := AF_UNIX;
  Move(Path[1], Addr.sun_path[0], Length(Path));
  if Path[1] = '@' then
    Addr.sun_path[0] := #0;    { an abstract socket }
  S := fpSocket(AF_UNIX, SOCK_DGRAM, 0);
  if S < 0 then
    Exit;
  fpSendTo(S, @Message[1], Length(Message), 0, psockaddr(@Addr),
    SizeOf(Addr.sun_family) + Length(Path));
  CloseSocket(S);
end;
{$ELSE}
{$IFDEF WINDOWS}
function OnConsoleEvent(Event: DWORD): BOOL; stdcall;
var
  Waited: Integer;
begin
  StopRequested := True;
  { closing the window or logging off ends the process when this returns:
    give the service a few seconds to stop cleanly }
  if Event in [CTRL_CLOSE_EVENT, CTRL_LOGOFF_EVENT, CTRL_SHUTDOWN_EVENT] then
  begin
    Waited := 0;
    while (Waited < 5000) and StopRequested do
    begin
      Sleep(50);
      Inc(Waited, 50);
    end;
  end;
  Result := True;
end;

procedure CatchSignals;
begin
  SetConsoleCtrlHandler(@OnConsoleEvent, True);
end;
{$ELSE}
procedure CatchSignals;
begin
end;
{$ENDIF}

procedure NotifySystemd(const Message: string);
begin
end;
{$ENDIF}

function NextDailyRun(const Time: string; Now: TDateTime): TDateTime;
var
  H, M: Integer;
  Parts: TStringArray;
begin
  Parts := Time.Split([':']);
  if (Length(Parts) <> 2) or not TryStrToInt(Parts[0], H) or not TryStrToInt(Parts[1], M) or
     (H < 0) or (H > 23) or (M < 0) or (M > 59) then
    raise EConvertError.CreateFmt('"%s" is not a time of day; use HH:MM, like 03:30', [Time]);
  Result := DateOf(Now) + EncodeTime(H, M, 0, 0);
  if Result <= Now then
    Result := IncDay(Result);
end;

{ ---------------- TService ---------------- }

constructor TService.Create(const AName: string; const AVersion: string);
var
  Error: string;
begin
  inherited Create;
  FName := AName;
  FVersion := AVersion;
  FJobs := TList.Create;
  { settings are there from the start, so jobs can be set up from them }
  FConfig := LoadConfig(Error);
  if FConfig = nil then
  begin
    Log.Error('%s: %s', [FName, Error]);
    FConfig := TConfig.Create(FName);
  end;
end;

destructor TService.Destroy;
var
  I: Integer;
begin
  for I := 0 to FJobs.Count - 1 do
    TObject(FJobs[I]).Free;
  FJobs.Free;
  FConfig.Free;
  inherited Destroy;
end;

procedure TService.Configure(C: TConfig);
begin
end;

procedure TService.Started;
begin
end;

procedure TService.Stopping;
begin
end;

procedure TService.Reloaded;
begin
end;

function TService.LoadConfig(out Error: string): TConfig;
begin
  Error := '';
  Result := TConfig.Create(FName);
  try
    Configure(Result);
    Result.LoadStandard;
  except
    on E: Exception do
    begin
      Error := E.Message;
      FreeAndNil(Result);
    end;
  end;
end;

{ [log] level = "debug", format = "json" in the settings }
procedure TService.ApplyLogSettings;
var
  F: string;
begin
  try
    if FConfig.Has('log.level') then
      Log.SetLevel(FConfig.Get('log.level'));
    F := LowerCase(FConfig.Get('log.format'));
    if F = 'json' then
      Log.Format := lfJson
    else if F = 'text' then
      Log.Format := lfText
    else if F = 'journal' then
      Log.Format := lfJournal
    else if F <> '' then
      Log.Warn('unknown log format "%s" (text, json or journal)', [F]);
  except
    on E: Exception do
      Log.Warn('log settings: %s', [E.Message]);
  end;
end;

function TService.GetStopping: Boolean;
begin
  Result := StopRequested;
end;

function TService.GetStateDir: string;
begin
  if FStateDir = '' then
  begin
    FStateDir := GetEnv('STATE_DIRECTORY');
    {$IFDEF UNIX}
    if Pos(':', FStateDir) > 1 then           { several folders: the first }
      FStateDir := Copy(FStateDir, 1, Pos(':', FStateDir) - 1);
    {$ENDIF}
    if FStateDir = '' then
      FStateDir := ExpandFileName('data');
    FStateDir := IncludeTrailingPathDelimiter(FStateDir);
    EnsureDir(FStateDir);
  end;
  Result := FStateDir;
end;

function TService.AddJob(const JobName: string): TServiceJob;
begin
  Result := TServiceJob.Create;
  if JobName <> '' then
    Result.Name := JobName
  else
    Result.Name := Format('job %d', [FJobs.Count + 1]);
  FJobs.Add(Result);
end;

function TService.AddInterval(Seconds: Double; const JobName: string; RunAtStart: Boolean): TServiceJob;
begin
  if Seconds <= 0 then
    raise EArgumentException.CreateFmt('job "%s": the interval must be more than 0 seconds', [JobName]);
  Result := AddJob(JobName);
  Result.Interval := Seconds;
  if RunAtStart then
    Result.NextRun := 0
  else
    Result.NextRun := IncMilliSecond(SysUtils.Now, Round(Seconds * 1000));
end;

function TService.AddDaily(const Time, JobName: string): TServiceJob;
var
  Next: TDateTime;
begin
  Next := NextDailyRun(Time, SysUtils.Now);   { checks the time first }
  Result := AddJob(JobName);
  Result.DailyTime := Time;
  Result.NextRun := Next;
end;

procedure TService.Every(Seconds: Double; Job: TJobMethod; const JobName: string; RunAtStart: Boolean);
begin
  AddInterval(Seconds, JobName, RunAtStart).Method := Job;
end;

procedure TService.Every(Seconds: Double; Job: TJobProc; const JobName: string; RunAtStart: Boolean);
begin
  AddInterval(Seconds, JobName, RunAtStart).Proc := Job;
end;

procedure TService.DailyAt(const Time: string; Job: TJobMethod; const JobName: string);
begin
  AddDaily(Time, JobName).Method := Job;
end;

procedure TService.DailyAt(const Time: string; Job: TJobProc; const JobName: string);
begin
  AddDaily(Time, JobName).Proc := Job;
end;

procedure TService.Stop;
begin
  StopRequested := True;
end;

procedure TService.Reload;
begin
  ReloadRequested := True;
end;

function TService.Wait(Ms: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while (Waited < Ms) and not StopRequested do
  begin
    if Ms - Waited < 50 then
      Sleep(Ms - Waited)
    else
      Sleep(50);
    Inc(Waited, 50);
  end;
  Result := not StopRequested;
end;

procedure TService.RunDueJobs;
var
  I: Integer;
  J: TServiceJob;
  Now: TDateTime;
begin
  for I := 0 to FJobs.Count - 1 do
  begin
    if StopRequested then
      Exit;
    J := TServiceJob(FJobs[I]);
    Now := SysUtils.Now;
    if J.NextRun > Now then
      Continue;
    { the next run is planned from now: a slow job does not pile up runs }
    if J.DailyTime <> '' then
      J.NextRun := NextDailyRun(J.DailyTime, Now)
    else
      J.NextRun := IncMilliSecond(Now, Round(J.Interval * 1000));
    Inc(J.Runs);
    try
      Log.Debug('running %s', [J.Name]);
      if Assigned(J.Proc) then
        J.Proc()
      else
        J.Method();
    except
      on E: Exception do
      begin
        Inc(J.Failures);
        Log.Error(E, J.Name + ' failed');
      end;
    end;
  end;
end;

procedure TService.DoReload;
var
  NewConfig: TConfig;
  Error: string;
begin
  ReloadRequested := False;
  NewConfig := LoadConfig(Error);
  if NewConfig = nil then
  begin
    Log.Error('reload: %s; keeping the old settings', [Error]);
    Exit;
  end;
  { systemd wants the clock with it (CLOCK_MONOTONIC, which GetTickCount64 reads) }
  NotifySystemd('RELOADING=1'#10'MONOTONIC_USEC=' + IntToStr(GetTickCount64 * 1000));
  FConfig.Free;
  FConfig := NewConfig;
  ApplyLogSettings;
  try
    Reloaded;
    Log.Info('settings reloaded');
  except
    on E: Exception do
      Log.Error(E, 'reload');
  end;
  NotifySystemd('READY=1');
end;

function TService.Run: Integer;
var
  Watchdog: Int64;
  LastPing: QWord;
  Error: string;
  Fresh: TConfig;
begin
  Result := 0;
  if FRunning then
    raise EInvalidOperation.Create('TService.Run is already running');
  FRunning := True;
  StopRequested := False;
  ReloadRequested := False;
  CatchSignals;

  { the settings as they are now; a mistake in them stops the start }
  Fresh := LoadConfig(Error);
  if Fresh = nil then
  begin
    Log.Error('could not start %s: %s', [FName, Error]);
    FRunning := False;
    Exit(1);
  end;
  FConfig.Free;
  FConfig := Fresh;
  ApplyLogSettings;

  if FVersion <> '' then
    Log.Info('%s %s starting', [FName, FVersion])
  else
    Log.Info('%s starting', [FName]);
  try
    Started;
  except
    on E: Exception do
    begin
      Log.Error(E, 'could not start ' + FName);
      NotifySystemd('STOPPING=1');
      FRunning := False;
      Exit(1);
    end;
  end;
  NotifySystemd('READY=1');
  Log.Info('%s is running', [FName]);

  { WatchdogSec= in the unit: tell systemd twice as often as it asks }
  Watchdog := StrToInt64Def(GetEnv('WATCHDOG_USEC'), 0) div 2000;
  if (GetEnv('WATCHDOG_PID') <> '') and (GetEnv('WATCHDOG_PID') <> IntToStr(GetProcessID)) then
    Watchdog := 0;
  LastPing := GetTickCount64;

  while not StopRequested do
  begin
    if ReloadRequested then
      DoReload;
    RunDueJobs;
    if (Watchdog > 0) and (GetTickCount64 - LastPing >= QWord(Watchdog)) then
    begin
      NotifySystemd('WATCHDOG=1');
      LastPing := GetTickCount64;
    end;
    if not StopRequested then
      Sleep(50);
  end;

  NotifySystemd('STOPPING=1');
  Log.Info('%s stopping', [FName]);
  try
    Stopping;
  except
    on E: Exception do
    begin
      Log.Error(E, 'while stopping');
      Result := 1;
    end;
  end;
  Log.Info('%s stopped', [FName]);
  StopRequested := False;
  FRunning := False;
end;

end.
