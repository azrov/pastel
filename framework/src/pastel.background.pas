{ Pastel - work that goes on when the app is not on the screen.

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
  Part of the Pastel project, MIT License. }
unit Pastel.Background;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TBackgroundKind = (bkDataSync, bkMediaPlayback, bkLocation, bkConnectedDevice);
  { a background job: True when done, False when it should be tried again later }
  TBackgroundJob = function: Boolean;

{ The app keeps running with a notification (Title, Text) until StopBackgroundWork.
  Kind must be in pastel.toml's [package.android] background. }
procedure StartBackgroundWork(const Title, Text: string; Kind: TBackgroundKind = bkDataSync);
{ A new text for its notification. }
procedure UpdateBackgroundWork(const Text: string);
procedure StopBackgroundWork;
function BackgroundWorkRunning: Boolean;

{ A job by name; in a unit's initialization, so it is there when Android starts the app for it. }
procedure RegisterBackgroundJob(const Name: string; Job: TBackgroundJob);
{ Runs it about every EveryMinutes (15 at least), when there is a network if
  NeedsNetwork; also after the phone restarted. False when it could not be planned. }
function ScheduleBackgroundJob(const Name: string; EveryMinutes: Integer = 60; NeedsNetwork: Boolean = True): Boolean;
procedure CancelBackgroundJob(const Name: string);
{ Runs a registered job now (tests, a "Sync now" button); its answer. }
function RunBackgroundJob(const Name: string): Boolean;
{ True inside a job Android started without the app's window. }
function InBackgroundJob: Boolean;

implementation

uses
  Math, SyncObjs, Pastel.UI{$IFDEF ANDROID}, Pastel.Android{$ENDIF};

const
  { Android's ServiceInfo.FOREGROUND_SERVICE_TYPE_... }
  KindCodes: array[TBackgroundKind] of Integer = (1, 2, 8, 16);

var
  Jobs: TStringList;          { name -> TJobEntry }
  Lock: TCriticalSection;
  WorkTitle: string = '';
  {$IFNDEF ANDROID}
  WorkOn: Boolean = False;
  {$ENDIF}

threadvar
  InJob: Boolean;

type
  TJobEntry = class
    Job: TBackgroundJob;
    Timer: TComponent;         { computers: the timer that runs it while the app is open }
    procedure Tick(Sender: TObject);
  end;

function FindJob(const Name: string): TJobEntry;
var
  I: Integer;
begin
  Result := nil;
  Lock.Enter;
  try
    I := Jobs.IndexOf(Name);
    if I >= 0 then
      Result := TJobEntry(Jobs.Objects[I]);
  finally
    Lock.Leave;
  end;
end;

procedure TJobEntry.Tick(Sender: TObject);
begin
  InJob := True;
  try
    try
      Job();
    except
      on E: Exception do
        if IsConsole then
          WriteLn(StdErr, 'error: a background job: ', E.Message);
    end;
  finally
    InJob := False;
  end;
end;

procedure StartBackgroundWork(const Title, Text: string; Kind: TBackgroundKind);
begin
  WorkTitle := Title;
  {$IFDEF ANDROID}
  AndroidCall('startWork', '(Ljava/lang/String;Ljava/lang/String;I)V', [Title, Text, KindCodes[Kind]]);
  {$ELSE}
  WorkOn := True;
  if KindCodes[Kind] = 0 then ;
  {$ENDIF}
end;

procedure UpdateBackgroundWork(const Text: string);
begin
  {$IFDEF ANDROID}
  if BackgroundWorkRunning then
    AndroidCall('updateWork', '(Ljava/lang/String;Ljava/lang/String;)V', [WorkTitle, Text]);
  {$ELSE}
  if Text = '' then ;
  {$ENDIF}
end;

procedure StopBackgroundWork;
begin
  {$IFDEF ANDROID}
  AndroidCall('stopWork', '()V', []);
  {$ELSE}
  WorkOn := False;
  {$ENDIF}
end;

function BackgroundWorkRunning: Boolean;
begin
  {$IFDEF ANDROID}
  Result := AndroidCallString('workRunning', '()Ljava/lang/String;', []) <> '';
  {$ELSE}
  Result := WorkOn;
  {$ENDIF}
end;

procedure RegisterBackgroundJob(const Name: string; Job: TBackgroundJob);
var
  E: TJobEntry;
  I: Integer;
begin
  Lock.Enter;
  try
    I := Jobs.IndexOf(Name);
    if I >= 0 then
      E := TJobEntry(Jobs.Objects[I])
    else
    begin
      E := TJobEntry.Create;
      Jobs.AddObject(Name, E);
    end;
    E.Job := Job;
  finally
    Lock.Leave;
  end;
end;

function RunBackgroundJob(const Name: string): Boolean;
var
  E: TJobEntry;
  Was: Boolean;
begin
  E := FindJob(Name);
  if (E = nil) or not Assigned(E.Job) then
    raise Exception.CreateFmt('there is no background job "%s" (RegisterBackgroundJob)', [Name]);
  Was := InJob;
  InJob := True;
  try
    Result := E.Job();
  finally
    InJob := Was;
  end;
end;

function InBackgroundJob: Boolean;
begin
  Result := InJob;
end;

function ScheduleBackgroundJob(const Name: string; EveryMinutes: Integer; NeedsNetwork: Boolean): Boolean;
var
  E: TJobEntry;
begin
  E := FindJob(Name);
  if E = nil then
    raise Exception.CreateFmt('there is no background job "%s" (RegisterBackgroundJob)', [Name]);
  EveryMinutes := Max(15, EveryMinutes);
  {$IFDEF ANDROID}
  Result := AndroidCallString('scheduleJob', '(Ljava/lang/String;IZ)Ljava/lang/String;', [Name, EveryMinutes, NeedsNetwork]) <> '';
  if E.Timer <> nil then ;
  {$ELSE}
  { a computer: while the app is open }
  if E.Timer = nil then
  begin
    E.Timer := TTimer.Create(nil);
    TTimer(E.Timer).OnTimer := @E.Tick;
  end;
  TTimer(E.Timer).Interval := EveryMinutes * 60000;
  TTimer(E.Timer).Enabled := True;
  Result := True;
  if NeedsNetwork then ;
  {$ENDIF}
end;

procedure CancelBackgroundJob(const Name: string);
var
  E: TJobEntry;
begin
  {$IFDEF ANDROID}
  AndroidCall('cancelJob', '(Ljava/lang/String;)V', [Name]);
  {$ENDIF}
  E := FindJob(Name);
  if (E <> nil) and (E.Timer <> nil) then
    TTimer(E.Timer).Enabled := False;
end;

{$IFDEF ANDROID}
{ Pastel.Android's nativeJob: on Java's thread for the job }
function HandleJob(const Name: string): Boolean;
var
  E: TJobEntry;
begin
  E := FindJob(Name);
  if (E = nil) or not Assigned(E.Job) then
  begin
    AndroidLog('the background job "' + Name + '" is not registered (RegisterBackgroundJob in an initialization)');
    Exit(True);
  end;
  InJob := True;
  try
    Result := E.Job();
  finally
    InJob := False;
  end;
end;
{$ENDIF}

procedure FreeJobs;
var
  I: Integer;
begin
  for I := 0 to Jobs.Count - 1 do
  begin
    TJobEntry(Jobs.Objects[I]).Timer.Free;
    Jobs.Objects[I].Free;
  end;
  Jobs.Free;
end;

initialization
  Lock := TCriticalSection.Create;
  Jobs := TStringList.Create;
  {$IFDEF ANDROID}
  AndroidJobHandler := @HandleJob;
  {$ENDIF}

finalization
  FreeJobs;
  Lock.Free;
end.
