{ Pastel - "pastel java": typed Pascal for Java classes, like Delphi's Java2OP.

  Reads the classes from Android's android.jar (and the project's own Java,
  and jars of [java] jars) — the .class files themselves, no Java needed —
  and writes src/java/javaclasses.pas: for each class a record (JToast) with
  its methods, constructors (New), constants and static fields, which call
  Java through Pastel.Java:

    JToast.makeText(JavaActivity, 'Saved', JToast.LENGTH_SHORT).show;

  pastel.toml keeps the list:
    [java]
    classes = ["android.widget.Toast", "android.os.Build"]
  Part of the Pastel project, MIT License. }
unit Pastel.JavaGen;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

{ pastel java [add|remove|search] [names] }
function RunJava(const Args: TStringArray): Integer;

{ The project's own Java files (src/java/**/*.java), '' when it has none. }
function ProjectJavaFiles(const Root: string): TStringArray;
{ Compiles them (and Extra) for Android (BootJar: android.jar) into OutDir; '' or what went wrong. }
function CompileJava(const Root, BootJar, OutDir: string; const Extra: TStringArray; const ClassPath: TStringArray = nil): string;

implementation

uses
  Math, StrUtils, zipper, Pastel.Console, Pastel.Project, Pastel.Toml, Pastel.Packages, Pastel.Files, Pastel.Builder,
  Pastel.Package, Pastel.AndroidLibs;

const
  ACC_PUBLIC = $0001;
  ACC_STATIC = $0008;
  ACC_FINAL = $0010;
  ACC_BRIDGE = $0040;
  ACC_INTERFACE = $0200;
  ACC_ABSTRACT = $0400;
  ACC_SYNTHETIC = $1000;
  GeneratedUnit = 'src' + PathDelim + 'java' + PathDelim + 'javaclasses.pas';

type
  TConstKind = (ckNone, ckInt, ckLong, ckFloat, ckDouble, ckString);

  TMember = record
    Access: Integer;
    Name, Desc: string;
    ConstKind: TConstKind;
    ConstInt: Int64;
    ConstFloat: Double;
    ConstStr: string;
  end;

  TJClass = class
    Name, Super: string;           { slash names: android/widget/Toast }
    Access: Integer;
    Interfaces: TStringArray;
    Fields, Methods: array of TMember;
  end;

  { the jars and folders classes are read from }
  TClassPath = class
  private
    FJars: TStringList;            { jar file -> list of its entries (Objects) }
    FDirs: TStringList;
    FCache: TStringList;           { slash name -> TJClass }
    function ReadEntry(const Jar, Entry: string; Data: TMemoryStream): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddJar(const Jar: string);
    procedure AddDir(const Dir: string);
    { nil when there is no such class }
    function Find(const SlashName: string): TJClass;
    { every class name (dotted) with all the words in it }
    procedure Search(const Words: TStringArray; Into: TStrings);
  end;

{ ---- reading .class files ---- }

type
  TCpEntry = record
    Tag: Byte;
    I1, I2: Integer;
    IntVal: Int64;
    FloatVal: Double;
    Str: string;
  end;

  TReader = record
    Data: TBytes;
    Pos: Integer;
    function U1: Byte;
    function U2: Word;
    function U4: LongWord;
    function U8: QWord;
    procedure Skip(N: Integer);
  end;

function TReader.U1: Byte;
begin
  Result := Data[Pos];
  Inc(Pos);
end;

function TReader.U2: Word;
begin
  Result := (Data[Pos] shl 8) or Data[Pos + 1];
  Inc(Pos, 2);
end;

function TReader.U4: LongWord;
begin
  Result := (LongWord(U2) shl 16) or U2;
end;

function TReader.U8: QWord;
begin
  Result := (QWord(U4) shl 32) or U4;
end;

procedure TReader.Skip(N: Integer);
begin
  Inc(Pos, N);
end;

function ParseClass(const Data: TBytes): TJClass;
var
  R: TReader;
  Cp: array of TCpEntry;
  N, I, J, Count, ACount, Len: Integer;
  Bits: LongWord;
  Bits64: QWord;
  S: Single;
  D: Double;
  M: TMember;
  AName: string;
  Raw: RawByteString;

  function CpStr(Index: Integer): string;
  begin
    if (Index > 0) and (Index < Length(Cp)) then
      Result := Cp[Index].Str
    else
      Result := '';
  end;

  function ClassName(Index: Integer): string;
  begin
    if (Index > 0) and (Index < Length(Cp)) then
      Result := CpStr(Cp[Index].I1)
    else
      Result := '';
  end;

  procedure ReadMembers(var List: array of TMember; IsField: Boolean);
  var
    K, A: Integer;
  begin
    for K := 0 to High(List) do
    begin
      M := Default(TMember);
      M.Access := R.U2;
      M.Name := CpStr(R.U2);
      M.Desc := CpStr(R.U2);
      ACount := R.U2;
      for A := 1 to ACount do
      begin
        AName := CpStr(R.U2);
        Len := R.U4;
        if IsField and (AName = 'ConstantValue') then
        begin
          J := R.U2;
          case Cp[J].Tag of
            3: begin M.ConstKind := ckInt; M.ConstInt := Cp[J].IntVal; end;
            5: begin M.ConstKind := ckLong; M.ConstInt := Cp[J].IntVal; end;
            4: begin M.ConstKind := ckFloat; M.ConstFloat := Cp[J].FloatVal; end;
            6: begin M.ConstKind := ckDouble; M.ConstFloat := Cp[J].FloatVal; end;
            8: begin M.ConstKind := ckString; M.ConstStr := CpStr(Cp[J].I1); end;
          end;
          R.Skip(Len - 2);
        end
        else
          R.Skip(Len);
      end;
      List[K] := M;
    end;
  end;

begin
  Result := nil;
  R.Data := Data;
  R.Pos := 0;
  if (Length(Data) < 10) or (R.U4 <> $CAFEBABE) then
    Exit;
  R.Skip(4);
  N := R.U2;
  Cp := nil;
  SetLength(Cp, N);
  I := 1;
  while I < N do
  begin
    Cp[I] := Default(TCpEntry);
    Cp[I].Tag := R.U1;
    case Cp[I].Tag of
      1:
        begin
          Len := R.U2;
          SetLength(Raw, Len);
          if Len > 0 then
            Move(R.Data[R.Pos], Raw[1], Len);
          R.Skip(Len);
          Cp[I].Str := Raw;
        end;
      3: Cp[I].IntVal := LongInt(R.U4);
      4:
        begin
          Bits := R.U4;
          Move(Bits, S, 4);
          Cp[I].FloatVal := S;
        end;
      5:
        begin
          Cp[I].IntVal := Int64(R.U8);
          Inc(I);
        end;
      6:
        begin
          Bits64 := R.U8;
          Move(Bits64, D, 8);
          Cp[I].FloatVal := D;
          Inc(I);
        end;
      7, 8, 16, 19, 20: Cp[I].I1 := R.U2;
      9, 10, 11, 12, 17, 18:
        begin
          Cp[I].I1 := R.U2;
          Cp[I].I2 := R.U2;
        end;
      15: R.Skip(3);
    else
      Exit;          { a constant this reader does not know: not read }
    end;
    Inc(I);
  end;
  Result := TJClass.Create;
  Result.Access := R.U2;
  Result.Name := ClassName(R.U2);
  Result.Super := ClassName(R.U2);
  Count := R.U2;
  SetLength(Result.Interfaces, Count);
  for I := 0 to Count - 1 do
    Result.Interfaces[I] := ClassName(R.U2);
  Count := R.U2;
  SetLength(Result.Fields, Count);
  ReadMembers(Result.Fields, True);
  Count := R.U2;
  SetLength(Result.Methods, Count);
  ReadMembers(Result.Methods, False);
end;

{ ---- the class path ---- }

type
  TMemoryCatcher = class
    Target: TMemoryStream;
    procedure CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
  end;

procedure TMemoryCatcher.CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream := Target;
end;

procedure TMemoryCatcher.DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream := nil;     { kept: it is Target }
end;

constructor TClassPath.Create;
begin
  FJars := TStringList.Create;
  FJars.OwnsObjects := True;
  FDirs := TStringList.Create;
  FCache := TStringList.Create;
  FCache.Sorted := True;
  FCache.OwnsObjects := True;
end;

destructor TClassPath.Destroy;
begin
  FCache.Free;
  FDirs.Free;
  FJars.Free;
  inherited Destroy;
end;

procedure TClassPath.AddJar(const Jar: string);
var
  Z: TUnZipper;
  Names: TStringList;
  I: Integer;
begin
  if not FileExists(Jar) then
    Exit;
  Names := TStringList.Create;
  Names.Sorted := True;
  Z := TUnZipper.Create;
  try
    Z.FileName := Jar;
    Z.Examine;
    for I := 0 to Z.Entries.Count - 1 do
      if AnsiEndsText('.class', Z.Entries[I].ArchiveFileName) then
        Names.Add(Copy(Z.Entries[I].ArchiveFileName, 1, Length(Z.Entries[I].ArchiveFileName) - 6));
  finally
    Z.Free;
  end;
  FJars.AddObject(Jar, Names);
end;

procedure TClassPath.AddDir(const Dir: string);
begin
  if DirectoryExists(Dir) then
    FDirs.Add(IncludeTrailingPathDelimiter(Dir));
end;

function TClassPath.ReadEntry(const Jar, Entry: string; Data: TMemoryStream): Boolean;
var
  Z: TUnZipper;
  C: TMemoryCatcher;
  L: TStringList;
begin
  Z := TUnZipper.Create;
  C := TMemoryCatcher.Create;
  L := TStringList.Create;
  try
    C.Target := Data;
    Z.FileName := Jar;
    Z.OnCreateStream := @C.CreateStream;
    Z.OnDoneStream := @C.DoneStream;
    L.Add(Entry);
    Z.UnZipFiles(L);
    Result := Data.Size > 0;
  finally
    L.Free;
    C.Free;
    Z.Free;
  end;
end;

function TClassPath.Find(const SlashName: string): TJClass;
var
  I: Integer;
  Data: TMemoryStream;
  Bytes: TBytes;
  Found: Boolean;
begin
  I := FCache.IndexOf(SlashName);
  if I >= 0 then
    Exit(TJClass(FCache.Objects[I]));
  Result := nil;
  Data := TMemoryStream.Create;
  try
    Found := False;
    for I := 0 to FDirs.Count - 1 do
      if FileExists(FDirs[I] + SetDirSeparators(SlashName) + '.class') then
      begin
        Data.LoadFromFile(FDirs[I] + SetDirSeparators(SlashName) + '.class');
        Found := True;
        Break;
      end;
    if not Found then
      for I := 0 to FJars.Count - 1 do
        if TStringList(FJars.Objects[I]).IndexOf(SlashName) >= 0 then
        begin
          Found := ReadEntry(FJars[I], SlashName + '.class', Data);
          if Found then
            Break;
        end;
    if Found then
    begin
      SetLength(Bytes, Data.Size);
      if Data.Size > 0 then
        Move(Data.Memory^, Bytes[0], Data.Size);
      Result := ParseClass(Bytes);
    end;
  finally
    Data.Free;
  end;
  FCache.AddObject(SlashName, Result);
end;

procedure TClassPath.Search(const Words: TStringArray; Into: TStrings);
var
  I, J: Integer;
  Names: TStringList;
  N, W: string;
  Ok: Boolean;
  Files: TStringArray;
  F: string;

  procedure Consider(const Slash: string);
  var
    Dotted: string;
  begin
    if Pos('$', Slash) > 0 then
      if (Length(Slash) > Pos('$', Slash)) and (Slash[Pos('$', Slash) + 1] in ['0'..'9']) then
        Exit;               { anonymous classes }
    Dotted := StringReplace(StringReplace(Slash, '/', '.', [rfReplaceAll]), '$', '.', [rfReplaceAll]);
    Ok := True;
    for W in Words do
      if Pos(LowerCase(W), LowerCase(Dotted)) = 0 then
        Ok := False;
    if Ok and (Into.IndexOf(Dotted) < 0) then
      Into.Add(Dotted);
  end;

begin
  for I := 0 to FJars.Count - 1 do
  begin
    Names := TStringList(FJars.Objects[I]);
    for J := 0 to Names.Count - 1 do
    begin
      N := Names[J];
      Consider(N);
    end;
  end;
  for I := 0 to FDirs.Count - 1 do
  begin
    Files := ListFiles(FDirs[I], '*.class', True);
    for F in Files do
      Consider(StringReplace(ChangeFileExt(ExtractRelativePath(FDirs[I], F), ''), PathDelim, '/', [rfReplaceAll]));
  end;
end;

{ ---- names ---- }

const
  Reserved: array[0..71] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports',
    'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or',
    'out', 'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set',
    'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while',
    'with', 'xor', 'operator', 'self', 'result', 'obj', 'true', 'false', 'new');

function SafeName(const S: string): string;
var
  W: string;
begin
  for W in Reserved do
    if SameText(S, W) then
    begin
      if SameText(W, 'self') or SameText(W, 'result') or SameText(W, 'obj') or SameText(W, 'true') or
        SameText(W, 'false') or SameText(W, 'new') then
        Exit(S + '_');
      Exit('&' + S);
    end;
  Result := S;
end;

{ 'android.app.Notification.Builder' -> 'android/app/Notification$Builder' (the parts
  after a capitalized one are inner classes) }
function ToSlash(const Dotted: string): string;
var
  Parts: TStringArray;
  I: Integer;
begin
  if (Pos('/', Dotted) > 0) then
    Exit(Dotted);
  Parts := Dotted.Split(['.']);
  Result := '';
  for I := 0 to High(Parts) do
  begin
    if I > 0 then
      if (Parts[I - 1] <> '') and (Parts[I - 1][1] in ['A'..'Z']) then
        Result := Result + '$'
      else
        Result := Result + '/';
    Result := Result + Parts[I];
  end;
end;

function ToDotted(const Slash: string): string;
begin
  Result := StringReplace(Slash, '/', '.', [rfReplaceAll]);
end;

function SimpleName(const Slash: string): string;
var
  P: Integer;
begin
  Result := Slash;
  P := LastDelimiter('/', Result);
  Result := Copy(Result, P + 1, MaxInt);
end;

{ ---- the generator ---- }

type
  TGenerator = class
  private
    FPath: TClassPath;
    FWanted: TStringList;          { slash name -> Pascal type name }
    FIntf, FImpl: TStringList;
    function TypeOf(const Slash: string): string;
    function ParamType(const Desc: string; out Pass: string; const PName: string): string;
    function JavaTypeName(const Desc: string): string;
    procedure SplitParams(const Desc: string; Params: TStrings; out Ret: string);
    procedure Collect(C: TJClass; Own: Boolean; Methods: TList; Seen: TStrings; Fields: TList; FieldSeen: TStrings);
    procedure WriteClass(const Slash: string);
  public
    constructor Create(APath: TClassPath);
    destructor Destroy; override;
    { the unit; Missing gets the classes that were not found }
    function Generate(const Classes_: TStrings; const Source: string; Missing: TStrings): string;
  end;

  PMember = ^TMember;

constructor TGenerator.Create(APath: TClassPath);
begin
  FPath := APath;
  FWanted := TStringList.Create;
  FIntf := TStringList.Create;
  FImpl := TStringList.Create;
end;

destructor TGenerator.Destroy;
begin
  FWanted.Free;
  FIntf.Free;
  FImpl.Free;
  inherited Destroy;
end;

function TGenerator.TypeOf(const Slash: string): string;
begin
  Result := FWanted.Values[Slash];
end;

{ the parameters of a method descriptor, one descriptor each; Ret: the result's }
procedure TGenerator.SplitParams(const Desc: string; Params: TStrings; out Ret: string);
var
  I, Start: Integer;
begin
  Params.Clear;
  I := 2;
  while (I <= Length(Desc)) and (Desc[I] <> ')') do
  begin
    Start := I;
    while Desc[I] = '[' do
      Inc(I);
    if Desc[I] = 'L' then
      while Desc[I] <> ';' do
        Inc(I);
    Params.Add(Copy(Desc, Start, I - Start + 1));
    Inc(I);
  end;
  Ret := Copy(Desc, I + 1, MaxInt);
end;

function TGenerator.JavaTypeName(const Desc: string): string;
begin
  case Desc[1] of
    'Z': Result := 'boolean';
    'B': Result := 'byte';
    'C': Result := 'char';
    'S': Result := 'short';
    'I': Result := 'int';
    'J': Result := 'long';
    'F': Result := 'float';
    'D': Result := 'double';
    'V': Result := 'void';
    '[': Result := JavaTypeName(Copy(Desc, 2, MaxInt)) + '[]';
    'L': Result := StringReplace(SimpleName(Copy(Desc, 2, Length(Desc) - 2)), '$', '.', [rfReplaceAll]);
  else
    Result := Desc;
  end;
end;

{ the Pascal type of a parameter, and how it is passed to Java (Pass, with %s for its name) }
function TGenerator.ParamType(const Desc: string; out Pass: string; const PName: string): string;
var
  Cls: string;
begin
  Pass := PName;
  case Desc[1] of
    'Z': Result := 'Boolean';
    'B': Result := 'ShortInt';
    'C': Result := 'WideChar';
    'S': Result := 'SmallInt';
    'I': Result := 'Integer';
    'J': Result := 'Int64';
    'F': Result := 'Single';
    'D': Result := 'Double';
    'L':
      begin
        Cls := Copy(Desc, 2, Length(Desc) - 2);
        if (Cls = 'java/lang/String') or (Cls = 'java/lang/CharSequence') then
          Result := 'string'
        else if TypeOf(Cls) <> '' then
        begin
          Result := TypeOf(Cls);
          Pass := PName + '.Obj.Handle';
        end
        else
        begin
          Result := 'TJavaObject';
          Pass := PName + '.Handle';
        end;
      end;
  else
    begin
      Result := 'TJavaObject';
      Pass := PName + '.Handle';
    end;
  end;
end;

{ the public methods and fields of a class and the classes above it (not java.lang.Object's) }
procedure TGenerator.Collect(C: TJClass; Own: Boolean; Methods: TList; Seen: TStrings; Fields: TList; FieldSeen: TStrings);
var
  I: Integer;
  Up: TJClass;
  S: string;
begin
  if (C = nil) or (C.Name = 'java/lang/Object') then
    Exit;
  { constructors are the class's own: none from above }
  for I := 0 to High(C.Methods) do
    with C.Methods[I] do
      if ((Access and ACC_PUBLIC) <> 0) and ((Access and (ACC_SYNTHETIC or ACC_BRIDGE)) = 0) and
        (Name <> '<clinit>') and ((Name <> '<init>') or Own) and (Seen.IndexOf(Name + Desc) < 0) then
      begin
        Seen.Add(Name + Desc);
        Methods.Add(@C.Methods[I]);
      end;
  for I := 0 to High(C.Fields) do
    with C.Fields[I] do
      if ((Access and ACC_PUBLIC) <> 0) and ((Access and ACC_STATIC) <> 0) and (FieldSeen.IndexOf(Name) < 0) then
      begin
        FieldSeen.Add(Name);
        Fields.Add(@C.Fields[I]);
      end;
  S := C.Super;
  if S <> '' then
  begin
    Up := FPath.Find(S);
    if Up <> nil then
      Collect(Up, False, Methods, Seen, Fields, FieldSeen);
  end;
  for S in C.Interfaces do
  begin
    Up := FPath.Find(S);
    if Up <> nil then
      Collect(Up, False, Methods, Seen, Fields, FieldSeen);
  end;
end;

procedure TGenerator.WriteClass(const Slash: string);
var
  C: TJClass;
  Methods, Fields: TList;
  Seen, FieldSeen, Params, Used, Names, Decls: TStringList;
  I, J, K: Integer;
  M: PMember;
  T, Helper, Ret, PT, Pass, PName, PList, PassList, Decl, Head, Body, Call, Kind, MName, Key, Base, Comment,
    JavaSig, Dotted, ParamNames: string;
  IsStatic, IsCtor, Abstract_: Boolean;

  function Conv(const V: string): string;
  begin
    Result := V;
  end;

begin
  C := FPath.Find(Slash);
  T := TypeOf(Slash);
  Helper := T + 'Helper';
  Dotted := ToDotted(Slash);
  Methods := TList.Create;
  Fields := TList.Create;
  Seen := TStringList.Create;
  FieldSeen := TStringList.Create;
  Params := TStringList.Create;
  Used := TStringList.Create;
  Names := TStringList.Create;
  Decls := TStringList.Create;
  try
    Abstract_ := (C.Access and (ACC_ABSTRACT or ACC_INTERFACE)) <> 0;
    Collect(C, True, Methods, Seen, Fields, FieldSeen);
    Names.CaseSensitive := False;
    Names.Add('Obj');
    Names.Add('IsNull');
    FIntf.Add('');
    FIntf.Add(Format('  { %s }', [StringReplace(Dotted, '$', '.', [rfReplaceAll])]));
    FIntf.Add(Format('  %s = record helper for %s', [Helper, T]));
    { constants }
    Decls.Clear;
    for I := 0 to Fields.Count - 1 do
    begin
      M := PMember(Fields[I]);
      if (M^.ConstKind = ckNone) or ((M^.Access and ACC_FINAL) = 0) then
        Continue;
      MName := SafeName(M^.Name);
      if Names.IndexOf(StringReplace(MName, '&', '', [])) >= 0 then
        MName := MName + '_';
      Names.Add(StringReplace(MName, '&', '', []));
      case M^.ConstKind of
        ckInt:
          if M^.Desc = 'Z' then
            Decls.Add(Format('    %s = %s;', [MName, BoolToStr(M^.ConstInt <> 0, 'True', 'False')]))
          else if M^.Desc = 'C' then
            Decls.Add(Format('    %s = WideChar(%d);', [MName, M^.ConstInt]))
          else
            Decls.Add(Format('    %s = %d;', [MName, M^.ConstInt]));
        ckLong: Decls.Add(Format('    %s = Int64(%d);', [MName, M^.ConstInt]));
        ckFloat, ckDouble:
          if IsNan(M^.ConstFloat) or IsInfinite(M^.ConstFloat) then
            Continue
          else
            Decls.Add(Format('    %s = %s;', [MName, FloatToStr(M^.ConstFloat, DefaultFormatSettings)]));
        ckString: Decls.Add(Format('    %s = %s;', [MName, QuotedStr(M^.ConstStr)]));
      end;
    end;
    if Decls.Count > 0 then
    begin
      FIntf.Add('  public const');
      FIntf.AddStrings(Decls);
    end;
    FIntf.Add('  public');
    { static fields that are not constants: functions }
    for I := 0 to Fields.Count - 1 do
    begin
      M := PMember(Fields[I]);
      if (M^.ConstKind <> ckNone) and ((M^.Access and ACC_FINAL) <> 0) then
        Continue;
      MName := SafeName(M^.Name);
      if Names.IndexOf(StringReplace(MName, '&', '', [])) >= 0 then
        MName := MName + '_';
      Names.Add(StringReplace(MName, '&', '', []));
      Ret := ParamType(M^.Desc, Pass, 'X');
      case M^.Desc[1] of
        'Z': Call := Format('JavaFieldZ(''%s'', ''%s'')', [Dotted, M^.Name]);
        'B', 'C', 'S', 'I': Call := Format('%s(JavaFieldI(''%s'', ''%s''))', [Ret, Dotted, M^.Name]);
        'J': Call := Format('JavaFieldJ(''%s'', ''%s'')', [Dotted, M^.Name]);
        'F', 'D': Call := Format('JavaFieldD(''%s'', ''%s'', ''%s'')', [Dotted, M^.Name, M^.Desc]);
      else
        if Ret = 'string' then
        begin
          if M^.Desc = 'Ljava/lang/String;' then
            Call := Format('JavaFieldStr(''%s'', ''%s'')', [Dotted, M^.Name])
          else
            Call := Format('JavaFieldO(''%s'', ''%s'', ''%s'').ToString', [Dotted, M^.Name, M^.Desc]);
        end
        else
          Call := Format('JavaFieldO(''%s'', ''%s'', ''%s'')', [Dotted, M^.Name, M^.Desc]);
      end;
      FIntf.Add(Format('    { static %s %s }', [JavaTypeName(M^.Desc), M^.Name]));
      FIntf.Add(Format('    class function %s: %s; static;', [MName, Ret]));
      FImpl.Add('');
      FImpl.Add(Format('class function %s.%s: %s;', [Helper, MName, Ret]));
      FImpl.Add('begin');
      FImpl.Add('  Result := ' + Call + ';');
      FImpl.Add('end;');
    end;
    { methods and constructors }
    Used.CaseSensitive := False;
    for I := 0 to Methods.Count - 1 do
    begin
      M := PMember(Methods[I]);
      IsCtor := M^.Name = '<init>';
      if IsCtor and Abstract_ then
        Continue;
      IsStatic := (M^.Access and ACC_STATIC) <> 0;
      SplitParams(M^.Desc, Params, Ret);
      if IsCtor then
        MName := 'New'
      else
        MName := SafeName(M^.Name);
      { the parameters: their names from their types (Java does not keep the names) }
      PList := '';
      PassList := '';
      ParamNames := ',';
      Key := '';
      JavaSig := '';
      for J := 0 to Params.Count - 1 do
      begin
        Base := JavaTypeName(Params[J]);
        Base := StringReplace(StringReplace(Base, '[]', 'Array', [rfReplaceAll]), '.', '', [rfReplaceAll]);
        PName := 'A' + UpCase(Base[1]) + Copy(Base, 2, MaxInt);
        K := 2;
        while (Pos(',' + LowerCase(PName) + ',', ParamNames) > 0) or SameText(PName, StringReplace(MName, '&', '', [])) do
        begin
          PName := 'A' + UpCase(Base[1]) + Copy(Base, 2, MaxInt) + IntToStr(K);
          Inc(K);
        end;
        ParamNames := ParamNames + LowerCase(PName) + ',';
        PT := ParamType(Params[J], Pass, PName);
        if PList <> '' then
        begin
          PList := PList + '; ';
          PassList := PassList + ', ';
          JavaSig := JavaSig + ', ';
        end;
        if PT = 'string' then
          PList := PList + 'const ' + PName + ': ' + PT
        else
          PList := PList + PName + ': ' + PT;
        PassList := PassList + Pass;
        Key := Key + ',' + LowerCase(PT);
        JavaSig := JavaSig + JavaTypeName(Params[J]);
      end;
      { two Java methods that look the same in Pascal (String and CharSequence...): the second gets a number }
      Base := StringReplace(MName, '&', '', []);
      K := 2;
      while Used.IndexOf(Base + '(' + Key + ')' + BoolToStr(IsStatic or IsCtor, 's', 'i')) >= 0 do
      begin
        MName := StringReplace(MName, '&', '', []) + '_' + IntToStr(K);
        Base := MName;
        Inc(K);
      end;
      Used.Add(Base + '(' + Key + ')' + BoolToStr(IsStatic or IsCtor, 's', 'i'));
      { what it answers }
      if IsCtor then
      begin
        Decl := T;
        Kind := 'New';
      end
      else
        case Ret[1] of
          'V': begin Decl := ''; Kind := ''; end;
          'Z': begin Decl := 'Boolean'; Kind := 'Z'; end;
          'B': begin Decl := 'ShortInt'; Kind := 'I'; end;
          'C': begin Decl := 'WideChar'; Kind := 'I'; end;
          'S': begin Decl := 'SmallInt'; Kind := 'I'; end;
          'I': begin Decl := 'Integer'; Kind := 'I'; end;
          'J': begin Decl := 'Int64'; Kind := 'J'; end;
          'F': begin Decl := 'Single'; Kind := 'F'; end;
          'D': begin Decl := 'Double'; Kind := 'D'; end;
        else
          begin
            Decl := ParamType(Ret, Pass, 'X');
            if Ret = 'Ljava/lang/String;' then
              Kind := 'Str'
            else
              Kind := 'O';
          end;
        end;
      Comment := Format('    { %s%s%s(%s) }', [BoolToStr(IsStatic, 'static ', ''),
        BoolToStr(IsCtor, 'new ' + StringReplace(SimpleName(Slash), '$', '.', [rfReplaceAll]),
        JavaTypeName(Ret) + ' ' + M^.Name), '', JavaSig]);
      if PList <> '' then
        PList := '(' + PList + ')';
      if Decl = '' then
        Head := 'procedure %s' + PList + ';'
      else if IsStatic or IsCtor then
        Head := 'class function %s' + PList + ': ' + Decl + ';'
      else
        Head := 'function %s' + PList + ': ' + Decl + ';';
      if IsStatic and (Decl = '') then
        Head := 'class ' + Head;
      FIntf.Add(Comment);
      if IsStatic or IsCtor then
        FIntf.Add('    ' + Format(Head, [MName]) + ' static; overload;')
      else
        FIntf.Add('    ' + Format(Head, [MName]) + ' overload;');
      { the call }
      if PassList <> '' then
        PassList := '[' + PassList + ']'
      else
        PassList := '[]';
      if IsCtor then
        Body := Format('  Result := JavaNew(''%s'', ''%s'', %s);', [Dotted, M^.Desc, PassList])
      else if IsStatic then
      begin
        if Kind = '' then
          Body := Format('  JavaStatic(''%s'', ''%s'', ''%s'', %s);', [Dotted, M^.Name, M^.Desc, PassList])
        else
          Body := Format('  Result := %sJavaStatic%s(''%s'', ''%s'', ''%s'', %s)%s;', [IfThen(Pos(Decl, 'ShortInt WideChar SmallInt') > 0, Decl + '(', ''),
            Kind, Dotted, M^.Name, M^.Desc, PassList, IfThen(Pos(Decl, 'ShortInt WideChar SmallInt') > 0, ')', '')]);
      end
      else
      begin
        if Kind = '' then
          Body := Format('  JavaCall(Obj, ''%s'', ''%s'', ''%s'', %s);', [Dotted, M^.Name, M^.Desc, PassList])
        else
          Body := Format('  Result := %sJavaCall%s(Obj, ''%s'', ''%s'', ''%s'', %s)%s;', [IfThen(Pos(Decl, 'ShortInt WideChar SmallInt') > 0, Decl + '(', ''),
            Kind, Dotted, M^.Name, M^.Desc, PassList, IfThen(Pos(Decl, 'ShortInt WideChar SmallInt') > 0, ')', '')]);
      end;
      { a CharSequence answered: its text }
      if (Kind = 'O') and (Decl = 'string') then
        Body := StringReplace(Body, ', ' + PassList + ');', ', ' + PassList + ').ToString;', []);
      FImpl.Add('');
      FImpl.Add(Format(StringReplace(Head, '%s', Helper + '.%s', []), [MName]));
      FImpl.Add('begin');
      FImpl.Add(Body);
      FImpl.Add('end;');
    end;
    { an interface (a listener): Pascal's object of it }
    if ((C.Access and ACC_INTERFACE) <> 0) and (Names.IndexOf('Implement') < 0) then
    begin
      FIntf.Add('    { this interface done by Pascal: Handler gets each call of its methods (JavaImplement) }');
      FIntf.Add(Format('    class function Implement(Handler: TJavaCallbackEvent; OnAppThread: Boolean = True): %s; static;', [T]));
      FImpl.Add('');
      FImpl.Add(Format('class function %s.Implement(Handler: TJavaCallbackEvent; OnAppThread: Boolean): %s;', [Helper, T]));
      FImpl.Add('begin');
      FImpl.Add(Format('  Result := JavaImplement(''%s'', Handler, OnAppThread);', [Dotted]));
      FImpl.Add('end;');
    end;
    FIntf.Add('  end;');
  finally
    Decls.Free;
    Names.Free;
    Used.Free;
    Params.Free;
    FieldSeen.Free;
    Seen.Free;
    Fields.Free;
    Methods.Free;
  end;
  if Conv('') = '' then ;
end;

function TGenerator.Generate(const Classes_: TStrings; const Source: string; Missing: TStrings): string;
var
  I: Integer;
  Slash, T, Pkg: string;
  Out_, Types: TStringList;
begin
  FWanted.Clear;
  FIntf.Clear;
  FImpl.Clear;
  { the Pascal names: JToast; JNotification_Builder; a second Toast of another package: JWidgetToast }
  for I := 0 to Classes_.Count - 1 do
  begin
    Slash := ToSlash(Trim(Classes_[I]));
    if FPath.Find(Slash) = nil then
    begin
      Missing.Add(Trim(Classes_[I]));
      Continue;
    end;
    T := 'J' + StringReplace(SimpleName(Slash), '$', '_', [rfReplaceAll]);
    if FWanted.IndexOfName(Slash) >= 0 then
      Continue;
    if (FWanted.IndexOfName(Slash) < 0) and (Pos('=' + LowerCase(T) + LineEnding, LowerCase(FWanted.Text)) > 0) then
    begin
      Pkg := ExtractFileName(ExtractFileDir(SetDirSeparators(Slash)));
      T := 'J' + UpCase(Pkg[1]) + Copy(Pkg, 2, MaxInt) + StringReplace(SimpleName(Slash), '$', '_', [rfReplaceAll]);
    end;
    FWanted.Add(Slash + '=' + T);
  end;
  Types := TStringList.Create;
  Out_ := TStringList.Create;
  try
    for I := 0 to FWanted.Count - 1 do
    begin
      T := FWanted.ValueFromIndex[I];
      Types.Add(Format('  %s = record', [T]));
      Types.Add('    Obj: TJavaObject;');
      Types.Add(Format('    class operator :=(const A: %s): TJavaObject;', [T]));
      Types.Add(Format('    class operator :=(const A: TJavaObject): %s;', [T]));
      Types.Add('    function IsNull: Boolean;');
      Types.Add('  end;');
      FImpl.Add('');
      FImpl.Add(Format('class operator %s.:=(const A: %s): TJavaObject;', [T, T]));
      FImpl.Add('begin');
      FImpl.Add('  Result := A.Obj;');
      FImpl.Add('end;');
      FImpl.Add('');
      FImpl.Add(Format('class operator %s.:=(const A: TJavaObject): %s;', [T, T]));
      FImpl.Add('begin');
      FImpl.Add('  Result.Obj := A;');
      FImpl.Add('end;');
      FImpl.Add('');
      FImpl.Add(Format('function %s.IsNull: Boolean;', [T]));
      FImpl.Add('begin');
      FImpl.Add('  Result := Obj.IsNull;');
      FImpl.Add('end;');
    end;
    for I := 0 to FWanted.Count - 1 do
      WriteClass(FWanted.Names[I]);
    Out_.Add('{ Java classes for Pascal, written by "pastel java" from ' + Source + '.');
    Out_.Add('  Do not change it: "pastel java add" and "pastel java remove" write it again');
    Out_.Add('  (the list is [java] classes in pastel.toml). }');
    Out_.Add('unit JavaClasses;');
    Out_.Add('');
    Out_.Add('{$mode objfpc}{$H+}');
    Out_.Add('{$modeswitch advancedrecords}');
    Out_.Add('');
    Out_.Add('interface');
    Out_.Add('');
    Out_.Add('uses');
    Out_.Add('  Pastel.Java;');
    Out_.Add('');
    Out_.Add('type');
    Out_.AddStrings(Types);
    Out_.AddStrings(FIntf);
    Out_.Add('');
    Out_.Add('implementation');
    Out_.AddStrings(FImpl);
    Out_.Add('');
    Out_.Add('end.');
    Result := Out_.Text;
  finally
    Out_.Free;
    Types.Free;
  end;
end;

{ ---- the project's Java ---- }

function ProjectJavaFiles(const Root: string): TStringArray;
begin
  Result := nil;
  if DirectoryExists(Root + 'src' + PathDelim + 'java') then
    Result := ListFiles(Root + 'src' + PathDelim + 'java', '*.java', True);
end;

function CompileJava(const Root, BootJar, OutDir: string; const Extra: TStringArray; const ClassPath: TStringArray): string;
var
  Javac, Output, F: string;
  Args: TStringList;
  Files: TStringArray;
begin
  Result := '';
  Files := Concat(ProjectJavaFiles(Root), Extra);
  if Length(Files) = 0 then
    Exit;
  Javac := ExeSearch({$IFDEF WINDOWS}'javac.exe'{$ELSE}'javac'{$ENDIF}, GetEnvironmentVariable('PATH'));
  if Javac = '' then
    Exit('the Java files in src/java need javac (a JDK: sudo apt install default-jdk-headless, or Android Studio''s)');
  DeleteTree(ExcludeTrailingPathDelimiter(OutDir));
  ForceDirectories(OutDir);
  Args := TStringList.Create;
  try
    Args.AddStrings(['-source', '8', '-target', '8', '-nowarn', '-Xlint:-options', '-encoding', 'UTF-8', '-d', OutDir]);
    if BootJar <> '' then
    begin
      Args.Add('-bootclasspath');
      Args.Add(BootJar);
    end;
    if Length(ClassPath) > 0 then
    begin
      Args.Add('-classpath');
      Args.Add(string.Join(PathSeparator, ClassPath));
    end;
    for F in Files do
      Args.Add(F);
    if RunCapture(Javac, Args, Root, Output) <> 0 then
      Result := 'javac: ' + Trim(Output);
  finally
    Args.Free;
  end;
end;

{ ---- the command ---- }

function JavaListOf(const Root: string): TStringArray;
var
  Doc: TTomlDocument;
begin
  Doc := TTomlDocument.Create;
  try
    Doc.LoadFromFile(Root + ProjectFileName);
    Result := Doc.GetArray('java.classes');
  finally
    Doc.Free;
  end;
end;

function JarsOf(const Root: string): TStringArray;
var
  Doc: TTomlDocument;
  J: string;
begin
  Doc := TTomlDocument.Create;
  try
    Doc.LoadFromFile(Root + ProjectFileName);
    Result := nil;
    for J in Doc.GetArray('java.jars') do
      Result := Concat(Result, [ExpandFileName(Root + SetDirSeparators(J))]);
  finally
    Doc.Free;
  end;
end;

procedure SaveList(const Root: string; const L: TStrings);
var
  S: string;
  I: Integer;
begin
  S := '[';
  for I := 0 to L.Count - 1 do
  begin
    if I > 0 then
      S := S + ', ';
    S := S + TomlStr(L[I]);
  end;
  SetProjectSetting(Root, 'java', 'classes', S + ']');
end;

function RunJava(const Args: TStringArray): Integer;
var
  Root, Jar, Sub, A, Src, Text, Err: string;
  Api: Integer;
  Jars: TAndroidJars;
  Path: TClassPath;
  List, Missing, Found: TStringList;
  Gen: TGenerator;
  Words: TStringArray;
  I: Integer;
  Project: TPastelProject;
  Libs: TAndroidLibraries;
begin
  Result := 1;
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if Root = '' then
  begin
    Fail('not in a Pastel project (no pastel.toml here or above)');
    Exit;
  end;
  Root := IncludeTrailingPathDelimiter(Root);
  Sub := '';
  if Length(Args) > 0 then
    Sub := Args[0];
  { where classes come from: the newest android.jar, the project's Java, [java] jars }
  Jars := AndroidJars;
  Jar := '';
  Api := 0;
  if Length(Jars) > 0 then
  begin
    Jar := Jars[0].Path;
    Api := Jars[0].Api;
  end;
  { the classes of [package.android] libraries }
  Project := TPastelProject.Load(Root);
  try
    Err := ResolveAndroidLibraries(Project, Root + 'build' + PathDelim + 'android' + PathDelim, Libs);
  finally
    Project.Free;
  end;
  if Err <> '' then
  begin
    Fail(Err);
    Exit;
  end;
  Err := CompileJava(Root, Jar, Root + 'build' + PathDelim + 'java' + PathDelim + 'classes' + PathDelim, nil,
    LibraryJars(Libs));
  if Err <> '' then
  begin
    Fail(Err);
    Exit;
  end;
  Path := TClassPath.Create;
  List := TStringList.Create;
  Missing := TStringList.Create;
  Found := TStringList.Create;
  try
    Path.AddDir(Root + 'build' + PathDelim + 'java' + PathDelim + 'classes');
    for A in JarsOf(Root) do
      Path.AddJar(A);
    for A in LibraryJars(Libs) do
      Path.AddJar(A);
    { what a desktop run gives Java (Pastel.Java reads it): the project's classes, [java] jars }
    ForceDirectories(Root + 'build' + PathDelim + 'java');
    Found.Clear;
    for A in JarsOf(Root) do
      Found.Add(A);
    Found.SaveToFile(Root + 'build' + PathDelim + 'java' + PathDelim + 'classpath.txt');
    Found.Clear;
    if Jar <> '' then
      Path.AddJar(Jar);
    if (Jar = '') and (Length(JarsOf(Root)) = 0) and (Length(ProjectJavaFiles(Root)) = 0) then
    begin
      Fail('no Android platform (android.jar) here to read the classes from');
      Hint('Android Studio''s SDK Manager: "Android 16 (API 36)"; set ANDROID_HOME');
      Exit;
    end;
    if Sub = 'search' then
    begin
      Words := Copy(Args, 1, MaxInt);
      if Length(Words) = 0 then
      begin
        Fail('what to look for: pastel java search Toast (or android.app Notification)');
        Exit;
      end;
      Found.Sorted := True;
      Path.Search(Words, Found);
      for I := 0 to Min(Found.Count, 60) - 1 do
        WriteLn('  ', Found[I]);
      if Found.Count > 60 then
        WriteLn(Format('  ... %d more: add a word', [Found.Count - 60]))
      else if Found.Count = 0 then
        WriteLn('  no class has all of these words');
      Exit(0);
    end;
    for A in JavaListOf(Root) do
      List.Add(A);
    if Sub = 'add' then
    begin
      for I := 1 to High(Args) do
      begin
        A := Trim(Args[I]);
        if Path.Find(ToSlash(A)) = nil then
        begin
          Fail(Format('there is no Java class %s', [A]));
          Hint('find it: pastel java search ' + A.Split(['.'])[High(A.Split(['.']))]);
          Exit;
        end;
        if List.IndexOf(A) < 0 then
          List.Add(A);
      end;
      SaveList(Root, List);
    end
    else if Sub = 'remove' then
    begin
      for I := 1 to High(Args) do
        if List.IndexOf(Trim(Args[I])) >= 0 then
          List.Delete(List.IndexOf(Trim(Args[I])));
      SaveList(Root, List);
    end
    else if Sub <> '' then
    begin
      Fail(Format('pastel java %s: add, remove or search', [Sub]));
      Exit;
    end;
    if List.Count = 0 then
    begin
      WriteLn('No Java classes yet. Add some:');
      WriteLn('  pastel java add android.widget.Toast        (then: uses JavaClasses; JToast.makeText(...))');
      WriteLn('  pastel java search Notification             (the classes with that name)');
      DeleteFile(Root + GeneratedUnit);
      Exit(0);
    end;
    { the unit }
    if Jar <> '' then
      Src := Format('android.jar of Android %d', [Api])
    else
      Src := 'the project''s Java';
    Gen := TGenerator.Create(Path);
    try
      Text := Gen.Generate(List, Src, Missing);
    finally
      Gen.Free;
    end;
    for A in Missing do
      Warn(Format('there is no Java class %s here (left out)', [A]));
    ForceDirectories(Root + 'src' + PathDelim + 'java');
    List.Text := Text;
    List.SaveToFile(Root + GeneratedUnit);
    Status('Wrote', Format('%s (%d classes; uses JavaClasses)', [StringReplace(GeneratedUnit, PathDelim, '/', [rfReplaceAll]),
      Length(JavaListOf(Root)) - Missing.Count]));
    Result := 0;
  finally
    Found.Free;
    Missing.Free;
    List.Free;
    Path.Free;
  end;
end;

end.
