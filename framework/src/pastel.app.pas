{ Pastel - the application: window, event loop, hot reload.

    Application.Initialize;
    Application.CreateForm(TMainForm, MainForm);
    Application.Run;

  Environment variables useful for development and tests:
    PASTEL_TEST_SCRIPT=file  run a script of UI actions, then quit
    PASTEL_HEADLESS=1        no window: draw into memory only (for tests/CI)
  Part of the Pastel project, MIT License. }
unit Pastel.App;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI, Pastel.PForm, Pastel.Forms, Pastel.Env
  {$IFDEF ANDROID}, Pastel.Android{$ENDIF};

type
  { An exception an event handler did not catch (OnException). }
  TExceptionEvent = procedure(Sender: TObject; E: Exception) of object;

  TApplication = class
  private
    FMainForm: TForm;
    FOnException: TExceptionEvent;
    FInException: Boolean;
    FMouseCaptured: Boolean;
    FTerminated: Boolean;
    FHeadless: Boolean;
    FCheckRepaint: Boolean;   { PASTEL_CHECK_REPAINT=1: compare partial repaints with full ones }
    FRepaintMismatches, FRepaintsChecked: Integer;
    FWindow, FRenderer, FTexture: Pointer;
    FCanvas: TCanvas32;
    FWidth, FHeight: Integer;     { in layout units }
    FScale: Single;               { pixels per layout unit }
    FMouseScale: Single;          { window coordinates per layout unit }
    FTextureW, FTextureH: Integer;
    FPaintedW, FPaintedH: Integer;     { canvas size of the last full paint }
    FPresentArea: TRectI;              { what Present uploads; empty: all }
    FShowLater: Boolean;               { the main window is shown after its first picture }
    FCursors: array[TCursorKind] of Pointer;
    FCursorShown: TCursorKind;
    { window settings as last applied to the real window }
    FAppliedState: TWindowState;
    FAppliedResizable, FAppliedOnTop: Boolean;
    FAppliedMinW, FAppliedMinH: Integer;
    FLaidOutW, FLaidOutH: Integer;
    FWindowTitle: string;
    { hot reload }
    FSourcePath: string;
    FSeenText, FSeenViews: string;
    {$IFDEF ANDROID}
    FReloadPause: QWord;          { no form server answered: ask less often }
    {$ENDIF}
    FLastGood: string;
    FReloadError: string;
    FLastCheck, FLastBlink: QWord;
    { test scripts }
    FScript: TStringList;
    FScriptFile: string;
    FDropped: TStringArray;
    FDropBatch: Boolean;
    FFormWindows: TFPList;          { TFormWindow }
    FScriptPos, FScriptFailures: Integer;
    function RunScriptStep: Boolean;
    function FindAnyControl(const AName: string): TControl;
    procedure Step;
    procedure CaptureMouse(Dragging: Boolean);
    { Step; an exception of an event handler is shown (HandleException) and the app goes on }
    procedure SafeStep;
    procedure WakeUp(Sender: TObject);
    procedure Fatal(const Msg: string);
    procedure LoadForm(Form: TForm);
    procedure CreateWindow;
    procedure SetWindowIcon;
    procedure ProcessEvents(Timeout: Integer);
    procedure CheckHotReload;
    procedure Reload(const NewSource: string);
    procedure Paint;
    procedure PaintOverlay;
    procedure CheckPartialRepaint;
    procedure PaintIfNeeded;
    procedure Present;
    procedure UpdateCursor;
    procedure SyncWindow;
    procedure TryClose;
    function CurrentScreenClass: TScreenClass;
    procedure DoLayout;
    procedure RunScript(const FileName: string);
    procedure DeliverDrop;
    { forms in windows of their own (TForm.Show) }
    procedure OpenFormWindow(Form: TForm);
    function CloseFormWindow(Form: TForm): Boolean;
    procedure PaintFormWindows;
    procedure CloseAllFormWindows;
  {$IFDEF ANDROID}
  private
    FLanguageFromSystem, FKeyboardShown: Boolean;
    FKeyboardEdit: TControl;
    { Android: the edit's state the phone's keyboard has a copy of (bytes), and its number }
    FImeText: string;
    FImeSelStart, FImeSelEnd, FImeGen: Integer;
    FIsTV: Boolean;
    { pixels the system's bars cover at the top and the left (the form is drawn after them) }
    FInsetX, FInsetY: Integer;
    FTouchDown, FTouchScrolling, FLongPressDone: Boolean;
    { two fingers on the screen; a pinch whose last finger has not left yet }
    FPinching, FPinchDone: Boolean;
    FPinchDist, FPinchAngle: Single;
    FTouchStartX, FTouchStartY, FTouchX, FTouchY, FScrollFromY, FLastTapX, FLastTapY: Integer;
    FTouchTime, FLastTapTime: QWord;
    { flinging: the list goes on moving after the finger left, slower and slower }
    FFlingActive: Boolean;
    FFlingV, FFlingAccum: Double;          { layout units per ms; the part of a wheel step not done yet }
    FFlingLast, FSampleTime: QWord;
    FSampleY, FFlingX, FFlingY: Integer;
    procedure AndroidFling;
    procedure AndroidSizeFromWindow;
    procedure AndroidCreateWindow;
    procedure AndroidPresent;
    procedure AndroidCommand(Cmd: TAndroidCommand);
    procedure AndroidTouch(Action: Integer; RawX, RawY: Single);
    procedure AndroidPinch(Action, Count: Integer; X0, Y0, X1, Y1: Single);
    procedure AndroidLongPress;
    function AndroidKey(Action, Code, Meta: Integer): Boolean;
    procedure AndroidInputEvents;
    procedure AndroidProcessEvents(Timeout: Integer);
    procedure AndroidKeyboard;
    procedure AndroidImeEdit;
    procedure AndroidImeRemember(E: TCustomEdit);
  private
    { TalkBack: the controls on the screen, and its actions }
    FAccessTree: string;
    FAccessCheck: QWord;
    FAccessOn: Boolean;
    procedure AndroidAccessibility(NowMs: QWord);
  public
    { Internal: the event loop on Android's app thread. }
    procedure AndroidRun;
  {$ENDIF}
  public
    { One pass of the event loop: events, timers, threads, layout, paint.
      Long work in an event handler can call it to keep the window alive. }
    procedure ProcessMessages;
    constructor Create;
    destructor Destroy; override;
    procedure Initialize;
    procedure CreateForm(AFormClass: TFormClass; out AReference);
    procedure Run;
    procedure Terminate;
    { What happens to an exception an event handler did not catch: OnException,
      else a message with it (and the console and a crash report get it too);
      the app goes on, as in Delphi. EAbort (Abort) is quiet. }
    procedure HandleException(E: Exception);
    procedure ShowException(E: Exception);
    property OnException: TExceptionEvent read FOnException write FOnException;
    { Layout and paint now (used by tests and scripts). }
    procedure Refresh;
    property MainForm: TForm read FMainForm;
    property Canvas: TCanvas32 read FCanvas;
    property Terminated: Boolean read FTerminated;
  end;

var
  Application: TApplication;

implementation

uses
  Math, TypInfo, {$IFNDEF ANDROID}Process, Pastel.SDL2,{$ENDIF} {$IFDEF WINDOWS}Registry,{$ENDIF} Pastel.Assets,
  { linked into every app, so .pform files can use their controls }
  Pastel.Controls, Pastel.Menus, Pastel.Dialogs, Pastel.Grids, Pastel.Binding, Pastel.Inputs, Pastel.NativeViews, Pastel.Maps, Pastel.Push, Pastel.Accessibility, Pastel.Sensors, Pastel.Barcode, Pastel.Tray, Pastel.Toml, Pastel.Lang;

{ a form in a window of its own (TForm.Show, computers) }
type
  TFormWindow = class
    Form: TForm;
    Window, Renderer, Texture: Pointer;
    Canvas: TCanvas32;
    Id: LongWord;
    W, H, TexW, TexH: Integer;
    Shown: Boolean;
  end;

const
  DefaultWidth = 480;
  DefaultHeight = 360;

{$IFNDEF ANDROID}
function SdlClipboardGet: string;
var
  P: PChar;
begin
  P := SDL_GetClipboardText();
  if P = nil then
    Exit('');
  Result := StrPas(P);
  SDL_free(P);
end;

procedure SdlClipboardSet(const S: string);
begin
  SDL_SetClipboardText(PChar(S));
end;
{$ENDIF}

constructor TApplication.Create;
begin
  inherited Create;
  FCanvas := TCanvas32.Create;
  FCursorShown := ckArrow;
end;

destructor TApplication.Destroy;
begin
  CloseAllFormWindows;
  FMainForm.Free;
  {$IFNDEF ANDROID}
  if FTexture <> nil then SDL_DestroyTexture(FTexture);
  if FRenderer <> nil then SDL_DestroyRenderer(FRenderer);
  if FWindow <> nil then
  begin
    SDL_DestroyWindow(FWindow);
    SDL_Quit;
  end;
  {$ENDIF}
  FCanvas.Free;
  DoneFonts;
  inherited Destroy;
end;

{$IFDEF WINDOWS}
function MessageBoxA(Wnd: Pointer; Text, Caption: PChar; Flags: LongWord): LongInt;
  stdcall; external 'user32.dll';
{$ENDIF}

procedure TApplication.Fatal(const Msg: string);
begin
  {$IFDEF ANDROID}
  AndroidLog('error: ' + Msg);
  {$ENDIF}
  { to the console that started the app (Pastel.Startup: nowhere when there is none) }
  {$I-}
  WriteLn(StdErr, 'error: ', Msg);
  {$I+}
  InOutRes := 0;
  {$IFDEF WINDOWS}
  { an app opened from Explorer has no console: the message would be invisible }
  if not IsConsole and not FHeadless then
    MessageBoxA(nil, PChar(Msg), 'Pastel', $10);
  {$ENDIF}
  Halt(1);
end;

{ assets/font.ttf (and font-bold.ttf) instead of the system font }
procedure UseAssetFonts;

  function Extract(const Name: string): string;
  var
    S: TStream;
    F: TFileStream;
  begin
    S := OpenAsset(Name);
    try
      if S is TFileStream then
        Exit(TFileStream(S).FileName);
      Result := IncludeTrailingPathDelimiter(GetTempDir) + 'pastel-' + IntToStr(GetProcessID) + '-' +
        StringReplace(Name, '/', '-', [rfReplaceAll]);
      F := TFileStream.Create(Result, fmCreate);
      try
        F.CopyFrom(S, 0);
      finally
        F.Free;
      end;
    finally
      S.Free;
    end;
  end;

var
  R, B: string;
begin
  if not AssetExists('font.ttf') then
    Exit;
  R := Extract('font.ttf');
  B := '';
  if AssetExists('font-bold.ttf') then
    B := Extract('font-bold.ttf');
  SetFontFiles(R, B);
end;

var
  ThemeFile: TTomlDocument = nil;

{ assets/theme.toml: values for both themes, [dark] for the dark one only }
procedure ApplyThemeFile;
var
  I: Integer;
  K: string;

  procedure Apply(const Name, Path: string);
  begin
    if not SetThemeValue(Name, ThemeFile.GetString(Path)) then
      WriteLn(StdErr, Format('assets/theme.toml: "%s = %s" is not a theme value', [Path, ThemeFile.GetString(Path)]));
  end;

begin
  if ThemeFile = nil then
    Exit;
  for I := 0 to ThemeFile.Values.Count - 1 do
  begin
    K := ThemeFile.Values[I];
    if K = 'style' then
      Continue;
    if Pos('.', K) = 0 then
      Apply(K, K)
    else if Theme.Dark and (Copy(K, 1, 5) = 'dark.') then
      Apply(Copy(K, 6, MaxInt), K);
  end;
end;

{ assets/styles/Name.pstyle, for UseStyle('Name') }
function StyleFromAssets(const Name: string): string;
var
  F: string;
begin
  F := 'styles/' + Name + '.pstyle';
  if not AssetExists(F) then
    Exit('');
  Result := AssetText(F);
  if LoadStyle(Name, Result) <> '' then
  begin
    WriteLn(StdErr, Format('assets/%s: %s', [F, LoadStyle(Name, Result)]));
    Result := '';
  end;
end;

{ the style: PASTEL_STYLE, else style = in assets/theme.toml, else Pastel's }
procedure UseStyleSetting;
var
  S, From: string;
begin
  S := GetEnv('PASTEL_STYLE');
  From := 'PASTEL_STYLE';
  if (S = '') and (ThemeFile <> nil) then
  begin
    S := ThemeFile.GetString('style');
    From := 'assets/theme.toml';
  end;
  if S = '' then
    Exit;
  if not UseStyle(S) then
    WriteLn(StdErr, Format('%s: there is no style "%s" (pastel, fluent, material, auto, or assets/styles/%s.pstyle)',
      [From, S, S]));
end;

procedure UseThemeFile;
begin
  StyleFileHook := @StyleFromAssets;
  if AssetExists('theme.toml') then
  begin
    ThemeFile := TTomlDocument.Create;
    try
      ThemeFile.LoadFromString(AssetText('theme.toml'));
    except
      on E: Exception do
      begin
        WriteLn(StdErr, 'assets/theme.toml: ', E.Message);
        FreeAndNil(ThemeFile);
      end;
    end;
  end;
  if ThemeFile <> nil then
    ThemeCustomizer := @ApplyThemeFile;
  UseStyleSetting;
  UseDarkTheme(False);
end;

{ Is the computer set to dark colors? }
function SystemPrefersDark: Boolean;
{$IFNDEF ANDROID}
var
  Out_: string;
{$ENDIF}
begin
  Result := False;
  if GetEnv('PASTEL_THEME') <> '' then
    Exit(SameText(GetEnv('PASTEL_THEME'), 'dark'));
  {$IF defined(ANDROID)}
  Result := AndroidNightMode;
  {$ELSEIF defined(WINDOWS)}
  with TRegistry.Create(KEY_READ) do
  try
    RootKey := HKEY_CURRENT_USER;
    if OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and
       ValueExists('AppsUseLightTheme') then
      Result := ReadInteger('AppsUseLightTheme') = 0;
  finally
    Free;
  end;
  {$ELSEIF defined(DARWIN)}
  if RunCommand('defaults', ['read', '-g', 'AppleInterfaceStyle'], Out_, [poNoConsole]) then
    Result := Pos('dark', LowerCase(Out_)) > 0;
  {$ELSE}
  if RunCommand('gsettings', ['get', 'org.gnome.desktop.interface', 'color-scheme'], Out_, [poNoConsole]) and
     (Pos('dark', LowerCase(Out_)) > 0) then
    Exit(True);
  if RunCommand('gsettings', ['get', 'org.gnome.desktop.interface', 'gtk-theme'], Out_, [poNoConsole]) then
    Result := Pos('dark', LowerCase(Out_)) > 0;
  {$ENDIF}
end;

procedure TApplication.Initialize;
var
  Err: string;
begin
  { Graphics drivers may raise floating point exceptions Pascal would trap. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  Err := InitFonts;
  if Err <> '' then
    Fatal(Err);
  UseAssetFonts;
  UseThemeFile;
  if not LanguageChosen then
  begin
    UseLanguage(SystemLanguage);
    {$IFDEF ANDROID}
    FLanguageFromSystem := True;     { the phone's language is known once the activity is there }
    {$ENDIF}
  end;
  FHeadless := GetEnv('PASTEL_HEADLESS') = '1';
  FCheckRepaint := GetEnv('PASTEL_CHECK_REPAINT') = '1';
  if GetEnv('PASTEL_FULL_REPAINT') = '1' then
    PartialRepaint := False;
  FScale := 1;
  FMouseScale := 1;
end;

procedure TApplication.LoadForm(Form: TForm);
var
  Src: TFormSource;
  Root: TPFormNode;
  Text: string;
  Lines: TStringList;
begin
  Src := FindFormSource(Form);
  if Src = nil then
    Fatal(Form.ClassName + ' has no .pform file (is it compiled with "pastel build"?)');
  Text := Src.Source;
  { in debug builds, read the file itself so edits show up without a rebuild }
  if (Src.FilePath <> '') and FileExists(Src.FilePath) then
  begin
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(Src.FilePath);
      Text := Lines.Text;
    finally
      Lines.Free;
    end;
  end;
  try
    Root := ParsePForm(Text);
    try
      BuildForm(Form, Root);
    finally
      Root.Free;
    end;
  except
    on E: EPFormError do
    begin
      if Src.FilePath <> '' then
        Fatal(ExtractFileName(Src.FilePath) + ', ' + E.Message)
      else
        Fatal(Form.ClassName + ': ' + E.Message);
    end;
  end;
  if Form = FMainForm then
  begin
    case Form.Appearance of
      tmDark: UseDarkTheme(True);
      tmSystem: UseDarkTheme(SystemPrefersDark);
    end;
    FSourcePath := Src.FilePath;
    {$IFDEF ANDROID}
    { the .pform files are on the computer: a debug build asks "pastel run --target android"
      for them through the USB cable (adb reverse), so a saved form shows on the phone at once }
    FSourcePath := '';
    {$IFNDEF PASTEL_RELEASE}
    if Src.FilePath <> '' then
      FSourcePath := AndroidFormServer + ExtractFileName(StringReplace(Src.FilePath, '\', '/', [rfReplaceAll]));
    {$ENDIF}
    {$ENDIF}
    FSeenText := Text;
    FSeenViews := FormViewFilesText(Form);
    FLastGood := Text;
  end;
  {$IFDEF ANDROID}
  { Android stopped the app in the background and started it again: as the user left it }
  if (Form = FMainForm) and (AndroidRestoredState <> '') then
  begin
    RestoreFormStateText(Form, AndroidRestoredState);
    AndroidRestoredState := '';
  end;
  {$ENDIF}
  if Assigned(Form.OnCreate) then
    Form.OnCreate(Form);
end;

procedure TApplication.CreateForm(AFormClass: TFormClass; out AReference);
var
  Form: TForm;
begin
  Form := AFormClass.Create(nil);
  TForm(AReference) := Form;
  if FMainForm = nil then
  begin
    FMainForm := Form;
    Pastel.UI.MainForm := Form;
  end;
  LoadForm(Form);
end;

procedure TApplication.Terminate;
begin
  FTerminated := True;
end;

procedure TApplication.SetWindowIcon;
{$IFDEF ANDROID}
begin
  { the app's icon is in the APK }
end;
{$ELSE}
var
  B: TBitmap32;
  S: TStream;
  Surface: Pointer;
begin
  if not AssetExists('icon.png') then
    Exit;
  B := TBitmap32.Create;
  try
    S := OpenAsset('icon.png');
    try
      B.LoadFromStream(S);
    finally
      S.Free;
    end;
    Surface := SDL_CreateRGBSurfaceFrom(@B.Pixels[0], B.Width, B.Height, 32, B.Width * 4,
      $00FF0000, $0000FF00, $000000FF, $FF000000);
    if Surface <> nil then
    begin
      SDL_SetWindowIcon(FWindow, Surface);
      SDL_FreeSurface(Surface);
    end;
  except
    on E: Exception do
      WriteLn(StdErr, 'assets/icon.png: ', E.Message);
  end;
  B.Free;
end;
{$ENDIF}

procedure TApplication.CreateWindow;
{$IFDEF ANDROID}
begin
  FWidth := DefaultWidth;
  FHeight := DefaultHeight;
  if not FHeadless then
    AndroidCreateWindow;
end;
{$ELSE}
var
  Err, WmClass: string;
  W, H, WW, WH, PW, PH: Integer;
  Flags: LongWord;
  Dpi, ForcedScale: Single;
begin
  W := FMainForm.Width;
  H := FMainForm.Height;
  if W <= 0 then W := DefaultWidth;
  if H <= 0 then H := DefaultHeight;
  FWidth := W;
  FHeight := H;
  ForcedScale := StrToFloatDef(GetEnv('PASTEL_SCALE'), 0, InvariantFormat);
  if FHeadless then
  begin
    if ForcedScale > 0 then
      FScale := ForcedScale;
    Exit;
  end;
  Err := LoadSDL2;
  if Err <> '' then
    Fatal(Err);
  SDL_SetHint('SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR', '0');
  { SDL takes the whole screen's mouse when a button goes down (X11: a pointer
    grab) until it sees the button up: an event handler that works long (a slow
    query) left every other window without clicks. Pastel takes the mouse only
    while something is dragged (CaptureMouse). }
  SDL_SetHint('SDL_MOUSE_AUTO_CAPTURE', '0');
  { Linux desktops find the app's menu entry (its icon in the dock) by this name:
    the .desktop file of "pastel package deb" and AppImages says StartupWMClass=<program> }
  WmClass := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  SDL_SetHint('SDL_VIDEO_X11_WMCLASS', PChar(WmClass));
  SDL_SetHint('SDL_VIDEO_WAYLAND_WMCLASS', PChar(WmClass));
  SDL_SetHint('SDL_WINDOWS_DPI_AWARENESS', 'permonitorv2');
  if SDL_Init(SDL_INIT_VIDEO) <> 0 then
    Fatal('could not open a window: ' + StrPas(SDL_GetError()));
  FWindowTitle := FMainForm.Title;
  { a normal window is shown when its first picture is ready (Run): not an empty
    frame first, then the size for the screen's DPI, then the picture }
  FShowLater := FMainForm.WindowState = wsNormal;
  if FShowLater then
    Flags := SDL_WINDOW_HIDDEN or SDL_WINDOW_ALLOW_HIGHDPI
  else
    Flags := SDL_WINDOW_SHOWN or SDL_WINDOW_ALLOW_HIGHDPI;
  if FMainForm.Resizable then
    Flags := Flags or SDL_WINDOW_RESIZABLE;
  if FMainForm.AlwaysOnTop then
    Flags := Flags or SDL_WINDOW_ALWAYS_ON_TOP;
  case FMainForm.WindowState of
    wsMaximized: Flags := Flags or SDL_WINDOW_MAXIMIZED;
    wsMinimized: Flags := Flags or SDL_WINDOW_MINIMIZED;
    wsFullScreen: Flags := Flags or SDL_WINDOW_FULLSCREEN_DESKTOP;
  end;
  FWindow := SDL_CreateWindow(PChar(FWindowTitle), SDL_WINDOWPOS_CENTERED,
    SDL_WINDOWPOS_CENTERED, W, H, Flags);
  if FWindow = nil then
    Fatal('could not open a window: ' + StrPas(SDL_GetError()));
  SDL_SetWindowMinimumSize(FWindow, FMainForm.MinWidth, FMainForm.MinHeight);
  FAppliedState := FMainForm.WindowState;
  FAppliedResizable := FMainForm.Resizable;
  FAppliedOnTop := FMainForm.AlwaysOnTop;
  FAppliedMinW := FMainForm.MinWidth;
  FAppliedMinH := FMainForm.MinHeight;
  NeedsWindowSync := False;
  FRenderer := SDL_CreateRenderer(FWindow, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
  if FRenderer = nil then
    FRenderer := SDL_CreateRenderer(FWindow, -1, SDL_RENDERER_SOFTWARE);
  if FRenderer = nil then
    Fatal('could not create a renderer: ' + StrPas(SDL_GetError()));
  { sharp on high-density screens: either the system gives more pixels than
    window points (macOS, Wayland), or Pastel sizes the window by the DPI }
  SDL_GetWindowSize(FWindow, @WW, @WH);
  SDL_GetRendererOutputSize(FRenderer, @PW, @PH);
  if (WW > 0) and (PW > WW) then
  begin
    FScale := PW / WW;
    FMouseScale := 1;
  end
  else
  begin
    Dpi := 96;
    if Assigned(SDL_GetDisplayDPI) then
      SDL_GetDisplayDPI(0, @Dpi, nil, nil);
    if ForcedScale > 0 then
      FScale := ForcedScale
    else
      FScale := Round(Dpi / 96 * 4) / 4;
    if FScale < 1.2 then
      FScale := 1;
    FMouseScale := FScale;
    if FScale > 1 then
    begin
      SDL_SetWindowSize(FWindow, Round(W * FScale), Round(H * FScale));
      SDL_SetWindowMinimumSize(FWindow, Round(FMainForm.MinWidth * FScale), Round(FMainForm.MinHeight * FScale));
      { bigger: in the middle of the screen again }
      SDL_SetWindowPosition(FWindow, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
    end;
  end;
  SetWindowIcon;
  FCursors[ckArrow] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
  FCursors[ckIBeam] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM);
  FCursors[ckHand] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND);
  FCursors[ckSizeWE] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZEWE);
  FCursors[ckSizeNS] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZENS);
  ClipboardGetText := @SdlClipboardGet;
  ClipboardSetText := @SdlClipboardSet;
  SDL_StartTextInput;
end;
{$ENDIF}

{ the kind of screen: a phone, a tablet or a TV on Android; on a computer, a narrow
  window counts as a phone (to try phone layouts); PASTEL_SCREEN=phone|tablet|desktop|tv sets it }
function TApplication.CurrentScreenClass: TScreenClass;
var
  Forced: string;
begin
  Forced := LowerCase(GetEnv('PASTEL_SCREEN'));
  if Forced = 'phone' then Exit(scPhone);
  if Forced = 'tablet' then Exit(scTablet);
  if Forced = 'desktop' then Exit(scDesktop);
  if Forced = 'tv' then Exit(scTV);
  {$IFDEF ANDROID}
  if FIsTV then
    Result := scTV
  else if Min(FWidth, FHeight) >= 600 then
    Result := scTablet
  else
    Result := scPhone;
  {$ELSE}
  if (FWidth > 0) and (FWidth < 600) then
    Result := scPhone
  else
    Result := scDesktop;
  {$ENDIF}
end;

procedure TApplication.DoLayout;
begin
  { the view for this kind of screen first (Home.tablet.pform), then the layout }
  FMainForm.SetScreenClass(CurrentScreenClass);
  { on a TV (also PASTEL_SCREEN=tv on a computer) the arrows move the focus, as with a remote }
  if FMainForm.ScreenClass = scTV then
    ArrowKeysMoveFocus := True;
  FMainForm.Layout(FWidth, FHeight);
  if ((FLaidOutW <> 0) or (FLaidOutH <> 0)) and
     ((FLaidOutW <> FWidth) or (FLaidOutH <> FHeight)) and Assigned(FMainForm.OnResize) then
    FMainForm.OnResize(FMainForm);
  FLaidOutW := FWidth;
  FLaidOutH := FHeight;
end;

procedure TApplication.Refresh;
begin
  if NeedsLayout or (FMainForm.Bounds.W <> FWidth) or (FMainForm.Bounds.H <> FHeight) then
    DoLayout;
  Paint;
end;

procedure TApplication.TryClose;
begin
  CloseRequested := False;
  if not FMainForm.CloseQuery then
    Exit;
  if Assigned(FMainForm.OnClose) then
    FMainForm.OnClose(FMainForm);
  FTerminated := True;
end;

{ Applies window settings changed from code (Maximize, Resizable := ...). }
procedure TApplication.SyncWindow;
{$IFDEF ANDROID}
begin
  NeedsWindowSync := False;     { a phone's app fills the screen }
  { full screen: the status and navigation bars hidden (a swipe from the edge shows them for a moment) }
  if (FMainForm <> nil) and ((FMainForm.WindowState = wsFullScreen) <> (FAppliedState = wsFullScreen)) then
  begin
    AndroidCall('setFullScreen', '(Z)V', [FMainForm.WindowState = wsFullScreen]);
    FAppliedState := FMainForm.WindowState;
  end;
end;
{$ELSE}
var
  Want: TWindowState;
begin
  NeedsWindowSync := False;
  if FHeadless or (FWindow = nil) then
    Exit;
  if (FMainForm.Resizable <> FAppliedResizable) and Assigned(SDL_SetWindowResizable) then
  begin
    SDL_SetWindowResizable(FWindow, Ord(FMainForm.Resizable));
    FAppliedResizable := FMainForm.Resizable;
  end;
  if (FMainForm.AlwaysOnTop <> FAppliedOnTop) and Assigned(SDL_SetWindowAlwaysOnTop) then
  begin
    SDL_SetWindowAlwaysOnTop(FWindow, Ord(FMainForm.AlwaysOnTop));
    FAppliedOnTop := FMainForm.AlwaysOnTop;
  end;
  if (FMainForm.MinWidth <> FAppliedMinW) or (FMainForm.MinHeight <> FAppliedMinH) then
  begin
    SDL_SetWindowMinimumSize(FWindow, Round(FMainForm.MinWidth * FMouseScale), Round(FMainForm.MinHeight * FMouseScale));
    FAppliedMinW := FMainForm.MinWidth;
    FAppliedMinH := FMainForm.MinHeight;
  end;
  Want := FMainForm.WindowState;
  if Want <> FAppliedState then
  begin
    if FAppliedState = wsFullScreen then
      SDL_SetWindowFullscreen(FWindow, 0);
    case Want of
      wsNormal: SDL_RestoreWindow(FWindow);
      wsMaximized: SDL_MaximizeWindow(FWindow);
      wsMinimized: SDL_MinimizeWindow(FWindow);
      wsFullScreen: SDL_SetWindowFullscreen(FWindow, SDL_WINDOW_FULLSCREEN_DESKTOP);
    end;
    FAppliedState := Want;
  end;
end;
{$ENDIF}

procedure TApplication.Paint;
begin
  FCanvas.Scale := FScale;
  FCanvas.SetSize(FWidth, FHeight);
  if not NeedsRepaint and NeedsPartialRepaint and (FReloadError = '') and
    (FCanvas.PixelWidth = FPaintedW) and (FCanvas.PixelHeight = FPaintedH) then
  begin
    { only what changed: a blinking caret, a button under the mouse... }
    FPresentArea := DirtyArea;
    if FCheckRepaint then
      FrozenTime := GetTickCount64;
    FMainForm.RenderArea(FCanvas, FPresentArea);
    if FCheckRepaint then
    begin
      CheckPartialRepaint;
      FrozenTime := 0;
    end;
  end
  else
  begin
    FPresentArea := RectI(0, 0, 0, 0);
    FMainForm.Render(FCanvas);
    PaintOverlay;
    FPaintedW := FCanvas.PixelWidth;
    FPaintedH := FCanvas.PixelHeight;
  end;
end;

{ A partial repaint must give the same picture as a full one: paints
  everything again and reports the first pixel that differs. }
procedure TApplication.CheckPartialRepaint;
var
  Before: array of Cardinal;
  P: PCardinal;
  I, N: Integer;
  Again, Full: Boolean;
  Area: TRectI;
begin
  Inc(FRepaintsChecked);
  N := FCanvas.PixelWidth * FCanvas.PixelHeight;
  SetLength(Before, N);
  Move(FCanvas.Data^, Before[0], N * 4);
  Again := NeedsPartialRepaint;
  Full := NeedsRepaint;
  Area := DirtyArea;
  FMainForm.Render(FCanvas);
  NeedsPartialRepaint := Again;
  NeedsRepaint := Full;
  DirtyArea := Area;
  P := FCanvas.Data;
  for I := 0 to N - 1 do
    if P[I] <> Before[I] then
    begin
      Inc(FRepaintMismatches);
      WriteLn(Format('repaint mismatch at %d,%d (dirty area %d,%d %dx%d, script line %d)',
        [I mod FCanvas.PixelWidth, I div FCanvas.PixelWidth, FPresentArea.X, FPresentArea.Y,
        FPresentArea.W, FPresentArea.H, FScriptPos]));
      Exit;
    end;
end;

procedure TApplication.PaintOverlay;
var
  F, B: TPastelFont;
  Lines: TStringList;
  I, H, Y: Integer;
begin
  if FReloadError = '' then
    Exit;
  F := GetFont(13);
  B := GetFont(13, True);
  Lines := TStringList.Create;
  try
    Lines.Text := FReloadError;
    H := 20 + B.LineHeight + Lines.Count * F.LineHeight + 12;
    Y := FHeight - H;
    FCanvas.FillRect(0, Y, FWidth, H, RGBA($B9, $1C, $1C, $F2));
    FCanvas.DrawText(B, 14, Y + 10, 'Hot reload failed - the last working version is shown', RGB(255, 255, 255));
    for I := 0 to Lines.Count - 1 do
      FCanvas.DrawText(F, 14, Y + 14 + B.LineHeight + I * F.LineHeight, Lines[I], RGB($FE, $E2, $E2));
  finally
    Lines.Free;
  end;
end;

procedure TApplication.Present;
{$IFDEF ANDROID}
begin
  if not FHeadless then
    AndroidPresent;
end;
{$ELSE}
var
  R: TRectI;    { the same layout as SDL_Rect }
begin
  if FHeadless then
    Exit;
  if (FTexture = nil) or (FTextureW <> FCanvas.PixelWidth) or (FTextureH <> FCanvas.PixelHeight) then
  begin
    FPresentArea := RectI(0, 0, 0, 0);     { a new texture gets everything }
    if FTexture <> nil then
      SDL_DestroyTexture(FTexture);
    FTexture := SDL_CreateTexture(FRenderer, SDL_PIXELFORMAT_ARGB8888,
      SDL_TEXTUREACCESS_STREAMING, FCanvas.PixelWidth, FCanvas.PixelHeight);
    FTextureW := FCanvas.PixelWidth;
    FTextureH := FCanvas.PixelHeight;
  end;
  R := FCanvas.PixelRect(FPresentArea).Intersect(RectI(0, 0, FTextureW, FTextureH));
  if (FPresentArea.W > 0) and (R.W > 0) and (R.H > 0) then
    SDL_UpdateTexture(FTexture, @R, PByte(FCanvas.Data) + (R.Y * FTextureW + R.X) * 4, FTextureW * 4)
  else
    SDL_UpdateTexture(FTexture, nil, FCanvas.Data, FCanvas.PixelWidth * 4);
  SDL_RenderClear(FRenderer);
  SDL_RenderCopy(FRenderer, FTexture, nil, nil);
  SDL_RenderPresent(FRenderer);
end;
{$ENDIF}

procedure TApplication.UpdateCursor;
{$IFDEF ANDROID}
begin
  if not FHeadless then
    AndroidKeyboard;      { no mouse pointer; the on-screen keyboard for edits }
end;
{$ELSE}
var
  K: TCursorKind;
begin
  if FHeadless then
    Exit;
  K := FMainForm.CurrentCursor;
  if K <> FCursorShown then
  begin
    FCursorShown := K;
    if FCursors[K] <> nil then
      SDL_SetCursor(FCursors[K]);
  end;
  if FMainForm.Title <> FWindowTitle then
  begin
    FWindowTitle := FMainForm.Title;
    SDL_SetWindowTitle(FWindow, PChar(FWindowTitle));
  end;
end;
{$ENDIF}

procedure TApplication.ProcessEvents(Timeout: Integer);
{$IFDEF ANDROID}
begin
  AndroidProcessEvents(Timeout);
end;
{$ELSE}
var
  Ev: TSDL_Event;
  Got: Boolean;
  Mods: Word;
  G: TGestureInfo;
  FW: TFormWindow;
  F: TForm;
  I: Integer;
begin
  Got := SDL_WaitEventTimeout(@Ev, Timeout) <> 0;
  while Got do
  begin
    { an event of a form's own window }
    FW := nil;
    if (FFormWindows <> nil) and (FFormWindows.Count > 0) then
      case Ev.type_ of
        SDL_WINDOWEVENT, SDL_MOUSEMOTION, SDL_MOUSEBUTTONDOWN, SDL_MOUSEBUTTONUP, SDL_MOUSEWHEEL, SDL_KEYDOWN, SDL_KEYUP,
        SDL_TEXTINPUT:
          for I := 0 to FFormWindows.Count - 1 do
            if TFormWindow(FFormWindows[I]).Id = Ev.window.windowID then
              FW := TFormWindow(FFormWindows[I]);
      end;
    if FW <> nil then
    begin
      F := FW.Form;
      case Ev.type_ of
        SDL_WINDOWEVENT:
          case Ev.window.event of
            SDL_WINDOWEVENT_CLOSE:
              if F.CloseQuery then
                CloseFormWindow(F);
            SDL_WINDOWEVENT_RESIZED, SDL_WINDOWEVENT_SIZE_CHANGED:
              begin
                FW.W := Max(1, Round(Ev.window.data1 / FMouseScale));
                FW.H := Max(1, Round(Ev.window.data2 / FMouseScale));
                NeedsLayout := True;
              end;
            SDL_WINDOWEVENT_EXPOSED:
              NeedsRepaint := True;
            SDL_WINDOWEVENT_LEAVE:
              F.HandleMouseLeave;
          end;
        SDL_MOUSEMOTION:
          begin
            CaptureMouse(Ev.motion.state <> 0);
            F.HandleMouseMove(Round(Ev.motion.x / FMouseScale), Round(Ev.motion.y / FMouseScale));
          end;
        SDL_MOUSEBUTTONDOWN:
          F.HandleMouseDown(Round(Ev.button.x / FMouseScale), Round(Ev.button.y / FMouseScale), Ev.button.button,
            Ev.button.clicks);
        SDL_MOUSEBUTTONUP:
          begin
            CaptureMouse(False);
            F.HandleMouseUp(Round(Ev.button.x / FMouseScale), Round(Ev.button.y / FMouseScale), Ev.button.button);
          end;
        SDL_MOUSEWHEEL:
          F.HandleMouseWheel(Ev.wheel.x, Ev.wheel.y);
        SDL_KEYDOWN:
          begin
            Mods := Ev.key.keysym.mods;
            F.ShiftDown := (Mods and KMOD_SHIFT) <> 0;
            F.HandleKeyDown(Ev.key.keysym.sym, (Mods and KMOD_SHIFT) <> 0, (Mods and (KMOD_CTRL or KMOD_GUI)) <> 0);
          end;
        SDL_KEYUP:
          F.ShiftDown := (Ev.key.keysym.mods and KMOD_SHIFT) <> 0;
        SDL_TEXTINPUT:
          F.HandleTextInput(StrPas(@Ev.text.text[0]));
      end;
      Got := SDL_PollEvent(@Ev) <> 0;
      Continue;
    end;
    case Ev.type_ of
      SDL_QUIT_EV:
        TryClose;
      SDL_WINDOWEVENT:
        case Ev.window.event of
          SDL_WINDOWEVENT_MINIMIZED:
            begin
              FAppliedState := wsMinimized;
              FMainForm.WindowStateChanged(wsMinimized);
            end;
          SDL_WINDOWEVENT_MAXIMIZED:
            begin
              FAppliedState := wsMaximized;
              FMainForm.WindowStateChanged(wsMaximized);
            end;
          SDL_WINDOWEVENT_RESTORED:
            if FAppliedState <> wsFullScreen then
            begin
              FAppliedState := wsNormal;
              FMainForm.WindowStateChanged(wsNormal);
            end;
          SDL_WINDOWEVENT_RESIZED, SDL_WINDOWEVENT_SIZE_CHANGED:
            begin
              FWidth := Max(1, Round(Ev.window.data1 / FMouseScale));
              FHeight := Max(1, Round(Ev.window.data2 / FMouseScale));
              NeedsLayout := True;
            end;
          SDL_WINDOWEVENT_EXPOSED:
            NeedsRepaint := True;
          SDL_WINDOWEVENT_LEAVE:
            FMainForm.HandleMouseLeave;
          SDL_WINDOWEVENT_CLOSE:
            { the main window: the app (with other windows open SDL sends no quit) }
            TryClose;
        end;
      SDL_MOUSEMOTION:
        begin
          CaptureMouse(Ev.motion.state <> 0);
          FMainForm.HandleMouseMove(Round(Ev.motion.x / FMouseScale), Round(Ev.motion.y / FMouseScale));
        end;
      SDL_MOUSEBUTTONDOWN:
        FMainForm.HandleMouseDown(Round(Ev.button.x / FMouseScale), Round(Ev.button.y / FMouseScale),
          Ev.button.button, Ev.button.clicks);
      SDL_MOUSEBUTTONUP:
        begin
          CaptureMouse(False);
          FMainForm.HandleMouseUp(Round(Ev.button.x / FMouseScale), Round(Ev.button.y / FMouseScale),
            Ev.button.button);
        end;
      SDL_MOUSEWHEEL:
        if ((SDL_GetModState() and KMOD_CTRL) <> 0) and (Ev.wheel.y <> 0) then
        begin
          { Ctrl and the wheel: a pinch, as two fingers would }
          G.State := gsUpdate;
          G.Scale := Power(1.1, Ev.wheel.y);
          G.Rotation := 0;
          G.X := FMainForm.MouseX;
          G.Y := FMainForm.MouseY;
          FMainForm.HandleGesture(G);
        end
        else
          FMainForm.HandleMouseWheel(Ev.wheel.x, Ev.wheel.y);
      SDL_USEREVENT:
        ;       { woken up: TThread.Queue/Synchronize has work }
      SDL_DROPBEGIN:
        begin
          FDropped := nil;
          FDropBatch := True;
        end;
      SDL_DROPFILE:
        begin
          if Ev.drop.file_ <> nil then
          begin
            FDropped := Concat(FDropped, [StrPas(Ev.drop.file_)]);
            SDL_free(Ev.drop.file_);
          end;
          { an SDL older than 2.0.5 sends no DROPCOMPLETE: one file at a time }
          if not FDropBatch then
            DeliverDrop;
        end;
      SDL_DROPCOMPLETE:
        DeliverDrop;
      SDL_KEYDOWN:
        begin
          Mods := Ev.key.keysym.mods;
          KeyAlt := (Mods and KMOD_ALT) <> 0;
          FMainForm.ShiftDown := (Mods and KMOD_SHIFT) <> 0;
          FMainForm.HandleKeyDown(Ev.key.keysym.sym, (Mods and KMOD_SHIFT) <> 0,
            (Mods and (KMOD_CTRL or KMOD_GUI)) <> 0);
          KeyAlt := False;
        end;
      SDL_KEYUP:
        FMainForm.ShiftDown := (Ev.key.keysym.mods and KMOD_SHIFT) <> 0;
      SDL_TEXTINPUT:
        FMainForm.HandleTextInput(StrPas(@Ev.text.text[0]));
    end;
    Got := SDL_PollEvent(@Ev) <> 0;
  end;
end;
{$ENDIF}

{ the files dropped on the window: where the mouse is }
procedure TApplication.DeliverDrop;
var
  MX, MY, WX, WY: LongInt;
  X, Y: Integer;
  Files: TStringArray;
begin
  Files := FDropped;
  FDropped := nil;
  FDropBatch := False;
  if Length(Files) = 0 then
    Exit;
  X := FMainForm.MouseX;
  Y := FMainForm.MouseY;
  {$IFNDEF ANDROID}
  if Assigned(SDL_GetGlobalMouseState) and Assigned(SDL_GetWindowPosition) and (FWindow <> nil) then
  begin
    SDL_GetGlobalMouseState(@MX, @MY);
    SDL_GetWindowPosition(FWindow, @WX, @WY);
    X := Round((MX - WX) / FMouseScale);
    Y := Round((MY - WY) / FMouseScale);
  end;
  {$ENDIF}
  FMainForm.HandleDropFiles(X, Y, Files);
end;

procedure TApplication.Reload(const NewSource: string);
var
  Root: TPFormNode;
  Err: string;
  State: TStringList;
begin
  Err := '';
  Root := nil;
  try
    Root := ParsePForm(NewSource);
  except
    on E: EPFormError do
      Err := E.Message;
  end;
  State := nil;
  if Root <> nil then
  try
    State := CaptureState(FMainForm);
    FMainForm.ClearControls;
    try
      BuildForm(FMainForm, Root);
      RestoreState(FMainForm, State);
      FLastGood := NewSource;
      if Assigned(FMainForm.OnCreate) then
        FMainForm.OnCreate(FMainForm);
    except
      on E: Exception do
      begin
        Err := E.Message;
        { go back to the last version that worked }
        FMainForm.ClearControls;
        Root.Free;
        Root := ParsePForm(FLastGood);
        BuildForm(FMainForm, Root);
        RestoreState(FMainForm, State);
      end;
    end;
  finally
    Root.Free;
    State.Free;
  end;
  if Err <> '' then
  begin
    FReloadError := ExtractFileName(FSourcePath) + ', ' + Err;
    WriteLn(StdErr, 'hot reload: ', FReloadError);
  end
  else
  begin
    FReloadError := '';
    WriteLn('hot reload: ', ExtractFileName(FSourcePath), ' updated');
  end;
  Flush(Output);
  NeedsLayout := True;
  NeedsRepaint := True;
end;

{$IFDEF ANDROID}
{ a frame's .pform on a phone: from "pastel run" on the computer, like the form's }
function FetchFrame(const FilePath: string; Lines: TStrings): Boolean;
begin
  Result := AndroidFetchForm(AndroidFormServer + ExtractFileName(FilePath), Lines);
end;
{$ENDIF}

procedure TApplication.CheckHotReload;
var
  S: TStringList;
begin
  if FSourcePath = '' then
    Exit;
  if GetTickCount64 - FLastCheck < 250 then
    Exit;
  FLastCheck := GetTickCount64;
  { comparing the text is more reliable than file times, which may only
    have one-second precision; .pform files are small }
  S := TStringList.Create;
  try
    {$IFDEF ANDROID}
    { from the computer; when nobody answers (started without pastel run), ask less often }
    if GetTickCount64 < FReloadPause then
      Exit;
    if not AndroidFetchForm(FSourcePath, S) then
    begin
      FReloadPause := GetTickCount64 + 3000;
      Exit;
    end;
    {$ELSE}
    try
      S.LoadFromFile(FSourcePath);
    except
      Exit;   { the editor may be writing the file right now }
    end;
    {$ENDIF}
    { a view (Home.tablet.pform) changed: applied again }
    if FormViewFilesText(FMainForm) <> FSeenViews then
    begin
      FSeenViews := FormViewFilesText(FMainForm);
      FMainForm.View := '?';
      try
        ApplyFormView(FMainForm, FMainForm.ScreenClass);
        WriteLn('hot reload: the ', FMainForm.View, ' view updated');
      except
        on E: Exception do
          WriteLn(StdErr, 'hot reload: ', E.Message);
      end;
      NeedsLayout := True;
      NeedsRepaint := True;
    end;
    { a frame of the form changed: the form is built again with it }
    if RefreshFrameSources({$IFDEF ANDROID}@FetchFrame{$ELSE}nil{$ENDIF}) then
    begin
      FSeenText := S.Text;
      Reload(S.Text);
      Exit;
    end;
    if S.Text = FSeenText then
      Exit;
    FSeenText := S.Text;
    Reload(S.Text);
  finally
    S.Free;
  end;
end;

function TApplication.FindAnyControl(const AName: string): TControl;

  function Search(Root: TComponent): TControl;
  var
    I: Integer;
    C: TComponent;
  begin
    Result := nil;
    if SameText(Root.Name, AName) and (Root is TControl) then
      Exit(TControl(Root));
    C := Root.FindComponent(AName);
    if C is TControl then
      Exit(TControl(C));
    for I := 0 to Root.ComponentCount - 1 do
    begin
      Result := Search(Root.Components[I]);
      if Result <> nil then
        Exit;
    end;
    { a form shown in a dialog is a child, not owned }
    if Root is TControl then
      for I := 0 to TControl(Root).ChildCount - 1 do
        if TControl(Root).Children[I] is TForm then
        begin
          Result := Search(TControl(Root).Children[I]);
          if Result <> nil then
            Exit;
        end;
  end;

  function SearchTree(C: TControl): TControl;
  var
    I: Integer;
  begin
    Result := nil;
    if C is TForm then
      Exit(Search(C));
    for I := 0 to C.ChildCount - 1 do
    begin
      Result := SearchTree(C.Children[I]);
      if Result <> nil then
        Exit;
    end;
  end;

var
  I: Integer;
begin
  { dialogs first: they are on top }
  for I := FMainForm.PopupCount - 1 downto 0 do
  begin
    Result := Search(FMainForm.PopupAt(I));
    if Result = nil then
      Result := SearchTree(FMainForm.PopupAt(I));
    if Result <> nil then
      Exit;
  end;
  Result := Search(FMainForm);
end;

{ Test scripts: one command per line.

    click Name | doubleclick Name | rightclick Name | hover Name
    type Name text            key enter | key ctrl+a | key shift+down
    wheel Name -3             wait 500 (timers and threads run)
    expect Name text          expect Name.Property value
    shot file.png             resize 800 600
    reload | close | quit | print Name | sleep ms

  A command that opens a dialog (ShowModal, ShowMessage) waits there; the
  next commands of the script act on the dialog until it is closed. }
function TApplication.RunScriptStep: Boolean;
var
  Line, Cmd, Arg1, Rest, Prop, Want, Got: string;
  C: TControl;
  R: TRectI;
  X, Y, I, DX, DY: Integer;
  Parts: TStringArray;
  Until_: QWord;

  function TakeWord(var S: string): string;
  var
    P: Integer;
  begin
    P := Pos(' ', S);
    if P = 0 then
    begin
      Result := S;
      S := '';
    end
    else
    begin
      Result := Copy(S, 1, P - 1);
      S := Copy(S, P + 1, MaxInt);
    end;
  end;

  { Name, or Frame.Name (a control in a frame); Prop gets what is left after the controls ('' when nothing) }
  function Resolve(const Path: string; out Prop: string): TControl;
  var
    Parts: TStringArray;
    I: Integer;
    C: TComponent;
  begin
    Parts := Path.Split(['.']);
    Prop := '';
    Result := FindAnyControl(Parts[0]);
    if Result = nil then
      Fatal(Format('%s:%d: no control named "%s"', [FScriptFile, FScriptPos, Parts[0]]));
    for I := 1 to High(Parts) do
    begin
      C := Result.FindComponent(Parts[I]);
      if C is TControl then
        Result := TControl(C)
      else
      begin
        Prop := string.Join('.', Copy(Parts, I, MaxInt));
        Exit;
      end;
    end;
  end;

  function Ctl(const AName: string): TControl;
  var
    Rest_: string;
  begin
    Result := Resolve(AName, Rest_);
    if Rest_ <> '' then
      Fatal(Format('%s:%d: no control named "%s"', [FScriptFile, FScriptPos, AName]));
  end;

  function ValueOf(Ctrl: TControl; const AProp: string): string;
  var
    Info: PPropInfo;
  begin
    Info := GetPropInfo(Ctrl, AProp);
    if Info = nil then
      Fatal(Format('%s:%d: %s has no property "%s"', [FScriptFile, FScriptPos, Ctrl.Name, AProp]));
    case Info^.PropType^.Kind of
      TypInfo.tkInteger, TypInfo.tkInt64:
        Result := IntToStr(GetOrdProp(Ctrl, Info));
      TypInfo.tkEnumeration, TypInfo.tkBool:
        Result := GetEnumProp(Ctrl, Info);
      TypInfo.tkClass:
        if GetObjectProp(Ctrl, Info) is TStrings then
          Result := StringReplace(Trim(TStrings(GetObjectProp(Ctrl, Info)).Text), LineEnding, '|', [rfReplaceAll])
        else
          Result := '';
    else
      Result := GetStrProp(Ctrl, Info);
    end;
  end;

  function TextOf(Ctrl: TControl): string;
  begin
    if Ctrl is TCustomEdit then
      Result := TCustomEdit(Ctrl).Text
    else if IsPublishedProp(Ctrl, 'Text') then
      Result := GetStrProp(Ctrl, 'Text')
    else
      Result := '';
    { several lines (a memo, a label): one line with | between them }
    Result := StringReplace(StringReplace(Result, #13#10, #10, [rfReplaceAll]), #10, '|', [rfReplaceAll]);
  end;

  procedure Key(const Spec: string);
  var
    Parts: TStringArray;
    K: string;
    Code: LongInt;
    Shift, Ctrl: Boolean;
    I: Integer;
  begin
    Parts := LowerCase(Spec).Split(['+']);
    Shift := False;
    Ctrl := False;
    KeyAlt := False;
    for I := 0 to High(Parts) - 1 do
      case Parts[I] of
        'shift': Shift := True;
        'ctrl', 'cmd': Ctrl := True;
        'alt': KeyAlt := True;
      end;
    K := Parts[High(Parts)];
    case K of
      'enter': Code := KEY_ENTER;
      'tab': Code := KEY_TAB;
      'backspace': Code := KEY_BACKSPACE;
      'delete': Code := KEY_DELETE;
      'escape', 'esc': Code := KEY_ESCAPE;
      'left': Code := KEY_LEFT;
      'right': Code := KEY_RIGHT;
      'up': Code := KEY_UP;
      'down': Code := KEY_DOWN;
      'home': Code := KEY_HOME;
      'end': Code := KEY_END;
      'pageup': Code := KEY_PAGEUP;
      'pagedown': Code := KEY_PAGEDOWN;
      'space': Code := KEY_SPACE;
      'menu': Code := KEY_MENU;
    else
      if (Length(K) >= 2) and (K[1] = 'f') and TryStrToInt(Copy(K, 2, 2), I) and (I >= 1) and (I <= 12) then
        Code := KEY_F1 + I - 1
      else if Length(K) = 1 then
        Code := Ord(K[1])
      else
      begin
        Fatal(Format('%s:%d: unknown key "%s"', [FScriptFile, FScriptPos, Spec]));
        Code := 0;
      end;
    end;
    FMainForm.ShiftDown := Shift;
    FMainForm.HandleKeyDown(Code, Shift, Ctrl);
    FMainForm.ShiftDown := False;
    KeyAlt := False;
  end;

begin
  Result := False;
  while FScriptPos < FScript.Count do
  begin
    Line := Trim(FScript[FScriptPos]);
    Inc(FScriptPos);
    if (Line = '') or (Line[1] = '#') then
      Continue;
    Result := True;
    Rest := Line;
    Cmd := LowerCase(TakeWord(Rest));
    Arg1 := TakeWord(Rest);
    Refresh;
    case Cmd of
      'click', 'doubleclick', 'rightclick':
        begin
          C := Ctl(Arg1);
          R := C.Bounds;
          { things that are drawn by another control: a page's tab, an item of an open menu }
          if (C is TTabSheet) and (C.Parent is TTabControl) then
            R := TTabControl(C.Parent).TabRect(TTabSheet(C))
          else if (C is TMenuItem) and not (C.Parent is TMenuBar) and not MenuItemRect(TMenuItem(C), R) then
            Fatal(Format('%s:%d: the menu with "%s" is not open', [FScriptFile, FScriptPos, Arg1]));
          X := R.X + R.W div 2;
          Y := R.Y + R.H div 2;
          if Rest <> '' then     { click Name 10 5: at a point inside the control }
          begin
            X := R.X + StrToIntDef(TakeWord(Rest), 0);
            Y := R.Y + StrToIntDef(Rest, R.H div 2);
          end;
          FMainForm.HandleMouseMove(X, Y);
          if Cmd = 'rightclick' then
          begin
            FMainForm.HandleMouseDown(X, Y, 3, 1);
            FMainForm.HandleMouseUp(X, Y, 3);
          end
          else
          begin
            FMainForm.HandleMouseDown(X, Y, 1, 1);
            FMainForm.HandleMouseUp(X, Y, 1);
            if Cmd = 'doubleclick' then
            begin
              FMainForm.HandleMouseDown(X, Y, 1, 2);
              FMainForm.HandleMouseUp(X, Y, 1);
            end;
          end;
        end;
      'hover':
        begin
          C := Ctl(Arg1);
          R := C.Bounds;
          if (C is TMenuItem) and not (C.Parent is TMenuBar) and not MenuItemRect(TMenuItem(C), R) then
            Fatal(Format('%s:%d: the menu with "%s" is not open', [FScriptFile, FScriptPos, Arg1]));
          FMainForm.HandleMouseMove(R.X + R.W div 2, R.Y + R.H div 2);
        end;
      'drag':     { drag Name 120 0: press in its middle, move by 120, 0 and let go }
        begin
          C := Ctl(Arg1);
          X := C.Bounds.X + C.Bounds.W div 2;
          Y := C.Bounds.Y + C.Bounds.H div 2;
          DX := StrToIntDef(TakeWord(Rest), 0);
          DY := StrToIntDef(Rest, 0);
          FMainForm.HandleMouseMove(X, Y);
          FMainForm.HandleMouseDown(X, Y, 1, 1);
          for I := 1 to 4 do
            FMainForm.HandleMouseMove(X + DX * I div 4, Y + DY * I div 4);
          FMainForm.HandleMouseUp(X + DX, Y + DY, 1);
        end;
      'wheel':
        begin
          C := Ctl(Arg1);
          FMainForm.HandleMouseMove(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2);
          FMainForm.HandleMouseWheel(0, StrToIntDef(Rest, -1));
        end;
      'drop':
        begin
          { drop <name> <file> [<file>...]: files from the file manager on it }
          C := Ctl(Arg1);
          if not FMainForm.HandleDropFiles(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2,
            Rest.Split([' '], TStringSplitOptions.ExcludeEmpty)) then
            Fatal(Format('%s:%d: nothing takes files dropped on %s (OnDropFiles)', [FScriptFile, FScriptPos, Arg1]));
        end;
      'type':
        begin
          C := Ctl(Arg1);
          if FMainForm.Focused <> C then
            C.SetFocus;
          { \n presses Enter: a new line in a memo, OnSubmit or the default button elsewhere }
          Parts := Rest.Split(['\n']);
          for I := 0 to High(Parts) do
          begin
            if I > 0 then
              Key('enter');
            if Parts[I] <> '' then
              FMainForm.HandleTextInput(Parts[I]);
          end;
        end;
      'key':
        Key(Arg1);
      'wait':
        begin
          Until_ := GetTickCount64 + QWord(StrToIntDef(Arg1, 100));
          repeat
            CheckSynchronize(5);
            ProcessTimers(GetTickCount64);
            FMainForm.UpdateTooltip(GetTickCount64);
          until GetTickCount64 >= Until_;
        end;
      'resize':
        begin
          FWidth := StrToIntDef(Arg1, FWidth);
          FHeight := StrToIntDef(Rest, FHeight);
          NeedsLayout := True;
        end;
      'reload':
        begin
          FLastCheck := 0;
          CheckHotReload;
        end;
      'shot':
        begin
          Refresh;
          FCanvas.SaveToPNG(Arg1);
          WriteLn('saved ', Arg1);
        end;
      'expect':
        begin
          C := Resolve(Arg1, Prop);
          if Prop <> '' then
            Got := ValueOf(C, Prop)
          else
            Got := TextOf(C);
          Want := Rest;
          if not SameText(Got, Want) and (Got <> Want) then
          begin
            Inc(FScriptFailures);
            WriteLn(Format('FAIL line %d: %s is "%s", expected "%s"', [FScriptPos, Arg1, Got, Want]));
          end
          else
            WriteLn(Format('ok: %s = "%s"', [Arg1, Want]));
        end;
      'set':
        begin
          { set Name.Property value: like the .pform line Property = value }
          C := Resolve(Arg1, Prop);
          if Prop = '' then
            Fatal(Format('%s:%d: set needs Name.Property, like: set DueDate.DateText 2026-11-01',
              [FScriptFile, FScriptPos]));
          if GetPropInfo(C, Prop) = nil then
            Fatal(Format('%s:%d: %s has no property "%s"', [FScriptFile, FScriptPos, C.Name, Prop]));
          try
            SetPropValue(C, Prop, Rest);
          except
            on E: Exception do
              Fatal(Format('%s:%d: %s.%s = %s: %s', [FScriptFile, FScriptPos, C.Name, Prop, Rest, E.Message]));
          end;
        end;
      'print':
        WriteLn(Arg1, ': ', TextOf(Ctl(Arg1)));
      'sleep':
        Sleep(StrToIntDef(Arg1, 100));
      'close':
        begin
          TryClose;
          if FTerminated then
          begin
            WriteLn('closed');
            FScriptPos := FScript.Count;
            Exit(False);
          end;
          WriteLn('close cancelled');
        end;
      'quit':
        begin
          FScriptPos := FScript.Count;
          Exit(False);
        end;
    else
      Fatal(Format('%s:%d: unknown command "%s"', [FScriptFile, FScriptPos, Cmd]));
    end;
    Refresh;
    Present;
    Exit(True);
  end;
end;

procedure TApplication.PaintIfNeeded;
var
  Others: Boolean;
begin
  Others := (FFormWindows <> nil) and (FFormWindows.Count > 0) and (NeedsLayout or NeedsRepaint or NeedsPartialRepaint);
  if NeedsLayout or (FLaidOutW <> FWidth) or (FLaidOutH <> FHeight) then
    DoLayout;
  if NeedsRepaint or NeedsPartialRepaint then
  begin
    Paint;
    Present;
  end;
  if Others then
    PaintFormWindows;
end;

procedure TApplication.RunScript(const FileName: string);
begin
  FScript := TStringList.Create;
  try
    FScript.LoadFromFile(FileName);
    FScriptFile := FileName;
    FScriptPos := 0;
    FScriptFailures := 0;
    while RunScriptStep do
      PaintIfNeeded;     { like the event loop: what a line changed is drawn }
  finally
    FreeAndNil(FScript);
  end;
  if FCheckRepaint then
    WriteLn(Format('partial repaints: %d checked, %d wrong', [FRepaintsChecked, FRepaintMismatches]));
  if FRepaintMismatches > 0 then
    Inc(FScriptFailures);
  if FScriptFailures > 0 then
    Halt(1);
end;

procedure TApplication.Step;
var
  Timeout, NextTimer: Integer;
  NowMs: QWord;
  Others: Boolean;
  I: Integer;
begin
  if FScript <> nil then
  begin
    { in a test script, a dialog waits for the script's next commands }
    if not RunScriptStep then
      Fatal(Format('%s: the script ended while a dialog was open', [FScriptFile]));
    Exit;
  end;
  if FSourcePath <> '' then Timeout := 100 else Timeout := 250;
  NextTimer := ProcessTimers(GetTickCount64);
  if (NextTimer >= 0) and (NextTimer < Timeout) then
    Timeout := NextTimer;
  if AnimationRequested then
    Timeout := 16;
  if (FMainForm.Hovered <> nil) and (FMainForm.Hovered.Hint <> '') then
    Timeout := Min(Timeout, 100);
  if FHeadless then
    Sleep(Min(Timeout, 20))
  else
    ProcessEvents(Timeout);
  if FTerminated then
    Exit;
  CheckSynchronize(0);
  NowMs := GetTickCount64;
  ProcessTimers(NowMs);
  CheckHotReload;
  if CloseRequested then
  begin
    TryClose;
    if FTerminated then
      Exit;
  end;
  if NeedsWindowSync then
    SyncWindow;
  if (FMainForm.Focused is TCustomEdit) and (NowMs - FLastBlink >= 530) then
  begin
    FLastBlink := NowMs;
    CaretVisible := not CaretVisible;
    FMainForm.Focused.Invalidate;
  end;
  FMainForm.UpdateTooltip(NowMs);
  { the forms in windows of their own: their caret blinks too }
  Others := (FFormWindows <> nil) and (FFormWindows.Count > 0);
  if Others and (NowMs - FLastBlink < 20) then
    for I := 0 to FFormWindows.Count - 1 do
      if TFormWindow(FFormWindows[I]).Form.Focused is TCustomEdit then
        NeedsRepaint := True;
  Others := Others and (NeedsLayout or NeedsRepaint or NeedsPartialRepaint);
  if NeedsLayout or (FLaidOutW <> FWidth) or (FLaidOutH <> FHeight) then
    DoLayout;
  if NeedsRepaint or NeedsPartialRepaint then
  begin
    AnimationRequested := False;
    Paint;
    Present;
  end;
  if Others then
    PaintFormWindows;
  {$IFDEF ANDROID}
  AndroidAccessibility(NowMs);
  {$ENDIF}
  UpdateCursor;
end;

procedure TApplication.ProcessMessages;
begin
  if FScript = nil then
    SafeStep;
end;

procedure TApplication.CaptureMouse(Dragging: Boolean);
begin
  { while a button is held and the mouse moves: dragging out of the window
    (a splitter, a selection) still reaches the app }
  {$IFNDEF ANDROID}
  if (Dragging <> FMouseCaptured) and Assigned(SDL_CaptureMouse) then
  begin
    SDL_CaptureMouse(Ord(Dragging));
    FMouseCaptured := Dragging;
  end;
  {$ENDIF}
end;

procedure TApplication.SafeStep;
begin
  { test scripts: an exception ends the script, as it always did }
  if FScript <> nil then
  begin
    Step;
    Exit;
  end;
  try
    Step;
  except
    on E: Exception do
    begin
      if not (E is EAbort) then
      begin
        {$I-}
        WriteLn(StdErr, 'error: ', E.Message);
        DumpExceptionBackTrace(StdErr);
        {$I+}
        InOutRes := 0;
        {$IFDEF ANDROID}
        AndroidLog('error: ' + E.Message);
        {$ENDIF}
        if Assigned(HandledErrorHook) then
        try
          HandledErrorHook(E, 'event');
        except
          { the report cannot be kept: the app goes on }
        end;
      end;
      HandleException(E);
    end;
  end;
end;

procedure TApplication.HandleException(E: Exception);
begin
  if (E is EAbort) or FInException then
    Exit;
  FInException := True;
  try
    try
      if Assigned(FOnException) then
        FOnException(Self, E)
      else
        ShowException(E);
    except
      on E2: Exception do
      begin
        {$I-}
        WriteLn(StdErr, 'error: ', E2.Message);
        {$I+}
        InOutRes := 0;
      end;
    end;
  finally
    FInException := False;
  end;
end;

procedure TApplication.ShowException(E: Exception);
begin
  if (FMainForm = nil) or FHeadless then
    Exit;
  ShowMessage(E.Message, FMainForm.Title);
end;

{ ---- forms in windows of their own (computers) ---- }

procedure AppShowForm(Form: TForm);
begin
  Application.OpenFormWindow(Form);
end;

function AppCloseForm(Form: TForm): Boolean;
begin
  Result := Application.CloseFormWindow(Form);
end;

function FindFormWindow(L: TFPList; Form: TForm): TFormWindow;
var
  I: Integer;
begin
  Result := nil;
  if L <> nil then
    for I := 0 to L.Count - 1 do
      if TFormWindow(L[I]).Form = Form then
        Exit(TFormWindow(L[I]));
end;

procedure TApplication.OpenFormWindow(Form: TForm);
{$IFDEF ANDROID}
begin
  Form.ShowModal(TModalDoneEvent(nil));
end;
{$ELSE}
var
  FW: TFormWindow;
  Flags: LongWord;
begin
  if FFormWindows = nil then
    FFormWindows := TFPList.Create;
  FW := FindFormWindow(FFormWindows, Form);
  if FW <> nil then
  begin
    if Assigned(SDL_RaiseWindow) and (FW.Window <> nil) then
      SDL_RaiseWindow(FW.Window);
    Exit;
  end;
  FW := TFormWindow.Create;
  FW.Form := Form;
  FW.W := Form.Width;
  FW.H := Form.Height;
  if FW.W <= 0 then FW.W := DefaultWidth;
  if FW.H <= 0 then FW.H := DefaultHeight;
  FW.Canvas := TCanvas32.Create;
  FFormWindows.Add(FW);
  Form.FWindowed := True;
  if not FHeadless then
  begin
    { shown with its first picture (PaintFormWindows) }
    Flags := SDL_WINDOW_HIDDEN or SDL_WINDOW_ALLOW_HIGHDPI;
    if Form.Resizable then
      Flags := Flags or SDL_WINDOW_RESIZABLE;
    if Form.AlwaysOnTop then
      Flags := Flags or SDL_WINDOW_ALWAYS_ON_TOP;
    FW.Window := SDL_CreateWindow(PChar(Form.Title), SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
      Round(FW.W * FMouseScale), Round(FW.H * FMouseScale), Flags);
    if FW.Window = nil then
      Fatal('could not open a window: ' + StrPas(SDL_GetError()));
    FW.Id := SDL_GetWindowID(FW.Window);
    FW.Renderer := SDL_CreateRenderer(FW.Window, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
    if FW.Renderer = nil then
      FW.Renderer := SDL_CreateRenderer(FW.Window, -1, SDL_RENDERER_SOFTWARE);
    if Assigned(SDL_SetWindowMinimumSize) then
      SDL_SetWindowMinimumSize(FW.Window, Round(Form.MinWidth * FMouseScale), Round(Form.MinHeight * FMouseScale));
  end;
  NeedsLayout := True;
  NeedsRepaint := True;
end;
{$ENDIF}

function TApplication.CloseFormWindow(Form: TForm): Boolean;
var
  FW: TFormWindow;
begin
  FW := FindFormWindow(FFormWindows, Form);
  Result := FW <> nil;
  if not Result then
    Exit;
  FFormWindows.Remove(FW);
  Form.FWindowed := False;
  {$IFNDEF ANDROID}
  if FW.Texture <> nil then SDL_DestroyTexture(FW.Texture);
  if FW.Renderer <> nil then SDL_DestroyRenderer(FW.Renderer);
  if FW.Window <> nil then SDL_DestroyWindow(FW.Window);
  {$ENDIF}
  FW.Canvas.Free;
  FW.Free;
  if Assigned(Form.OnClose) then
    Form.OnClose(Form);
  NeedsRepaint := True;
end;

procedure TApplication.CloseAllFormWindows;
begin
  while (FFormWindows <> nil) and (FFormWindows.Count > 0) do
    CloseFormWindow(TFormWindow(FFormWindows[0]).Form);
  FreeAndNil(FFormWindows);
end;

procedure TApplication.PaintFormWindows;
var
  I: Integer;
  FW: TFormWindow;
begin
  if FFormWindows = nil then
    Exit;
  for I := FFormWindows.Count - 1 downto 0 do
  begin
    FW := TFormWindow(FFormWindows[I]);
    FW.Form.Layout(FW.W, FW.H);
    FW.Canvas.Scale := FScale;
    FW.Canvas.SetSize(FW.W, FW.H);
    FW.Form.Render(FW.Canvas);
    {$IFNDEF ANDROID}
    if FW.Renderer = nil then
    begin
      if not FW.Shown and (FW.Window <> nil) then
      begin
        FW.Shown := True;
        SDL_ShowWindow(FW.Window);
      end;
      Continue;
    end;
    if (FW.Texture = nil) or (FW.TexW <> FW.Canvas.PixelWidth) or (FW.TexH <> FW.Canvas.PixelHeight) then
    begin
      if FW.Texture <> nil then
        SDL_DestroyTexture(FW.Texture);
      FW.Texture := SDL_CreateTexture(FW.Renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING,
        FW.Canvas.PixelWidth, FW.Canvas.PixelHeight);
      FW.TexW := FW.Canvas.PixelWidth;
      FW.TexH := FW.Canvas.PixelHeight;
    end;
    SDL_UpdateTexture(FW.Texture, nil, FW.Canvas.Data, FW.Canvas.PixelWidth * 4);
    SDL_RenderClear(FW.Renderer);
    SDL_RenderCopy(FW.Renderer, FW.Texture, nil, nil);
    SDL_RenderPresent(FW.Renderer);
    if not FW.Shown then
    begin
      FW.Shown := True;
      SDL_ShowWindow(FW.Window);
      SDL_RenderClear(FW.Renderer);
      SDL_RenderCopy(FW.Renderer, FW.Texture, nil, nil);
      SDL_RenderPresent(FW.Renderer);
    end;
    {$ENDIF}
  end;
end;

procedure AppModalStep;
begin
  Application.SafeStep;
end;

function AppPixelRect(const R: TRectI): TRectI;
var
  S: Single;
begin
  S := Application.FScale;
  Result.X := Round(R.X * S);
  Result.Y := Round(R.Y * S);
  Result.W := Round((R.X + R.W) * S) - Result.X;
  Result.H := Round((R.Y + R.H) * S) - Result.Y;
  {$IFDEF ANDROID}
  Inc(Result.X, Application.FInsetX);
  Inc(Result.Y, Application.FInsetY);
  {$ENDIF}
end;

procedure TApplication.WakeUp(Sender: TObject);
{$IFDEF ANDROID}
begin
  AndroidWake;
end;
{$ELSE}
var
  Ev: TSDL_Event;
begin
  if Assigned(SDL_PushEvent) and not FHeadless and (FWindow <> nil) then
  begin
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.type_ := SDL_USEREVENT;
    SDL_PushEvent(@Ev);
  end;
end;
{$ENDIF}

{$IFDEF ANDROID}
{$I pastel.app.android.inc}
{$ENDIF}

procedure TApplication.Run;
var
  Script: string;
begin
  if FMainForm = nil then
    Fatal('Application.Run needs a form: call Application.CreateForm first');
  {$IFDEF ANDROID}
  { Android starts the app when its activity is there (Pastel.Android) }
  if not FHeadless then
  begin
    AndroidAppMain := @AndroidRunApp;
    Exit;
  end;
  {$ENDIF}
  CreateWindow;
  ModalStep := @AppModalStep;
  WindowPixelRect := @AppPixelRect;
  ShowFormHook := @AppShowForm;
  CloseFormHook := @AppCloseForm;
  WakeMainThread := @WakeUp;
  Refresh;
  Present;
  {$IFNDEF ANDROID}
  if FShowLater and (FWindow <> nil) then
  begin
    { the first picture is there: now the window, and the picture again (some
      drivers drop what was shown into a hidden window) }
    SDL_ShowWindow(FWindow);
    FPresentArea := RectI(0, 0, 0, 0);
    Present;
  end;
  {$ENDIF}

  Script := GetEnv('PASTEL_TEST_SCRIPT');
  if Script <> '' then
  begin
    RunScript(Script);
    Exit;
  end;

  FLastBlink := GetTickCount64;
  while not FTerminated do
    SafeStep;
end;

{ the HWND for system dialogs on Windows (an SDL_SysWMinfo: version, subsystem, then the window) }
function WindowHandle: Pointer;
{$IFDEF WINDOWS}
var
  Info: array[0..127] of Byte;
{$ENDIF}
begin
  Result := nil;
  {$IF defined(WINDOWS) and not defined(ANDROID)}
  if (Application = nil) or (Application.FWindow = nil) or not Assigned(SDL_GetWindowWMInfo) then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  Info[0] := 2;     { SDL 2.0.x }
  if SDL_GetWindowWMInfo(Application.FWindow, @Info) <> 0 then
    Result := PPointer(@Info[8])^;
  {$ENDIF}
end;

initialization
  Application := TApplication.Create;
  NativeWindowHook := @WindowHandle;
  SystemDarkHook := @SystemPrefersDark;

finalization
  FreeAndNil(Application);
  FreeAndNil(ThemeFile);

end.
