{ Pastel.App on Android: the window is an ANativeWindow drawn in software, the
  mouse is a finger, and the event loop runs on the app thread (see Pastel.Android).
  Included by pastel.app.pas. }

const
  { a finger that moves this far (layout units) scrolls instead of clicking }
  TouchSlop = 12;
  { one wheel step per this many units of finger movement }
  WheelStep = 32;
  LongPressMs = 500;
  DoubleTapMs = 350;

procedure TApplication.AndroidSizeFromWindow;
var
  W, H: Integer;
begin
  if AndroidWindow = nil then
    Exit;
  ANativeWindow_setBuffersGeometry(AndroidWindow, 0, 0, WINDOW_FORMAT_RGBA_8888);
  W := ANativeWindow_getWidth(AndroidWindow);
  H := ANativeWindow_getHeight(AndroidWindow);
  if (W <= 0) or (H <= 0) then
    Exit;
  { the keyboard covers the bottom: the form is laid out in what is left, so the edit stays in sight }
  if (AndroidVisibleBottom > H div 3) and (AndroidVisibleBottom < H) then
    H := AndroidVisibleBottom;
  FWidth := Max(1, Round(W / FScale));
  FHeight := Max(1, Round(H / FScale));
  NeedsLayout := True;
  NeedsRepaint := True;
end;

procedure TApplication.AndroidCreateWindow;
var
  ForcedScale: Single;
begin
  ForcedScale := StrToFloatDef(GetEnv('PASTEL_SCALE'), 0, DefaultFormatSettings);
  if ForcedScale > 0 then
    FScale := ForcedScale
  else
    FScale := Max(0.75, AndroidDensity / 160);
  FMouseScale := FScale;
  if FLanguageFromSystem and (AndroidLanguage <> '') then
    UseLanguage(AndroidLanguage);
  if FMainForm.Appearance = tmSystem then
    UseDarkTheme(AndroidNightMode);
  { wait until Android gives the window }
  while (AndroidWindow = nil) and not AndroidDestroyRequested do
    ProcessEvents(500);
  AndroidSizeFromWindow;
end;

procedure TApplication.AndroidPresent;
var
  Buf: TANativeWindowBuffer;
  X, Y, W, H: Integer;
  Src, Dst: PCardinal;
  P: Cardinal;
begin
  if (AndroidWindow = nil) or (FCanvas.Data = nil) then
    Exit;
  FillChar(Buf, SizeOf(Buf), 0);
  if ANativeWindow_lock(AndroidWindow, Buf, nil) <> 0 then
    Exit;
  try
    { the whole picture every time: the window's buffers take turns }
    W := Min(Buf.width, FCanvas.PixelWidth);
    H := Min(Buf.height, FCanvas.PixelHeight);
    for Y := 0 to H - 1 do
    begin
      Src := PCardinal(FCanvas.Data) + Y * FCanvas.PixelWidth;
      Dst := PCardinal(Buf.bits) + Y * Buf.stride;
      for X := 0 to W - 1 do
      begin
        { $AARRGGBB to the bytes R, G, B, A }
        P := Src[X];
        Dst[X] := (P and $FF00FF00) or ((P shr 16) and $FF) or ((P and $FF) shl 16);
      end;
    end;
  finally
    ANativeWindow_unlockAndPost(AndroidWindow);
  end;
end;

procedure TApplication.AndroidCommand(Cmd: TAndroidCommand);
begin
  case Cmd of
    acWindowCreated, acWindowResized:
      AndroidSizeFromWindow;
    acRedraw:
      begin
        if AndroidWindow <> nil then
        begin
          AndroidSizeFromWindow;
          DoLayout;
          NeedsRepaint := True;
          Paint;
          AndroidPresent;
        end;
      end;
    acResume, acFocusChanged:
      NeedsRepaint := True;
    acConfigChanged:
      begin
        FScale := Max(0.75, AndroidDensity / 160);
        FMouseScale := FScale;
        if FMainForm.Appearance = tmSystem then
          UseDarkTheme(AndroidNightMode);
        AndroidSizeFromWindow;
      end;
    acDestroy:
      FTerminated := True;
    acText:
      begin
        { letters from the on-screen keyboard, in the keyboard's language }
        FMainForm.HandleTextInput(AndroidTakeText);
      end;
  end;
  AndroidCommandDone;
end;

{ the pressed control wants the finger's movement itself (a slider, a splitter...) }
function DragsItself(C: TControl): Boolean;
begin
  Result := (C <> nil) and ((C.ClassName = 'TSlider') or (C.ClassName = 'TSplitter') or
    (C.ClassName = 'TPaintBox') or (C is TCustomEdit));
end;

procedure TApplication.AndroidTouch(Ev: Pointer);
var
  Action, X, Y, Clicks, Steps: Integer;
  NowMs: QWord;
begin
  Action := AMotionEvent_getAction(Ev) and AMOTION_EVENT_ACTION_MASK;
  X := Round(AMotionEvent_getX(Ev, 0) / FMouseScale);
  Y := Round(AMotionEvent_getY(Ev, 0) / FMouseScale);
  NowMs := GetTickCount64;
  case Action of
    AMOTION_EVENT_ACTION_DOWN:
      begin
        FFlingActive := False;     { a finger stops a flinging list }
        FTouchDown := True;
        FTouchScrolling := False;
        FLongPressDone := False;
        FTouchStartX := X;
        FTouchStartY := Y;
        FTouchX := X;
        FTouchY := Y;
        FScrollFromY := Y;
        FTouchTime := NowMs;
        Clicks := 1;
        if (NowMs - FLastTapTime < DoubleTapMs) and (Abs(X - FLastTapX) < 24) and (Abs(Y - FLastTapY) < 24) then
          Clicks := 2;
        FMainForm.HandleMouseMove(X, Y);
        FMainForm.HandleMouseDown(X, Y, 1, Clicks);
      end;
    AMOTION_EVENT_ACTION_MOVE:
      begin
        if not FTouchDown then
          Exit;
        FTouchX := X;
        FTouchY := Y;
        if not FTouchScrolling and not FLongPressDone and (Abs(Y - FTouchStartY) > TouchSlop) and
           (Abs(Y - FTouchStartY) > Abs(X - FTouchStartX)) and not DragsItself(FMainForm.Captured) then
        begin
          { a scroll, not a click: the press is let go somewhere else }
          FTouchScrolling := True;
          FMainForm.HandleMouseUp(-10000, -10000, 1);
          FMainForm.HandleMouseMove(FTouchStartX, FTouchStartY);
          FScrollFromY := Y;
          FFlingV := 0;
          FSampleY := Y;
          FSampleTime := NowMs;
        end;
        if FTouchScrolling then
        begin
          { the finger's speed, for flinging when it leaves }
          if NowMs > FSampleTime then
          begin
            FFlingV := 0.6 * FFlingV + 0.4 * ((Y - FSampleY) / (NowMs - FSampleTime));
            FSampleY := Y;
            FSampleTime := NowMs;
          end;
          Steps := (Y - FScrollFromY) div WheelStep;
          if Steps <> 0 then
          begin
            FMainForm.HandleMouseWheel(0, Steps);
            Inc(FScrollFromY, Steps * WheelStep);
          end;
        end
        else
          FMainForm.HandleMouseMove(X, Y);
      end;
    AMOTION_EVENT_ACTION_UP:
      begin
        if FTouchDown and not FTouchScrolling and not FLongPressDone then
        begin
          FMainForm.HandleMouseUp(X, Y, 1);
          FLastTapTime := NowMs;
          FLastTapX := X;
          FLastTapY := Y;
        end;
        { a quick swipe goes on: the list keeps moving after the finger }
        if FTouchScrolling and (NowMs - FSampleTime < 80) and (Abs(FFlingV) > 0.3) then
        begin
          FFlingActive := True;
          FFlingAccum := 0;
          FFlingLast := NowMs;
          FFlingX := FTouchStartX;
          FFlingY := FTouchStartY;
          FFlingV := EnsureRange(FFlingV, -6, 6);
        end;
        FTouchDown := False;
        { no mouse rests over anything on a touch screen }
        if not FFlingActive then
          FMainForm.HandleMouseLeave;
      end;
    AMOTION_EVENT_ACTION_CANCEL:
      begin
        if FTouchDown and not FTouchScrolling then
          FMainForm.HandleMouseUp(-10000, -10000, 1);
        FTouchDown := False;
        FMainForm.HandleMouseLeave;
      end;
  end;
end;

{ one step of a fling: as far as the speed goes since the last step; the speed fades like Android's lists }
procedure TApplication.AndroidFling;
var
  NowMs: QWord;
  Dt: Double;
  Steps: Integer;
begin
  if not FFlingActive then
    Exit;
  NowMs := GetTickCount64;
  Dt := NowMs - FFlingLast;
  if Dt <= 0 then
    Exit;
  FFlingLast := NowMs;
  FFlingAccum := FFlingAccum + FFlingV * Dt;
  Steps := Trunc(FFlingAccum / WheelStep);
  if Steps <> 0 then
  begin
    FMainForm.HandleMouseMove(FFlingX, FFlingY);
    FMainForm.HandleMouseWheel(0, Steps);
    FFlingAccum := FFlingAccum - Steps * WheelStep;
  end;
  FFlingV := FFlingV * Exp(-Dt / 325);
  if Abs(FFlingV) < 0.05 then
  begin
    FFlingActive := False;
    FMainForm.HandleMouseLeave;
  end;
end;

{ a finger held still: a right click (a popup menu) }
procedure TApplication.AndroidLongPress;
begin
  if not FTouchDown or FTouchScrolling or FLongPressDone then
    Exit;
  if (GetTickCount64 - FTouchTime < LongPressMs) or (Abs(FTouchX - FTouchStartX) > TouchSlop) or
     (Abs(FTouchY - FTouchStartY) > TouchSlop) then
    Exit;
  FLongPressDone := True;
  FMainForm.HandleMouseUp(-10000, -10000, 1);
  FMainForm.HandleMouseDown(FTouchX, FTouchY, 3, 1);
  FMainForm.HandleMouseUp(FTouchX, FTouchY, 3);
end;

{ Android key codes to Pastel's (the same as SDL's); characters as text }
function TApplication.AndroidKey(Ev: Pointer): Boolean;
const
  Letters = 'abcdefghijklmnopqrstuvwxyz';
var
  Action, Code, Meta, K: Integer;
  Shift, Ctrl: Boolean;
  Ch: string;
begin
  Result := True;
  Action := AKeyEvent_getAction(Ev);
  Code := AKeyEvent_getKeyCode(Ev);
  Meta := AKeyEvent_getMetaState(Ev);
  Shift := (Meta and AMETA_SHIFT_ON) <> 0;
  Ctrl := (Meta and AMETA_CTRL_ON) <> 0;
  { the back button: closes the dialog or menu on top, else the app }
  if Code = 4 then
  begin
    if Action = AKEY_EVENT_ACTION_UP then
    begin
      if FMainForm.PopupCount > 0 then
        FMainForm.HandleKeyDown(KEY_ESCAPE, False, False)
      else
        CloseRequested := True;
    end;
    Exit;
  end;
  if Action <> AKEY_EVENT_ACTION_DOWN then
    Exit;
  K := 0;
  case Code of
    67: K := KEY_BACKSPACE;
    112: K := KEY_DELETE;
    66, 160: K := KEY_ENTER;
    19: K := KEY_UP;
    20: K := KEY_DOWN;
    21: K := KEY_LEFT;
    22: K := KEY_RIGHT;
    61: K := KEY_TAB;
    111: K := KEY_ESCAPE;
    122: K := KEY_HOME;
    123: K := KEY_END;
    92: K := KEY_PAGEUP;
    93: K := KEY_PAGEDOWN;
  end;
  if K <> 0 then
  begin
    FMainForm.ShiftDown := Shift;
    FMainForm.HandleKeyDown(K, Shift, Ctrl);
    FMainForm.ShiftDown := False;
    Exit;
  end;
  Ch := '';
  case Code of
    29..54:
      begin
        Ch := Letters[Code - 28];
        if Ctrl then
        begin
          FMainForm.HandleKeyDown(Ord(Ch[1]), Shift, True);
          Exit;
        end;
        if Shift then
          Ch := UpperCase(Ch);
      end;
    7..16: Ch := Chr(Ord('0') + Code - 7);
    17: Ch := '*';
    18: Ch := '#';
    55: Ch := ',';
    56: Ch := '.';
    62: Ch := ' ';
    68: Ch := '`';
    69: Ch := '-';
    70: Ch := '=';
    71: Ch := '[';
    72: Ch := ']';
    73: Ch := '\';
    74: Ch := ';';
    75: Ch := '''';
    76: Ch := '/';
    77: Ch := '@';
    81: Ch := '+';
  else
    Exit(False);     { not ours: Android handles it (the volume keys...) }
  end;
  FMainForm.HandleTextInput(Ch);
end;

procedure TApplication.AndroidInputEvents;
var
  Ev: Pointer;
  Handled: Boolean;
begin
  if AndroidInput = nil then
    Exit;
  while AInputQueue_getEvent(AndroidInput, Ev) >= 0 do
  begin
    if AInputQueue_preDispatchEvent(AndroidInput, Ev) <> 0 then
      Continue;     { the on-screen keyboard took it }
    Handled := True;
    case AInputEvent_getType(Ev) of
      AINPUT_EVENT_TYPE_MOTION: AndroidTouch(Ev);
      AINPUT_EVENT_TYPE_KEY: Handled := AndroidKey(Ev);
    end;
    AInputQueue_finishEvent(AndroidInput, Ev, Ord(Handled));
    if AndroidInput = nil then
      Break;
  end;
end;

procedure TApplication.AndroidProcessEvents(Timeout: Integer);
var
  Id: Integer;
begin
  if FTouchDown then
    Timeout := Min(Timeout, 50);
  if FFlingActive then
    Timeout := Min(Timeout, 16);
  Id := ALooper_pollOnce(Timeout, nil, nil, nil);
  while Id >= 0 do
  begin
    case Id of
      LooperIdMain: AndroidCommand(AndroidTakeCommand);
      LooperIdInput: AndroidInputEvents;
    end;
    if FTerminated then
      Break;
    Id := ALooper_pollOnce(0, nil, nil, nil);
  end;
  AndroidLongPress;
  AndroidFling;
end;

{ the on-screen keyboard comes up for an edit and goes when the focus leaves it }
procedure TApplication.AndroidKeyboard;
var
  Wanted: Boolean;
begin
  if AndroidActivity = nil then
    Exit;
  Wanted := FMainForm.Focused is TCustomEdit;
  if Wanted = FKeyboardShown then
    Exit;
  FKeyboardShown := Wanted;
  if Wanted then
    ANativeActivity_showSoftInput(AndroidActivity, 2)
  else
    ANativeActivity_hideSoftInput(AndroidActivity, 0);
end;

procedure AndroidRunApp;
begin
  Application.AndroidRun;
end;

{ the app's event loop, on the app thread }
procedure TApplication.AndroidRun;
begin
  CreateWindow;
  ModalStep := @AppModalStep;
  WakeMainThread := @WakeUp;
  if AndroidWindow <> nil then
  begin
    Refresh;
    Present;
  end;
  FLastBlink := GetTickCount64;
  while not FTerminated do
    Step;
end;
