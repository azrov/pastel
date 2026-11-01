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

  TAndroidCommand = (acNone, acInputChanged, acWindowCreated, acWindowDestroyed, acWindowResized,
    acRedraw, acResume, acPause, acConfigChanged, acFocusChanged, acDestroy, acWake);

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
procedure AConfiguration_getLanguage(Config: Pointer; OutLanguage: PChar); cdecl; external 'android';
function __android_log_write(Prio: LongInt; Tag, Text: PChar): LongInt; cdecl; external 'log';

{ Android calls this when the app starts (exported by the app's libmain.so). }
procedure ANativeActivity_onCreate(Activity: PANativeActivity; SavedState: Pointer; SavedStateSize: PtrUInt); cdecl;

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
{$ENDIF}

implementation

{$IFDEF ANDROID}
var
  CmdRead, CmdWrite: cint;
  Lock: TRTLCriticalSection;
  Ack: PRTLEvent;
  PendingWindow, PendingInput: Pointer;
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
  if AppThread = TThreadID(0) then
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

procedure OnContentRectChanged(Activity: PANativeActivity; Rect: Pointer); cdecl;
begin
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
