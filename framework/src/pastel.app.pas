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
  Classes, SysUtils, Pastel.Graphics, Pastel.UI, Pastel.PForm, Pastel.Forms;

type
  TApplication = class
  private
    FMainForm: TForm;
    FTerminated: Boolean;
    FHeadless: Boolean;
    FWindow, FRenderer, FTexture: Pointer;
    FCanvas: TCanvas32;
    FWidth, FHeight: Integer;
    FTextureW, FTextureH: Integer;
    FCursors: array[TCursorKind] of Pointer;
    FCursorShown: TCursorKind;
    FWindowTitle: string;
    { hot reload }
    FSourcePath: string;
    FSeenText: string;
    FLastGood: string;
    FReloadError: string;
    FLastCheck, FLastBlink: QWord;
    procedure Fatal(const Msg: string);
    procedure LoadForm(Form: TForm);
    procedure CreateWindow;
    procedure ProcessEvents(Timeout: Integer);
    procedure CheckHotReload;
    procedure Reload(const NewSource: string);
    procedure Paint;
    procedure PaintOverlay;
    procedure Present;
    procedure UpdateCursor;
    procedure RunScript(const FileName: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Initialize;
    procedure CreateForm(AFormClass: TFormClass; out AReference);
    procedure Run;
    procedure Terminate;
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
  Math, Pastel.SDL2;

const
  DefaultWidth = 480;
  DefaultHeight = 360;

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

constructor TApplication.Create;
begin
  inherited Create;
  FCanvas := TCanvas32.Create;
  FCursorShown := ckArrow;
end;

destructor TApplication.Destroy;
begin
  FMainForm.Free;
  if FTexture <> nil then SDL_DestroyTexture(FTexture);
  if FRenderer <> nil then SDL_DestroyRenderer(FRenderer);
  if FWindow <> nil then
  begin
    SDL_DestroyWindow(FWindow);
    SDL_Quit;
  end;
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
  {$IFDEF WINDOWS}
  { release builds have no console, so the message would be invisible }
  if not IsConsole then
    MessageBoxA(nil, PChar(Msg), 'Pastel', $10);
  {$ENDIF}
  if IsConsole then
    WriteLn(StdErr, 'error: ', Msg);
  Halt(1);
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
  FHeadless := GetEnvironmentVariable('PASTEL_HEADLESS') = '1';
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
    FSourcePath := Src.FilePath;
    FSeenText := Text;
    FLastGood := Text;
  end;
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
    FMainForm := Form;
  LoadForm(Form);
end;

procedure TApplication.Terminate;
begin
  FTerminated := True;
end;

procedure TApplication.CreateWindow;
var
  Err: string;
  W, H: Integer;
begin
  W := FMainForm.Width;
  H := FMainForm.Height;
  if W <= 0 then W := DefaultWidth;
  if H <= 0 then H := DefaultHeight;
  FWidth := W;
  FHeight := H;
  if FHeadless then
    Exit;

  Err := LoadSDL2;
  if Err <> '' then
    Fatal(Err);
  SDL_SetHint('SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR', '0');
  if SDL_Init(SDL_INIT_VIDEO) <> 0 then
    Fatal('could not open a window: ' + StrPas(SDL_GetError()));
  FWindowTitle := FMainForm.Title;
  FWindow := SDL_CreateWindow(PChar(FWindowTitle), SDL_WINDOWPOS_CENTERED,
    SDL_WINDOWPOS_CENTERED, W, H, SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE);
  if FWindow = nil then
    Fatal('could not open a window: ' + StrPas(SDL_GetError()));
  SDL_SetWindowMinimumSize(FWindow, 200, 120);
  FRenderer := SDL_CreateRenderer(FWindow, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
  if FRenderer = nil then
    FRenderer := SDL_CreateRenderer(FWindow, -1, SDL_RENDERER_SOFTWARE);
  if FRenderer = nil then
    Fatal('could not create a renderer: ' + StrPas(SDL_GetError()));
  FCursors[ckArrow] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
  FCursors[ckIBeam] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM);
  FCursors[ckHand] := SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND);
  ClipboardGetText := @SdlClipboardGet;
  ClipboardSetText := @SdlClipboardSet;
  SDL_StartTextInput;
end;

procedure TApplication.Refresh;
begin
  if NeedsLayout or (FMainForm.Bounds.W <> FWidth) or (FMainForm.Bounds.H <> FHeight) then
    FMainForm.Layout(FWidth, FHeight);
  Paint;
end;

procedure TApplication.Paint;
begin
  FCanvas.SetSize(FWidth, FHeight);
  FMainForm.Render(FCanvas);
  PaintOverlay;
  NeedsRepaint := False;
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
begin
  if FHeadless then
    Exit;
  if (FTexture = nil) or (FTextureW <> FWidth) or (FTextureH <> FHeight) then
  begin
    if FTexture <> nil then
      SDL_DestroyTexture(FTexture);
    FTexture := SDL_CreateTexture(FRenderer, SDL_PIXELFORMAT_ARGB8888,
      SDL_TEXTUREACCESS_STREAMING, FWidth, FHeight);
    FTextureW := FWidth;
    FTextureH := FHeight;
  end;
  SDL_UpdateTexture(FTexture, nil, FCanvas.Data, FWidth * 4);
  SDL_RenderClear(FRenderer);
  SDL_RenderCopy(FRenderer, FTexture, nil, nil);
  SDL_RenderPresent(FRenderer);
end;

procedure TApplication.UpdateCursor;
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

procedure TApplication.ProcessEvents(Timeout: Integer);
var
  Ev: TSDL_Event;
  Got: Boolean;
  Mods: Word;
begin
  Got := SDL_WaitEventTimeout(@Ev, Timeout) <> 0;
  while Got do
  begin
    case Ev.type_ of
      SDL_QUIT_EV:
        FTerminated := True;
      SDL_WINDOWEVENT:
        case Ev.window.event of
          SDL_WINDOWEVENT_RESIZED, SDL_WINDOWEVENT_SIZE_CHANGED:
            begin
              FWidth := Max(1, Ev.window.data1);
              FHeight := Max(1, Ev.window.data2);
              NeedsLayout := True;
            end;
          SDL_WINDOWEVENT_EXPOSED:
            NeedsRepaint := True;
          SDL_WINDOWEVENT_LEAVE:
            FMainForm.HandleMouseLeave;
        end;
      SDL_MOUSEMOTION:
        FMainForm.HandleMouseMove(Ev.motion.x, Ev.motion.y);
      SDL_MOUSEBUTTONDOWN:
        if Ev.button.button = SDL_BUTTON_LEFT then
          FMainForm.HandleMouseDown(Ev.button.x, Ev.button.y);
      SDL_MOUSEBUTTONUP:
        if Ev.button.button = SDL_BUTTON_LEFT then
          FMainForm.HandleMouseUp(Ev.button.x, Ev.button.y);
      SDL_KEYDOWN:
        begin
          Mods := Ev.key.keysym.mods;
          FMainForm.HandleKeyDown(Ev.key.keysym.sym, (Mods and KMOD_SHIFT) <> 0,
            (Mods and (KMOD_CTRL or KMOD_GUI)) <> 0);
        end;
      SDL_TEXTINPUT:
        FMainForm.HandleTextInput(StrPas(@Ev.text.text[0]));
    end;
    Got := SDL_PollEvent(@Ev) <> 0;
  end;
end;

procedure TApplication.Reload(const NewSource: string);
var
  Root: TPFormNode;
  Err: string;
begin
  Err := '';
  Root := nil;
  try
    Root := ParsePForm(NewSource);
  except
    on E: EPFormError do
      Err := E.Message;
  end;
  if Root <> nil then
  try
    FMainForm.ClearControls;
    try
      BuildForm(FMainForm, Root);
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
      end;
    end;
  finally
    Root.Free;
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
    try
      S.LoadFromFile(FSourcePath);
    except
      Exit;   { the editor may be writing the file right now }
    end;
    if S.Text = FSeenText then
      Exit;
    FSeenText := S.Text;
    Reload(S.Text);
  finally
    S.Free;
  end;
end;

procedure TApplication.RunScript(const FileName: string);
var
  Lines: TStringList;
  I, Failures: Integer;
  Line, Cmd, Arg1, Rest: string;
  C: TControl;

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

  function Ctl(const AName: string): TControl;
  begin
    Result := FMainForm.FindControl(AName);
    if Result = nil then
      Fatal(Format('%s:%d: no control named "%s"', [FileName, I + 1, AName]));
  end;

  function TextOf(Ctrl: TControl): string;
  begin
    if Ctrl is TEdit then Result := TEdit(Ctrl).Text
    else if Ctrl is TLabel then Result := TLabel(Ctrl).Text
    else if Ctrl is TButton then Result := TButton(Ctrl).Text
    else Result := '';
  end;

  function KeyCode(const N: string): LongInt;
  begin
    case LowerCase(N) of
      'enter': Result := KEY_ENTER;
      'tab': Result := KEY_TAB;
      'backspace': Result := KEY_BACKSPACE;
      'delete': Result := KEY_DELETE;
      'left': Result := KEY_LEFT;
      'right': Result := KEY_RIGHT;
      'home': Result := KEY_HOME;
      'end': Result := KEY_END;
      'space': Result := KEY_SPACE;
    else
      Fatal(Format('%s:%d: unknown key "%s"', [FileName, I + 1, N]));
      Result := 0;
    end;
  end;

begin
  Failures := 0;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = '#') then
        Continue;
      { command, first argument, then the rest of the line as is }
      Rest := Line;
      Cmd := LowerCase(TakeWord(Rest));
      Arg1 := TakeWord(Rest);
      Refresh;
      case Cmd of
        'click':
          begin
            C := Ctl(Arg1);
            FMainForm.HandleMouseMove(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2);
            FMainForm.HandleMouseDown(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2);
            FMainForm.HandleMouseUp(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2);
          end;
        'hover':
          begin
            C := Ctl(Arg1);
            FMainForm.HandleMouseMove(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2);
          end;
        'type':
          begin
            C := Ctl(Arg1);
            C.SetFocus;
            FMainForm.HandleTextInput(Rest);
          end;
        'key':
          FMainForm.HandleKeyDown(KeyCode(Arg1), False, False);
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
            C := Ctl(Arg1);
            if TextOf(C) <> Rest then
            begin
              Inc(Failures);
              WriteLn(Format('FAIL line %d: %s is "%s", expected "%s"', [I + 1, Arg1, TextOf(C), Rest]));
            end
            else
              WriteLn(Format('ok: %s = "%s"', [Arg1, Rest]));
          end;
        'print':
          WriteLn(Arg1, ': ', TextOf(Ctl(Arg1)));
        'sleep':
          Sleep(StrToIntDef(Arg1, 100));
        'quit':
          Break;
      else
        Fatal(Format('%s:%d: unknown command "%s"', [FileName, I + 1, Cmd]));
      end;
      Refresh;
      Present;
    end;
  finally
    Lines.Free;
  end;
  if Failures > 0 then
    Halt(1);
end;

procedure TApplication.Run;
var
  Script: string;
  Timeout: Integer;
begin
  if FMainForm = nil then
    Fatal('Application.Run needs a form: call Application.CreateForm first');
  CreateWindow;
  Refresh;
  Present;

  Script := GetEnvironmentVariable('PASTEL_TEST_SCRIPT');
  if Script <> '' then
  begin
    RunScript(Script);
    Exit;
  end;

  FLastBlink := GetTickCount64;
  while not FTerminated do
  begin
    if FSourcePath <> '' then Timeout := 100 else Timeout := 250;
    ProcessEvents(Timeout);
    if FTerminated then
      Break;
    CheckHotReload;
    if (FMainForm.Focused is TEdit) and (GetTickCount64 - FLastBlink >= 530) then
    begin
      FLastBlink := GetTickCount64;
      CaretVisible := not CaretVisible;
      NeedsRepaint := True;
    end;
    if NeedsLayout then
      FMainForm.Layout(FWidth, FHeight);
    if NeedsRepaint then
    begin
      Paint;
      Present;
    end;
    UpdateCursor;
  end;
end;

initialization
  Application := TApplication.Create;

finalization
  FreeAndNil(Application);

end.
