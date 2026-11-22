{ Pastel - notifications on Linux (used by Pastel.Notifications): the
  desktop's notifications (org.freedesktop.Notifications on D-Bus, the same
  for GNOME, KDE, Cinnamon, XFCE...) through gdbus, which can replace and take
  back a notification; else notify-send.
  Part of the Pastel project, MIT License. }
unit Pastel.Notifications.Linux;

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
  Classes, SysUtils, Process;

var
  { the desktop's number of each notification shown, by name: to replace or close it }
  Ids: TStringList = nil;

{ a text as a GVariant string: 'it''s' -> 'it\'s' }
function GStr(const S: string): string;
begin
  Result := '''' + StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]), '''', '\''', [rfReplaceAll]) + '''';
end;

function AppName: string;
begin
  Result := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
end;

function Gdbus(const Method: string; const Args: array of string; out Output: string): Boolean;
var
  A: array of string;
  I: Integer;
begin
  A := nil;
  SetLength(A, 9 + Length(Args));
  A[0] := 'call';
  A[1] := '--session';
  A[2] := '--dest';
  A[3] := 'org.freedesktop.Notifications';
  A[4] := '--object-path';
  A[5] := '/org/freedesktop/Notifications';
  A[6] := '--method';
  A[7] := 'org.freedesktop.Notifications.' + Method;
  A[8] := '--timeout=5';
  for I := 0 to High(Args) do
    A[9 + I] := Args[I];
  Result := RunCommand('gdbus', A, Output, [poNoConsole]);
end;

function PlatformShow(const Name, Title, Body: string): Boolean;
var
  Output, Old, Id: string;
  P, Q: Integer;
begin
  PlatformError := '';
  if Ids = nil then
    Ids := TStringList.Create;
  Old := Ids.Values[Name];
  if Old = '' then
    Old := '0';
  { Notify(app, replaces id, icon, title, text, actions, hints, timeout) -> (uint32 id,) }
  if Gdbus('Notify', [GStr(AppName), 'uint32 ' + Old, GStr(''), GStr(Title), GStr(Body), '@as []',
    '@a{sv} {}', 'int32 -1'], Output) then
  begin
    P := Pos('uint32 ', Output);
    if P > 0 then
    begin
      Id := Copy(Output, P + 7, MaxInt);
      Q := 1;
      while (Q <= Length(Id)) and (Id[Q] in ['0'..'9']) do
        Inc(Q);
      Ids.Values[Name] := Copy(Id, 1, Q - 1);
    end;
    Exit(True);
  end;
  Result := RunCommand('notify-send', ['--app-name=' + AppName, Title, Body], Output, [poNoConsole]);
  if not Result then
    PlatformError := 'no notifications on this desktop (gdbus or notify-send: sudo apt install libnotify-bin)';
end;

function PlatformSchedule(const Name, Title, Body: string; AtUnixMs, RepeatMs: Int64): Boolean;
begin
  Result := False;      { shown by Pastel.Notifications while the app runs }
end;

procedure PlatformCancel(const Name: string);
var
  Output: string;
begin
  if (Ids = nil) or (Ids.Values[Name] = '') then
    Exit;
  Gdbus('CloseNotification', ['uint32 ' + Ids.Values[Name]], Output);
  Ids.Values[Name] := '';
end;

procedure PlatformCancelAll;
var
  I: Integer;
  Output: string;
begin
  if Ids = nil then
    Exit;
  for I := 0 to Ids.Count - 1 do
    Gdbus('CloseNotification', ['uint32 ' + Ids.ValueFromIndex[I]], Output);
  Ids.Clear;
end;

function PlatformTakeClicked: string;
begin
  Result := '';
end;

finalization
  Ids.Free;

end.
