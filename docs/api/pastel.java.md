# Pastel.Java

Java from Pascal: any class of Android (or of the app's own Java
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

`uses Pastel.Java;` · source: [framework/src/pastel.java.pas](../../framework/src/pastel.java.pas)

**Contents:** [EJavaError](#ejavaerror) · [IJavaRef](#ijavaref) · [TJavaObject](#tjavaobject) · [JavaAvailable](#javaavailable) · [JavaProblem](#javaproblem) · [JavaClass](#javaclass) · [JavaHasClass](#javahasclass) · [JavaNew](#javanew) · [JavaCall](#javacall) · [JavaCallZ](#javacallz) · [JavaCallI](#javacalli) · [JavaCallJ](#javacallj) · [JavaCallF](#javacallf) · [JavaCallD](#javacalld) · [JavaCallO](#javacallo) · [JavaCallStr](#javacallstr) · [JavaStatic](#javastatic) · [JavaStaticZ](#javastaticz) · [JavaStaticI](#javastatici) · [JavaStaticJ](#javastaticj) · [JavaStaticF](#javastaticf) · [JavaStaticD](#javastaticd) · [JavaStaticO](#javastatico) · [JavaStaticStr](#javastaticstr) · [JavaFieldI](#javafieldi) · [JavaFieldJ](#javafieldj) · [JavaFieldZ](#javafieldz) · [JavaFieldD](#javafieldd) · [JavaFieldO](#javafieldo) · [JavaFieldStr](#javafieldstr) · [JavaString](#javastring) · [JavaToString](#javatostring) · [JavaWrap](#javawrap) · [JavaActivity](#javaactivity) · [JavaRunOnUiThread](#javarunonuithread) · [JavaImplement](#javaimplement) · [JavaCallbackSignature](#javacallbacksignature) · [JavaInteger](#javainteger) · [JavaInt64](#javaint64) · [JavaBoolean](#javaboolean) · [JavaSingle](#javasingle) · [JavaDouble](#javadouble)

## Types

### EJavaError

```pascal
type EJavaError = class(Exception)
```

### IJavaRef

```pascal
type IJavaRef = interface
```

| | |
|---|---|
| `function Handle: Pointer` |  |

### TJavaObject

```pascal
type TJavaObject = record
```

A Java object; Pascal keeps it alive while it is used (a global reference).

| | |
|---|---|
| `Ref: IJavaRef` |  |
| `function Handle: Pointer` | Java's handle (jobject) for calls; nil for null |
| `function IsNull: Boolean` |  |
| `function ToString: string` | java.lang.Object's toString |
| `function JavaClassName: string` | its class's name: 'android.widget.Toast' |
| `function IsInstanceOf(const AClass: string): Boolean` |  |
| `function AsInteger: Integer` | a boxed value's (java.lang.Integer, Long, Boolean, Double, Character...): 0, False, '' for null |
| `function AsInt64: Int64` |  |
| `function AsBoolean: Boolean` |  |
| `function AsDouble: Double` |  |
| `function AsString: string` |  |

## Other types

| | |
|---|---|
| `type TJavaUiProc = procedure` |  |
| `type TJavaArgs = array of TJavaObject` |  |
| `type TJavaCallbackEvent = procedure(Method: string; Args: TJavaArgs; Answer: TJavaObject)` | a call of an interface's method that Pascal does (JavaImplement): the method's name, its arguments (numbers boxed: Args[0].AsInteger) and what to answer (left null: null, 0 or False; a number boxed: JavaInteger(1)) |

## Routines

### JavaAvailable

```pascal
function JavaAvailable: Boolean
```

True when Java can be called here (Android; a computer with Java).

### JavaProblem

```pascal
function JavaProblem: string
```

Why Java cannot be called ('' when it can).

### JavaClass

```pascal
function JavaClass(const Name: string): Pointer
```

A class by its name ('android.widget.Toast', 'android.app.Notification$Builder'
or with a dot for the inner class): Java's handle, kept. EJavaError when there is none.

### JavaHasClass

```pascal
function JavaHasClass(const Name: string): Boolean
```

True when the class is there.

### JavaNew

```pascal
function JavaNew(const Cls: string; const Sig: string; const Args: array of const): TJavaObject
```

A new object: JavaNew('java.lang.StringBuilder', '(Ljava/lang/String;)V', ['abc']).

### JavaCall

```pascal
procedure JavaCall(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const)
```

An object's method, by what it answers: nothing (JavaCall), Boolean, Integer
(int, short, byte, char), Int64 (long), Single, Double, an object, a string.

### JavaCallZ

```pascal
function JavaCallZ(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): Boolean
```

### JavaCallI

```pascal
function JavaCallI(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): Integer
```

### JavaCallJ

```pascal
function JavaCallJ(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): Int64
```

### JavaCallF

```pascal
function JavaCallF(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): Single
```

### JavaCallD

```pascal
function JavaCallD(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): Double
```

### JavaCallO

```pascal
function JavaCallO(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): TJavaObject
```

### JavaCallStr

```pascal
function JavaCallStr(const Obj: TJavaObject; const Cls: string; const Name: string; const Sig: string; const Args: array of const): string
```

### JavaStatic

```pascal
procedure JavaStatic(const Cls: string; const Name: string; const Sig: string; const Args: array of const)
```

The same for a class's static methods.

### JavaStaticZ

```pascal
function JavaStaticZ(const Cls: string; const Name: string; const Sig: string; const Args: array of const): Boolean
```

### JavaStaticI

```pascal
function JavaStaticI(const Cls: string; const Name: string; const Sig: string; const Args: array of const): Integer
```

### JavaStaticJ

```pascal
function JavaStaticJ(const Cls: string; const Name: string; const Sig: string; const Args: array of const): Int64
```

### JavaStaticF

```pascal
function JavaStaticF(const Cls: string; const Name: string; const Sig: string; const Args: array of const): Single
```

### JavaStaticD

```pascal
function JavaStaticD(const Cls: string; const Name: string; const Sig: string; const Args: array of const): Double
```

### JavaStaticO

```pascal
function JavaStaticO(const Cls: string; const Name: string; const Sig: string; const Args: array of const): TJavaObject
```

### JavaStaticStr

```pascal
function JavaStaticStr(const Cls: string; const Name: string; const Sig: string; const Args: array of const): string
```

### JavaFieldI

```pascal
function JavaFieldI(const Cls: string; const Name: string): Integer
```

A static field's value (Sig: its type, 'I', 'Ljava/lang/String;').

### JavaFieldJ

```pascal
function JavaFieldJ(const Cls: string; const Name: string): Int64
```

### JavaFieldZ

```pascal
function JavaFieldZ(const Cls: string; const Name: string): Boolean
```

### JavaFieldD

```pascal
function JavaFieldD(const Cls: string; const Name: string; const Sig: string): Double
```

### JavaFieldO

```pascal
function JavaFieldO(const Cls: string; const Name: string; const Sig: string): TJavaObject
```

### JavaFieldStr

```pascal
function JavaFieldStr(const Cls: string; const Name: string): string
```

### JavaString

```pascal
function JavaString(const S: string): TJavaObject
```

A java.lang.String; a Pascal string of one.

### JavaToString

```pascal
function JavaToString(const Obj: TJavaObject): string
```

### JavaWrap

```pascal
function JavaWrap(Handle: Pointer): TJavaObject
```

A Java object from a handle Java gave (a local reference is kept as global).

### JavaActivity

```pascal
function JavaActivity: TJavaObject
```

The app's activity on Android (a Context, for Toast, Intent...); null elsewhere.

### JavaRunOnUiThread

```pascal
procedure JavaRunOnUiThread(Proc: TJavaUiProc)
```

Runs Proc on Android's UI thread (views, Toast), later, without waiting; at once elsewhere.
It must not touch Pastel's forms (they live on the app's own thread).

### JavaImplement

```pascal
function JavaImplement(const InterfaceName: string; Handler: TJavaCallbackEvent; OnAppThread: Boolean = True): TJavaObject
```

An object of a Java interface (a listener, a Runnable, a Comparator) whose
methods are done by Handler:
Button.setOnClickListener(JavaImplement('android.view.View$OnClickListener', @Clicked));
OnAppThread: Handler runs on the app's own thread, where Pastel's forms can be
used (a method that answers nothing does not wait for it); False: on Java's
thread that called, at once. The object lives while the program does.

### JavaCallbackSignature

```pascal
function JavaCallbackSignature: string
```

Inside a handler of JavaImplement: Java's signature of the method called,
'(Landroid/view/View;I)V' - for an interface with two methods of one name.

### JavaInteger

```pascal
function JavaInteger(V: Integer): TJavaObject
```

Boxed values for Java (java.lang.Integer, Long, Boolean, Float, Double): answers of JavaImplement's handlers.

### JavaInt64

```pascal
function JavaInt64(V: Int64): TJavaObject
```

### JavaBoolean

```pascal
function JavaBoolean(V: Boolean): TJavaObject
```

### JavaSingle

```pascal
function JavaSingle(V: Single): TJavaObject
```

### JavaDouble

```pascal
function JavaDouble(V: Double): TJavaObject
```

## Constants and variables

| | |
|---|---|
| `var JavaActivityHandle: Pointer` |  |
| `var JavaVMHandle: Pointer` |  |
