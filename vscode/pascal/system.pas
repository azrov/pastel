{ The built-in names of Free Pascal (unit System, objpas mode) for code
  intelligence: types, TObject and the routines every program can use.
  Only declarations; the compiler has the real ones. }
unit System;

interface

type
  { Whole number, 32 bits: -2147483648 .. 2147483647 }
  Integer = LongInt;
  { Whole number, 32 bits }
  LongInt = LongInt;
  { Whole number, 64 bits }
  Int64 = Int64;
  { Whole number 0 .. 4294967295 }
  Cardinal = LongWord;
  LongWord = LongWord;
  { Whole number 0 .. 18446744073709551615 }
  QWord = QWord;
  UInt64 = QWord;
  { 0 .. 255 }
  Byte = Byte;
  { -128 .. 127 }
  ShortInt = ShortInt;
  { 0 .. 65535 }
  Word = Word;
  { -32768 .. 32767 }
  SmallInt = SmallInt;
  { Whole number with the size of a pointer }
  NativeInt = Int64;
  NativeUInt = QWord;
  PtrInt = Int64;
  PtrUInt = QWord;
  SizeInt = Int64;
  SizeUInt = QWord;
  { True or False }
  Boolean = Boolean;
  ByteBool = Boolean;
  WordBool = Boolean;
  LongBool = Boolean;
  { One byte of text; UTF-8 text uses several for one letter }
  Char = AnsiChar;
  AnsiChar = AnsiChar;
  WideChar = WideChar;
  UnicodeChar = WideChar;
  { Text of any length (UTF-8 in Pastel programs) }
  string = AnsiString;
  AnsiString = AnsiString;
  RawByteString = AnsiString;
  UTF8String = AnsiString;
  UnicodeString = UnicodeString;
  WideString = WideString;
  ShortString = ShortString;
  { Floating point number, 64 bits (about 15 digits) }
  Double = Double;
  { Floating point number, 32 bits (about 7 digits) }
  Single = Single;
  Extended = Double;
  Real = Double;
  { Fixed point number with 4 decimals, for money }
  Currency = Currency;
  Comp = Int64;
  { Date and time: days since 30 December 1899; the time is the fraction }
  TDateTime = Double;
  TDate = TDateTime;
  TTime = TDateTime;
  Pointer = Pointer;
  PChar = ^Char;
  PAnsiChar = ^AnsiChar;
  PWideChar = ^WideChar;
  PByte = ^Byte;
  PInteger = ^Integer;
  Variant = Variant;
  OleVariant = Variant;
  HRESULT = LongInt;
  TClass = class of TObject;
  TGUID = record
    D1: LongWord;
    D2: Word;
    D3: Word;
    D4: array[0..7] of Byte;
  end;
  TVarRec = record
    VType: Byte;
  end;
  TBoundArray = array of SizeInt;
  TStringArray = array of string;

  { The ancestor of every class. }
  TObject = class
  public
    { Makes a new object. }
    constructor Create;
    { Frees the object; call Free instead, which also works for nil. }
    destructor Destroy; virtual;
    { Frees the object, if it is not nil. }
    procedure Free;
    { The name of the class, e.g. 'TButton'. }
    class function ClassName: ShortString;
    { True when the class is called Name (case does not matter). }
    class function ClassNameIs(const Name: string): Boolean;
    { The class of the object. }
    function ClassType: TClass;
    { The parent class. }
    class function ClassParent: TClass;
    { True when the class is AClass or descends from it. }
    class function InheritsFrom(AClass: TClass): Boolean;
    { The unit the class is declared in. }
    class function UnitName: ansistring;
    { Size of an object of this class in bytes. }
    class function InstanceSize: SizeInt;
    { Text for the object; by default its class name. }
    function ToString: ansistring; virtual;
    function Equals(Obj: TObject): Boolean; virtual;
    function GetHashCode: PtrInt; virtual;
    { Called after the last constructor finished. }
    procedure AfterConstruction; virtual;
    { Called before the destructor runs. }
    procedure BeforeDestruction; virtual;
    function GetInterface(const IID: TGUID; out Obj): Boolean;
    function FieldAddress(const Name: ShortString): Pointer;
    procedure Dispatch(var Message); virtual;
  end;

  IInterface = interface
    function QueryInterface(const IID: TGUID; out Obj): HRESULT;
    function _AddRef: LongInt;
    function _Release: LongInt;
  end;
  IUnknown = IInterface;

  { An object that is freed by itself when no interface refers to it any more. }
  TInterfacedObject = class(TObject, IInterface)
  public
    function QueryInterface(const IID: TGUID; out Obj): HRESULT;
    function _AddRef: LongInt;
    function _Release: LongInt;
    property RefCount: LongInt;
  end;

  TTextLineBreakStyle = (tlbsLF, tlbsCRLF, tlbsCR);
  TSystemCodePage = Word;
  TThreadID = PtrUInt;
  TRTLCriticalSection = record
  end;
  PRTLEvent = Pointer;
  Text = TextFile;
  TextFile = record
  end;
  THandle = PtrInt;
  TProcedure = procedure;
  PPointer = ^Pointer;
  PString = ^string;
  CodePointer = Pointer;
  TDateTimeArray = array of TDateTime;

const
  True = Boolean(1);
  False = Boolean(0);
  { The largest Integer: 2147483647 }
  MaxInt = 2147483647;
  MaxLongInt = 2147483647;
  { The line ending of this platform: #10 on Linux and macOS, #13#10 on Windows }
  LineEnding = #10;
  DirectorySeparator = '/';
  PathDelim = '/';
  PathSeparator = ':';
  AllFilesMask = '*';
  Pi = 3.141592653589793;
  { Code page numbers for SetCodePage and friends }
  CP_UTF8 = 65001;
  CP_ACP = 0;
  CP_NONE = $FFFF;
  CP_UTF16 = 1200;
  { Platform information }
  DriveSeparator = '';
  ExtensionSeparator = '.';
  MaxPathLen = 4096;
  FileNameCaseSensitive = True;

var
  { Exit code of the program, returned when it ends. }
  ExitCode: LongInt;
  { Text read with ReadLn }
  Input: Text;
  { Text written with WriteLn }
  Output: Text;
  { Text written to the error output }
  StdErr: Text;

{ Writes values to the console (or to a file given first), then a line break. }
procedure WriteLn(const Values: array of const);
{ Writes values to the console (or to a file given first). }
procedure Write(const Values: array of const);
{ Reads a line from the console (or a file given first). }
procedure ReadLn(var Values);
procedure Read(var Values);
{ The number of characters (bytes) of a string, or elements of an array. }
function Length(const S): SizeInt;
{ Changes the length of a string or dynamic array. }
procedure SetLength(var S; NewLength: SizeInt);
{ The highest index of an array (Length - 1), or the highest value of an ordinal type. }
function High(const X): SizeInt;
{ The lowest index of an array (0 for dynamic arrays), or the lowest value of an ordinal type. }
function Low(const X): SizeInt;
{ Adds 1 (or N) to a variable. }
procedure Inc(var X; N: Int64 = 1);
{ Subtracts 1 (or N) from a variable. }
procedure Dec(var X; N: Int64 = 1);
{ The number of an ordinal value: Ord('A') = 65, Ord(True) = 1. }
function Ord(X): Int64;
{ The character with this number: Chr(65) = 'A'. }
function Chr(B: Byte): Char;
{ Part of a string or array: Copy('Pastel', 1, 3) = 'Pas'. Strings start at 1. }
function Copy(const S: string; Index: SizeInt; Count: SizeInt = MaxInt): string;
{ Removes Count characters from S, starting at Index. }
procedure Delete(var S: string; Index, Count: SizeInt);
{ Inserts Source into S at Index. }
procedure Insert(const Source: string; var S: string; Index: SizeInt);
{ Where Substr is in S (1 for the first character), 0 if not at all. }
function Pos(const Substr, S: string; Offset: SizeInt = 1): SizeInt;
{ True when a pointer, object or method variable is not nil. }
function Assigned(const P): Boolean;
{ Leaves the routine; with a value, a function returns it. }
procedure Exit(const Result);
{ Ends the program with an exit code. }
procedure Halt(ExitCode: LongInt = 0);
{ Leaves the loop. }
procedure Break;
{ Goes on with the next round of the loop. }
procedure Continue;
{ The size of a type or variable in bytes. }
function SizeOf(const X): SizeInt;
{ The whole part of a number: Trunc(2.7) = 2. }
function Trunc(X: Double): Int64;
{ The nearest whole number; halves go to the even one: Round(2.5) = 2. }
function Round(X: Double): Int64;
function Abs(X: Double): Double;
function Sqr(X: Double): Double;
function Sqrt(X: Double): Double;
function Sin(X: Double): Double;
function Cos(X: Double): Double;
function ArcTan(X: Double): Double;
function Ln(X: Double): Double;
function Exp(X: Double): Double;
function Frac(X: Double): Double;
function Int(X: Double): Double;
function Odd(X: Int64): Boolean;
function Succ(X): Int64;
function Pred(X): Int64;
{ A random number: Random(N) is 0 .. N-1, Random alone 0 .. <1. }
function Random(N: Int64): Int64;
{ Starts the random numbers from the clock. }
procedure Randomize;
{ Adds a value to a set. }
procedure Include(var S; E);
{ Removes a value from a set. }
procedure Exclude(var S; E);
procedure New(var P);
procedure Dispose(var P);
procedure GetMem(var P: Pointer; Size: SizeInt);
procedure FreeMem(P: Pointer);
procedure FillChar(var X; Count: SizeInt; Value: Byte);
procedure Move(const Source; var Dest; Count: SizeInt);
function Concat(const S1, S2: string): string;
function UpCase(C: Char): Char;
function StringOfChar(C: Char; Count: SizeInt): string;
procedure SetString(out S: string; Buf: PChar; Len: SizeInt);
procedure Val(const S: string; out V; out Code: Word);
procedure Str(X; var S: string);
{ Stops with an error when Condition is False (in builds with assertions on). }
procedure Assert(Condition: Boolean; const Message: string = '');
{ The number of command-line arguments. }
function ParamCount: LongInt;
{ A command-line argument; 0 is the program itself. }
function ParamStr(Index: LongInt): string;
{ The default value of a type: 0, '', nil, False. }
function Default(T): T;
function TypeInfo(T): Pointer;
procedure Initialize(var X);
procedure Finalize(var X);
function Hi(X: Word): Byte;
function Lo(X: Word): Byte;
procedure RunError(Code: Word);
function IOResult: Word;
procedure Assign(var F; const Name: string);
procedure Reset(var F);
procedure Rewrite(var F);
procedure Append(var F);
procedure Close(var F);
function Eof(var F): Boolean;
procedure Flush(var F);
{ The exception being handled, in an except block. }
function ExceptObject: TObject;
function GetCurrentThreadId: TThreadID;
function InterLockedIncrement(var Target: LongInt): LongInt;
function InterLockedDecrement(var Target: LongInt): LongInt;
procedure Sleep(Milliseconds: Cardinal);
{ Sets the code page of a string, converting it when Convert is True. }
procedure SetCodePage(var S: RawByteString; CodePage: TSystemCodePage; Convert: Boolean = True);
{ The code page of a string (CP_UTF8 for UTF-8 text). }
function StringCodePage(const S: RawByteString): TSystemCodePage;
function get_caller_addr(framebp: Pointer; addr: CodePointer = nil): CodePointer;
function get_frame: Pointer;
function get_caller_frame(framebp: Pointer; addr: CodePointer = nil): Pointer;
function ExceptAddr: CodePointer;
procedure InitCriticalSection(var cs: TRTLCriticalSection);
procedure DoneCriticalSection(var cs: TRTLCriticalSection);
procedure EnterCriticalSection(var cs: TRTLCriticalSection);
procedure LeaveCriticalSection(var cs: TRTLCriticalSection);
function RTLEventCreate: PRTLEvent;
procedure RTLEventDestroy(state: PRTLEvent);
procedure RTLEventSetEvent(state: PRTLEvent);
procedure RTLEventResetEvent(state: PRTLEvent);
procedure RTLEventWaitFor(state: PRTLEvent; timeout: LongInt = -1);
function BeginThread(ThreadFunction: Pointer; p: Pointer = nil): TThreadID;
function GetTickCount64: QWord;
function UpCase(const S: string): string;
function LowerCase(C: Char): Char;
procedure SetTextLineEnding(var F: Text; Ending: string);
function FPower10(Val: Extended; Power: LongInt): Extended;
function Power(Base, Exponent: Double): Double;
function SwapEndian(const AValue: LongWord): LongWord;
function NtoBE(const AValue: LongWord): LongWord;
function BEtoN(const AValue: LongWord): LongWord;
procedure ReadStr(const S: string; var Values);
procedure WriteStr(out S: string; const Values: array of const);
procedure SetMultiByteConversionCodePage(CodePage: TSystemCodePage);
procedure Seek(var F; N: Int64);
function FileSize(var F): Int64;
procedure BlockRead(var F; var Buf; Count: Int64);
procedure BlockWrite(var F; const Buf; Count: Int64);
procedure Erase(var F);
procedure Rename(var F; const NewName: string);

var
  { The code page of strings without one (CP_UTF8 in Pastel programs) }
  DefaultSystemCodePage: TSystemCodePage;
  DefaultFileSystemCodePage: TSystemCodePage;
  DefaultRTLFileSystemCodePage: TSystemCodePage;
  DefaultTextLineBreakStyle: TTextLineBreakStyle;
  { True in console programs }
  IsConsole: Boolean;
  IsMultiThread: Boolean;
  FileMode: Byte;
  ErrOutput: Text;
  ExitProc: Pointer;
  ThreadID: TThreadID;

implementation

end.
