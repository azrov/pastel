{ Pastel - a desktop app in the system tray, and keys that work everywhere.

    object Tray: TTrayIcon
      Hint = 'Salon - 3 appointments today'
      Menu = ('Open', 'Sync now', '-', 'Quit')
      OnMenuItem = TrayMenuItem
      OnClick = TrayClick                    // Windows: a click on the icon
    end

    RegisterHotKey('Ctrl+Shift+S', @QuickSearch);     // also when another app is in front

  Windows: the notification area (Shell_NotifyIcon), hot keys with RegisterHotKey.
  Linux: the tray of KDE, Xfce, Cinnamon, MATE, Budgie (GNOME with the
  AppIndicator extension) through libayatana-appindicator (or libappindicator);
  its icon opens the menu. Hot keys on X11 (not Wayland, which does not let
  apps take keys of other windows). Phones: nothing.
  Part of the Pastel project, MIT License. }
unit Pastel.Tray;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI;

type
  TTrayMenuEvent = procedure(Sender: TObject; Index: Integer; const Caption: string) of object;

  TTrayIcon = class(TComponent)
  private
    FHint, FIconFile: string;
    FVisible, FShown: Boolean;
    FMenu: TStringList;
    FOnClick: TNotifyEvent;
    FOnMenuItem: TTrayMenuEvent;
    FHandle: Pointer;           { Linux: the indicator }
    FTimer: TTimer;
    procedure SetVisible(AValue: Boolean);
    procedure SetHint(const AValue: string);
    procedure SetIconFile(const AValue: string);
    procedure SetMenu(AValue: TStringList);
    procedure MenuChanged(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Show;
    procedure Hide;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Internal: what the system said }
    procedure Clicked;
    procedure MenuItem(Index: Integer);
    { '' or why the tray is not there }
    function Error: string;
  published
    property Hint: string read FHint write SetHint;
    { a PNG (Linux) or .ico (Windows); default: the app's icon }
    property IconFile: string read FIconFile write SetIconFile;
    property Visible: Boolean read FVisible write SetVisible default True;
    { the menu's items; '-' a line between them }
    property Menu: TStringList read FMenu write SetMenu;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
    property OnMenuItem: TTrayMenuEvent read FOnMenuItem write FOnMenuItem;
  end;

{ Keys like 'Ctrl+Shift+K', 'Alt+F9', 'Win+Space': OnPressed even when another
  app is in front; its id (0: not taken - another app has it, or Wayland). }
function RegisterHotKey(const Keys: string; OnPressed: TNotifyEvent): Integer;
procedure UnregisterHotKey(Id: Integer);

implementation

uses
  dynlibs, Pastel.Dialogs, Pastel.Files
  {$IFDEF WINDOWS}, Windows{$ENDIF};

var
  TrayError: string = '';
  Hotkeys: array of record
    Id: Integer;
    Mods, Key: Cardinal;
    Code: Integer;
    OnPressed: TNotifyEvent;
  end;
  NextHotkey: Integer = 1;
  Icons: TFPList;

procedure ParseKeys(const Keys: string; out Ctrl, Shift, Alt, Win: Boolean; out Key: string);
var
  P: string;
begin
  Ctrl := False; Shift := False; Alt := False; Win := False; Key := '';
  for P in Keys.Split(['+']) do
    case LowerCase(Trim(P)) of
      'ctrl', 'control': Ctrl := True;
      'shift': Shift := True;
      'alt': Alt := True;
      'win', 'super', 'meta', 'cmd': Win := True;
    else
      Key := Trim(P);
    end;
  if Key = '' then
    raise Exception.CreateFmt('"%s": a hot key needs a key besides Ctrl, Shift, Alt, Win', [Keys]);
end;

{$IFDEF WINDOWS}
{ ---------------- Windows ---------------- }

type
  TNotifyIconDataW = record
    cbSize: DWORD;
    hWnd: HWND;
    uID, uFlags, uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array[0..127] of WideChar;
  end;

const
  NIM_ADD = 0; NIM_MODIFY = 1; NIM_DELETE = 2;
  NIF_MESSAGE = 1; NIF_ICON = 2; NIF_TIP = 4;
  WM_TRAY = $8000 + 77;     { WM_APP + 77 }

function Shell_NotifyIconW(Msg: DWORD; Data: Pointer): BOOL; stdcall; external 'shell32.dll';
function ExtractIconW(Inst: HINST; Path: PWideChar; Index: UINT): HICON; stdcall; external 'shell32.dll';

type
  TMessageHook = procedure(UserData, Wnd: Pointer; Msg: Cardinal; WParam: QWord; LParam: Int64); cdecl;

var
  HookSet: Boolean = False;

procedure OnMessage(UserData, Wnd: Pointer; Msg: Cardinal; WParam: QWord; LParam: Int64); cdecl;
var
  I: Integer;
begin
  if (Msg = WM_TRAY) and (WParam < QWord(Icons.Count)) then
    case LParam and $FFFF of
      WM_LBUTTONUP: TTrayIcon(Icons[WParam]).Clicked;
      WM_RBUTTONUP: TTrayIcon(Icons[WParam]).MenuItem(-1);
    end
  else if Msg = WM_HOTKEY then
    for I := 0 to High(Hotkeys) do
      if (Hotkeys[I].Id = Integer(WParam)) and Assigned(Hotkeys[I].OnPressed) then
        Hotkeys[I].OnPressed(nil);
end;

function EnsureHook: Boolean;
var
  SetHook: procedure(Hook: TMessageHook; UserData: Pointer); cdecl;
begin
  if not HookSet then
  begin
    Pointer(SetHook) := GetProcAddress(GetModuleHandle('SDL2.dll'), 'SDL_SetWindowsMessageHook');
    if Assigned(SetHook) then
    begin
      SetHook(@OnMessage, nil);
      HookSet := True;
    end;
  end;
  Result := HookSet;
end;

function MainHwnd: HWND;
begin
  Result := 0;
  if Assigned(NativeWindowHook) then
    Result := HWND(NativeWindowHook());
end;

procedure IconData(T: TTrayIcon; out D: TNotifyIconDataW);
var
  Tip: UnicodeString;
begin
  D := Default(TNotifyIconDataW);
  D.cbSize := SizeOf(D);
  D.hWnd := MainHwnd;
  D.uID := Icons.IndexOf(T);
  D.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
  D.uCallbackMessage := WM_TRAY;
  if T.FIconFile <> '' then
    D.hIcon := LoadImageW(0, PWideChar(UnicodeString(T.FIconFile)), IMAGE_ICON, 0, 0, LR_LOADFROMFILE or LR_DEFAULTSIZE)
  else
    D.hIcon := ExtractIconW(HInstance, PWideChar(UnicodeString(ParamStr(0))), 0);
  if D.hIcon <= 1 then
    D.hIcon := LoadIcon(0, IDI_APPLICATION);
  Tip := UnicodeString(Copy(T.FHint, 1, 120));
  if Tip <> '' then
    Move(Tip[1], D.szTip[0], Length(Tip) * 2);
end;

procedure TTrayIcon.Show;
var
  D: TNotifyIconDataW;
begin
  if MainHwnd = 0 then
  begin
    TrayError := 'the tray needs the app''s window (it is shown after Application.Run starts)';
    Exit;
  end;
  EnsureHook;
  IconData(Self, D);
  if FShown then
    Shell_NotifyIconW(NIM_MODIFY, @D)
  else
    FShown := Shell_NotifyIconW(NIM_ADD, @D);
end;

procedure TTrayIcon.Hide;
var
  D: TNotifyIconDataW;
begin
  if not FShown then
    Exit;
  IconData(Self, D);
  Shell_NotifyIconW(NIM_DELETE, @D);
  FShown := False;
end;

procedure TTrayIcon.MenuItem(Index: Integer);
var
  M: HMENU;
  I: Integer;
  P: TPoint;
  Cmd: LongBool;
begin
  if Index >= 0 then
  begin
    if Assigned(FOnMenuItem) then
      FOnMenuItem(Self, Index, FMenu[Index]);
    Exit;
  end;
  if FMenu.Count = 0 then
    Exit;
  { the right button: the menu where the mouse is }
  M := CreatePopupMenu;
  for I := 0 to FMenu.Count - 1 do
    if FMenu[I] = '-' then
      AppendMenuW(M, MF_SEPARATOR, 0, nil)
    else
      AppendMenuW(M, MF_STRING, I + 1, PWideChar(UnicodeString(FMenu[I])));
  GetCursorPos(P);
  SetForegroundWindow(MainHwnd);
  Cmd := TrackPopupMenu(M, TPM_RETURNCMD or TPM_RIGHTBUTTON, P.X, P.Y, 0, MainHwnd, nil);
  DestroyMenu(M);
  if Integer(Cmd) > 0 then
    MenuItem(Integer(Cmd) - 1);
end;

procedure TTrayIcon.Tick(Sender: TObject);
begin
  if FVisible and not FShown and not (csDesigning in ComponentState) then
    Show;
  if FShown then
    FTimer.Enabled := False;
end;

function KeyCode(const K: string): Cardinal;
var
  U: string;
begin
  U := UpperCase(K);
  if (Length(U) = 1) and (U[1] in ['A'..'Z', '0'..'9']) then
    Exit(Ord(U[1]));
  if (Length(U) >= 2) and (U[1] = 'F') and (StrToIntDef(Copy(U, 2, 2), 0) in [1..24]) then
    Exit($70 + StrToInt(Copy(U, 2, 2)) - 1);
  case U of
    'SPACE': Result := VK_SPACE;
    'ENTER', 'RETURN': Result := VK_RETURN;
    'ESC', 'ESCAPE': Result := VK_ESCAPE;
    'TAB': Result := VK_TAB;
    'HOME': Result := VK_HOME;
    'END': Result := VK_END;
    'INSERT': Result := VK_INSERT;
    'DELETE': Result := VK_DELETE;
    'PRINTSCREEN': Result := VK_SNAPSHOT;
  else
    raise Exception.CreateFmt('the key "%s" is not one a hot key can be (A-Z, 0-9, F1-F24, Space...)', [K]);
  end;
end;

function RegisterHotKey(const Keys: string; OnPressed: TNotifyEvent): Integer;
var
  C, S, A, W: Boolean;
  K: string;
  Mods: Cardinal;
begin
  ParseKeys(Keys, C, S, A, W, K);
  Mods := $4000;    { MOD_NOREPEAT }
  if A then Mods := Mods or 1;
  if C then Mods := Mods or 2;
  if S then Mods := Mods or 4;
  if W then Mods := Mods or 8;
  Result := 0;
  if (MainHwnd = 0) or not EnsureHook then
    Exit;
  if not Windows.RegisterHotKey(MainHwnd, NextHotkey, Mods, KeyCode(K)) then
    Exit;
  Result := NextHotkey;
  Inc(NextHotkey);
  SetLength(Hotkeys, Length(Hotkeys) + 1);
  Hotkeys[High(Hotkeys)].Id := Result;
  Hotkeys[High(Hotkeys)].OnPressed := OnPressed;
end;

procedure UnregisterHotKey(Id: Integer);
var
  I: Integer;
begin
  for I := High(Hotkeys) downto 0 do
    if Hotkeys[I].Id = Id then
    begin
      Windows.UnregisterHotKey(MainHwnd, Id);
      Delete(Hotkeys, I, 1);
    end;
end;

procedure PollHotkeys;
begin
end;
{$ENDIF}

{$IF defined(LINUX) and not defined(ANDROID)}
{ ---------------- Linux ---------------- }

type
  TGCallback = procedure(Widget, Data: Pointer); cdecl;

var
  Gtk, GObject, Indicator, X11: TLibHandle;
  GtkReady: Boolean = False;
  gtk_init_check: function(argc, argv: Pointer): LongInt; cdecl;
  gtk_menu_new: function: Pointer; cdecl;
  gtk_menu_item_new_with_label: function(Lbl: PChar): Pointer; cdecl;
  gtk_separator_menu_item_new: function: Pointer; cdecl;
  gtk_menu_shell_append: procedure(Shell, Child: Pointer); cdecl;
  gtk_widget_show_all: procedure(W: Pointer); cdecl;
  gtk_events_pending: function: LongInt; cdecl;
  gtk_main_iteration_do: function(Blocking: LongInt): LongInt; cdecl;
  g_signal_connect_data: function(Instance: Pointer; Signal: PChar; Handler, Data, Destroy: Pointer;
    Flags: LongInt): PtrUInt; cdecl;
  app_indicator_new: function(Id, IconName: PChar; Category: LongInt): Pointer; cdecl;
  app_indicator_set_status: procedure(Ind: Pointer; Status: LongInt); cdecl;
  app_indicator_set_menu: procedure(Ind, Menu: Pointer); cdecl;
  app_indicator_set_title: procedure(Ind: Pointer; Title: PChar); cdecl;
  app_indicator_set_icon_full: procedure(Ind: Pointer; Icon, Desc: PChar); cdecl;

function LoadGtk: Boolean;
begin
  if GtkReady then
    Exit(True);
  Result := False;
  Indicator := LoadLibrary('libayatana-appindicator3.so.1');
  if Indicator = NilHandle then
    Indicator := LoadLibrary('libappindicator3.so.1');
  Gtk := LoadLibrary('libgtk-3.so.0');
  GObject := LoadLibrary('libgobject-2.0.so.0');
  if (Indicator = NilHandle) or (Gtk = NilHandle) or (GObject = NilHandle) then
  begin
    TrayError := 'the tray needs libayatana-appindicator3-1 (sudo apt install libayatana-appindicator3-1)';
    Exit;
  end;
  Pointer(gtk_init_check) := GetProcAddress(Gtk, 'gtk_init_check');
  Pointer(gtk_menu_new) := GetProcAddress(Gtk, 'gtk_menu_new');
  Pointer(gtk_menu_item_new_with_label) := GetProcAddress(Gtk, 'gtk_menu_item_new_with_label');
  Pointer(gtk_separator_menu_item_new) := GetProcAddress(Gtk, 'gtk_separator_menu_item_new');
  Pointer(gtk_menu_shell_append) := GetProcAddress(Gtk, 'gtk_menu_shell_append');
  Pointer(gtk_widget_show_all) := GetProcAddress(Gtk, 'gtk_widget_show_all');
  Pointer(gtk_events_pending) := GetProcAddress(Gtk, 'gtk_events_pending');
  Pointer(gtk_main_iteration_do) := GetProcAddress(Gtk, 'gtk_main_iteration_do');
  Pointer(g_signal_connect_data) := GetProcAddress(GObject, 'g_signal_connect_data');
  Pointer(app_indicator_new) := GetProcAddress(Indicator, 'app_indicator_new');
  Pointer(app_indicator_set_status) := GetProcAddress(Indicator, 'app_indicator_set_status');
  Pointer(app_indicator_set_menu) := GetProcAddress(Indicator, 'app_indicator_set_menu');
  Pointer(app_indicator_set_title) := GetProcAddress(Indicator, 'app_indicator_set_title');
  Pointer(app_indicator_set_icon_full) := GetProcAddress(Indicator, 'app_indicator_set_icon_full');
  if not Assigned(gtk_init_check) or not Assigned(app_indicator_new) or (gtk_init_check(nil, nil) = 0) then
  begin
    TrayError := 'the tray needs a desktop session (GTK could not start)';
    Exit;
  end;
  GtkReady := True;
  Result := True;
end;

procedure MenuActivated(Widget, Data: Pointer); cdecl;
var
  T, I: PtrInt;
begin
  { Data: the icon's index * 1000 + the item's }
  T := PtrInt(PtrUInt(Data)) div 1000;
  I := PtrInt(PtrUInt(Data)) mod 1000;
  if T < Icons.Count then
    TTrayIcon(Icons[T]).MenuItem(I);
end;

procedure BuildMenu(T: TTrayIcon);
var
  M, Item: Pointer;
  I: Integer;
begin
  M := gtk_menu_new();
  for I := 0 to T.FMenu.Count - 1 do
  begin
    if T.FMenu[I] = '-' then
      Item := gtk_separator_menu_item_new()
    else
    begin
      Item := gtk_menu_item_new_with_label(PChar(T.FMenu[I]));
      g_signal_connect_data(Item, 'activate', @MenuActivated, Pointer(PtrInt(Icons.IndexOf(T) * 1000 + I)), nil, 0);
    end;
    gtk_menu_shell_append(M, Item);
  end;
  gtk_widget_show_all(M);
  app_indicator_set_menu(T.FHandle, M);
end;

function IconPath(T: TTrayIcon): string;
var
  F: string;
begin
  if T.FIconFile <> '' then
    Exit(ExpandFileName(T.FIconFile));
  { the app's icon, next to it or in its assets }
  for F in [JoinPath([ExtractFilePath(ParamStr(0)), 'icon.png']), JoinPath([ExtractFilePath(ParamStr(0)), 'assets', 'icon.png']),
    JoinPath([GetCurrentDir, 'assets', 'icon.png'])] do
    if FileExists(F) then
      Exit(F);
  Result := 'application-x-executable';
end;

procedure TTrayIcon.Show;
begin
  if not LoadGtk then
    Exit;
  if FHandle = nil then
  begin
    FHandle := app_indicator_new(PChar(ChangeFileExt(ExtractFileName(ParamStr(0)), '') + '-' + IntToStr(Icons.IndexOf(Self))),
      PChar(IconPath(Self)), 0);
    BuildMenu(Self);
  end
  else if Assigned(app_indicator_set_icon_full) then
    { shown before: the icon may have changed }
    app_indicator_set_icon_full(FHandle, PChar(IconPath(Self)), PChar(FHint));
  if Assigned(app_indicator_set_title) then
    app_indicator_set_title(FHandle, PChar(FHint));
  app_indicator_set_status(FHandle, 1);
  FShown := True;
end;

procedure TTrayIcon.Hide;
begin
  if FHandle <> nil then
    app_indicator_set_status(FHandle, 0);
  FShown := False;
end;

procedure TTrayIcon.MenuItem(Index: Integer);
begin
  if (Index >= 0) and (Index < FMenu.Count) and Assigned(FOnMenuItem) then
    FOnMenuItem(Self, Index, FMenu[Index]);
end;

{ X11 hot keys: a grab on the root window of a connection of our own }
var
  XDisplay: Pointer = nil;
  XOpenDisplay: function(Name: PChar): Pointer; cdecl;
  XDefaultRootWindow: function(D: Pointer): PtrUInt; cdecl;
  XStringToKeysym: function(S: PChar): PtrUInt; cdecl;
  XKeysymToKeycode: function(D: Pointer; Sym: PtrUInt): Byte; cdecl;
  XGrabKey: function(D: Pointer; Code: LongInt; Mods: Cardinal; Win: PtrUInt; Owner, PMode, KMode: LongInt): LongInt; cdecl;
  XUngrabKey: function(D: Pointer; Code: LongInt; Mods: Cardinal; Win: PtrUInt): LongInt; cdecl;
  XPending: function(D: Pointer): LongInt; cdecl;
  XNextEvent: function(D: Pointer; Ev: Pointer): LongInt; cdecl;
  XFlush: function(D: Pointer): LongInt; cdecl;

function OpenX: Boolean;
begin
  if XDisplay <> nil then
    Exit(True);
  Result := False;
  if (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '') and (GetEnvironmentVariable('DISPLAY') = '') then
    Exit;
  X11 := LoadLibrary('libX11.so.6');
  if X11 = NilHandle then
    Exit;
  Pointer(XOpenDisplay) := GetProcAddress(X11, 'XOpenDisplay');
  Pointer(XDefaultRootWindow) := GetProcAddress(X11, 'XDefaultRootWindow');
  Pointer(XStringToKeysym) := GetProcAddress(X11, 'XStringToKeysym');
  Pointer(XKeysymToKeycode) := GetProcAddress(X11, 'XKeysymToKeycode');
  Pointer(XGrabKey) := GetProcAddress(X11, 'XGrabKey');
  Pointer(XUngrabKey) := GetProcAddress(X11, 'XUngrabKey');
  Pointer(XPending) := GetProcAddress(X11, 'XPending');
  Pointer(XNextEvent) := GetProcAddress(X11, 'XNextEvent');
  Pointer(XFlush) := GetProcAddress(X11, 'XFlush');
  XDisplay := XOpenDisplay(nil);
  Result := XDisplay <> nil;
end;

const
  { with and without Caps Lock and Num Lock }
  LockVariants: array[0..3] of Cardinal = (0, 2, 16, 18);

function RegisterHotKey(const Keys: string; OnPressed: TNotifyEvent): Integer;
var
  C, S, A, W: Boolean;
  K: string;
  Mods: Cardinal;
  Code: Integer;
  V: Cardinal;
begin
  ParseKeys(Keys, C, S, A, W, K);
  Result := 0;
  if not OpenX then
    Exit;
  Mods := 0;
  if S then Mods := Mods or 1;
  if C then Mods := Mods or 4;
  if A then Mods := Mods or 8;
  if W then Mods := Mods or 64;
  if Length(K) = 1 then
    K := LowerCase(K);
  if SameText(K, 'Space') then K := 'space';
  if SameText(K, 'Enter') then K := 'Return';
  if SameText(K, 'Esc') then K := 'Escape';
  Code := XKeysymToKeycode(XDisplay, XStringToKeysym(PChar(K)));
  if Code = 0 then
    raise Exception.CreateFmt('the key "%s" is not one a hot key can be', [K]);
  for V in LockVariants do
    XGrabKey(XDisplay, Code, Mods or V, XDefaultRootWindow(XDisplay), 1, 1, 1);
  XFlush(XDisplay);
  Result := NextHotkey;
  Inc(NextHotkey);
  SetLength(Hotkeys, Length(Hotkeys) + 1);
  Hotkeys[High(Hotkeys)].Id := Result;
  Hotkeys[High(Hotkeys)].Mods := Mods;
  Hotkeys[High(Hotkeys)].Code := Code;
  Hotkeys[High(Hotkeys)].OnPressed := OnPressed;
end;

procedure UnregisterHotKey(Id: Integer);
var
  I: Integer;
  V: Cardinal;
begin
  for I := High(Hotkeys) downto 0 do
    if Hotkeys[I].Id = Id then
    begin
      if XDisplay <> nil then
        for V in LockVariants do
          XUngrabKey(XDisplay, Hotkeys[I].Code, Hotkeys[I].Mods or V, XDefaultRootWindow(XDisplay));
      Delete(Hotkeys, I, 1);
    end;
end;

procedure PollHotkeys;
var
  Ev: array[0..191] of Byte;
  I: Integer;
  State, Code: Cardinal;
begin
  if XDisplay = nil then
    Exit;
  while XPending(XDisplay) > 0 do
  begin
    XNextEvent(XDisplay, @Ev);
    if PLongInt(@Ev[0])^ <> 2 then       { KeyPress }
      Continue;
    State := PCardinal(@Ev[80])^ and not Cardinal(18);
    Code := PCardinal(@Ev[84])^;
    for I := 0 to High(Hotkeys) do
      if (Hotkeys[I].Code = Integer(Code)) and (Hotkeys[I].Mods = State) and Assigned(Hotkeys[I].OnPressed) then
        Hotkeys[I].OnPressed(nil);
  end;
end;

procedure TTrayIcon.Tick(Sender: TObject);
begin
  if FVisible and not FShown and (FHandle = nil) and (TrayError = '') and not (csDesigning in ComponentState) then
    Show;
  if GtkReady then
    while gtk_events_pending() <> 0 do
      gtk_main_iteration_do(0);
end;
{$ENDIF}

{$IF not defined(WINDOWS) and not (defined(LINUX) and not defined(ANDROID))}
procedure TTrayIcon.Show;
begin
  TrayError := 'there is no tray on this system';
end;

procedure TTrayIcon.Hide;
begin
end;

procedure TTrayIcon.MenuItem(Index: Integer);
begin
  if (Index >= 0) and (Index < FMenu.Count) and Assigned(FOnMenuItem) then
    FOnMenuItem(Self, Index, FMenu[Index]);
end;

procedure TTrayIcon.Tick(Sender: TObject);
begin
  FTimer.Enabled := False;
end;

function RegisterHotKey(const Keys: string; OnPressed: TNotifyEvent): Integer;
begin
  Result := 0;
  if (Keys = '') and Assigned(OnPressed) then ;
end;

procedure UnregisterHotKey(Id: Integer);
begin
end;

procedure PollHotkeys;
begin
end;
{$ENDIF}

{ ---------------- common ---------------- }

type
  THotkeyPoller = class
    Timer: TTimer;
    procedure Tick(Sender: TObject);
  end;

var
  Poller: THotkeyPoller;

procedure THotkeyPoller.Tick(Sender: TObject);
begin
  PollHotkeys;
end;

constructor TTrayIcon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenu := TStringList.Create;
  FMenu.OnChange := @MenuChanged;
  FVisible := True;
  Icons.Add(Self);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 100;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;
end;

destructor TTrayIcon.Destroy;
begin
  Hide;
  Icons[Icons.IndexOf(Self)] := nil;
  FMenu.Free;
  inherited Destroy;
end;

procedure TTrayIcon.Loaded;
begin
  inherited Loaded;
  FTimer.Enabled := True;
end;

procedure TTrayIcon.Clicked;
begin
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

procedure TTrayIcon.SetVisible(AValue: Boolean);
begin
  FVisible := AValue;
  if not AValue then
    Hide
  else
    FTimer.Enabled := True;
end;

procedure TTrayIcon.SetHint(const AValue: string);
begin
  FHint := AValue;
  if FShown then
    Show;
end;

procedure TTrayIcon.SetIconFile(const AValue: string);
begin
  FIconFile := AValue;
  if FShown then
    Show;
end;

procedure TTrayIcon.SetMenu(AValue: TStringList);
begin
  FMenu.Assign(AValue);
end;

procedure TTrayIcon.MenuChanged(Sender: TObject);
begin
  {$IF defined(LINUX) and not defined(ANDROID)}
  if FHandle <> nil then
    BuildMenu(Self);
  {$ENDIF}
end;

function TTrayIcon.Error: string;
begin
  Result := TrayError;
end;

initialization
  Icons := TFPList.Create;
  Poller := THotkeyPoller.Create;
  Poller.Timer := TTimer.Create(nil);
  Poller.Timer.Interval := 50;
  Poller.Timer.OnTimer := @Poller.Tick;
  Poller.Timer.Enabled := True;
  RegisterNonVisual(TTrayIcon);

finalization
  Poller.Timer.Free;
  Poller.Free;
  Icons.Free;
end.
