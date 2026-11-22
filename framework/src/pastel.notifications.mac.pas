{ Pastel - notifications on macOS (used by Pastel.Notifications): the
  Notification Center, through osascript ("display notification").
  Part of the Pastel project, MIT License. }
unit Pastel.Notifications.Mac;

{$mode objfpc}{$H+}

interface

function PlatformShow(const Name, Title, Body: string): Boolean;
function PlatformSchedule(const Name, Title, Body: string; AtUnixMs, RepeatMs: Int64): Boolean;
procedure PlatformCancel(const Name: string);
procedure PlatformCancelAll;
function PlatformTakeClicked: string;

var
  PlatformError: string;

implementation

uses
  SysUtils, Process;

{ a text as an AppleScript string }
function AStr(const S: string): string;
begin
  Result := '"' + StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"';
end;

function PlatformShow(const Name, Title, Body: string): Boolean;
var
  Output: string;
begin
  PlatformError := '';
  Result := RunCommand('osascript', ['-e', 'display notification ' + AStr(Body) + ' with title ' + AStr(Title)],
    Output, [poNoConsole]);
  if not Result then
    PlatformError := 'osascript did not work';
end;

function PlatformSchedule(const Name, Title, Body: string; AtUnixMs, RepeatMs: Int64): Boolean;
begin
  Result := False;
end;

procedure PlatformCancel(const Name: string);
begin
end;

procedure PlatformCancelAll;
begin
end;

function PlatformTakeClicked: string;
begin
  Result := '';
end;

end.
