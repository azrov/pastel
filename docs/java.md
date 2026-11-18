# Java from Pascal

Android is written in Java: everything a phone can do is a Java class — `Toast`, `AlarmManager`, `BluetoothAdapter`,
`TextToSpeech`, `MediaPlayer`. Pastel's own units cover what most apps need (dialogs, notifications, the camera, the
place); for the rest, Pascal calls Java directly.

## The classes you need, as Pascal

`pastel java add` reads the classes from Android's `android.jar` and writes typed Pascal for them into
`src/java/javaclasses.pas` (like Delphi's Java2OP):

```sh
pastel java search Toast                       # which classes have that name
pastel java add android.widget.Toast android.os.Build android.os.Build.VERSION
```

```pascal
uses Pastel.Java, JavaClasses;

JToast.makeText(JavaActivity, 'Saved', JToast.LENGTH_SHORT).show;     // (on the UI thread: below)
Label1.Text := JBuild.MODEL + ', Android ' + JBuild_VERSION.RELEASE;
```

Each class becomes a record named `J` and the class's name (`JToast`; an inner class `JNotification_Builder`) with:

- its methods, the inherited ones too, with the same names (`show`, `setText`, `getWidth`);
- its constructors as `New`: `JIntent.New(JavaActivity, ...)`;
- its constants (`JToast.LENGTH_SHORT`) and static fields (`JBuild.MODEL`).

`String` and `CharSequence` are Pascal strings; `int`, `long`, `boolean`, `double`... their Pascal types; the
classes of the list their records; other objects `TJavaObject`. Java does not keep the names of parameters, so
they are named after their types (`AContext`, `AInt`). A comment above each method shows the Java one. The list
is kept in `pastel.toml`; `pastel java remove` takes a class out, `pastel java` writes the unit again.

```toml
[java]
classes = ["android.widget.Toast", "android.os.Build"]
```

The file is written by Pastel: change the list, not the file. It is part of the project (in git): building
does not need Android's SDK.

## The app's own Java

Java files in `src/java` (with their packages' folders) are compiled into the app with Pastel's: for an example
of Android's documentation copied as it is, or a listener, or anything that is easier in Java. Add their classes
to the list like Android's:

```java
// src/java/demo/Greeter.java
package demo;

public class Greeter {
    public static String hello(String name) { return "Hello, " + name; }
}
```

```sh
pastel java add demo.Greeter
```

```pascal
Label1.Text := JGreeter.hello('Ada');
```

They need Java's compiler (`javac`, a JDK) and Android's `d8` (build tools 28 or newer) or `dx`.

## Calls of your own

Without the generated records, `Pastel.Java` calls any method by its name and Java's signature:

```pascal
S := JavaFieldStr('android.os.Build', 'MODEL');
N := JavaStaticI('java.lang.Integer', 'parseInt', '(Ljava/lang/String;)I', ['42']);
L := JavaNew('java.util.ArrayList', '()V', []);
JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', [JavaString('x').Handle]);
```

`JavaCall` answers nothing; `JavaCallZ`, `...I`, `...J`, `...F`, `...D`, `...O`, `...Str` a `Boolean`, `Integer`,
`Int64`, `Single`, `Double`, `TJavaObject`, `string`; `JavaStatic...` the same for static methods. Pascal strings
become `java.lang.String`; objects are passed as `Obj.Handle`.

`TJavaObject` keeps a Java object alive while Pascal uses it and lets it go by itself, like a string. A Java
exception becomes an `EJavaError` with Java's message:

```pascal
try
  N := JavaStaticI('java.lang.Integer', 'parseInt', '(Ljava/lang/String;)I', [Edit1.Text]);
except
  on E: EJavaError do ShowMessage(E.Message);   // java.lang.NumberFormatException: For input string: "x"
end;
```

## Java calling Pascal: listeners

Android tells an app what happened through interfaces: `View.OnClickListener`, `Runnable`,
`TextToSpeech.OnInitListener`. `JavaImplement` makes an object of an interface whose methods are a Pascal method:

```pascal
procedure THomeForm.SpeechReady(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
begin
  if Method = 'onInit' then
    StatusLabel.Text := 'ready: ' + IntToStr(Args[0].AsInteger);
end;

Speech := JTextToSpeech.New(JavaActivity, JTextToSpeech_OnInitListener.Implement(@SpeechReady));
```

The handler gets the method's name and its arguments, `TJavaObject`s: numbers and `Boolean`s boxed (`AsInteger`,
`AsInt64`, `AsBoolean`, `AsDouble`), strings with `AsString`. A method that answers sets `Answer`: an object, a string
(`JavaString`), a boxed number of the method's type (`JavaInteger`, `JavaInt64`, `JavaBoolean`, `JavaSingle`,
`JavaDouble`); left alone, Java gets null, 0 or `False`. An exception in the handler becomes a Java
`RuntimeException` where Java called.

An interface with two methods of one name (`onClick(View)` and `onClick(DialogInterface, int)`) tells them apart
with `JavaCallbackSignature` inside the handler: Java's signature of the method called,
`'(Landroid/view/View;)V'`.

`pastel java add` writes `Implement` for the interfaces of the list; without them,
`JavaImplement('android.speech.tts.TextToSpeech$OnInitListener', @SpeechReady)`.

The handler runs on the app's own thread, where forms can be used, like an event of a button: a method that answers
nothing (`void`) is called later and Java goes on; one that answers waits for it. `JavaImplement(Name, @Handler,
False)` calls it at once on Java's thread (it must not touch forms then). The objects live while the program does:
make a listener once, not at each call.

## Threads

Pascal's code runs on the app's own thread; Java can be called from there and from any other thread. Android's
views and `Toast` want Android's UI thread: `JavaRunOnUiThread(@Method)` runs a method there, later, without
waiting (it must not touch Pastel's forms):

```pascal
procedure THomeForm.SayIt;           // on Android's UI thread
begin
  JToast.makeText(JavaActivity, 'Hello', JToast.LENGTH_LONG).show;
end;

JavaRunOnUiThread(@SayIt);
```

For a short message `ShowToast('Saved')` (Pastel.Dialogs) does all this — and draws one on computers.

## On computers

The same calls work in desktop apps with Java installed (`JAVA_HOME`, else the `java` of the PATH): Pastel starts
Java the first time it is needed. Java's own classes (`java.util`, `java.time`...) are there; the project's
`src/java` while it is developed; a program's `.jar` files beside it in `java/` (or `PASTEL_JAVA_CLASSPATH`).
`[java] jars = ["libs/some.jar"]` adds a library's classes to `pastel java add`. `JavaAvailable` says whether Java
is there (`JavaProblem` why not).
