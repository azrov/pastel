{ Pastel - notifications on Windows (used by Pastel.Notifications): a message
  from the app's icon in the notification area (Shell_NotifyIcon); Windows 10
  and 11 show it as a toast, older ones as a balloon. The icon stays while the
  app runs and goes when it ends.
  Part of the Pastel project, MIT License. }
unit Pastel.Notifications.Windows;

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
  Windows, SysUtils;

type
  { NOTIFYICONDATAW of Windows Vista and newer (written out: every text is wide) }
  TNotifyIconData = record
    cbSize: DWORD;
    Wnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array[0..127] of WideChar;
    dwState, dwStateMask: DWORD;
    szInfo: array[0..255] of WideChar;
    uTimeout: UINT;
    szInfoTitle: array[0..63] of WideChar;
    dwInfoFlags: DWORD;
    guidItem: TGUID;
    hBalloonIcon: HICON;
  end;

const
  NIM_ADD = 0;
  NIM_MODIFY = 1;
  NIM_DELETE = 2;
  NIF_ICON = 2;
  NIF_TIP = 4;
  NIF_INFO = $10;
  NIIF_INFO = 1;

function Shell_NotifyIconW(Message: DWORD; Data: Pointer): BOOL; stdcall; external 'shell32.dll';

var
  Wnd: HWND = 0;
  Added: Boolean = False;

procedure CopyText(const S: string; P: PWideChar; Size: Integer);
var
  W: UnicodeString;
begin
  W := UTF8Decode(S);
  if Length(W) > Size - 1 then
    W := Copy(W, 1, Size - 2) + #$2026;
  FillChar(P^, Size * SizeOf(WideChar), 0);
  if W <> '' then
    Move(W[1], P^, Length(W) * SizeOf(WideChar));
end;

function NewData: TNotifyIconData;
begin
  Result := Default(TNotifyIconData);
  Result.cbSize := SizeOf(TNotifyIconData);
  Result.Wnd := Wnd;
  Result.uID := 1;
end;

{ the app's icon in the notification area, once: a hidden window of its own holds it }
function EnsureIcon: Boolean;
var
  D: TNotifyIconData;
begin
  if Added then
    Exit(True);
  if Wnd = 0 then
    Wnd := CreateWindowExW(0, 'STATIC', 'Pastel', WS_POPUP, 0, 0, 0, 0, 0, 0, HInstance, nil);
  if Wnd = 0 then
    Exit(False);
  D := NewData;
  D.uFlags := NIF_ICON or NIF_TIP;
  D.hIcon := LoadIconW(HInstance, PWideChar(PtrUInt(1)));      { the app's icon (assets/icon.png) }
  if D.hIcon = 0 then
    D.hIcon := LoadIconW(0, PWideChar(PtrUInt(32512)));          { IDI_APPLICATION }
  CopyText(ChangeFileExt(ExtractFileName(ParamStr(0)), ''), D.szTip, Length(D.szTip));
  Added := Shell_NotifyIconW(NIM_ADD, @D);
  Result := Added;
end;

function PlatformShow(const Name, Title, Body: string): Boolean;
var
  D: TNotifyIconData;
begin
  PlatformError := '';
  if not EnsureIcon then
  begin
    PlatformError := 'the notification area did not take the app''s icon';
    Exit(False);
  end;
  D := NewData;
  D.uFlags := NIF_INFO;
  D.dwInfoFlags := NIIF_INFO;
  CopyText(Title, D.szInfoTitle, Length(D.szInfoTitle));
  CopyText(Body, D.szInfo, Length(D.szInfo));
  Result := Shell_NotifyIconW(NIM_MODIFY, @D);
  if not Result then
    PlatformError := 'Windows did not show the notification';
end;

function PlatformSchedule(const Name, Title, Body: string; AtUnixMs, RepeatMs: Int64): Boolean;
begin
  Result := False;      { shown by Pastel.Notifications while the app runs }
end;

{ a toast cannot be taken back; the balloon of older Windows goes }
procedure PlatformCancel(const Name: string);
var
  D: TNotifyIconData;
begin
  if not Added then
    Exit;
  D := NewData;
  D.uFlags := NIF_INFO;
  Shell_NotifyIconW(NIM_MODIFY, @D);
end;

procedure PlatformCancelAll;
begin
  PlatformCancel('');
end;

function PlatformTakeClicked: string;
begin
  Result := '';
end;

var
  D: TNotifyIconData;

finalization
  if Added then
  begin
    D := NewData;
    Shell_NotifyIconW(NIM_DELETE, @D);
  end;
  if Wnd <> 0 then
    DestroyWindow(Wnd);

end.
