{ Pastel - notifications: a message in the system's notification area, now or
  at a time, once or again and again; taken back; which one the user tapped.

    ShowNotification('Sync', '12 appointments came in');
    ScheduleNotification('appt-42', 'Appointment', 'Ayşe at 10:00', Start - OneHour);
    ScheduleNotification('backup', 'Backup', 'Time for the weekly backup', NextMonday9, riWeekly);
    CancelNotification('appt-42');

  Or as a component on the form (TNotificationCenter), with an event for taps:
    procedure THomeForm.NotificationsNotificationClick(Sender: TObject; const AName: string);
    begin
      if AName = 'appt-42' then OpenAppointment(42);
    end;

  A notification has a name: the same name replaces it (shown or scheduled),
  CancelNotification takes it back. Times are local (Now, EncodeDateTime...).

  Each platform does it its own way, in its own unit:
    Android  Pastel.Notifications.Android: the notification bar; scheduled ones
             come also when the app is closed and after a restart of the phone
             (AlarmManager; a few minutes late at most while the phone sleeps);
             taps are told (OnNotificationClick). Needs [package.android]
             permissions = ["notifications"] (Android 13 and newer ask the user).
    Linux    Pastel.Notifications.Linux: the desktop's notifications (D-Bus
             through gdbus, else notify-send).
    Windows  Pastel.Notifications.Windows: a message from the app's icon in the
             notification area (Windows 10 and 11 show it as a toast).
    macOS    Pastel.Notifications.Mac: the Notification Center (osascript).
  On computers, scheduled notifications come while the app is running.

  Part of the Pastel project, MIT License. }
unit Pastel.Notifications;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { How often a scheduled notification comes again. }
  TRepeatInterval = (riNone, riHourly, riDaily, riWeekly);

  { AName: the notification's name (not Name: a form has a Name of its own). }
  TNotificationClickEvent = procedure(Sender: TObject; const AName: string) of object;

{ Shows a notification now; the same Name replaces the one before ('' : a new one each time). }
function ShowNotification(const Title, Body: string; const Name: string = ''): Boolean;
{ Shows it at the time At (local), and again every hour, day or week. A time
  that has passed: now. The same Name replaces it. }
function ScheduleNotification(const Name, Title, Body: string; At: TDateTime;
  Repeats: TRepeatInterval = riNone): Boolean;
{ Takes back a notification: the scheduled one and the one shown. }
procedure CancelNotification(const Name: string);
procedure CancelAllNotifications;
{ The name of the notification the user tapped last (that opened the app), once; ''
  when none. TNotificationCenter.OnNotificationClick tells it by itself. }
function TakeClickedNotification: string;

type
  { The notifications as a component: put it on the form (it is not drawn) for
    the event of taps. }
  TNotificationCenter = class(TComponent)
  private
    FOnClick: TNotificationClickEvent;
    FTimer: TComponent;
    procedure SetOnClick(AValue: TNotificationClickEvent);
    procedure Tick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    function Show(const Title, Body: string; const AName: string = ''): Boolean;
    function Schedule(const AName, Title, Body: string; At: TDateTime; Repeats: TRepeatInterval = riNone): Boolean;
    procedure Cancel(const AName: string);
    procedure CancelAll;
  published
    { The user tapped a notification of the app (on Android; the app was opened by it). }
    property OnNotificationClick: TNotificationClickEvent read FOnClick write SetOnClick;
  end;

var
  { Why the last call did not work ('' when it did). }
  LastNotificationError: string;
  { For tests: when set, notifications are not shown but added here as
    'name|title|body' lines; scheduled ones too, when their time comes
    (ProcessTimers; none kept by the system). }
  CapturedNotifications: TStrings = nil;

implementation

uses
  DateUtils, Pastel.UI,
  {$IF defined(ANDROID)}
  Pastel.Notifications.Android, Pastel.Device
  {$ELSEIF defined(WINDOWS)}
  Pastel.Notifications.Windows
  {$ELSEIF defined(DARWIN)}
  Pastel.Notifications.Mac
  {$ELSE}
  Pastel.Notifications.Linux
  {$ENDIF};

const
  RepeatMs: array[TRepeatInterval] of Int64 = (0, 3600000, 86400000, 7 * 86400000);

type
  { scheduled notifications where the system does not keep them (computers): shown by a timer while the app runs }
  TWaiting = class
    Name, Title, Body: string;
    At: TDateTime;
    Repeats: TRepeatInterval;
  end;

  TScheduler = class(TComponent)
  private
    FList: TFPList;
    FTimer: TTimer;
    procedure Tick(Sender: TObject);
    function IndexOf(const AName: string): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Add(const AName, Title, Body: string; At: TDateTime; Repeats: TRepeatInterval);
    procedure Remove(const AName: string);
    procedure Clear;
  end;

var
  Scheduler: TScheduler = nil;
  Counter: Integer = 0;

function DoShow(const Name, Title, Body: string): Boolean;
begin
  if CapturedNotifications <> nil then
  begin
    CapturedNotifications.Add(Name + '|' + Title + '|' + Body);
    Exit(True);
  end;
  Result := PlatformShow(Name, Title, Body);
end;

constructor TScheduler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FList := TFPList.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.Enabled := False;
  FTimer.OnTimer := @Tick;
end;

destructor TScheduler.Destroy;
begin
  Clear;
  FList.Free;
  inherited Destroy;
end;

function TScheduler.IndexOf(const AName: string): Integer;
begin
  for Result := 0 to FList.Count - 1 do
    if TWaiting(FList[Result]).Name = AName then
      Exit;
  Result := -1;
end;

procedure TScheduler.Add(const AName, Title, Body: string; At: TDateTime; Repeats: TRepeatInterval);
var
  W: TWaiting;
begin
  Remove(AName);
  W := TWaiting.Create;
  W.Name := AName;
  W.Title := Title;
  W.Body := Body;
  W.At := At;
  W.Repeats := Repeats;
  FList.Add(W);
  FTimer.Enabled := True;
end;

procedure TScheduler.Remove(const AName: string);
var
  I: Integer;
begin
  I := IndexOf(AName);
  if I >= 0 then
  begin
    TWaiting(FList[I]).Free;
    FList.Delete(I);
  end;
  FTimer.Enabled := FList.Count > 0;
end;

procedure TScheduler.Clear;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    TWaiting(FList[I]).Free;
  FList.Clear;
  FTimer.Enabled := False;
end;

procedure TScheduler.Tick(Sender: TObject);
var
  I: Integer;
  W: TWaiting;
  T: TDateTime;
begin
  T := Now;
  for I := FList.Count - 1 downto 0 do
  begin
    W := TWaiting(FList[I]);
    if W.At > T then
      Continue;
    DoShow(W.Name, W.Title, W.Body);
    if W.Repeats = riNone then
    begin
      W.Free;
      FList.Delete(I);
    end
    else
      while W.At <= T do
        W.At := IncMilliSecond(W.At, RepeatMs[W.Repeats]);
  end;
  FTimer.Enabled := FList.Count > 0;
end;

function NewName: string;
begin
  Inc(Counter);
  Result := Format('pastel-%d-%d', [Counter, DateTimeToUnix(Now)]);
end;

function ShowNotification(const Title, Body: string; const Name: string): Boolean;
var
  N: string;
begin
  LastNotificationError := '';
  N := Name;
  if N = '' then
    N := NewName;
  {$IFDEF ANDROID}
  if CapturedNotifications = nil then
    RequestPermission(dpNotifications, nil);   { Android 13 and newer: asked once }
  {$ENDIF}
  Result := DoShow(N, Title, Body);
  if not Result then
    LastNotificationError := PlatformError;
end;

function ScheduleNotification(const Name, Title, Body: string; At: TDateTime; Repeats: TRepeatInterval): Boolean;
begin
  LastNotificationError := '';
  if Name = '' then
  begin
    LastNotificationError := 'a scheduled notification needs a name (to replace or cancel it)';
    Exit(False);
  end;
  {$IFDEF ANDROID}
  RequestPermission(dpNotifications, nil);
  {$ENDIF}
  { the system keeps it (Android), else the app does while it runs }
  if (CapturedNotifications = nil) and PlatformSchedule(Name, Title, Body, DateTimeToUnix(LocalTimeToUniversal(At)) * 1000 + MilliSecondOf(At),
    RepeatMs[Repeats]) then
    Exit(True);
  if Scheduler = nil then
    Scheduler := TScheduler.Create(nil);
  Scheduler.Add(Name, Title, Body, At, Repeats);
  Result := True;
end;

procedure CancelNotification(const Name: string);
begin
  LastNotificationError := '';
  if Scheduler <> nil then
    Scheduler.Remove(Name);
  if CapturedNotifications = nil then
    PlatformCancel(Name);
end;

procedure CancelAllNotifications;
begin
  LastNotificationError := '';
  if Scheduler <> nil then
    Scheduler.Clear;
  if CapturedNotifications = nil then
    PlatformCancelAll;
end;

function TakeClickedNotification: string;
begin
  Result := PlatformTakeClicked;
end;

{ ---- TNotificationCenter ---- }

constructor TNotificationCenter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

procedure TNotificationCenter.SetOnClick(AValue: TNotificationClickEvent);
begin
  FOnClick := AValue;
  { taps are looked for a few times a second while someone listens }
  if Assigned(FOnClick) and (FTimer = nil) and not (csDesigning in ComponentState) then
  begin
    FTimer := TTimer.Create(Self);
    TTimer(FTimer).Interval := 300;
    TTimer(FTimer).OnTimer := @Tick;
  end;
end;

procedure TNotificationCenter.Tick(Sender: TObject);
var
  N: string;
begin
  if not Assigned(FOnClick) then
    Exit;
  N := TakeClickedNotification;
  if N <> '' then
    FOnClick(Self, N);
end;

function TNotificationCenter.Show(const Title, Body: string; const AName: string): Boolean;
begin
  Result := ShowNotification(Title, Body, AName);
end;

function TNotificationCenter.Schedule(const AName, Title, Body: string; At: TDateTime;
  Repeats: TRepeatInterval): Boolean;
begin
  Result := ScheduleNotification(AName, Title, Body, At, Repeats);
end;

procedure TNotificationCenter.Cancel(const AName: string);
begin
  CancelNotification(AName);
end;

procedure TNotificationCenter.CancelAll;
begin
  CancelAllNotifications;
end;

initialization
  RegisterNonVisual(TNotificationCenter);

finalization
  FreeAndNil(Scheduler);

end.
