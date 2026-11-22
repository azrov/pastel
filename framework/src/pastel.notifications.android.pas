{ Pastel - notifications on Android (used by Pastel.Notifications): the
  notification bar through Pastel's activity (PastelNotifications.java);
  scheduled ones are kept by AlarmManager, also when the app is closed and
  after a restart of the phone.
  Part of the Pastel project, MIT License. }
unit Pastel.Notifications.Android;

{$mode objfpc}{$H+}

interface

function PlatformShow(const Name, Title, Body: string): Boolean;
{ True: the system keeps it (else Pastel.Notifications shows it while the app runs). }
function PlatformSchedule(const Name, Title, Body: string; AtUnixMs, RepeatMs: Int64): Boolean;
procedure PlatformCancel(const Name: string);
procedure PlatformCancelAll;
function PlatformTakeClicked: string;

var
  PlatformError: string;

implementation

uses
  Pastel.Android;

function PlatformShow(const Name, Title, Body: string): Boolean;
begin
  PlatformError := '';
  Result := AndroidCall('showNotification', '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V',
    [Name, Title, Body]);
  if not Result then
    PlatformError := 'the notification could not be shown';
end;

function PlatformSchedule(const Name, Title, Body: string; AtUnixMs, RepeatMs: Int64): Boolean;
begin
  PlatformError := '';
  Result := AndroidCall('scheduleNotification',
    '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;JJ)V', [Name, Title, Body, AtUnixMs, RepeatMs]);
end;

procedure PlatformCancel(const Name: string);
begin
  AndroidCall('cancelNotification', '(Ljava/lang/String;)V', [Name]);
end;

procedure PlatformCancelAll;
begin
  AndroidCall('cancelAllNotifications', '()V', []);
end;

function PlatformTakeClicked: string;
begin
  Result := AndroidCallString('takeClickedNotification', '()Ljava/lang/String;', []);
end;

end.
