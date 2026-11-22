{ Pastel - Java from Pascal: any class of Android (or of the app's own Java
  files, or of a Java library on a computer), called by its name.

  "pastel java add android.widget.Toast" writes typed Pascal for the classes
  you name (src/java/javaclasses.pas, like Delphi's Java2OP):
    JToast.makeText(JavaActivity, 'Saved', JToast.LENGTH_SHORT).show;

  Underneath, and for calls of your own, this unit:
    S := JavaStaticStr('android.os.Build', 'MODEL', '');                      // a static field
    N := JavaCallI(Obj, 'java.lang.String', 'length', '()I', []);             // a method
    L := JavaNew('java.util.ArrayList', '()V', []);                           // a new object
  The signature is Java's ('(Ljava/lang/String;I)V'); Pascal strings become
  java.lang.String, objects are passed as TJavaObject.Handle.

  Objects are TJavaObject: a reference Java keeps alive until Pascal no longer
  uses it (freed by itself, like a string). A Java exception becomes an
  EJavaError with Java's message.

  Where Java runs:
    Android    the app's own Java (Pastel's activity); any thread. Android's
               views and Toast want the UI thread: JavaRunOnUiThread.
    Computers  a Java VM started the first time (JAVA_HOME, else the java of
               the PATH; PASTEL_JVM: the path of libjvm / jvm.dll). Its class
               path: PASTEL_JAVA_CLASSPATH, else the project's own Java
               (build/java, written by "pastel java") and java/ beside the
               program (its .jar files): Java libraries in desktop apps.
  Part of the Pastel project, MIT License. }
unit Pastel.Java;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

type
  EJavaError = class(Exception);

  IJavaRef = interface
    ['{5B0F0C3E-3E57-4C8B-9B52-2F7B6C1D9A41}']
    function Handle: Pointer;
  end;

  { A Java object; Pascal keeps it alive while it is used (a global reference). }
  TJavaObject = record
    Ref: IJavaRef;
    { Java's handle (jobject) for calls; nil for null }
    function Handle: Pointer;
    function IsNull: Boolean;
    { java.lang.Object's toString }
    function ToString: string;
    { its class's name: 'android.widget.Toast' }
    function JavaClassName: string;
    function IsInstanceOf(const AClass: string): Boolean;
    { a boxed value's (java.lang.Integer, Long, Boolean, Double, Character...): 0, False, '' for null }
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsBoolean: Boolean;
    function AsDouble: Double;
    function AsString: string;
  end;

  TJavaUiProc = procedure of object;

  TJavaArgs = array of TJavaObject;
  { a call of an interface's method that Pascal does (JavaImplement): the method's
    name, its arguments (numbers boxed: Args[0].AsInteger) and what to answer
    (left null: null, 0 or False; a number boxed: JavaInteger(1)) }
  TJavaCallbackEvent = procedure(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject) of object;

{ True when Java can be called here (Android; a computer with Java). }
function JavaAvailable: Boolean;
{ Why Java cannot be called ('' when it can). }
function JavaProblem: string;

{ A class by its name ('android.widget.Toast', 'android.app.Notification$Builder'
  or with a dot for the inner class): Java's handle, kept. EJavaError when there is none. }
function JavaClass(const Name: string): Pointer;
{ True when the class is there. }
function JavaHasClass(const Name: string): Boolean;

{ A new object: JavaNew('java.lang.StringBuilder', '(Ljava/lang/String;)V', ['abc']). }
function JavaNew(const Cls, Sig: string; const Args: array of const): TJavaObject;

{ An object's method, by what it answers: nothing (JavaCall), Boolean, Integer
  (int, short, byte, char), Int64 (long), Single, Double, an object, a string. }
procedure JavaCall(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const);
function JavaCallZ(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Boolean;
function JavaCallI(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Integer;
function JavaCallJ(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Int64;
function JavaCallF(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Single;
function JavaCallD(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Double;
function JavaCallO(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): TJavaObject;
function JavaCallStr(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): string;

{ The same for a class's static methods. }
procedure JavaStatic(const Cls, Name, Sig: string; const Args: array of const);
function JavaStaticZ(const Cls, Name, Sig: string; const Args: array of const): Boolean;
function JavaStaticI(const Cls, Name, Sig: string; const Args: array of const): Integer;
function JavaStaticJ(const Cls, Name, Sig: string; const Args: array of const): Int64;
function JavaStaticF(const Cls, Name, Sig: string; const Args: array of const): Single;
function JavaStaticD(const Cls, Name, Sig: string; const Args: array of const): Double;
function JavaStaticO(const Cls, Name, Sig: string; const Args: array of const): TJavaObject;
function JavaStaticStr(const Cls, Name, Sig: string; const Args: array of const): string;

{ A static field's value (Sig: its type, 'I', 'Ljava/lang/String;'). }
function JavaFieldI(const Cls, Name: string): Integer;
function JavaFieldJ(const Cls, Name: string): Int64;
function JavaFieldZ(const Cls, Name: string): Boolean;
function JavaFieldD(const Cls, Name, Sig: string): Double;
function JavaFieldO(const Cls, Name, Sig: string): TJavaObject;
function JavaFieldStr(const Cls, Name: string): string;

{ A java.lang.String; a Pascal string of one. }
function JavaString(const S: string): TJavaObject;
function JavaToString(const Obj: TJavaObject): string;
{ A Java object from a handle Java gave (a local reference is kept as global). }
function JavaWrap(Handle: Pointer): TJavaObject;
{ The app's activity on Android (a Context, for Toast, Intent...); null elsewhere. }
function JavaActivity: TJavaObject;
{ Runs Proc on Android's UI thread (views, Toast), later, without waiting; at once elsewhere.
  It must not touch Pastel's forms (they live on the app's own thread). }
procedure JavaRunOnUiThread(Proc: TJavaUiProc);

{ An object of a Java interface (a listener, a Runnable, a Comparator) whose
  methods are done by Handler:
    Button.setOnClickListener(JavaImplement('android.view.View$OnClickListener', @Clicked));
  OnAppThread: Handler runs on the app's own thread, where Pastel's forms can be
  used (a method that answers nothing does not wait for it); False: on Java's
  thread that called, at once. The object lives while the program does. }
function JavaImplement(const InterfaceName: string; Handler: TJavaCallbackEvent;
  OnAppThread: Boolean = True): TJavaObject;
{ Inside a handler of JavaImplement: Java's signature of the method called,
  '(Landroid/view/View;I)V' - for an interface with two methods of one name. }
function JavaCallbackSignature: string;

{ Boxed values for Java (java.lang.Integer, Long, Boolean, Float, Double): answers of JavaImplement's handlers. }
function JavaInteger(V: Integer): TJavaObject;
function JavaInt64(V: Int64): TJavaObject;
function JavaBoolean(V: Boolean): TJavaObject;
function JavaSingle(V: Single): TJavaObject;
function JavaDouble(V: Double): TJavaObject;

{ Internal: the activity's object, set by Pastel.Android. }
var
  JavaActivityHandle: Pointer = nil;
  JavaVMHandle: Pointer = nil;

implementation

uses
  jni, DynLibs, SyncObjs{$IFDEF ANDROID}, Pastel.Android{$ENDIF}{$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  TJavaRef = class(TInterfacedObject, IJavaRef)
  private
    FHandle: Pointer;
  public
    constructor Create(AHandle: Pointer);
    destructor Destroy; override;
    function Handle: Pointer;
  end;

  TCallback = class
    Handler: TJavaCallbackEvent;
    OnAppThread: Boolean;
  end;

  TCreateJavaVM = function(VM: PPJavaVM; Env: PPJNIEnv; Args: Pointer): JInt; cdecl;

  TJavaVMOption = record
    optionString: PChar;
    extraInfo: Pointer;
  end;

  TJavaVMInitArgs = record
    version: JInt;
    nOptions: JInt;
    options: ^TJavaVMOption;
    ignoreUnrecognized: JBoolean;
  end;

var
  Lock: TCriticalSection;
  Classes_, Methods: TStringList;     { name -> global jclass; class.name.sig -> jmethodID }
  Problem: string = '';
  Started: Boolean = False;
  JvmLib: TLibHandle = NilHandle;
  Callbacks: TList;                   { TCallback: JavaImplement's, kept }
  ProxyClass: Pointer = nil;          { dev.pastel.PastelProxy }
  ProxyCreate: JMethodID = nil;

{ ---- the VM and this thread's environment ---- }

{$IFNDEF ANDROID}
{ the Java of the PATH: java's real place (links followed), two folders up }
function JavaHomeFromPath: string;
var
  P: string;
  {$IFDEF UNIX}
  Target: string;
  I: Integer;
  {$ENDIF}
begin
  Result := '';
  P := ExeSearch({$IFDEF WINDOWS}'java.exe'{$ELSE}'java'{$ENDIF}, SysUtils.GetEnvironmentVariable('PATH'));
  if P = '' then
    Exit;
  {$IFDEF UNIX}
  for I := 1 to 10 do
  begin
    Target := fpReadLink(P);
    if Target = '' then
      Break;
    if Target[1] <> '/' then
      Target := ExtractFilePath(P) + Target;
    P := ExpandFileName(Target);
  end;
  {$ENDIF}
  Result := ExtractFileDir(ExtractFileDir(P));
end;

{ without PASTEL_JAVA_CLASSPATH: the project's Java while developing (build/java of
  the folder it runs in: its classes, the jars "pastel java" listed), and java/
  beside the program (its jars and classes) }
function DefaultClassPath: string;
var
  Parts, L: TStringList;
  Dir, F: string;
  SR: TSearchRec;
begin
  Parts := TStringList.Create;
  L := TStringList.Create;
  try
    Dir := IncludeTrailingPathDelimiter(GetCurrentDir) + 'build' + PathDelim + 'java' + PathDelim;
    if DirectoryExists(Dir + 'classes') then
      Parts.Add(Dir + 'classes');
    if FileExists(Dir + 'classpath.txt') then
    begin
      L.LoadFromFile(Dir + 'classpath.txt');
      for F in L do
        if Trim(F) <> '' then
          Parts.Add(Trim(F));
    end;
    Dir := ExtractFilePath(ParamStr(0)) + 'java' + PathDelim;
    if DirectoryExists(Dir + 'classes') then
      Parts.Add(Dir + 'classes');
    if FindFirst(Dir + '*.jar', faAnyFile, SR) = 0 then
    begin
      repeat
        Parts.Add(Dir + SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    Parts.Delimiter := {$IFDEF WINDOWS}';'{$ELSE}':'{$ENDIF};
    Parts.StrictDelimiter := True;
    Result := Parts.DelimitedText;
  finally
    L.Free;
    Parts.Free;
  end;
end;

function StartVM: Boolean;
var
  Path, Home, ClassPath: string;
  Create: TCreateJavaVM;
  VM: PJavaVM;
  Env: PJNIEnv;
  Args: TJavaVMInitArgs;
  Opts: array[0..0] of TJavaVMOption;
  Opt: AnsiString;
begin
  Result := False;
  Path := SysUtils.GetEnvironmentVariable('PASTEL_JVM');
  if Path = '' then
  begin
    Home := SysUtils.GetEnvironmentVariable('JAVA_HOME');
    if Home = '' then
      Home := JavaHomeFromPath;
    if Home = '' then
    begin
      Problem := 'no Java here: set JAVA_HOME (or PASTEL_JVM, the path of ' +
        {$IFDEF WINDOWS}'jvm.dll'{$ELSE}'libjvm.so'{$ENDIF} + ')';
      Exit;
    end;
    Home := IncludeTrailingPathDelimiter(Home);
    {$IFDEF WINDOWS}
    Path := Home + 'bin\server\jvm.dll';
    {$ELSE}
    {$IFDEF DARWIN}
    Path := Home + 'lib/server/libjvm.dylib';
    {$ELSE}
    Path := Home + 'lib/server/libjvm.so';
    {$ENDIF}
    {$ENDIF}
  end;
  JvmLib := LoadLibrary(Path);
  if JvmLib = NilHandle then
  begin
    Problem := 'cannot load Java: ' + Path;
    Exit;
  end;
  Create := TCreateJavaVM(GetProcAddress(JvmLib, 'JNI_CreateJavaVM'));
  if not Assigned(Create) then
  begin
    Problem := Path + ' is not a Java VM';
    Exit;
  end;
  ClassPath := SysUtils.GetEnvironmentVariable('PASTEL_JAVA_CLASSPATH');
  if ClassPath = '' then
    ClassPath := DefaultClassPath;
  Opt := '-Djava.class.path=' + ClassPath;
  Opts[0].optionString := PChar(Opt);
  Opts[0].extraInfo := nil;
  Args.version := JNI_VERSION_1_6;
  Args.nOptions := 1;
  Args.options := @Opts[0];
  Args.ignoreUnrecognized := JNI_TRUE;
  if Create(@VM, @Env, @Args) <> JNI_OK then
  begin
    Problem := 'Java did not start';
    Exit;
  end;
  JavaVMHandle := VM;
  Result := True;
end;
{$ENDIF}

function EnsureVM: Boolean;
begin
  {$IFDEF ANDROID}
  if (JavaVMHandle = nil) and (AndroidActivity <> nil) then
  begin
    JavaVMHandle := AndroidActivity^.vm;
    JavaActivityHandle := AndroidActivity^.clazz;
  end;
  { a background job without a window: the VM of JNI_OnLoad (no activity: Java's own class loader) }
  if (JavaVMHandle = nil) and (AndroidJavaVM <> nil) then
    JavaVMHandle := AndroidJavaVM;
  Result := JavaVMHandle <> nil;
  if not Result then
    Problem := 'the app''s activity is not there yet';
  {$ELSE}
  if JavaVMHandle = nil then
  begin
    Lock.Enter;
    try
      if not Started then
      begin
        Started := True;
        StartVM;
      end;
    finally
      Lock.Leave;
    end;
  end;
  Result := JavaVMHandle <> nil;
  {$ENDIF}
end;

{ this thread's environment; a thread Java does not know is made known for the call (Attached) }
function GetEnv(out Attached: Boolean): PJNIEnv;
var
  VM: PJavaVM;
begin
  Result := nil;
  Attached := False;
  if not EnsureVM then
    raise EJavaError.Create(Problem);
  VM := PJavaVM(JavaVMHandle);
  if VM^^.GetEnv(VM, @Result, JNI_VERSION_1_6) = JNI_OK then
    Exit;
  Result := nil;
  if VM^^.AttachCurrentThread(VM, @Result, nil) <> JNI_OK then
    raise EJavaError.Create('this thread cannot call Java');
  Attached := True;
end;

procedure DoneEnv(Attached: Boolean);
var
  VM: PJavaVM;
begin
  if Attached then
  begin
    VM := PJavaVM(JavaVMHandle);
    VM^^.DetachCurrentThread(VM);
  end;
end;

function JavaAvailable: Boolean;
begin
  Result := EnsureVM;
end;

function JavaProblem: string;
begin
  if EnsureVM then
    Result := ''
  else
    Result := Problem;
end;

{ ---- references and strings ---- }

constructor TJavaRef.Create(AHandle: Pointer);
begin
  inherited Create;
  FHandle := AHandle;
end;

destructor TJavaRef.Destroy;
var
  Env: PJNIEnv;
  Attached: Boolean;
begin
  if (FHandle <> nil) and (JavaVMHandle <> nil) then
  try
    Env := GetEnv(Attached);
    try
      Env^^.DeleteGlobalRef(Env, FHandle);
    finally
      DoneEnv(Attached);
    end;
  except
    { the VM is gone: nothing to give back }
  end;
  inherited Destroy;
end;

function TJavaRef.Handle: Pointer;
begin
  Result := FHandle;
end;

{ a local reference as a TJavaObject (global); the local one is let go }
function Keep(Env: PJNIEnv; Local: Pointer): TJavaObject;
begin
  Result := Default(TJavaObject);
  if Local = nil then
    Exit;
  Result.Ref := TJavaRef.Create(Env^^.NewGlobalRef(Env, Local));
  Env^^.DeleteLocalRef(Env, Local);
end;

function NewJString(Env: PJNIEnv; const S: string): Pointer;
var
  W: UnicodeString;
begin
  W := UTF8Decode(S);
  if W = '' then
    Result := Env^^.NewString(Env, nil, 0)
  else
    Result := Env^^.NewString(Env, PJChar(PWideChar(W)), Length(W));
end;

function FromJString(Env: PJNIEnv; Str: Pointer): string;
var
  IsCopy: JBoolean;
  Len: Integer;
  P: PJChar;
  W: UnicodeString;
begin
  Result := '';
  if Str = nil then
    Exit;
  Len := Env^^.GetStringLength(Env, Str);
  if Len = 0 then
    Exit;
  P := Env^^.GetStringChars(Env, Str, IsCopy);
  try
    SetLength(W, Len);
    Move(P^, W[1], Len * SizeOf(WideChar));
  finally
    Env^^.ReleaseStringChars(Env, Str, P);
  end;
  Result := UTF8Encode(W);
end;

{ a Java exception: its message as an EJavaError }
procedure CheckException(Env: PJNIEnv; const Where: string);
var
  Ex, Cls, Msg: Pointer;
  Mid: JMethodID;
  Text: string;
begin
  if Env^^.ExceptionCheck(Env) = 0 then
    Exit;
  Ex := Env^^.ExceptionOccurred(Env);
  Env^^.ExceptionClear(Env);
  Text := 'a Java exception';
  if Ex <> nil then
  begin
    Cls := Env^^.GetObjectClass(Env, Ex);
    Mid := Env^^.GetMethodID(Env, Cls, 'toString', '()Ljava/lang/String;');
    if Mid <> nil then
    begin
      Msg := Env^^.CallObjectMethodA(Env, Ex, Mid, nil);
      if Env^^.ExceptionCheck(Env) <> 0 then
        Env^^.ExceptionClear(Env)
      else
      begin
        Text := FromJString(Env, Msg);
        Env^^.DeleteLocalRef(Env, Msg);
      end;
    end;
    Env^^.DeleteLocalRef(Env, Cls);
    Env^^.DeleteLocalRef(Env, Ex);
  end;
  raise EJavaError.Create(Where + ': ' + Text);
end;

{ ---- classes and methods ---- }

function SlashName(const Name: string): string;
var
  I: Integer;
  Parts: TStringArray;
  Path: string;
begin
  { 'android.app.Notification.Builder' -> 'android/app/Notification$Builder':
    the parts after the first capitalized one are inner classes }
  if Pos('/', Name) > 0 then
    Exit(Name);
  Parts := Name.Split(['.']);
  Path := '';
  for I := 0 to High(Parts) do
  begin
    if I > 0 then
      if (I > 0) and (Parts[I - 1] <> '') and (Parts[I - 1][1] in ['A'..'Z']) then
        Path := Path + '$'
      else
        Path := Path + '/';
    Path := Path + Parts[I];
  end;
  Result := Path;
end;

function FindClassIn(Env: PJNIEnv; const Name: string): Pointer;
var
  Local, Loader, LoaderCls, Str: Pointer;
  Mid: JMethodID;
  Arg: jvalue;
  Dotted: string;
begin
  Local := Env^^.FindClass(Env, PChar(SlashName(Name)));
  if Env^^.ExceptionCheck(Env) <> 0 then
  begin
    Env^^.ExceptionClear(Env);
    Local := nil;
  end;
  { the app's own classes: through the activity's class loader (threads of
    Pascal see only the system's classes with FindClass) }
  if (Local = nil) and (JavaActivityHandle <> nil) then
  begin
    LoaderCls := Env^^.GetObjectClass(Env, JavaActivityHandle);
    Mid := Env^^.GetMethodID(Env, LoaderCls, 'getClassLoader', '()Ljava/lang/ClassLoader;');
    Loader := Env^^.CallObjectMethodA(Env, JavaActivityHandle, Mid, nil);
    Env^^.DeleteLocalRef(Env, LoaderCls);
    LoaderCls := Env^^.GetObjectClass(Env, Loader);
    Mid := Env^^.GetMethodID(Env, LoaderCls, 'loadClass', '(Ljava/lang/String;)Ljava/lang/Class;');
    Dotted := StringReplace(SlashName(Name), '/', '.', [rfReplaceAll]);
    Str := NewJString(Env, Dotted);
    Arg.l := Str;
    Local := Env^^.CallObjectMethodA(Env, Loader, Mid, @Arg);
    if Env^^.ExceptionCheck(Env) <> 0 then
    begin
      Env^^.ExceptionClear(Env);
      Local := nil;
    end;
    Env^^.DeleteLocalRef(Env, Str);
    Env^^.DeleteLocalRef(Env, LoaderCls);
    Env^^.DeleteLocalRef(Env, Loader);
  end;
  Result := nil;
  if Local <> nil then
  begin
    Result := Env^^.NewGlobalRef(Env, Local);
    Env^^.DeleteLocalRef(Env, Local);
  end;
end;

function ClassIn(Env: PJNIEnv; const Name: string): Pointer;
var
  I: Integer;
begin
  Lock.Enter;
  try
    I := Classes_.IndexOf(Name);
    if I >= 0 then
      Exit(Pointer(Classes_.Objects[I]));
  finally
    Lock.Leave;
  end;
  Result := FindClassIn(Env, Name);
  if Result = nil then
    raise EJavaError.CreateFmt('there is no Java class %s', [Name]);
  Lock.Enter;
  try
    if Classes_.IndexOf(Name) < 0 then
      Classes_.AddObject(Name, TObject(Result));
  finally
    Lock.Leave;
  end;
end;

function JavaClass(const Name: string): Pointer;
var
  Env: PJNIEnv;
  Attached: Boolean;
begin
  Env := GetEnv(Attached);
  try
    Result := ClassIn(Env, Name);
  finally
    DoneEnv(Attached);
  end;
end;

function JavaHasClass(const Name: string): Boolean;
begin
  try
    Result := JavaAvailable and (JavaClass(Name) <> nil);
  except
    on EJavaError do
      Result := False;
  end;
end;

function MethodIn(Env: PJNIEnv; Cls: Pointer; const ClsName, Name, Sig: string; IsStatic: Boolean): JMethodID;
var
  Key: string;
  I: Integer;
begin
  Key := ClsName + '.' + Name + Sig;
  if IsStatic then
    Key := Key + '/s';
  Lock.Enter;
  try
    I := Methods.IndexOf(Key);
    if I >= 0 then
      Exit(JMethodID(Methods.Objects[I]));
  finally
    Lock.Leave;
  end;
  if IsStatic then
    Result := Env^^.GetStaticMethodID(Env, Cls, PChar(Name), PChar(Sig))
  else
    Result := Env^^.GetMethodID(Env, Cls, PChar(Name), PChar(Sig));
  if Env^^.ExceptionCheck(Env) <> 0 then
    Env^^.ExceptionClear(Env);
  if Result = nil then
    raise EJavaError.CreateFmt('%s has no method %s%s', [ClsName, Name, Sig]);
  Lock.Enter;
  try
    if Methods.IndexOf(Key) < 0 then
      Methods.AddObject(Key, TObject(Result));
  finally
    Lock.Leave;
  end;
end;

{ ---- arguments ---- }

type
  TArgs = record
    Values: array of jvalue;
    Locals: array of Pointer;     { strings made for the call: let go after it }
  end;

{ the types of a signature's parameters: '(ILjava/lang/String;[B)V' -> 'I', 'L', '[' }
function ParamKinds(const Sig: string; out Ret: Char): string;
var
  I: Integer;
begin
  Result := '';
  I := 2;
  while (I <= Length(Sig)) and (Sig[I] <> ')') do
  begin
    case Sig[I] of
      'L':
        begin
          Result := Result + 'L';
          while (I <= Length(Sig)) and (Sig[I] <> ';') do
            Inc(I);
        end;
      '[':
        begin
          Result := Result + '[';
          while (I <= Length(Sig)) and (Sig[I] = '[') do
            Inc(I);
          if Sig[I] = 'L' then
            while (I <= Length(Sig)) and (Sig[I] <> ';') do
              Inc(I);
        end;
    else
      Result := Result + Sig[I];
    end;
    Inc(I);
  end;
  Ret := 'V';
  if I < Length(Sig) then
    Ret := Sig[I + 1];
end;

function ArgInt(const A: TVarRec): Int64;
begin
  case A.VType of
    vtInteger: Result := A.VInteger;
    vtInt64: Result := A.VInt64^;
    vtQWord: Result := Int64(A.VQWord^);
    vtBoolean: Result := Ord(A.VBoolean);
    vtChar: Result := Ord(A.VChar);
    vtWideChar: Result := Ord(A.VWideChar);
  else
    raise EJavaError.Create('a whole number was expected');
  end;
end;

function ArgFloat(const A: TVarRec): Double;
begin
  case A.VType of
    vtExtended: Result := A.VExtended^;
    vtCurrency: Result := A.VCurrency^;
  else
    Result := ArgInt(A);
  end;
end;

function ArgString(const A: TVarRec; out S: string): Boolean;
begin
  Result := True;
  case A.VType of
    vtAnsiString: S := AnsiString(A.VAnsiString);
    vtUnicodeString: S := UTF8Encode(UnicodeString(A.VUnicodeString));
    vtWideString: S := UTF8Encode(WideString(A.VWideString));
    vtString: S := A.VString^;
    vtChar: S := A.VChar;
    vtWideChar: S := UTF8Encode(UnicodeString(A.VWideChar));
    vtPChar: S := A.VPChar;
  else
    Result := False;
  end;
end;

function MakeArgs(Env: PJNIEnv; const Sig: string; const Args: array of const; out Ret: Char): TArgs;
var
  Kinds, S: string;
  I: Integer;
begin
  Result := Default(TArgs);
  Kinds := ParamKinds(Sig, Ret);
  if Length(Kinds) <> Length(Args) then
    raise EJavaError.CreateFmt('%s takes %d values, not %d', [Sig, Length(Kinds), Length(Args)]);
  SetLength(Result.Values, Length(Args) + 1);
  for I := 0 to High(Args) do
  begin
    Result.Values[I].j := 0;
    case Kinds[I + 1] of
      'Z': Result.Values[I].z := Ord(ArgInt(Args[I]) <> 0);
      'B': Result.Values[I].b := ArgInt(Args[I]);
      'C': Result.Values[I].c := ArgInt(Args[I]);
      'S': Result.Values[I].s := ArgInt(Args[I]);
      'I': Result.Values[I].i := ArgInt(Args[I]);
      'J': Result.Values[I].j := ArgInt(Args[I]);
      'F': Result.Values[I].f := ArgFloat(Args[I]);
      'D': Result.Values[I].d := ArgFloat(Args[I]);
      'L', '[':
        if ArgString(Args[I], S) then
        begin
          Result.Values[I].l := NewJString(Env, S);
          Result.Locals := Concat(Result.Locals, [Result.Values[I].l]);
        end
        else if Args[I].VType = vtPointer then
          Result.Values[I].l := Args[I].VPointer
        else
          raise EJavaError.Create('an object (TJavaObject.Handle) or a string was expected');
    end;
  end;
end;

procedure FreeArgs(Env: PJNIEnv; const A: TArgs);
var
  P: Pointer;
begin
  for P in A.Locals do
    Env^^.DeleteLocalRef(Env, P);
end;

{ ---- calls ---- }

type
  TResult = record
    V: jvalue;
    Obj: TJavaObject;
    Str: string;
  end;

{ one call: an object's method (Obj), a static one (Obj nil), a constructor (IsNew) }
function Invoke(Obj: Pointer; const ClsName, Name, Sig: string; const Args: array of const;
  IsStatic, IsNew, WantString: Boolean): TResult;
var
  Env: PJNIEnv;
  Attached: Boolean;
  Cls, R: Pointer;
  Mid: JMethodID;
  A: TArgs;
  Ret: Char;
begin
  Result := Default(TResult);
  Env := GetEnv(Attached);
  try
    Cls := ClassIn(Env, ClsName);
    if not IsStatic and not IsNew and (Obj = nil) then
      raise EJavaError.CreateFmt('%s.%s: the object is null', [ClsName, Name]);
    if IsNew then
      Mid := MethodIn(Env, Cls, ClsName, '<init>', Sig, False)
    else
      Mid := MethodIn(Env, Cls, ClsName, Name, Sig, IsStatic);
    A := MakeArgs(Env, Sig, Args, Ret);
    try
      R := nil;
      if IsNew then
        R := Env^^.NewObjectA(Env, Cls, Mid, @A.Values[0])
      else if IsStatic then
        case Ret of
          'V': Env^^.CallStaticVoidMethodA(Env, Cls, Mid, @A.Values[0]);
          'Z': Result.V.z := Env^^.CallStaticBooleanMethodA(Env, Cls, Mid, @A.Values[0]);
          'B': Result.V.i := Env^^.CallStaticByteMethodA(Env, Cls, Mid, @A.Values[0]);
          'C': Result.V.i := Env^^.CallStaticCharMethodA(Env, Cls, Mid, @A.Values[0]);
          'S': Result.V.i := Env^^.CallStaticShortMethodA(Env, Cls, Mid, @A.Values[0]);
          'I': Result.V.i := Env^^.CallStaticIntMethodA(Env, Cls, Mid, @A.Values[0]);
          'J': Result.V.j := Env^^.CallStaticLongMethodA(Env, Cls, Mid, @A.Values[0]);
          'F': Result.V.f := Env^^.CallStaticFloatMethodA(Env, Cls, Mid, @A.Values[0]);
          'D': Result.V.d := Env^^.CallStaticDoubleMethodA(Env, Cls, Mid, @A.Values[0]);
        else
          R := Env^^.CallStaticObjectMethodA(Env, Cls, Mid, @A.Values[0]);
        end
      else
        case Ret of
          'V': Env^^.CallVoidMethodA(Env, Obj, Mid, @A.Values[0]);
          'Z': Result.V.z := Env^^.CallBooleanMethodA(Env, Obj, Mid, @A.Values[0]);
          'B': Result.V.i := Env^^.CallByteMethodA(Env, Obj, Mid, @A.Values[0]);
          'C': Result.V.i := Env^^.CallCharMethodA(Env, Obj, Mid, @A.Values[0]);
          'S': Result.V.i := Env^^.CallShortMethodA(Env, Obj, Mid, @A.Values[0]);
          'I': Result.V.i := Env^^.CallIntMethodA(Env, Obj, Mid, @A.Values[0]);
          'J': Result.V.j := Env^^.CallLongMethodA(Env, Obj, Mid, @A.Values[0]);
          'F': Result.V.f := Env^^.CallFloatMethodA(Env, Obj, Mid, @A.Values[0]);
          'D': Result.V.d := Env^^.CallDoubleMethodA(Env, Obj, Mid, @A.Values[0]);
        else
          R := Env^^.CallObjectMethodA(Env, Obj, Mid, @A.Values[0]);
        end;
      CheckException(Env, ClsName + '.' + Name);
      if R <> nil then
        if WantString then
        begin
          Result.Str := FromJString(Env, R);
          Env^^.DeleteLocalRef(Env, R);
        end
        else
          Result.Obj := Keep(Env, R);
    finally
      FreeArgs(Env, A);
    end;
  finally
    DoneEnv(Attached);
  end;
end;

function JavaNew(const Cls, Sig: string; const Args: array of const): TJavaObject;
begin
  Result := Invoke(nil, Cls, '<init>', Sig, Args, False, True, False).Obj;
end;

procedure JavaCall(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const);
begin
  Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False);
end;

function JavaCallZ(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Boolean;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False).V.z <> 0;
end;

function JavaCallI(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Integer;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False).V.i;
end;

function JavaCallJ(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Int64;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False).V.j;
end;

function JavaCallF(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Single;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False).V.f;
end;

function JavaCallD(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): Double;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False).V.d;
end;

function JavaCallO(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): TJavaObject;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, False).Obj;
end;

function JavaCallStr(const Obj: TJavaObject; const Cls, Name, Sig: string; const Args: array of const): string;
begin
  Result := Invoke(Obj.Handle, Cls, Name, Sig, Args, False, False, True).Str;
end;

procedure JavaStatic(const Cls, Name, Sig: string; const Args: array of const);
begin
  Invoke(nil, Cls, Name, Sig, Args, True, False, False);
end;

function JavaStaticZ(const Cls, Name, Sig: string; const Args: array of const): Boolean;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, False).V.z <> 0;
end;

function JavaStaticI(const Cls, Name, Sig: string; const Args: array of const): Integer;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, False).V.i;
end;

function JavaStaticJ(const Cls, Name, Sig: string; const Args: array of const): Int64;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, False).V.j;
end;

function JavaStaticF(const Cls, Name, Sig: string; const Args: array of const): Single;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, False).V.f;
end;

function JavaStaticD(const Cls, Name, Sig: string; const Args: array of const): Double;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, False).V.d;
end;

function JavaStaticO(const Cls, Name, Sig: string; const Args: array of const): TJavaObject;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, False).Obj;
end;

function JavaStaticStr(const Cls, Name, Sig: string; const Args: array of const): string;
begin
  Result := Invoke(nil, Cls, Name, Sig, Args, True, False, True).Str;
end;

{ ---- static fields ---- }

function GetField(const ClsName, Name, Sig: string; WantString: Boolean): TResult;
var
  Env: PJNIEnv;
  Attached: Boolean;
  Cls, R: Pointer;
  Fid: JFieldID;
begin
  Result := Default(TResult);
  Env := GetEnv(Attached);
  try
    Cls := ClassIn(Env, ClsName);
    Fid := Env^^.GetStaticFieldID(Env, Cls, PChar(Name), PChar(Sig));
    if Env^^.ExceptionCheck(Env) <> 0 then
      Env^^.ExceptionClear(Env);
    if Fid = nil then
      raise EJavaError.CreateFmt('%s has no field %s', [ClsName, Name]);
    R := nil;
    case Sig[1] of
      'Z': Result.V.z := Env^^.GetStaticBooleanField(Env, Cls, Fid);
      'B': Result.V.i := Env^^.GetStaticByteField(Env, Cls, Fid);
      'C': Result.V.i := Env^^.GetStaticCharField(Env, Cls, Fid);
      'S': Result.V.i := Env^^.GetStaticShortField(Env, Cls, Fid);
      'I': Result.V.i := Env^^.GetStaticIntField(Env, Cls, Fid);
      'J': Result.V.j := Env^^.GetStaticLongField(Env, Cls, Fid);
      'F': Result.V.d := Env^^.GetStaticFloatField(Env, Cls, Fid);
      'D': Result.V.d := Env^^.GetStaticDoubleField(Env, Cls, Fid);
    else
      R := Env^^.GetStaticObjectField(Env, Cls, Fid);
    end;
    if R <> nil then
      if WantString then
      begin
        Result.Str := FromJString(Env, R);
        Env^^.DeleteLocalRef(Env, R);
      end
      else
        Result.Obj := Keep(Env, R);
  finally
    DoneEnv(Attached);
  end;
end;

function JavaFieldI(const Cls, Name: string): Integer;
begin
  Result := GetField(Cls, Name, 'I', False).V.i;
end;

function JavaFieldJ(const Cls, Name: string): Int64;
begin
  Result := GetField(Cls, Name, 'J', False).V.j;
end;

function JavaFieldZ(const Cls, Name: string): Boolean;
begin
  Result := GetField(Cls, Name, 'Z', False).V.z <> 0;
end;

function JavaFieldD(const Cls, Name, Sig: string): Double;
begin
  Result := GetField(Cls, Name, Sig, False).V.d;
end;

function JavaFieldO(const Cls, Name, Sig: string): TJavaObject;
begin
  Result := GetField(Cls, Name, Sig, False).Obj;
end;

function JavaFieldStr(const Cls, Name: string): string;
begin
  Result := GetField(Cls, Name, 'Ljava/lang/String;', True).Str;
end;

{ ---- objects ---- }

function TJavaObject.Handle: Pointer;
begin
  if Ref = nil then
    Result := nil
  else
    Result := Ref.Handle;
end;

function TJavaObject.IsNull: Boolean;
begin
  Result := Handle = nil;
end;

function TJavaObject.ToString: string;
begin
  if IsNull then
    Result := 'null'
  else
    Result := JavaCallStr(Self, 'java.lang.Object', 'toString', '()Ljava/lang/String;', []);
end;

function TJavaObject.JavaClassName: string;
var
  C: TJavaObject;
begin
  if IsNull then
    Exit('');
  C := JavaCallO(Self, 'java.lang.Object', 'getClass', '()Ljava/lang/Class;', []);
  Result := JavaCallStr(C, 'java.lang.Class', 'getName', '()Ljava/lang/String;', []);
end;

function TJavaObject.IsInstanceOf(const AClass: string): Boolean;
var
  Env: PJNIEnv;
  Attached: Boolean;
begin
  if IsNull then
    Exit(False);
  Env := GetEnv(Attached);
  try
    Result := Env^^.IsInstanceOf(Env, Handle, ClassIn(Env, AClass)) <> 0;
  finally
    DoneEnv(Attached);
  end;
end;

function TJavaObject.AsInteger: Integer;
begin
  Result := Integer(AsInt64);
end;

function TJavaObject.AsInt64: Int64;
begin
  if IsNull then
    Result := 0
  else if IsInstanceOf('java.lang.Number') then
    Result := JavaCallJ(Self, 'java.lang.Number', 'longValue', '()J', [])
  else if IsInstanceOf('java.lang.Character') then
    Result := JavaCallI(Self, 'java.lang.Character', 'charValue', '()C', [])
  else if IsInstanceOf('java.lang.Boolean') then
    Result := Ord(AsBoolean)
  else
    raise EJavaError.CreateFmt('%s is not a number', [JavaClassName]);
end;

function TJavaObject.AsBoolean: Boolean;
begin
  if IsNull then
    Result := False
  else if IsInstanceOf('java.lang.Boolean') then
    Result := JavaCallZ(Self, 'java.lang.Boolean', 'booleanValue', '()Z', [])
  else
    Result := AsInt64 <> 0;
end;

function TJavaObject.AsDouble: Double;
begin
  if IsNull then
    Result := 0
  else if IsInstanceOf('java.lang.Number') then
    Result := JavaCallD(Self, 'java.lang.Number', 'doubleValue', '()D', [])
  else
    Result := AsInt64;
end;

function TJavaObject.AsString: string;
begin
  if IsNull then
    Result := ''
  else
    Result := ToString;
end;

function JavaInteger(V: Integer): TJavaObject;
begin
  Result := JavaStaticO('java.lang.Integer', 'valueOf', '(I)Ljava/lang/Integer;', [V]);
end;

function JavaInt64(V: Int64): TJavaObject;
begin
  Result := JavaStaticO('java.lang.Long', 'valueOf', '(J)Ljava/lang/Long;', [V]);
end;

function JavaBoolean(V: Boolean): TJavaObject;
begin
  Result := JavaStaticO('java.lang.Boolean', 'valueOf', '(Z)Ljava/lang/Boolean;', [V]);
end;

function JavaSingle(V: Single): TJavaObject;
begin
  Result := JavaStaticO('java.lang.Float', 'valueOf', '(F)Ljava/lang/Float;', [V]);
end;

function JavaDouble(V: Double): TJavaObject;
begin
  Result := JavaStaticO('java.lang.Double', 'valueOf', '(D)Ljava/lang/Double;', [V]);
end;

function JavaString(const S: string): TJavaObject;
var
  Env: PJNIEnv;
  Attached: Boolean;
begin
  Env := GetEnv(Attached);
  try
    Result := Keep(Env, NewJString(Env, S));
  finally
    DoneEnv(Attached);
  end;
end;

function JavaToString(const Obj: TJavaObject): string;
begin
  Result := Obj.ToString;
end;

function JavaWrap(Handle: Pointer): TJavaObject;
var
  Env: PJNIEnv;
  Attached: Boolean;
begin
  Result := Default(TJavaObject);
  if Handle = nil then
    Exit;
  Env := GetEnv(Attached);
  try
    Result.Ref := TJavaRef.Create(Env^^.NewGlobalRef(Env, Handle));
  finally
    DoneEnv(Attached);
  end;
end;

var
  ActivityObj: TJavaObject;
  I_: Integer;

function JavaActivity: TJavaObject;
begin
  EnsureVM;
  if ActivityObj.IsNull and (JavaActivityHandle <> nil) then
    ActivityObj := JavaWrap(JavaActivityHandle);
  Result := ActivityObj;
end;

{ ---- the UI thread ---- }

type
  PUiCall = ^TUiCall;
  TUiCall = record
    Proc: TJavaUiProc;
  end;

{$IFDEF ANDROID}
{ called on the UI thread (Pastel.Android's nativeRun) with what JavaRunOnUiThread gave }
procedure RunUiCall(Token: Int64);
var
  C: PUiCall;
begin
  C := PUiCall(PtrUInt(Token));
  try
    try
      C^.Proc();
    except
      on E: Exception do
        AndroidLog('error: ' + E.Message);
    end;
  finally
    Dispose(C);
  end;
end;
{$ENDIF}

procedure JavaRunOnUiThread(Proc: TJavaUiProc);
{$IFDEF ANDROID}
var
  C: PUiCall;
{$ENDIF}
begin
  {$IFDEF ANDROID}
  New(C);
  C^.Proc := Proc;
  if not AndroidCall('runOnUi', '(J)V', [Int64(PtrUInt(C))]) then
  begin
    Dispose(C);
    raise EJavaError.Create('the UI thread cannot be reached');
  end;
  {$ELSE}
  Proc();
  {$ENDIF}
end;

{ ---- Java interfaces done by Pascal ---- }

{$IFNDEF ANDROID}
{$I pastel.javaproxy.inc}
{$ENDIF}

type
  { one call of an implemented interface's method }
  TCallbackCall = class
    Callback: TCallback;
    Method, Signature: string;
    Args: TJavaArgs;
    Answer: TJavaObject;
    Error: string;
    procedure Run;
    procedure RunAndFree;
  end;

threadvar
  CurrentSignature: string;

function JavaCallbackSignature: string;
begin
  Result := CurrentSignature;
end;

procedure TCallbackCall.Run;
var
  Before: string;
begin
  Before := CurrentSignature;
  CurrentSignature := Signature;
  try
    Callback.Handler(Method, Args, Answer);
  except
    on E: Exception do
      if E.Message <> '' then
        Error := E.Message
      else
        Error := E.ClassName;
  end;
  CurrentSignature := Before;
end;

{ a call that answers nothing, on the app thread later: an error has no one to go to }
procedure TCallbackCall.RunAndFree;
begin
  try
    Run;
    if Error <> '' then
      {$IFDEF ANDROID}
      AndroidLog('error: ' + Method + ': ' + Error);
      {$ELSE}
      WriteLn(StdErr, 'error: ', Method, ': ', Error);
      {$ENDIF}
  finally
    Free;
  end;
end;

{ PastelProxy.nativeInvoke: a method of an object JavaImplement made, on the thread that called it }
function NativeInvoke(Env: PJNIEnv; Cls: JClass; Token: JLong; Method, Sig: JString; Args: JObjectArray;
  WantsAnswer: JBoolean): JObject; {$IFDEF MSWINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
var
  C: TCallbackCall;
  I, N: Integer;
  Ex: Pointer;
begin
  Result := nil;
  C := TCallbackCall.Create;
  try
    C.Callback := TCallback(PtrUInt(Token));
    C.Method := FromJString(Env, Method);
    C.Signature := FromJString(Env, Sig);
    N := 0;
    if Args <> nil then
      N := Env^^.GetArrayLength(Env, Args);
    SetLength(C.Args, N);
    for I := 0 to N - 1 do
      C.Args[I] := Keep(Env, Env^^.GetObjectArrayElement(Env, Args, I));
    if C.Callback.OnAppThread and (GetCurrentThreadID <> MainThreadID) then
    begin
      if WantsAnswer = 0 then
      begin
        TThread.Queue(nil, @C.RunAndFree);
        C := nil;
        Exit;
      end;
      TThread.Synchronize(nil, @C.Run);
    end
    else
      C.Run;
    if C.Error <> '' then
    begin
      Ex := Env^^.FindClass(Env, 'java/lang/RuntimeException');
      Env^^.ThrowNew(Env, Ex, PChar(C.Method + ': ' + C.Error));
      Env^^.DeleteLocalRef(Env, Ex);
    end
    else if not C.Answer.IsNull then
      Result := Env^^.NewLocalRef(Env, C.Answer.Handle);
  finally
    C.Free;
  end;
end;

{ dev.pastel.PastelProxy, with its native method: in the app's classes.dex on
  Android, given to the Java VM here elsewhere }
procedure EnsureProxy(Env: PJNIEnv);
var
  Cls: Pointer;
  {$IFNDEF ANDROID}
    Local, LoaderCls, Loader: Pointer;
  Mid: JMethodID;
  {$ENDIF}
  M: JNINativeMethod;
begin
  Lock.Enter;
  try
    if ProxyClass <> nil then
      Exit;
    { Java's threads will call Pascal: the heap and TThread.Queue must know there are threads }
    IsMultiThread := True;
    Cls := FindClassIn(Env, 'dev.pastel.PastelProxy');
    {$IFNDEF ANDROID}
    if Cls = nil then
    begin
      LoaderCls := Env^^.FindClass(Env, 'java/lang/ClassLoader');
      Mid := Env^^.GetStaticMethodID(Env, LoaderCls, 'getSystemClassLoader', '()Ljava/lang/ClassLoader;');
      Loader := Env^^.CallStaticObjectMethodA(Env, LoaderCls, Mid, nil);
      CheckException(Env, 'ClassLoader.getSystemClassLoader');
      Local := Env^^.DefineClass(Env, 'dev/pastel/PastelProxy', Loader, PJByte(@PastelProxyClass[0]),
        Length(PastelProxyClass));
      Env^^.DeleteLocalRef(Env, Loader);
      Env^^.DeleteLocalRef(Env, LoaderCls);
      CheckException(Env, 'dev.pastel.PastelProxy');
      Cls := Env^^.NewGlobalRef(Env, Local);
      Env^^.DeleteLocalRef(Env, Local);
    end;
    {$ENDIF}
    if Cls = nil then
      raise EJavaError.Create('dev.pastel.PastelProxy is not in the app (Pastel''s classes.dex is older)');
    M.name := 'nativeInvoke';
    M.signature := '(JLjava/lang/String;Ljava/lang/String;[Ljava/lang/Object;Z)Ljava/lang/Object;';
    M.fnPtr := @NativeInvoke;
    if Env^^.RegisterNatives(Env, Cls, @M, 1) <> 0 then
    begin
      CheckException(Env, 'dev.pastel.PastelProxy');
      raise EJavaError.Create('dev.pastel.PastelProxy: its native method cannot be given');
    end;
    ProxyCreate := Env^^.GetStaticMethodID(Env, Cls, 'create', '(Ljava/lang/Class;J)Ljava/lang/Object;');
    CheckException(Env, 'dev.pastel.PastelProxy.create');
    ProxyClass := Cls;
  finally
    Lock.Leave;
  end;
end;

function JavaImplement(const InterfaceName: string; Handler: TJavaCallbackEvent;
  OnAppThread: Boolean): TJavaObject;
var
  Env: PJNIEnv;
  Attached: Boolean;
  C: TCallback;
  A: array[0..1] of jvalue;
  R: Pointer;
begin
  if not Assigned(Handler) then
    raise EJavaError.Create('JavaImplement ' + InterfaceName + ': no handler');
  Env := GetEnv(Attached);
  try
    EnsureProxy(Env);
    A[0].l := ClassIn(Env, InterfaceName);
    C := TCallback.Create;
    C.Handler := Handler;
    C.OnAppThread := OnAppThread;
    Lock.Enter;
    try
      Callbacks.Add(C);
    finally
      Lock.Leave;
    end;
    A[1].j := Int64(PtrUInt(C));
    R := Env^^.CallStaticObjectMethodA(Env, ProxyClass, ProxyCreate, @A[0]);
    CheckException(Env, 'JavaImplement ' + InterfaceName);
    Result := Keep(Env, R);
  finally
    DoneEnv(Attached);
  end;
end;

initialization
  {$IFDEF ANDROID}
  AndroidUiCall := @RunUiCall;
  {$ENDIF}
  Lock := TCriticalSection.Create;
  Classes_ := TStringList.Create;
  Classes_.Sorted := True;
  Methods := TStringList.Create;
  Methods.Sorted := True;
  Callbacks := TList.Create;

finalization
  ActivityObj.Ref := nil;
  {$IFNDEF ANDROID}
  { a Java started here ends before the program (its threads would outlive Pascal's runtime) }
  if Started and (JavaVMHandle <> nil) then
  begin
    PJavaVM(JavaVMHandle)^^.DestroyJavaVM(PJavaVM(JavaVMHandle));
    JavaVMHandle := nil;
  end;
  {$ENDIF}
  for I_ := 0 to Callbacks.Count - 1 do
    TObject(Callbacks[I_]).Free;
  Callbacks.Free;
  Methods.Free;
  Classes_.Free;
  Lock.Free;

end.
