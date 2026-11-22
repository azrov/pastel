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
  cthreads, BaseUnix, Unix, SysUtils, Classes, Math, dl;

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
  TInt64Array = array of Int64;
  TPointerArray = array of Pointer;

  TAndroidCommand = (acNone, acInputChanged, acWindowCreated, acWindowDestroyed, acWindowResized,
    acRedraw, acResume, acPause, acConfigChanged, acFocusChanged, acDestroy, acWake, acText, acKey, acEdit);

  { the focused edit's copy after the on-screen keyboard changed it (positions: UTF-16 units; -1: none) }
  TAndroidEdit = record
    Text: string;
    SelStart, SelEnd, ComposeStart, ComposeEnd, Gen: Integer;
  end;

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
{ Called on Android's UI thread by the activity's runOnUi (Pastel.Java's JavaRunOnUiThread). }
procedure Java_dev_pastel_PastelActivity_nativeRun(Env: Pointer; Cls: Pointer; Token: Int64); cdecl;
{ Java loads libmain.so: its VM and Pastel's activity class are kept (exported). }
function JNI_OnLoad(VM: Pointer; Reserved: Pointer): LongInt; cdecl;
{ A background job (dev.pastel.PastelJob), also without the app's window; exported. }
function Java_dev_pastel_PastelJob_nativeJob(Env: Pointer; Cls: Pointer; Name, FilesDir: Pointer): Byte; cdecl;
{ The app thread: the text typed since the last acText. }
function AndroidTakeText: string;
{ Keys from the on-screen keyboard (Backspace, Enter, Tab: Android's key codes); exported by libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeKey(Env: Pointer; Cls: Pointer; KeyCode: LongInt); cdecl;
{ TalkBack's action on a control (PastelAccess): its id and Android's action; exported by libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeAccess(Env: Pointer; Cls: Pointer; Id, Action: LongInt); cdecl;
{ The next of those actions (the app thread takes them). }
function AndroidTakeAccessAction(out Id, Action: Integer): Boolean;
{ The app thread: the key codes since the last acKey. }
function AndroidTakeKeys: TIntegerArray;
{ The app thread: the on-screen keyboard for an edit; InputType and ImeOptions
  are Android's (EditorInfo): which keyboard, and what its Enter key does. }
procedure AndroidShowKeyboard(InputType, ImeOptions: Integer);
procedure AndroidHideKeyboard;
{ The app thread: the keyboard for an edit, with a copy of its text and selection
  (UTF-16 units); Gen numbers Pascal's states (answers of older ones are dropped). }
procedure AndroidEditStart(InputType, ImeOptions: Integer; const Text: string; SelStart, SelEnd, Gen: Integer);
{ The app thread: Pascal changed the focused edit itself; the keyboard's copy follows. }
procedure AndroidEditSync(const Text: string; SelStart, SelEnd, Gen: Integer);
{ The edit's copy after the keyboard's last change; exported by libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeEdit(Env: Pointer; Cls: Pointer; Text: Pointer;
  SelStart, SelEnd, ComposeStart, ComposeEnd, Gen: LongInt); cdecl;
{ The app thread: the keyboard's last change since the last acEdit; False when none. }
function AndroidTakeEdit(out Edit: TAndroidEdit): Boolean;

{ Debug builds: where "pastel run --target android" serves the project's .pform files
  (the computer's port, brought to the phone with adb reverse). }
const
  AndroidFormServer = 'http://127.0.0.1:7865/forms/';
{ A form's text from the computer; False when nobody answers. }
function AndroidFetchForm(const Url: string; Lines: TStrings): Boolean;

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
{ The edges the system covers; exported by libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeInsets(Env: Pointer; Cls: Pointer; ATop, ABottom, ALeft, ARight: LongInt); cdecl;
{ The answer to a request of Pastel.Device (a picked file, a photo, a permission, a place);
  exported by libmain.so. }
procedure Java_dev_pastel_PastelActivity_nativeResult(Env: Pointer; Cls: Pointer; Code, Ok: LongInt; Text: Pointer); cdecl;
{ A new number for a request; its answer comes with AndroidTakeResult. }
function AndroidNewRequest: Integer;
{ The answer to request Code, once it came (True; it is then forgotten). }
function AndroidTakeResult(Code: Integer; out Ok: Boolean; out Text: string): Boolean;
{ Calls a method of Pastel's activity with strings, integers and booleans
  (Sig: its JNI signature, '(Ljava/lang/String;I)V'); any thread. False when it is not there. }
function AndroidCall(const Name, Sig: string; const Args: array of const): Boolean;
{ The same for a method that answers a string ('()Ljava/lang/String;'). }
function AndroidCallString(const Name, Sig: string; const Args: array of const): string;
{ The phone's clipboard (Pastel.App makes copy and paste of edits use it). }
function AndroidClipboardText: string;
procedure AndroidSetClipboardText(const S: string);

{ HTTP and HTTPS through Android's own (Pastel.Http uses it; any thread). The answer:
  "status"#10"text"#10"final address"#10, header lines, an empty line, the body;
  status 0 with the reason when no answer came. }
function AndroidHttp(const Method, Url, Headers: string; const Body: RawByteString; HasBody: Boolean;
  TimeoutMs: Integer; Follow, Verify: Boolean): RawByteString;
{ The folder of the app's own libraries (libmain.so, libsqlite3.so), with a trailing slash. }
function AndroidNativeLibDir: string;
{ The device is a TV (Android TV, most TV boxes): used with a remote, seen from afar. }
function AndroidIsTV: Boolean;
{ The size of text the user chose in the phone's settings (1: normal, 1.3: large). }
function AndroidFontScale: Single;

var
  { Set by Pastel.App: the app's event loop, run on the app thread. }
  AndroidAppMain: procedure = nil;
  { The activity, the window (nil while the app is in the background) and the input queue. }
  AndroidActivity: PANativeActivity = nil;
  { Java's VM: from the activity, else from JNI_OnLoad (a background job without a window) }
  AndroidJavaVM: Pointer = nil;
  { dev.pastel.PastelActivity (a global reference): its static methods (HTTP) also without an activity }
  AndroidActivityClass: Pointer = nil;
  { Set by Pastel.Background: runs the background job of this name (on a thread of Java's); True when done. }
  AndroidJobHandler: function(const Name: string): Boolean = nil;
  { The state the app keeps when it is paused (Pastel.App writes it); the one
    Android gave back at a new start ('' when none). }
  AndroidSavedState: string = '';
  AndroidRestoredState: string = '';
  StateLock: TRTLCriticalSection;
  { Set by Pastel.Java: what nativeRun calls. }
  AndroidUiCall: procedure(Token: Int64) = nil;
  AndroidWindow: Pointer = nil;
  AndroidInput: Pointer = nil;
  AndroidLooper: Pointer = nil;
  AndroidPaused: Boolean = False;
  AndroidDestroyRequested: Boolean = False;
  AndroidAppFinished: Boolean = False;
  { The part of the window not covered by the on-screen keyboard (bottom = -1: not known). }
  AndroidVisibleBottom: Integer = -1;
  { What the system's bars and the keyboard cover at each edge, in pixels (from Pastel's activity). }
  AndroidInsetTop: Integer = 0;
  AndroidInsetBottom: Integer = 0;
  AndroidInsetLeft: Integer = 0;
  AndroidInsetRight: Integer = 0;
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

var
  AccessActions: array of Integer;

procedure Java_dev_pastel_PastelActivity_nativeAccess(Env: Pointer; Cls: Pointer; Id, Action: LongInt); cdecl;
begin
  EnterCriticalSection(Lock);
  try
    SetLength(AccessActions, Length(AccessActions) + 2);
    AccessActions[High(AccessActions) - 1] := Id;
    AccessActions[High(AccessActions)] := Action;
  finally
    LeaveCriticalSection(Lock);
  end;
  if AppThread <> TThreadID(0) then
    Send(acWake);
end;

function AndroidTakeAccessAction(out Id, Action: Integer): Boolean;
begin
  EnterCriticalSection(Lock);
  try
    Result := Length(AccessActions) >= 2;
    if Result then
    begin
      Id := AccessActions[0];
      Action := AccessActions[1];
      Delete(AccessActions, 0, 2);
    end
    else
    begin
      Id := 0;
      Action := 0;
    end;
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
  { the start of JNI's function table: what nativeText needs (GetStringUTFChars is the 170th entry) }
  TJniGetChars = function(Env: Pointer; S: Pointer; IsCopy: PByte): PChar; cdecl;
  TJniReleaseChars = procedure(Env: Pointer; S: Pointer; Chars: PChar); cdecl;

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

{ ---- from any thread ---- }

type
  TJniGetEnv = function(VM: Pointer; out Env: Pointer; Version: LongInt): LongInt; cdecl;
  TJniNewStringUTF = function(Env: Pointer; S: PChar): Pointer; cdecl;
  TJniNewByteArray = function(Env: Pointer; Len: LongInt): Pointer; cdecl;
  TJniSetByteArrayRegion = procedure(Env, Arr: Pointer; Start, Len: LongInt; Buf: Pointer); cdecl;
  TJniGetByteArrayRegion = procedure(Env, Arr: Pointer; Start, Len: LongInt; Buf: Pointer); cdecl;
  TJniGetArrayLength = function(Env, Arr: Pointer): LongInt; cdecl;
  TJniGetStaticMethodID = function(Env, Cls: Pointer; Name, Sig: PChar): Pointer; cdecl;
  TJniCallStaticObjectMethodA = function(Env, Cls, Method: Pointer; Args: Pointer): Pointer; cdecl;
  TJniNewLocalRef = function(Env, Ref: Pointer): Pointer; cdecl;
  TJniNewGlobalRef = function(Env, Ref: Pointer): Pointer; cdecl;
  TJniFindClass = function(Env: Pointer; Name: PChar): Pointer; cdecl;
  TJniGetJavaVM = function(Env: Pointer; out VM: Pointer): LongInt; cdecl;

{ the JNI environment of this thread; a thread Java does not know yet is made known
  (Attached: it must say goodbye with ThreadJniDone) }
function ThreadJniEnv(out Attached: Boolean): Pointer;
var
  VM: Pointer;
begin
  Result := nil;
  Attached := False;
  VM := nil;
  if (AndroidActivity <> nil) and (AndroidActivity^.vm <> nil) then
    VM := AndroidActivity^.vm
  else
    VM := AndroidJavaVM;
  if VM = nil then
    Exit;
  if TJniGetEnv(PPointer(PPointer(VM)^)[6])(VM, Result, $00010006) = 0 then
    Exit;
  Result := nil;
  if TJniAttach(PPointer(PPointer(VM)^)[4])(VM, Result, nil) = 0 then
    Attached := True
  else
    Result := nil;
end;

procedure ThreadJniDone(Attached: Boolean);
var
  VM: Pointer;
begin
  if not Attached then
    Exit;
  if AndroidActivity <> nil then
    VM := AndroidActivity^.vm
  else
    VM := AndroidJavaVM;
  if VM <> nil then
    TJniDetach(PPointer(PPointer(VM)^)[5])(VM);
end;

type
  TJniNewString = function(Env: Pointer; Chars: PWideChar; Len: LongInt): Pointer; cdecl;
  TJniGetStringLength = function(Env, S: Pointer): LongInt; cdecl;
  TJniGetStringChars = function(Env, S: Pointer; IsCopy: PByte): PWideChar; cdecl;
  TJniReleaseStringChars = procedure(Env, S: Pointer; Chars: PWideChar); cdecl;

{ A Pascal (UTF-8) string as a java.lang.String: through UTF-16, since JNI's
  "UTF" functions are Java's modified UTF-8, which has no 4-byte letters
  (emoji, some CJK) - with them a debug build stops ("not valid Modified UTF-8"). }
function JString(Env: Pointer; const S: string): Pointer;
var
  W: UnicodeString;
begin
  W := UTF8Decode(S);
  if W = '' then
    Result := TJniNewString(PPointer(PPointer(Env)^)[163])(Env, nil, 0)
  else
    Result := TJniNewString(PPointer(PPointer(Env)^)[163])(Env, PWideChar(W), Length(W));
end;

{ A java.lang.String as UTF-8 (through UTF-16: emoji stay whole) }
function JStringText(Env, S: Pointer): string;
var
  T: PPointer;
  N: LongInt;
  P: PWideChar;
  W: UnicodeString;
begin
  Result := '';
  if S = nil then
    Exit;
  T := PPointer(Env)^;
  N := TJniGetStringLength(T[164])(Env, S);
  if N <= 0 then
    Exit;
  P := TJniGetStringChars(T[165])(Env, S, nil);
  if P = nil then
    Exit;
  SetLength(W, N);
  Move(P^, W[1], N * SizeOf(WideChar));
  TJniReleaseStringChars(T[166])(Env, S, P);
  Result := UTF8Encode(W);
end;

function JBytes(Env: Pointer; const S: RawByteString): Pointer;
var
  T: PPointer;
begin
  T := PPointer(Env)^;
  Result := TJniNewByteArray(T[176])(Env, Length(S));
  if (Result <> nil) and (S <> '') then
    TJniSetByteArrayRegion(T[208])(Env, Result, 0, Length(S), @S[1]);
end;

function AndroidHttp(const Method, Url, Headers: string; const Body: RawByteString; HasBody: Boolean;
  TimeoutMs: Integer; Follow, Verify: Boolean): RawByteString;
var
  Env, Cls, Mid, Answer: Pointer;
  T: PPointer;
  Attached: Boolean;
  Args: array[0..6] of Int64;
  Refs: array[0..3] of Pointer;
  I, N: Integer;
begin
  Result := '0'#10'the app is not running yet (no Android activity)'#10#10#10;
  Env := ThreadJniEnv(Attached);
  if Env = nil then
    Exit;
  try
    T := PPointer(Env)^;
    if AndroidActivity <> nil then
      Cls := TJniGetObjectClass(T[31])(Env, AndroidActivity^.clazz)
    else if AndroidActivityClass <> nil then
      Cls := TJniNewLocalRef(T[25])(Env, AndroidActivityClass)     { a background job: no activity }
    else
      Exit;
    Mid := TJniGetStaticMethodID(T[113])(Env, Cls, 'http',
      '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;[BIZZ)[B');
    if Mid = nil then
    begin
      TJniVoid(T[17])(Env);
      TJniDeleteLocalRef(T[23])(Env, Cls);
      Exit('0'#10'this app''s Java part is too old for HTTP (build it again with this Pastel)'#10#10#10);
    end;
    Refs[0] := JString(Env, Method);
    Refs[1] := JString(Env, Url);
    Refs[2] := JString(Env, Headers);
    Refs[3] := nil;
    if HasBody then
      Refs[3] := JBytes(Env, Body);
    FillChar(Args, SizeOf(Args), 0);
    for I := 0 to 3 do
      Args[I] := PtrInt(Refs[I]);
    Args[4] := TimeoutMs;
    Args[5] := Ord(Follow);
    Args[6] := Ord(Verify);
    Answer := TJniCallStaticObjectMethodA(T[116])(Env, Cls, Mid, @Args[0]);
    if TJniExceptionCheck(T[228])(Env) <> 0 then
    begin
      TJniVoid(T[16])(Env);
      TJniVoid(T[17])(Env);
      Answer := nil;
      Result := '0'#10'Android''s HTTP stopped with an error (see the log)'#10#10#10;
    end;
    if Answer <> nil then
    begin
      N := TJniGetArrayLength(T[171])(Env, Answer);
      SetLength(Result, N);
      if N > 0 then
        TJniGetByteArrayRegion(T[200])(Env, Answer, 0, N, @Result[1]);
      TJniDeleteLocalRef(T[23])(Env, Answer);
    end;
    for I := 0 to 3 do
      if Refs[I] <> nil then
        TJniDeleteLocalRef(T[23])(Env, Refs[I]);
    TJniDeleteLocalRef(T[23])(Env, Cls);
  finally
    ThreadJniDone(Attached);
  end;
end;

function AndroidFetchForm(const Url: string; Lines: TStrings): Boolean;
var
  Answer: RawByteString;
  P: Integer;
begin
  Result := False;
  Answer := AndroidHttp('GET', Url, '', '', False, 800, False, True);
  { "200", the status text, the address, the headers, an empty line, the text }
  if Copy(Answer, 1, 4) <> '200'#10 then
    Exit;
  P := Pos(#10#10, Answer);
  if P = 0 then
    Exit;
  Lines.Text := Copy(Answer, P + 2, MaxInt);
  Result := True;
end;

{ ---- requests that are answered later (Pastel.Device) ---- }

var
  NextRequest: Integer = 4100;
  Results: TStringList = nil;     { 'code=ok|text' }

function AndroidNewRequest: Integer;
begin
  EnterCriticalSection(Lock);
  try
    Inc(NextRequest);
    if NextRequest > 65000 then
      NextRequest := 4101;
    Result := NextRequest;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function JavaText(Env, S: Pointer): string;
begin
  Result := JStringText(Env, S);
end;

procedure Java_dev_pastel_PastelActivity_nativeInsets(Env: Pointer; Cls: Pointer; ATop, ABottom, ALeft, ARight: LongInt); cdecl;
begin
  AndroidInsetTop := Max(0, ATop);
  AndroidInsetBottom := Max(0, ABottom);
  AndroidInsetLeft := Max(0, ALeft);
  AndroidInsetRight := Max(0, ARight);
  if AppThread <> TThreadID(0) then
    Send(acWindowResized);
end;

procedure Java_dev_pastel_PastelActivity_nativeResult(Env: Pointer; Cls: Pointer; Code, Ok: LongInt; Text: Pointer); cdecl;
var
  S: string;
begin
  S := JavaText(Env, Text);
  EnterCriticalSection(Lock);
  try
    if Results = nil then
      Results := TStringList.Create;
    Results.Add(IntToStr(Code) + '=' + IntToStr(Ok) + '|' + S);
  finally
    LeaveCriticalSection(Lock);
  end;
  if AppThread <> TThreadID(0) then
    Send(acWake);
end;

function AndroidTakeResult(Code: Integer; out Ok: Boolean; out Text: string): Boolean;
var
  I: Integer;
  V: string;
begin
  Result := False;
  Ok := False;
  Text := '';
  EnterCriticalSection(Lock);
  try
    if Results = nil then
      Exit;
    I := Results.IndexOfName(IntToStr(Code));
    if I < 0 then
      Exit;
    V := Results.ValueFromIndex[I];
    Results.Delete(I);
    Ok := Copy(V, 1, 1) = '1';
    Text := Copy(V, 3, MaxInt);
    Result := True;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

type
  TJniCallObjectMethodA = function(Env, Obj, Method: Pointer; Args: Pointer): Pointer; cdecl;
  TJniCallBooleanMethodA = function(Env, Obj, Method: Pointer; Args: Pointer): Byte; cdecl;

{ the arguments as jvalues; strings become Java strings (Refs, deleted afterwards) }
procedure JavaArgs(Env: Pointer; const Args: array of const; out Values: TInt64Array; out Refs: TPointerArray);
var
  I: Integer;
begin
  SetLength(Values, Max(1, Length(Args)));
  Refs := nil;
  for I := 0 to High(Args) do
  begin
    Values[I] := 0;
    case Args[I].VType of
      vtInteger: Values[I] := Args[I].VInteger;
      vtInt64: Values[I] := Args[I].VInt64^;
      vtBoolean: Values[I] := Ord(Args[I].VBoolean);
      vtAnsiString:
        begin
          Values[I] := PtrInt(JString(Env, AnsiString(Args[I].VAnsiString)));
          Refs := Concat(Refs, [Pointer(PtrInt(Values[I]))]);
        end;
      vtUnicodeString:
        begin
          Values[I] := PtrInt(JString(Env, UTF8Encode(UnicodeString(Args[I].VUnicodeString))));
          Refs := Concat(Refs, [Pointer(PtrInt(Values[I]))]);
        end;
      vtChar:
        begin
          Values[I] := PtrInt(JString(Env, Args[I].VChar));
          Refs := Concat(Refs, [Pointer(PtrInt(Values[I]))]);
        end;
    end;
  end;
end;

function CallActivityObject(const Name, Sig: string; const Args: array of const; WantString: Boolean;
  out Text: string): Boolean;
var
  Env, Cls, Method, Answer: Pointer;
  T: PPointer;
  Attached: Boolean;
  Values: TInt64Array;
  Refs: TPointerArray;
  R: Pointer;
begin
  Result := False;
  Text := '';
  Env := ThreadJniEnv(Attached);
  if Env = nil then
    Exit;
  try
    T := PPointer(Env)^;
    Cls := TJniGetObjectClass(T[31])(Env, AndroidActivity^.clazz);
    Method := TJniGetMethodID(T[33])(Env, Cls, PChar(Name), PChar(Sig));
    if Method <> nil then
    begin
      JavaArgs(Env, Args, Values, Refs);
      if WantString then
      begin
        Answer := TJniCallObjectMethodA(T[36])(Env, AndroidActivity^.clazz, Method, @Values[0]);
        if (Answer <> nil) and (TJniExceptionCheck(T[228])(Env) = 0) then
        begin
          Text := JavaText(Env, Answer);
          TJniDeleteLocalRef(T[23])(Env, Answer);
        end;
      end
      else
        TJniCallVoidMethodA(T[63])(Env, AndroidActivity^.clazz, Method, @Values[0]);
      for R in Refs do
        TJniDeleteLocalRef(T[23])(Env, R);
      Result := True;
    end;
    if TJniExceptionCheck(T[228])(Env) <> 0 then
    begin
      TJniVoid(T[16])(Env);
      TJniVoid(T[17])(Env);
      Result := False;
    end;
    TJniDeleteLocalRef(T[23])(Env, Cls);
  finally
    ThreadJniDone(Attached);
  end;
end;

function AndroidCall(const Name, Sig: string; const Args: array of const): Boolean;
var
  Ignored: string;
begin
  Result := CallActivityObject(Name, Sig, Args, False, Ignored);
end;

function AndroidCallString(const Name, Sig: string; const Args: array of const): string;
begin
  CallActivityObject(Name, Sig, Args, True, Result);
end;

function AndroidClipboardText: string;
begin
  Result := AndroidCallString('clipboardText', '()Ljava/lang/String;', []);
end;

procedure AndroidSetClipboardText(const S: string);
begin
  AndroidCall('setClipboardText', '(Ljava/lang/String;)V', [S]);
end;

procedure AndroidShowKeyboard(InputType, ImeOptions: Integer);
begin
  CallActivity('showKeyboard', '(II)V', [InputType, ImeOptions]);
end;

procedure AndroidEditStart(InputType, ImeOptions: Integer; const Text: string; SelStart, SelEnd, Gen: Integer);
begin
  AndroidCall('editStart', '(IILjava/lang/String;III)V', [InputType, ImeOptions, Text, SelStart, SelEnd, Gen]);
end;

procedure AndroidEditSync(const Text: string; SelStart, SelEnd, Gen: Integer);
begin
  AndroidCall('editSync', '(Ljava/lang/String;III)V', [Text, SelStart, SelEnd, Gen]);
end;

var
  PendingEdit: TAndroidEdit;
  HasPendingEdit: Boolean = False;

procedure Java_dev_pastel_PastelActivity_nativeEdit(Env: Pointer; Cls: Pointer; Text: Pointer;
  SelStart, SelEnd, ComposeStart, ComposeEnd, Gen: LongInt); cdecl;
var
  E: TAndroidEdit;
begin
  if Env = nil then
    Exit;
  E.Text := JStringText(Env, Text);
  E.SelStart := SelStart;
  E.SelEnd := SelEnd;
  E.ComposeStart := ComposeStart;
  E.ComposeEnd := ComposeEnd;
  E.Gen := Gen;
  EnterCriticalSection(Lock);
  try
    { only the latest counts: it is the whole text }
    PendingEdit := E;
    HasPendingEdit := True;
  finally
    LeaveCriticalSection(Lock);
  end;
  if AppThread <> TThreadID(0) then
    Send(acEdit);
end;

function AndroidTakeEdit(out Edit: TAndroidEdit): Boolean;
begin
  EnterCriticalSection(Lock);
  try
    Result := HasPendingEdit;
    Edit := PendingEdit;
    HasPendingEdit := False;
  finally
    LeaveCriticalSection(Lock);
  end;
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

procedure Java_dev_pastel_PastelActivity_nativeRun(Env: Pointer; Cls: Pointer; Token: Int64); cdecl;
begin
  if Assigned(AndroidUiCall) then
    AndroidUiCall(Token);
end;

procedure Java_dev_pastel_PastelActivity_nativeText(Env: Pointer; Cls: Pointer; Text: Pointer); cdecl;
var
  S: string;
begin
  if (Env = nil) or (Text = nil) then
    Exit;
  S := JStringText(Env, Text);
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

function AndroidNativeLibDir: string;
var
  Info: dl_info;
begin
  Result := '';
  FillChar(Info, SizeOf(Info), 0);
  if (dladdr(@AndroidNativeLibDir, @Info) <> 0) and (Info.dli_fname <> nil) then
    Result := ExtractFilePath(StrPas(Info.dli_fname));
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

function malloc(Size: PtrUInt): Pointer; cdecl; external 'c';

{ the state the app wrote when it was paused: Android keeps it, and gives it back
  if it stops the app in the background and starts it again }
function OnSaveInstanceState(Activity: PANativeActivity; OutSize: PPtrUInt): Pointer; cdecl;
var
  S: string;
begin
  OutSize^ := 0;
  Result := nil;
  EnterCriticalSection(StateLock);
  try
    S := AndroidSavedState;
  finally
    LeaveCriticalSection(StateLock);
  end;
  if S = '' then
    Exit;
  Result := malloc(Length(S));       { Android frees it with free() }
  if Result = nil then
    Exit;
  Move(S[1], Result^, Length(S));
  OutSize^ := Length(S);
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
  { started again after Android stopped the app in the background: what it was }
  if (SavedState <> nil) and (SavedStateSize > 0) and (AppThread = TThreadID(0)) then
  begin
    SetLength(AndroidRestoredState, SavedStateSize);
    Move(SavedState^, AndroidRestoredState[1], SavedStateSize);
  end;
  if AppThread <> TThreadID(0) then
  begin
    { the activity came back while the app still runs: carry on with it }
    Send(acRedraw);
    Exit;
  end;
  AndroidJavaVM := Activity^.vm;
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

function JNI_OnLoad(VM: Pointer; Reserved: Pointer): LongInt; cdecl;
var
  Env, Cls: Pointer;
  T: PPointer;
begin
  Result := $00010006;      { JNI 1.6 }
  AndroidJavaVM := VM;
  Env := nil;
  if TJniGetEnv(PPointer(PPointer(VM)^)[6])(VM, Env, $00010006) <> 0 then
    Exit;
  T := PPointer(Env)^;
  { found now with the class loader that loads the library (the app's) }
  Cls := TJniFindClass(T[6])(Env, 'dev/pastel/PastelActivity');
  if Cls <> nil then
  begin
    AndroidActivityClass := TJniNewGlobalRef(T[21])(Env, Cls);
    TJniDeleteLocalRef(T[23])(Env, Cls);
  end
  else
    TJniVoid(T[17])(Env);       { ExceptionClear: an older classes.dex }
end;

function Java_dev_pastel_PastelJob_nativeJob(Env: Pointer; Cls: Pointer; Name, FilesDir: Pointer): Byte; cdecl;
var
  JobName, Dir: string;
  VM: Pointer;
begin
  Result := 0;
  if Env = nil then
    Exit;
  if AndroidJavaVM = nil then
    if TJniGetJavaVM(PPointer(PPointer(Env)^)[219])(Env, VM) = 0 then
      AndroidJavaVM := VM;
  JobName := JStringText(Env, Name);
  Dir := JStringText(Env, FilesDir);
  { without a window the app's files are found as with one: HOME, its folder }
  if (AndroidActivity = nil) and (Dir <> '') then
  begin
    setenv('HOME', PChar(Dir), 1);
    ChDir(Dir);
  end;
  IsMultiThread := True;
  if not Assigned(AndroidJobHandler) then
  begin
    AndroidLog('the background job "' + JobName + '" is not known (Pastel.Background: RegisterBackgroundJob)');
    Exit(1);       { nothing to do: done }
  end;
  try
    Result := Ord(AndroidJobHandler(JobName));
  except
    on E: Exception do
      AndroidLog('the background job "' + JobName + '" failed: ' + E.Message);
  end;
end;

initialization
  InitCriticalSection(StateLock);
  InitCriticalSection(Lock);
  Ack := RTLEventCreate;
{$ENDIF}

end.
