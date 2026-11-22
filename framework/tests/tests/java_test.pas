{ Tests of Pastel.Java on a computer's Java (skipped without one). }
unit java_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Java;

type
  TJavaTests = class(TTestSuite)
  private
    FRan: Boolean;
    FLastSignature: string;
    FRanHere: Boolean;
    procedure ByLength(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
    procedure Ran(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
    procedure Fails(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
  public
    procedure SetUp; override;
  published
    procedure BoxedValues;
    procedure InterfacesDoneByPascal;
    procedure CallsFromJavaThreadsComeToTheAppThread;
    procedure ErrorsOfHandlersBecomeJavaExceptions;
    procedure StaticMethodsAndFields;
    procedure ObjectsAndStrings;
    procedure ExceptionsBecomeErrors;
    procedure ClassesByName;
  end;

implementation

procedure TJavaTests.SetUp;
begin
  if not JavaAvailable then
    Skip('no Java here (' + JavaProblem + ')');
end;

procedure TJavaTests.ByLength(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
begin
  if Method = 'compare' then
    FLastSignature := JavaCallbackSignature;
  if Method = 'compare' then
    Answer := JavaInteger(Length(Args[0].AsString) - Length(Args[1].AsString));
end;

procedure TJavaTests.Ran(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
begin
  FRan := Method = 'run';
  FRanHere := GetCurrentThreadID = MainThreadID;
end;

procedure TJavaTests.Fails(const Method: string; const Args: TJavaArgs; var Answer: TJavaObject);
begin
  raise Exception.Create('not today');
end;

procedure TJavaTests.BoxedValues;
begin
  AssertEquals(-7, JavaInteger(-7).AsInteger);
  AssertEquals(Int64(1) shl 40, JavaInt64(Int64(1) shl 40).AsInt64);
  AssertTrue(JavaBoolean(True).AsBoolean);
  AssertFalse(JavaBoolean(False).AsBoolean);
  AssertTrue(Abs(JavaDouble(2.25).AsDouble - 2.25) < 1e-9);
  AssertEquals(3, JavaSingle(3).AsInteger);
  AssertEquals('java.lang.Integer', JavaInteger(1).JavaClassName);
  AssertEquals('', Default(TJavaObject).AsString);
  AssertEquals(0, Default(TJavaObject).AsInteger);
end;

procedure TJavaTests.InterfacesDoneByPascal;
var
  C, L: TJavaObject;
  Msg: string;
begin
  C := JavaImplement('java.util.Comparator', @ByLength);
  AssertTrue(C.IsInstanceOf('java.util.Comparator'));
  L := JavaNew('java.util.ArrayList', '()V', []);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['kiraz']);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['elma']);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['karpuz']);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['nar']);
  JavaStatic('java.util.Collections', 'sort', '(Ljava/util/List;Ljava/util/Comparator;)V', [L.Handle, C.Handle]);
  AssertEquals('[nar, elma, kiraz, karpuz]', L.ToString);
  AssertEquals('(Ljava/lang/Object;Ljava/lang/Object;)I', FLastSignature, 'the signature of the method called');
  { the methods every object has are Java's own }
  AssertTrue(JavaCallZ(C, 'java.lang.Object', 'equals', '(Ljava/lang/Object;)Z', [C.Handle]));
  AssertFalse(JavaCallZ(C, 'java.lang.Object', 'equals', '(Ljava/lang/Object;)Z', [L.Handle]));
  AssertTrue(Pos('PastelProxy@', C.ToString) = 1, C.ToString);
  JavaCallI(C, 'java.lang.Object', 'hashCode', '()I', []);
  { not an interface }
  Msg := '';
  try
    JavaImplement('java.lang.String', @ByLength);
  except
    on E: EJavaError do
      Msg := E.Message;
  end;
  AssertTrue(Pos('IllegalArgumentException', Msg) > 0, Msg);
end;

procedure TJavaTests.CallsFromJavaThreadsComeToTheAppThread;
var
  R, T: TJavaObject;
  Until_: QWord;
begin
  FRan := False;
  FRanHere := False;
  R := JavaImplement('java.lang.Runnable', @Ran);
  T := JavaNew('java.lang.Thread', '(Ljava/lang/Runnable;)V', [R.Handle]);
  JavaCall(T, 'java.lang.Thread', 'start', '()V', []);
  JavaCall(T, 'java.lang.Thread', 'join', '()V', []);
  { Java's thread is done; the call waits for the app thread }
  AssertFalse(FRan, 'not before the app thread takes it');
  Until_ := GetTickCount64 + 2000;
  while not FRan and (GetTickCount64 < Until_) do
    CheckSynchronize(10);
  AssertTrue(FRan, 'run came');
  AssertTrue(FRanHere, 'on the app thread');
  { OnAppThread False: at once, on Java's thread }
  FRan := False;
  R := JavaImplement('java.lang.Runnable', @Ran, False);
  T := JavaNew('java.lang.Thread', '(Ljava/lang/Runnable;)V', [R.Handle]);
  JavaCall(T, 'java.lang.Thread', 'start', '()V', []);
  JavaCall(T, 'java.lang.Thread', 'join', '()V', []);
  AssertTrue(FRan, 'run came at once');
  AssertFalse(FRanHere, 'on Java''s thread');
end;

procedure TJavaTests.ErrorsOfHandlersBecomeJavaExceptions;
var
  C, L: TJavaObject;
  Msg: string;
begin
  C := JavaImplement('java.util.Comparator', @Fails);
  L := JavaNew('java.util.ArrayList', '()V', []);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['a']);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['b']);
  Msg := '';
  try
    JavaStatic('java.util.Collections', 'sort', '(Ljava/util/List;Ljava/util/Comparator;)V', [L.Handle, C.Handle]);
  except
    on E: EJavaError do
      Msg := E.Message;
  end;
  AssertTrue(Pos('not today', Msg) > 0, Msg);
end;

procedure TJavaTests.StaticMethodsAndFields;
begin
  AssertEquals(42, JavaStaticI('java.lang.Integer', 'parseInt', '(Ljava/lang/String;)I', ['42']));
  AssertEquals(Int64(2147483647), Int64(JavaFieldI('java.lang.Integer', 'MAX_VALUE')));
  AssertEquals('3.5', JavaStaticStr('java.lang.String', 'valueOf', '(D)Ljava/lang/String;', [3.5]));
  AssertTrue(JavaStaticJ('java.lang.System', 'currentTimeMillis', '()J', []) > 1600000000000);
end;

procedure TJavaTests.ObjectsAndStrings;
var
  B, L: TJavaObject;
begin
  B := JavaNew('java.lang.StringBuilder', '(Ljava/lang/String;)V', ['Şeker ']);
  JavaCallO(B, 'java.lang.StringBuilder', 'append', '(Ljava/lang/String;)Ljava/lang/StringBuilder;', ['bayramı 🍬']);
  JavaCallO(B, 'java.lang.StringBuilder', 'append', '(I)Ljava/lang/StringBuilder;', [2026]);
  AssertEquals('Şeker bayramı 🍬2026', B.ToString);
  AssertEquals('java.lang.StringBuilder', B.JavaClassName);
  AssertTrue(B.IsInstanceOf('java.lang.CharSequence'));
  L := JavaNew('java.util.ArrayList', '()V', []);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', [B.Handle]);
  JavaCallZ(L, 'java.util.ArrayList', 'add', '(Ljava/lang/Object;)Z', ['x']);
  AssertEquals(2, JavaCallI(L, 'java.util.ArrayList', 'size', '()I', []));
  AssertEquals('x', JavaCallO(L, 'java.util.ArrayList', 'get', '(I)Ljava/lang/Object;', [1]).ToString);
  AssertTrue(JavaCallO(L, 'java.util.ArrayList', 'get', '(I)Ljava/lang/Object;', [0]).Handle <> nil);
end;

procedure TJavaTests.ExceptionsBecomeErrors;
var
  Msg: string;
begin
  Msg := '';
  try
    JavaStaticI('java.lang.Integer', 'parseInt', '(Ljava/lang/String;)I', ['abc']);
  except
    on E: EJavaError do
      Msg := E.Message;
  end;
  AssertTrue(Pos('NumberFormatException', Msg) > 0, Msg);
  Msg := '';
  try
    JavaStatic('java.lang.Integer', 'noSuchMethod', '()V', []);
  except
    on E: EJavaError do
      Msg := E.Message;
  end;
  AssertTrue(Pos('noSuchMethod', Msg) > 0, Msg);
end;

procedure TJavaTests.ClassesByName;
begin
  AssertTrue(JavaHasClass('java.util.Map.Entry'), 'an inner class with dots');
  AssertTrue(JavaHasClass('java.util.Map$Entry'));
  AssertFalse(JavaHasClass('no.such.Thing'));
end;

initialization
  RegisterTests(TJavaTests);

end.
