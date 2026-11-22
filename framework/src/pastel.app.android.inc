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
  { the system's bars over the window (apps drawn behind them, Android 15): the form goes between }
  FInsetX := Min(AndroidInsetLeft, W div 3);
  FInsetY := Min(AndroidInsetTop, H div 3);
  W := W - FInsetX - Min(AndroidInsetRight, W div 3);
  if (AndroidInsetBottom > 0) and (AndroidInsetBottom < ANativeWindow_getHeight(AndroidWindow) * 2 div 3) then
    H := Min(H, ANativeWindow_getHeight(AndroidWindow) - AndroidInsetBottom);
  H := H - FInsetY;
  if (W <= 0) or (H <= 0) then
    Exit;
  FWidth := Max(1, Round(W / FScale));
  FHeight := Max(1, Round(H / FScale));
  NeedsLayout := True;
  NeedsRepaint := True;
end;

procedure TApplication.AndroidCreateWindow;
var
  ForcedScale: Single;
begin
  ForcedScale := StrToFloatDef(GetEnv('PASTEL_SCALE'), 0, InvariantFormat);
  if ForcedScale > 0 then
    FScale := ForcedScale
  else
    FScale := Max(0.75, AndroidDensity / 160);
  FMouseScale := FScale;
  { a TV is used with a remote: its arrows move from control to control; the text size of the settings }
  FIsTV := AndroidIsTV;
  ArrowKeysMoveFocus := True;
  TextScale := Min(1.3, AndroidFontScale);
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
    { the whole picture every time: the window's buffers take turns; what the
      system's bars cover gets the form's color }
    if (FInsetX > 0) or (FInsetY > 0) or (Buf.height > FCanvas.PixelHeight) or (Buf.width > FCanvas.PixelWidth) then
    begin
      P := Theme.Background;
      P := (P and $FF00FF00) or ((P shr 16) and $FF) or ((P and $FF) shl 16);
      for Y := 0 to Buf.height - 1 do
      begin
        Dst := PCardinal(Buf.bits) + Y * Buf.stride;
        for X := 0 to Buf.width - 1 do
          Dst[X] := P;
      end;
    end;
    W := Min(Buf.width - FInsetX, FCanvas.PixelWidth);
    H := Min(Buf.height - FInsetY, FCanvas.PixelHeight);
    for Y := 0 to H - 1 do
    begin
      Src := PCardinal(FCanvas.Data) + Y * FCanvas.PixelWidth;
      Dst := PCardinal(Buf.bits) + (Y + FInsetY) * Buf.stride + FInsetX;
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
var
  Code: Integer;
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
    acPause:
      { what the user did, kept by Android in case it stops the app in the background }
      if FMainForm <> nil then
      begin
        EnterCriticalSection(StateLock);
        try
          AndroidSavedState := FormStateText(FMainForm);
        finally
          LeaveCriticalSection(StateLock);
        end;
      end;
    acConfigChanged:
      begin
        FScale := Max(0.75, AndroidDensity / 160);
        FMouseScale := FScale;
        TextScale := Min(1.3, AndroidFontScale);
        NeedsLayout := True;
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
    acEdit:
      AndroidImeEdit;
    acKey:
      { the keys that edit: Backspace, Delete, Enter (Done, Search...), Tab (Next); Back (Android 13+) }
      for Code in AndroidTakeKeys do
        case Code of
          4: AndroidKey(AKEY_EVENT_ACTION_UP, 4, 0);
          67: FMainForm.HandleKeyDown(KEY_BACKSPACE, False, False);
          112: FMainForm.HandleKeyDown(KEY_DELETE, False, False);
          66, 160: FMainForm.HandleKeyDown(KEY_ENTER, False, False);
          61: FMainForm.HandleKeyDown(KEY_TAB, False, False);
          21: FMainForm.HandleKeyDown(KEY_LEFT, False, False);
          22: FMainForm.HandleKeyDown(KEY_RIGHT, False, False);
        end;
  end;
  AndroidCommandDone;
end;

{ the pressed control wants the finger's movement itself (a slider, a splitter...) }
function DragsItself(C: TControl; X, Y: Integer): Boolean;
begin
  Result := (C <> nil) and ((C.ClassName = 'TSlider') or (C.ClassName = 'TSplitter') or
    (C.ClassName = 'TPaintBox') or (C is TCustomEdit) or C.DragsAt(X, Y));
end;

procedure TApplication.AndroidTouch(Action: Integer; RawX, RawY: Single);
var
  X, Y, Clicks, Steps: Integer;
  NowMs: QWord;
begin
  X := Round((RawX - FInsetX) / FMouseScale);
  Y := Round((RawY - FInsetY) / FMouseScale);
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
           (Abs(Y - FTouchStartY) > Abs(X - FTouchStartX)) and not DragsItself(FMainForm.Captured, FTouchStartX, FTouchStartY) then
        begin
          { a scroll, not a click: the press is let go somewhere else }
          FTouchScrolling := True;
          WheelFromTouch := True;      { a list may be pulled down to refresh }
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
          { a tap on an edit brings the keyboard back (the back button may have closed it) }
          if FMainForm.Focused is TCustomEdit then
            FKeyboardShown := False;
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
        WheelFromTouch := False;
        { no mouse rests over anything on a touch screen }
        if not FFlingActive then
          FMainForm.HandleMouseLeave;
      end;
    AMOTION_EVENT_ACTION_CANCEL:
      begin
        if FTouchDown and not FTouchScrolling then
          FMainForm.HandleMouseUp(-10000, -10000, 1);
        FTouchDown := False;
        WheelFromTouch := False;
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
  { a finger held on an edit's text: the word there is selected first, as on any phone }
  if (FMainForm.HitTest(FTouchX, FTouchY) is TCustomEdit) and
    (TCustomEdit(FMainForm.HitTest(FTouchX, FTouchY)).SelLength = 0) then
  begin
    FMainForm.HandleMouseDown(FTouchX, FTouchY, 1, 2);
    FMainForm.HandleMouseUp(FTouchX, FTouchY, 1);
  end;
  FMainForm.HandleMouseDown(FTouchX, FTouchY, 3, 1);
  FMainForm.HandleMouseUp(FTouchX, FTouchY, 3);
end;

{ Android key codes to Pastel's (the same as SDL's); characters as text }
function TApplication.AndroidKey(Action, Code, Meta: Integer): Boolean;
const
  Letters = 'abcdefghijklmnopqrstuvwxyz';
var
  K: Integer;
  Shift, Ctrl: Boolean;
  Ch: string;
begin
  Result := True;
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
  { the remote's OK button (and a game pad's A): presses, ticks, opens; on an edit, the keyboard }
  if (Code = 23) or (Code = 96) then
  begin
    if FMainForm.Focused is TCustomEdit then
      FKeyboardShown := False
    else
      FMainForm.ActivateFocused;
    Exit;
  end;
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

{ True for the keys Pastel handles; the others (volume...) are Android's }
function AndroidKeyIsOurs(Action, Code: Integer): Boolean;
begin
  if (Code = 4) or (Action <> AKEY_EVENT_ACTION_DOWN) then
    Exit(True);
  case Code of
    7..56, 61, 62, 66..77, 81, 92, 93, 96, 111, 112, 122, 123, 160:
      Result := True;
  else
    Result := False;
  end;
end;

{ Every event is read and given back to Android first, then handled: a handler
  may show a dialog (ShowModal, ShowMessage) that waits for more events, and
  Android says "not responding" when an event is not given back in 5 seconds. }
{ two fingers: a pinch or a turn for the control under them }
procedure TApplication.AndroidPinch(Action, Count: Integer; X0, Y0, X1, Y1: Single);
var
  G: TGestureInfo;
  D, A: Single;
begin
  D := Max(1, Sqrt(Sqr(X1 - X0) + Sqr(Y1 - Y0)));
  A := ArcTan2(Y1 - Y0, X1 - X0);
  G.X := Round(((X0 + X1) / 2 - FInsetX) / FMouseScale);
  G.Y := Round(((Y0 + Y1) / 2 - FInsetY) / FMouseScale);
  G.Scale := 1;
  G.Rotation := 0;
  if (Count >= 2) and not FPinching and (Action <> AMOTION_EVENT_ACTION_UP) then
  begin
    { the second finger: the first one's press is no click }
    if FTouchDown then
      FMainForm.HandleMouseUp(-10000, -10000, 1);
    FTouchDown := False;
    FTouchScrolling := False;
    FFlingActive := False;
    FPinching := True;
    FPinchDone := True;
    FPinchDist := D;
    FPinchAngle := A;
    G.State := gsBegin;
    FMainForm.HandleGesture(G);
    Exit;
  end;
  if FPinching and (Count >= 2) and (Action = AMOTION_EVENT_ACTION_MOVE) then
  begin
    G.State := gsUpdate;
    G.Scale := D / FPinchDist;
    G.Rotation := A - FPinchAngle;
    if G.Rotation > Pi then G.Rotation := G.Rotation - 2 * Pi;
    if G.Rotation < -Pi then G.Rotation := G.Rotation + 2 * Pi;
    FPinchDist := D;
    FPinchAngle := A;
    if (Abs(G.Scale - 1) > 0.002) or (Abs(G.Rotation) > 0.002) then
      FMainForm.HandleGesture(G);
    Exit;
  end;
  if FPinching and ((Action = 6 { POINTER_UP }) or (Action = AMOTION_EVENT_ACTION_UP) or
     (Action = AMOTION_EVENT_ACTION_CANCEL)) then
  begin
    FPinching := False;
    G.State := gsEnd;
    FMainForm.HandleGesture(G);
  end;
  { the last finger of a pinch leaves: no click, no scroll }
  if Action in [AMOTION_EVENT_ACTION_UP, AMOTION_EVENT_ACTION_CANCEL] then
    FPinchDone := False;
end;

{ TalkBack (or another screen reader) on: what is on the screen goes to Android
  when it changed; its actions (a double tap: click) come back }
procedure TApplication.AndroidAccessibility(NowMs: QWord);
var
  T: string;
  Id, Action: Integer;
begin
  while AndroidTakeAccessAction(Id, Action) do
    AccessibilityAction(FMainForm, Id, Action);
  if (NowMs >= FAccessCheck) or (FAccessCheck = 0) then
  begin
    FAccessCheck := NowMs + 2000;
    FAccessOn := AndroidCallString('accessOn', '()Ljava/lang/String;', []) <> '';
    if not FAccessOn then
      FAccessTree := '';
  end;
  if not FAccessOn then
    Exit;
  T := AccessibilityTree(FMainForm, @AppPixelRect);
  if T <> FAccessTree then
  begin
    FAccessTree := T;
    AndroidCall('accessTree', '(Ljava/lang/String;)V', [T]);
  end;
end;

procedure TApplication.AndroidInputEvents;
var
  Ev: Pointer;
  Kind, Action, Code, Meta: Integer;
  RawX, RawY, RawX2, RawY2: Single;
  Count: PtrUInt;
begin
  if AndroidInput = nil then
    Exit;
  while AInputQueue_getEvent(AndroidInput, Ev) >= 0 do
  begin
    if AInputQueue_preDispatchEvent(AndroidInput, Ev) <> 0 then
      Continue;     { the on-screen keyboard took it }
    Kind := AInputEvent_getType(Ev);
    Action := 0; Code := 0; Meta := 0; RawX := 0; RawY := 0; RawX2 := 0; RawY2 := 0; Count := 1;
    case Kind of
      AINPUT_EVENT_TYPE_MOTION:
        begin
          Action := AMotionEvent_getAction(Ev) and AMOTION_EVENT_ACTION_MASK;
          RawX := AMotionEvent_getX(Ev, 0);
          RawY := AMotionEvent_getY(Ev, 0);
          Count := AMotionEvent_getPointerCount(Ev);
          if Count >= 2 then
          begin
            RawX2 := AMotionEvent_getX(Ev, 1);
            RawY2 := AMotionEvent_getY(Ev, 1);
          end;
          AInputQueue_finishEvent(AndroidInput, Ev, 1);
          if (Count >= 2) or FPinching or FPinchDone then
            AndroidPinch(Action, Count, RawX, RawY, RawX2, RawY2)
          else
            AndroidTouch(Action, RawX, RawY);
        end;
      AINPUT_EVENT_TYPE_KEY:
        begin
          Action := AKeyEvent_getAction(Ev);
          Code := AKeyEvent_getKeyCode(Ev);
          Meta := AKeyEvent_getMetaState(Ev);
          AInputQueue_finishEvent(AndroidInput, Ev, Ord(AndroidKeyIsOurs(Action, Code)));
          if AndroidKeyIsOurs(Action, Code) then
            AndroidKey(Action, Code, Meta);
        end;
    else
      AInputQueue_finishEvent(AndroidInput, Ev, 0);
    end;
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

{ Android's EditorInfo for an edit: which keyboard (inputType) and what its Enter key does (imeOptions) }
procedure KeyboardFor(E: TCustomEdit; out InputType, ImeOptions: Integer);
const
  TYPE_CLASS_TEXT = 1;
  TYPE_CLASS_NUMBER = 2;
  TYPE_CLASS_PHONE = 3;
  TYPE_CLASS_DATETIME = 4;
  TYPE_NUMBER_FLAG_SIGNED = $1000;
  TYPE_NUMBER_FLAG_DECIMAL = $2000;
  TYPE_NUMBER_VARIATION_PASSWORD = $10;
  TYPE_TEXT_FLAG_CAP_SENTENCES = $4000;
  TYPE_TEXT_FLAG_MULTI_LINE = $20000;
  TYPE_TEXT_VARIATION_URI = $10;
  TYPE_TEXT_VARIATION_EMAIL_ADDRESS = $20;
  TYPE_TEXT_VARIATION_PASSWORD = $80;
  TYPE_DATETIME_VARIATION_TIME = $20;
  IME_ACTION_GO = 2;
  IME_ACTION_SEARCH = 3;
  IME_ACTION_SEND = 4;
  IME_ACTION_NEXT = 5;
  IME_ACTION_DONE = 6;
  IME_FLAG_NO_ENTER_ACTION = $40000000;
begin
  case E.KeyboardKind of
    ktNumber: InputType := TYPE_CLASS_NUMBER or TYPE_NUMBER_FLAG_SIGNED;
    ktDecimal: InputType := TYPE_CLASS_NUMBER or TYPE_NUMBER_FLAG_SIGNED or TYPE_NUMBER_FLAG_DECIMAL;
    ktPhone: InputType := TYPE_CLASS_PHONE;
    ktEmail: InputType := TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_EMAIL_ADDRESS;
    ktUrl: InputType := TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_URI;
    ktTime: InputType := TYPE_CLASS_DATETIME or TYPE_DATETIME_VARIATION_TIME;
  else
    InputType := TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_CAP_SENTENCES;
  end;
  if E.IsPassword then
  begin
    if (InputType and $F) = TYPE_CLASS_NUMBER then
      InputType := TYPE_CLASS_NUMBER or TYPE_NUMBER_VARIATION_PASSWORD
    else
      InputType := TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_PASSWORD;
  end;
  if E.MultiLine then
  begin
    { Enter makes a new line }
    InputType := InputType or TYPE_TEXT_FLAG_MULTI_LINE;
    ImeOptions := IME_FLAG_NO_ENTER_ACTION;
    Exit;
  end;
  case E.ReturnKeyType of
    rkGo: ImeOptions := IME_ACTION_GO;
    rkNext: ImeOptions := IME_ACTION_NEXT;
    rkSearch: ImeOptions := IME_ACTION_SEARCH;
    rkSend: ImeOptions := IME_ACTION_SEND;
  else
    ImeOptions := IME_ACTION_DONE;
  end;
end;

{ the keyboard's copy gets the edit's state as it is now }
procedure TApplication.AndroidImeRemember(E: TCustomEdit);
begin
  FImeText := E.Text;
  FImeSelStart := E.SelStart;
  FImeSelEnd := E.SelStart + E.SelLength;
end;

{ the phone's keyboard changed its copy: the edit takes the change (through its own rules) }
procedure TApplication.AndroidImeEdit;
var
  Ed: TAndroidEdit;
  E: TCustomEdit;
  CS, CE: Integer;
begin
  if not AndroidTakeEdit(Ed) then
    Exit;
  if not (FKeyboardEdit is TCustomEdit) or not FKeyboardShown or (Ed.Gen <> FImeGen) then
    Exit;       { made from an older state of ours: that one was replaced already }
  E := TCustomEdit(FKeyboardEdit);
  CS := -1;
  CE := -1;
  if Ed.ComposeStart >= 0 then
  begin
    CS := Utf16ToByteIndex(Ed.Text, Ed.ComposeStart);
    CE := Utf16ToByteIndex(Ed.Text, Ed.ComposeEnd);
  end;
  E.ImeChange(Ed.Text, Utf16ToByteIndex(Ed.Text, Ed.SelStart), Utf16ToByteIndex(Ed.Text, Ed.SelEnd), CS, CE);
  AndroidImeRemember(E);
  if E.Text <> Ed.Text then
  begin
    { the edit did not take all of it (MaxLength, a mask): the copy is put right }
    Inc(FImeGen);
    AndroidEditSync(E.Text, ByteToUtf16Index(E.Text, FImeSelStart), ByteToUtf16Index(E.Text, FImeSelEnd), FImeGen);
  end;
end;

{ the on-screen keyboard comes up for an edit (the kind it needs, a copy of its text)
  and goes when the focus leaves it; what Pascal changes in it goes to the copy }
procedure TApplication.AndroidKeyboard;
var
  Edit: TControl;
  E: TCustomEdit;
  InputType, ImeOptions: Integer;
begin
  if AndroidActivity = nil then
    Exit;
  Edit := nil;
  if (FMainForm.Focused is TCustomEdit) and not TCustomEdit(FMainForm.Focused).ReadOnly and
     TCustomEdit(FMainForm.Focused).WantsKeyboard then
    Edit := FMainForm.Focused;
  if (Edit = FKeyboardEdit) and (FKeyboardShown = (Edit <> nil)) then
  begin
    if Edit = nil then
      Exit;
    E := TCustomEdit(Edit);
    if (E.Text <> FImeText) or (E.SelStart <> FImeSelStart) or (E.SelStart + E.SelLength <> FImeSelEnd) then
    begin
      AndroidImeRemember(E);
      Inc(FImeGen);
      AndroidEditSync(FImeText, ByteToUtf16Index(FImeText, FImeSelStart), ByteToUtf16Index(FImeText, FImeSelEnd), FImeGen);
    end;
    Exit;
  end;
  FKeyboardEdit := Edit;
  FKeyboardShown := Edit <> nil;
  if Edit <> nil then
  begin
    E := TCustomEdit(Edit);
    KeyboardFor(E, InputType, ImeOptions);
    AndroidImeRemember(E);
    Inc(FImeGen);
    AndroidEditStart(InputType, ImeOptions, FImeText, ByteToUtf16Index(FImeText, FImeSelStart),
      ByteToUtf16Index(FImeText, FImeSelEnd), FImeGen);
  end
  else
    AndroidHideKeyboard;
end;

procedure AndroidRunApp;
begin
  Application.AndroidRun;
end;

{ the app's event loop, on the app thread }
procedure TApplication.AndroidRun;
begin
  { the app's thread is its main thread: Java's main thread only hands on the
    system's events. TThread.Synchronize, Queue and CheckSynchronize (timers,
    workers) need to know that, or they stop the app ("CheckSynchronize called
    from non-main thread"). }
  MainThreadID := GetCurrentThreadID;
  { copy and paste in edits: the phone's clipboard }
  ClipboardGetText := @AndroidClipboardText;
  ClipboardSetText := @AndroidSetClipboardText;
  CreateWindow;
  ModalStep := @AppModalStep;
  WindowPixelRect := @AppPixelRect;
  WakeMainThread := @WakeUp;
  if AndroidWindow <> nil then
  begin
    Refresh;
    Present;
  end;
  FLastBlink := GetTickCount64;
  while not FTerminated do
    SafeStep;
end;
