{ Pastel - the bridge to Android: an app is a NativeActivity, so it needs no
  Java code. Android calls ANativeActivity_onCreate (exported by the app's
  libmain.so); Pastel then runs the app on a thread of its own, which gets the
  window, the touches and the keys from here.

  The calls from Android (window made, app paused, input...) arrive on Android's
  main thread; they are passed to the app thread through a pipe, and the ones
  that change the window or the input queue wait until the app thread has taken
  them (like android_native_app_glue of the NDK, written in Pascal).

  Part of the Pastel project, MIT License. }
unit Pastel.Android;

{$mode objfpc}{$H+}
{$packrecords c}

interface

{$IFDEF ANDROID}
uses
  cthreads, BaseUnix, Unix, SysUtils;

type
  PANativeActivity = ^TANativeActivity;
  TANativeActivity = record
    callbacks: Pointer;
    vm, env, clazz: Pointer;
    internalDataPath, externalDataPath: PChar;
    sdkVersion: LongInt;
    instance: Pointer;
    assetManager: Pointer;
    obbPath: PChar;
  end;

  TANativeWindowBuffer = record
    width, height, stride, format: LongInt;
    bits: Pointer;
    reserved: array[0..5] of LongWord;
  end;

  TIntegerArray = array of Integer;

  TAndroidCommand = (acNone, acInputChanged, acWindowCreated, acWindowDestroyed, acWindowResized,
    acRedraw, acResume, acPause, acConfigChanged, acFocusChanged, acDestroy, acWake, acText, acKey);

const
  LooperIdMain = 1;
  LooperIdInput = 2;
  { AInputEvent types and actions }
  AINPUT_EVENT_TYPE_KEY = 1;
  AINPUT_EVENT_TYPE_MOTION = 2;
  AKEY_EVENT_ACTION_DOWN = 0;
  AKEY_EVENT_ACTION_UP = 1;
  AMOTION_EVENT_ACTION_MASK = $FF;
  AMOTION_EVENT_ACTION_DOWN = 0;
  AMOTION_EVENT_ACTION_UP = 1;
  AMOTION_EVENT_ACTION_MOVE = 2;
  AMOTION_EVENT_ACTION_CANCEL = 3;
  AMETA_SHIFT_ON = 1;
  AMETA_CTRL_ON = $1000;
  WINDOW_FORMAT_RGBA_8888 = 1;
  AWINDOW_FLAG_KEEP_SCREEN_ON = $80;

{ NDK functions (libandroid.so, liblog.so) }
function ANativeWindow_setBuffersGeometry(Window: Pointer; Width, Height, Format: LongInt): LongInt; cdecl; external 'android';
function ANativeWindow_getWidth(Window: Pointer): LongInt; cdecl; external 'android';
function ANativeWindow_getHeight(Window: Pointer): LongInt; cdecl; external 'android';
function ANativeWindow_lock(Window: Pointer; var Buffer: TANativeWindowBuffer; DirtyBounds: Pointer): LongInt; cdecl; external 'android';
function ANativeWindow_unlockAndPost(Window: Pointer): LongInt; cdecl; external 'android';
function ALooper_prepare(Opts: LongInt): Pointer; cdecl; external 'android';
function ALooper_addFd(Looper: Pointer; Fd, Ident, Events: LongInt; Callback, Data: Pointer): LongInt; cdecl; external 'android';
function ALooper_pollOnce(TimeoutMillis: LongInt; OutFd, OutEvents: PLongInt; OutData: PPointer): LongInt; cdecl; external 'android';
procedure AInputQueue_attachLooper(Queue, Looper: Pointer; Ident: LongInt; Callback, Data: Pointer); cdecl; external 'android';
procedure AInputQueue_detachLooper(Queue: Pointer); cdecl; external 'android';
function AInputQueue_getEvent(Queue: Pointer; out Event: Pointer): LongInt; cdecl; external 'android';
function AInputQueue_preDispatchEvent(Queue, Event: Pointer): LongInt; cdecl; external 'android';
procedure AInputQueue_finishEvent(Queue, Event: Pointer; Handled: LongInt); cdecl; external 'android';
function AInputEvent_getType(Event: Pointer): LongInt; cdecl; external 'android';
function AMotionEvent_getAction(Event: Pointer): LongInt; cdecl; external 'android';
function AMotionEvent_getX(Event: Pointer; PointerIndex: PtrUInt): Single; cdecl; external 'android';
function AMotionEvent_getY(Event: Pointer; PointerIndex: PtrUInt): Single; cdecl; external 'android';
function AMotionEvent_getPointerCount(Event: Pointer): PtrUInt; cdecl; external 'android';
function AKeyEvent_getAction(Event: Pointer): LongInt; cdecl; external 'android';
function AKeyEvent_getKeyCode(Event: Pointer): LongInt; cdecl; external 'android';
function AKeyEvent_getMetaState(Event: Pointer): LongInt; cdecl; external 'android';
procedure ANativeActivity_finish(Activity: PANativeActivity); cdecl; external 'android';
procedure ANativeActivity_showSoftInput(Activity: PANativeActivity; Flags: LongWord); cdecl; external 'android';
procedure ANativeActivity_hideSoftInput(Activity: PANativeActivity; Flags: LongWord); cdecl; external 'android';
procedure ANativeActivity_setWindowFlags(Activity: PANativeActivity; AddFlags, RemoveFlags: LongWord); cdecl; external 'android';
function AConfiguration_new: Pointer; cdecl; external 'android';
procedure AConfiguration_delete(Config: Pointer); cdecl; external 'android';
procedure AConfiguration_fromAssetManager(Config, AssetManager: Pointer); cdecl; external 'android';
function AConfiguration_getDensity(Config: Pointer): LongInt; cdecl; external 'android';
function AConfiguration_getUiModeNight(Config: Pointer): LongInt; cdecl; external 'android';
function AConfiguration_getUiModeType(Config: Pointer): LongInt; cdecl; external 'android';
procedure AConfiguration_getLanguage(Config: Pointer; OutLanguage: PChar); cdecl; external 'android';
function __android_log_write(Prio: LongInt; Tag, Text: PChar): LongInt; cdecl; external 'log';

{ Android calls this when the app starts (exported by the app's libmain.so). }
procedure ANativeActivity_onCreate(Activity: PANativeActivity; SavedState: Pointer; SavedStateSize: PtrUInt); cdecl;

{ Text typed on the on-screen keyboard, from Pastel's Java activity (dev.pastel.PastelActivity);
  exported by the app's libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeText(Env: Pointer; Cls: Pointer; Text: Pointer); cdecl;
{ The app thread: the text typed since the last acText. }
function AndroidTakeText: string;
{ Keys from the on-screen keyboard (Backspace, Enter, Tab: Android's key codes); exported by libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeKey(Env: Pointer; Cls: Pointer; KeyCode: LongInt); cdecl;
{ The app thread: the key codes since the last acKey. }
function AndroidTakeKeys: TIntegerArray;
{ The app thread: the on-screen keyboard for an edit; InputType and ImeOptions
  are Android's (EditorInfo): which keyboard, and what its Enter key does. }
procedure AndroidShowKeyboard(InputType, ImeOptions: Integer);
procedure AndroidHideKeyboard;

{ A line in the device log (adb logcat -s pastel). }
procedure AndroidLog(const Msg: string);
{ The app thread: takes the commands waiting in the pipe. }
function AndroidTakeCommand: TAndroidCommand;
{ The app thread: the command was handled (the main thread may go on). }
procedure AndroidCommandDone;
{ From any thread: the app thread's poll returns (TThread.Queue has work). }
procedure AndroidWake;

{ The screen's density in dots per inch (160: one pixel per layout unit). }
function AndroidDensity: Integer;
{ True when the phone is set to dark colors. }
function AndroidNightMode: Boolean;
{ The phone's language: 'tr', 'en'... }
function AndroidLanguage: string;
{ The device is a TV (Android TV, most TV boxes): used with a remote, seen from afar. }
function AndroidIsTV: Boolean;
{ The size of text the user chose in the phone's settings (1: normal, 1.3: large). }
function AndroidFontScale: Single;

var
  { Set by Pastel.App: the app's event loop, run on the app thread. }
  AndroidAppMain: procedure = nil;
  { The activity, the window (nil while the app is in the background) and the input queue. }
  AndroidActivity: PANativeActivity = nil;
  AndroidWindow: Pointer = nil;
  AndroidInput: Pointer = nil;
  AndroidLooper: Pointer = nil;
  AndroidPaused: Boolean = False;
  AndroidDestroyRequested: Boolean = False;
  AndroidAppFinished: Boolean = False;
  { The part of the window not covered by the on-screen keyboard (bottom = -1: not known). }
  AndroidVisibleBottom: Integer = -1;
{$ENDIF}

implementation

{$IFDEF ANDROID}
var
  CmdRead, CmdWrite: cint;
  Lock: TRTLCriticalSection;
  Ack: PRTLEvent;
  PendingWindow, PendingInput: Pointer;
  PendingText: string = '';
  AppThread: TThreadID = TThreadID(0);

procedure AndroidLog(const Msg: string);
begin
  __android_log_write(4, 'pastel', PChar(Msg));
end;

procedure Send(Cmd: TAndroidCommand);
var
  B: Byte;
begin
  B := Ord(Cmd);
  FpWrite(CmdWrite, B, 1);
end;

{ commands that change what the app thread draws on wait until it has them }
procedure SendAndWait(Cmd: TAndroidCommand);
begin
  { no app thread, or it has ended (after an error): nobody would answer }
  if (AppThread = TThreadID(0)) or AndroidAppFinished then
    Exit;
  RTLEventResetEvent(Ack);
  Send(Cmd);
  RTLEventWaitFor(Ack, 3000);
end;

procedure AndroidWake;
begin
  Send(acWake);
end;

procedure AndroidCommandDone;
begin
  RTLEventSetEvent(Ack);
end;

function AndroidTakeCommand: TAndroidCommand;
var
  B: Byte;
begin
  if FpRead(CmdRead, B, 1) <> 1 then
    Exit(acNone);
  Result := TAndroidCommand(B);
  EnterCriticalSection(Lock);
  try
    case Result of
      acInputChanged:
        begin
          if AndroidInput <> nil then
            AInputQueue_detachLooper(AndroidInput);
          AndroidInput := PendingInput;
          if AndroidInput <> nil then
            AInputQueue_attachLooper(AndroidInput, AndroidLooper, LooperIdInput, nil, nil);
        end;
      acWindowCreated:
        AndroidWindow := PendingWindow;
      acWindowDestroyed:
        AndroidWindow := nil;
      acPause:
        AndroidPaused := True;
      acResume:
        AndroidPaused := False;
      acDestroy:
        AndroidDestroyRequested := True;
    end;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

var
  PendingKeys: TIntegerArray;

function AndroidTakeKeys: TIntegerArray;
begin
  EnterCriticalSection(Lock);
  try
    Result := PendingKeys;
    PendingKeys := nil;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

procedure Java_dev_pastel_PastelActivity_nativeKey(Env: Pointer; Cls: Pointer; KeyCode: LongInt); cdecl;
begin
  EnterCriticalSection(Lock);
  try
    SetLength(PendingKeys, Length(PendingKeys) + 1);
    PendingKeys[High(PendingKeys)] := KeyCode;
  finally
    LeaveCriticalSection(Lock);
  end;
  if AppThread <> TThreadID(0) then
    Send(acKey);
end;

{ ---- calling the activity's Java methods from the app thread ---- }

type
  TJniAttach = function(VM: Pointer; out Env: Pointer; Args: Pointer): LongInt; cdecl;
  TJniDetach = function(VM: Pointer): LongInt; cdecl;
  TJniGetObjectClass = function(Env, Obj: Pointer): Pointer; cdecl;
  TJniGetMethodID = function(Env, Cls: Pointer; Name, Sig: PChar): Pointer; cdecl;
  TJniCallVoidMethodA = procedure(Env, Obj, Method: Pointer; Args: Pointer); cdecl;
  TJniExceptionCheck = function(Env: Pointer): Byte; cdecl;
  TJniVoid = procedure(Env: Pointer); cdecl;
  TJniDeleteLocalRef = procedure(Env, Ref: Pointer); cdecl;

var
  AppEnv: Pointer = nil;

{ the app thread's JNI environment: the thread is made known to Java once }
function AppJniEnv: Pointer;
var
  VM: Pointer;
begin
  if (AppEnv = nil) and (AndroidActivity <> nil) and (AndroidActivity^.vm <> nil) then
  begin
    VM := AndroidActivity^.vm;
    if TJniAttach(PPointer(PPointer(VM)^)[4])(VM, AppEnv, nil) <> 0 then
      AppEnv := nil;
  end;
  Result := AppEnv;
end;

procedure AppJniDetach;
var
  VM: Pointer;
begin
  if (AppEnv <> nil) and (AndroidActivity <> nil) and (AndroidActivity^.vm <> nil) then
  begin
    VM := AndroidActivity^.vm;
    TJniDetach(PPointer(PPointer(VM)^)[5])(VM);
  end;
  AppEnv := nil;
end;

{ activity.Name(Args...) with int arguments (jvalue: 8 bytes each) }
procedure CallActivity(const Name, Sig: string; const Args: array of Integer);
var
  Env, Cls, Method: Pointer;
  T: PPointer;
  Values: array[0..3] of Int64;
  I: Integer;
begin
  Env := AppJniEnv;
  if (Env = nil) or (AndroidActivity = nil) then
    Exit;
  T := PPointer(Env)^;
  Cls := TJniGetObjectClass(T[31])(Env, AndroidActivity^.clazz);
  if Cls = nil then
    Exit;
  Method := TJniGetMethodID(T[33])(Env, Cls, PChar(Name), PChar(Sig));
  if Method <> nil then
  begin
    FillChar(Values, SizeOf(Values), 0);
    for I := 0 to High(Args) do
      if I <= High(Values) then
        Values[I] := Args[I];
    TJniCallVoidMethodA(T[63])(Env, AndroidActivity^.clazz, Method, @Values[0]);
  end;
  { a missing method (an older classes.dex) or an error in Java: not the app's end }
  if TJniExceptionCheck(T[228])(Env) <> 0 then
  begin
    TJniVoid(T[16])(Env);    { ExceptionDescribe: into the log }
    TJniVoid(T[17])(Env);    { ExceptionClear }
  end;
  TJniDeleteLocalRef(T[23])(Env, Cls);
end;

procedure AndroidShowKeyboard(InputType, ImeOptions: Integer);
begin
  CallActivity('showKeyboard', '(II)V', [InputType, ImeOptions]);
end;

procedure AndroidHideKeyboard;
begin
  CallActivity('hideKeyboard', '()V', []);
end;

function AndroidTakeText: string;
begin
  EnterCriticalSection(Lock);
  try
    Result := PendingText;
    PendingText := '';
  finally
    LeaveCriticalSection(Lock);
  end;
end;

type
  { the start of JNI's function table: what nativeText needs (GetStringUTFChars is the 170th entry) }
  TJniGetChars = function(Env: Pointer; S: Pointer; IsCopy: PByte): PChar; cdecl;
  TJniReleaseChars = procedure(Env: Pointer; S: Pointer; Chars: PChar); cdecl;

procedure Java_dev_pastel_PastelActivity_nativeText(Env: Pointer; Cls: Pointer; Text: Pointer); cdecl;
var
  Table: PPointer;
  Chars: PChar;
  S: string;
begin
  if (Env = nil) or (Text = nil) then
    Exit;
  Table := PPointer(Env)^;
  Chars := TJniGetChars(Table[169])(Env, Text, nil);
  if Chars = nil then
    Exit;
  S := StrPas(Chars);
  TJniReleaseChars(Table[170])(Env, Text, Chars);
  EnterCriticalSection(Lock);
  try
    PendingText := PendingText + S;
  finally
    LeaveCriticalSection(Lock);
  end;
  if AppThread <> TThreadID(0) then
    Send(acText);
end;

function AndroidDensity: Integer;
var
  C: Pointer;
begin
  Result := 160;
  if AndroidActivity = nil then
    Exit;
  C := AConfiguration_new;
  AConfiguration_fromAssetManager(C, AndroidActivity^.assetManager);
  Result := AConfiguration_getDensity(C);
  AConfiguration_delete(C);
  if (Result <= 0) or (Result = $FFFF) then
    Result := 160;
end;

function AndroidIsTV: Boolean;
var
  C: Pointer;
begin
  Result := False;
  if AndroidActivity = nil then
    Exit;
  C := AConfiguration_new;
  AConfiguration_fromAssetManager(C, AndroidActivity^.assetManager);
  Result := AConfiguration_getUiModeType(C) = 4;     { ACONFIGURATION_UI_MODE_TYPE_TELEVISION }
  AConfiguration_delete(C);
end;

type
  TJniCallFloatMethodA = function(Env, Obj, Method: Pointer; Args: Pointer): Single; cdecl;

function AndroidFontScale: Single;
var
  Env, Cls, Method: Pointer;
  T: PPointer;
begin
  Result := 1;
  Env := AppJniEnv;
  if (Env = nil) or (AndroidActivity = nil) then
    Exit;
  T := PPointer(Env)^;
  Cls := TJniGetObjectClass(T[31])(Env, AndroidActivity^.clazz);
  if Cls = nil then
    Exit;
  Method := TJniGetMethodID(T[33])(Env, Cls, 'fontScale', '()F');
  if Method <> nil then
    Result := TJniCallFloatMethodA(T[57])(Env, AndroidActivity^.clazz, Method, nil);
  if TJniExceptionCheck(T[228])(Env) <> 0 then
  begin
    TJniVoid(T[17])(Env);
    Result := 1;
  end;
  TJniDeleteLocalRef(T[23])(Env, Cls);
  if (Result < 0.5) or (Result > 3) then
    Result := 1;
end;

function AndroidNightMode: Boolean;
var
  C: Pointer;
begin
  Result := False;
  if AndroidActivity = nil then
    Exit;
  C := AConfiguration_new;
  AConfiguration_fromAssetManager(C, AndroidActivity^.assetManager);
  Result := AConfiguration_getUiModeNight(C) = 2;
  AConfiguration_delete(C);
end;

function AndroidLanguage: string;
var
  C: Pointer;
  L: array[0..2] of Char;
begin
  Result := '';
  if AndroidActivity = nil then
    Exit;
  FillChar(L, SizeOf(L), 0);
  C := AConfiguration_new;
  AConfiguration_fromAssetManager(C, AndroidActivity^.assetManager);
  AConfiguration_getLanguage(C, @L[0]);
  AConfiguration_delete(C);
  Result := LowerCase(StrPas(@L[0]));
end;

{ ---- the calls from Android, on its main thread ---- }

procedure OnStart(Activity: PANativeActivity); cdecl;
begin
end;

procedure OnResume(Activity: PANativeActivity); cdecl;
begin
  Send(acResume);
end;

function OnSaveInstanceState(Activity: PANativeActivity; OutSize: PPtrUInt): Pointer; cdecl;
begin
  OutSize^ := 0;
  Result := nil;
end;

procedure OnPause(Activity: PANativeActivity); cdecl;
begin
  SendAndWait(acPause);
end;

procedure OnStop(Activity: PANativeActivity); cdecl;
begin
end;

procedure OnDestroy(Activity: PANativeActivity); cdecl;
begin
  SendAndWait(acDestroy);
  { the app's forms belong to this process: the next start begins anew }
  if AndroidAppFinished then
    Halt(0);
end;

procedure OnWindowFocusChanged(Activity: PANativeActivity; HasFocus: LongInt); cdecl;
begin
  Send(acFocusChanged);
end;

procedure OnNativeWindowCreated(Activity: PANativeActivity; Window: Pointer); cdecl;
begin
  PendingWindow := Window;
  SendAndWait(acWindowCreated);
end;

procedure OnNativeWindowResized(Activity: PANativeActivity; Window: Pointer); cdecl;
begin
  Send(acWindowResized);
end;

procedure OnNativeWindowRedrawNeeded(Activity: PANativeActivity; Window: Pointer); cdecl;
begin
  SendAndWait(acRedraw);
end;

procedure OnNativeWindowDestroyed(Activity: PANativeActivity; Window: Pointer); cdecl;
begin
  PendingWindow := nil;
  SendAndWait(acWindowDestroyed);
end;

procedure OnInputQueueCreated(Activity: PANativeActivity; Queue: Pointer); cdecl;
begin
  PendingInput := Queue;
  SendAndWait(acInputChanged);
end;

procedure OnInputQueueDestroyed(Activity: PANativeActivity; Queue: Pointer); cdecl;
begin
  PendingInput := nil;
  SendAndWait(acInputChanged);
end;

type
  TARect = record
    left, top, right, bottom: LongInt;
  end;
  PARect = ^TARect;

procedure OnContentRectChanged(Activity: PANativeActivity; Rect: Pointer); cdecl;
begin
  { the on-screen keyboard came or went: the form uses the part above it }
  if Rect <> nil then
    AndroidVisibleBottom := PARect(Rect)^.bottom;
  Send(acWindowResized);
end;

procedure OnConfigurationChanged(Activity: PANativeActivity); cdecl;
begin
  Send(acConfigChanged);
end;

procedure OnLowMemory(Activity: PANativeActivity); cdecl;
begin
end;

type
  TCallbacks = record
    onStart, onResume, onSaveInstanceState, onPause, onStop, onDestroy, onWindowFocusChanged,
    onNativeWindowCreated, onNativeWindowResized, onNativeWindowRedrawNeeded, onNativeWindowDestroyed,
    onInputQueueCreated, onInputQueueDestroyed, onContentRectChanged, onConfigurationChanged,
    onLowMemory: Pointer;
  end;
  PCallbacks = ^TCallbacks;

function AppThreadMain(Param: Pointer): PtrInt;
begin
  Result := 0;
  AndroidLooper := ALooper_prepare(1);
  ALooper_addFd(AndroidLooper, CmdRead, LooperIdMain, 1, nil, nil);
  try
    if Assigned(AndroidAppMain) then
      AndroidAppMain
    else
      AndroidLog('the app did not call Application.Run');
  except
    on E: Exception do
      AndroidLog('the app stopped: ' + E.ClassName + ': ' + E.Message);
  end;
  AndroidAppFinished := True;
  if not AndroidDestroyRequested and (AndroidActivity <> nil) then
    ANativeActivity_finish(AndroidActivity);
  { a thread made known to Java must say goodbye before it ends }
  AppJniDetach;
  { the main thread may wait for an answer that will not come any more }
  RTLEventSetEvent(Ack);
end;

{ setenv of libc: there is no FpSetEnv in BaseUnix }
function setenv(Name, Value: PChar; Overwrite: LongInt): LongInt; cdecl; external 'c';

procedure ANativeActivity_onCreate(Activity: PANativeActivity; SavedState: Pointer; SavedStateSize: PtrUInt); cdecl;
var
  CB: PCallbacks;
  Fds: TFilDes;
begin
  CB := PCallbacks(Activity^.callbacks);
  CB^.onStart := @OnStart;
  CB^.onResume := @OnResume;
  CB^.onSaveInstanceState := @OnSaveInstanceState;
  CB^.onPause := @OnPause;
  CB^.onStop := @OnStop;
  CB^.onDestroy := @OnDestroy;
  CB^.onWindowFocusChanged := @OnWindowFocusChanged;
  CB^.onNativeWindowCreated := @OnNativeWindowCreated;
  CB^.onNativeWindowResized := @OnNativeWindowResized;
  CB^.onNativeWindowRedrawNeeded := @OnNativeWindowRedrawNeeded;
  CB^.onNativeWindowDestroyed := @OnNativeWindowDestroyed;
  CB^.onInputQueueCreated := @OnInputQueueCreated;
  CB^.onInputQueueDestroyed := @OnInputQueueDestroyed;
  CB^.onContentRectChanged := @OnContentRectChanged;
  CB^.onConfigurationChanged := @OnConfigurationChanged;
  CB^.onLowMemory := @OnLowMemory;
  AndroidActivity := Activity;
  if AppThread <> TThreadID(0) then
  begin
    { the activity came back while the app still runs: carry on with it }
    Send(acRedraw);
    Exit;
  end;
  { the app's files: its own folder; HOME for GetUserDir and the config files }
  if Activity^.internalDataPath <> nil then
  begin
    setenv('HOME', Activity^.internalDataPath, 1);
    ChDir(StrPas(Activity^.internalDataPath));
  end;
  if FpPipe(Fds) = 0 then
  begin
    CmdRead := Fds[0];
    CmdWrite := Fds[1];
  end;
  AppThread := BeginThread(@AppThreadMain, nil);
end;

initialization
  InitCriticalSection(Lock);
  Ack := RTLEventCreate;
{$ENDIF}

end.
