{ Pastel - unit testing.

  Write a class with published methods; each method is one test:

    type
      TGreetingTests = class(TTestSuite)
      published
        procedure GreetsByName;
      end;

    procedure TGreetingTests.GreetsByName;
    begin
      AssertEquals('Hello, Ali!', MakeGreeting('Ali'));
    end;

    initialization
      RegisterTests(TGreetingTests);

  "pastel test" finds the units in tests/, builds them into one program
  and runs it. A failing assert shows the file and line of the test.
  Part of the Pastel project, MIT License. }
unit Pastel.Testing;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Env;

type
  { Raised by a failing assert. }
  ETestFailure = class(Exception)
  public
    Location: string;
  end;

  { Raised by Skip. }
  ETestSkipped = class(Exception);

  {$M+}  { published methods (the tests) need RTTI }
  TTestSuite = class
  public
    { Runs before / after every test of the suite. }
    procedure SetUp; virtual;
    procedure TearDown; virtual;
  end;
  {$M-}

  TTestSuiteClass = class of TTestSuite;
  TTestProc = procedure;
  TTestMethod = procedure of object;

procedure RegisterTests(ASuite: TTestSuiteClass);
{ A single test as a plain procedure (no class needed). }
procedure Test(const AName: string; AProc: TTestProc);

{ ---- asserts ---- }
procedure AssertTrue(Condition: Boolean; const Msg: string = '');
procedure AssertFalse(Condition: Boolean; const Msg: string = '');
procedure AssertEquals(const Expected, Actual: string; const Msg: string = ''); overload;
procedure AssertEquals(Expected, Actual: Int64; const Msg: string = ''); overload;
procedure AssertEquals(Expected, Actual: Double; Delta: Double = 1E-9; const Msg: string = ''); overload;
procedure AssertEquals(Expected, Actual: Boolean; const Msg: string = ''); overload;
procedure AssertNotEquals(const NotExpected, Actual: string; const Msg: string = ''); overload;
procedure AssertNotEquals(NotExpected, Actual: Int64; const Msg: string = ''); overload;
procedure AssertContains(const Part, Actual: string; const Msg: string = '');
procedure AssertStartsWith(const Prefix, Actual: string; const Msg: string = '');
procedure AssertNil(P: Pointer; const Msg: string = '');
procedure AssertNotNil(P: Pointer; const Msg: string = '');
procedure AssertRaises(AClass: ExceptClass; AProc: TTestProc; const Msg: string = ''); overload;
procedure AssertRaises(AClass: ExceptClass; AMethod: TTestMethod; const Msg: string = ''); overload;
procedure Fail(const Msg: string);
procedure Skip(const Reason: string);

{ Runs the registered tests. Command line: [--json] [filter...].
  Returns the exit code: 0 if everything passed. }
function RunTests: Integer;

{ "GreetsByName" -> "greets by name" }
function HumanName(const Identifier: string): string;

implementation

type
  TTestEntry = class
    SuiteName, TestName: string;
    Suite: TTestSuiteClass;
    MethodId: string;
    Proc: TTestProc;
  end;

var
  Entries: TFPList = nil;

procedure TTestSuite.SetUp;
begin
end;

procedure TTestSuite.TearDown;
begin
end;

function HumanName(const Identifier: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(Identifier) do
  begin
    C := Identifier[I];
    if C = '_' then
    begin
      Result := Result + ' ';
      Continue;
    end;
    { a new word starts at a capital that follows a lower-case letter or digit,
      or at a capital followed by a lower-case letter (as in "HTTPServer") }
    if (I > 1) and (C in ['A'..'Z']) and
       ((Identifier[I - 1] in ['a'..'z', '0'..'9']) or
        ((I < Length(Identifier)) and (Identifier[I + 1] in ['a'..'z']) and
         (Identifier[I - 1] in ['A'..'Z']))) then
      Result := Result + ' ';
    Result := Result + C;
  end;
  { keep acronyms like HTTP, lower-case ordinary words }
  Result := Trim(Result);
  with TStringList.Create do
  try
    Delimiter := ' ';
    StrictDelimiter := True;
    DelimitedText := Result;
    for I := 0 to Count - 1 do
      if (Length(Strings[I]) < 2) or (UpperCase(Strings[I]) <> Strings[I]) then
        Strings[I] := LowerCase(Strings[I]);
    Result := DelimitedText;
  finally
    Free;
  end;
end;

function SuiteDisplayName(AClass: TClass): string;
var
  N: string;
begin
  N := AClass.ClassName;
  if (Length(N) > 1) and (N[1] = 'T') and (N[2] in ['A'..'Z']) then
    Delete(N, 1, 1);
  if (Length(N) > 5) and (Copy(N, Length(N) - 4, 5) = 'Tests') then
    SetLength(N, Length(N) - 5)
  else if (Length(N) > 4) and (Copy(N, Length(N) - 3, 4) = 'Test') then
    SetLength(N, Length(N) - 4);
  Result := HumanName(N);
  if Result <> '' then
    Result[1] := UpCase(Result[1]);
end;

type
  TMethodNameRec = packed record
    Name: PShortString;
    Addr: CodePointer;
  end;
  TMethodNameTable = packed record
    Count: DWord;
    Entries: packed array[0..0] of TMethodNameRec;
  end;
  PMethodNameTable = ^TMethodNameTable;

{ Published methods of a class (not of its ancestors), in declaration order.
  The table is a variable-length record, so range checks are switched off. }
{$push}{$R-}
procedure ListPublished(AClass: TClass; Names: TStrings);
var
  Table: PMethodNameTable;
  I: Integer;
begin
  Table := PMethodNameTable(PVmt(AClass)^.vMethodTable);
  if Table = nil then
    Exit;
  for I := 0 to Integer(Table^.Count) - 1 do
    Names.Add(Table^.Entries[I].Name^);
end;
{$pop}

procedure RegisterTests(ASuite: TTestSuiteClass);
var
  Chain: TFPList;
  Names: TStringList;
  C: TClass;
  I, J: Integer;
  E: TTestEntry;
begin
  Chain := TFPList.Create;
  Names := TStringList.Create;
  try
    { inherited tests first }
    C := ASuite;
    while (C <> nil) and (C <> TTestSuite) do
    begin
      Chain.Insert(0, C);
      C := C.ClassParent;
    end;
    for I := 0 to Chain.Count - 1 do
    begin
      Names.Clear;
      ListPublished(TClass(Chain[I]), Names);
      for J := 0 to Names.Count - 1 do
      begin
        E := TTestEntry.Create;
        E.Suite := ASuite;
        E.SuiteName := SuiteDisplayName(ASuite);
        E.MethodId := Names[J];
        E.TestName := HumanName(Names[J]);
        Entries.Add(E);
      end;
    end;
  finally
    Chain.Free;
    Names.Free;
  end;
end;

procedure Test(const AName: string; AProc: TTestProc);
var
  E: TTestEntry;
begin
  E := TTestEntry.Create;
  E.SuiteName := '';
  E.TestName := AName;
  E.Proc := AProc;
  Entries.Add(E);
end;

{ ---- failures with the test's file and line ---- }

function LocationOf(Addr: CodePointer): string;
var
  S: string;
  P: Integer;
begin
  Result := '';
  if Addr = nil then
    Exit;
  { with line info (debug builds) this looks like
    "  $0000000000401234  GREETSBYNAME,  line 12 of tests/greeting_test.pas" }
  S := BackTraceStrFunc(Addr);
  P := Pos(' line ', S);
  if P = 0 then
    Exit;
  S := Copy(S, P + 6, MaxInt);
  P := Pos(' of ', S);
  if P = 0 then
    Exit;
  Result := Trim(Copy(S, P + 4, MaxInt)) + ':' + Trim(Copy(S, 1, P - 1));
end;

procedure RaiseFailure(const Msg, Extra: string; Addr: CodePointer);
var
  E: ETestFailure;
  Text: string;
begin
  Text := Msg;
  if Extra <> '' then
    if Text <> '' then
      Text := Extra + ' (' + Text + ')'
    else
      Text := Extra;
  E := ETestFailure.Create(Text);
  E.Location := LocationOf(Addr);
  raise E;
end;

function Quote(const S: string): string;
begin
  Result := '"' + StringReplace(StringReplace(S, #13, '\r', [rfReplaceAll]),
    #10, '\n', [rfReplaceAll]) + '"';
end;

procedure AssertTrue(Condition: Boolean; const Msg: string);
begin
  if not Condition then
    RaiseFailure(Msg, 'expected the condition to be true', get_caller_addr(get_frame));
end;

procedure AssertFalse(Condition: Boolean; const Msg: string);
begin
  if Condition then
    RaiseFailure(Msg, 'expected the condition to be false', get_caller_addr(get_frame));
end;

procedure AssertEquals(const Expected, Actual: string; const Msg: string);
begin
  if Expected <> Actual then
    RaiseFailure(Msg, Format('expected %s but got %s', [Quote(Expected), Quote(Actual)]),
      get_caller_addr(get_frame));
end;

procedure AssertEquals(Expected, Actual: Int64; const Msg: string);
begin
  if Expected <> Actual then
    RaiseFailure(Msg, Format('expected %d but got %d', [Expected, Actual]), get_caller_addr(get_frame));
end;

procedure AssertEquals(Expected, Actual: Double; Delta: Double; const Msg: string);
begin
  if Abs(Expected - Actual) > Delta then
    RaiseFailure(Msg, Format('expected %g but got %g', [Expected, Actual]), get_caller_addr(get_frame));
end;

procedure AssertEquals(Expected, Actual: Boolean; const Msg: string);
begin
  if Expected <> Actual then
    RaiseFailure(Msg, Format('expected %s but got %s',
      [BoolToStr(Expected, True), BoolToStr(Actual, True)]), get_caller_addr(get_frame));
end;

procedure AssertNotEquals(const NotExpected, Actual: string; const Msg: string);
begin
  if NotExpected = Actual then
    RaiseFailure(Msg, Format('did not expect %s', [Quote(Actual)]), get_caller_addr(get_frame));
end;

procedure AssertNotEquals(NotExpected, Actual: Int64; const Msg: string);
begin
  if NotExpected = Actual then
    RaiseFailure(Msg, Format('did not expect %d', [Actual]), get_caller_addr(get_frame));
end;

procedure AssertContains(const Part, Actual: string; const Msg: string);
begin
  if Pos(Part, Actual) = 0 then
    RaiseFailure(Msg, Format('expected %s to contain %s', [Quote(Actual), Quote(Part)]),
      get_caller_addr(get_frame));
end;

procedure AssertStartsWith(const Prefix, Actual: string; const Msg: string);
begin
  if Copy(Actual, 1, Length(Prefix)) <> Prefix then
    RaiseFailure(Msg, Format('expected %s to start with %s', [Quote(Actual), Quote(Prefix)]),
      get_caller_addr(get_frame));
end;

procedure AssertNil(P: Pointer; const Msg: string);
begin
  if P <> nil then
    RaiseFailure(Msg, 'expected nil', get_caller_addr(get_frame));
end;

procedure AssertNotNil(P: Pointer; const Msg: string);
begin
  if P = nil then
    RaiseFailure(Msg, 'expected a value, got nil', get_caller_addr(get_frame));
end;

procedure CheckRaised(E: Exception; AClass: ExceptClass; const Msg: string; Addr: CodePointer);
begin
  if E = nil then
    RaiseFailure(Msg, Format('expected %s to be raised, but nothing was raised', [AClass.ClassName]), Addr)
  else if not E.InheritsFrom(AClass) then
    RaiseFailure(Msg, Format('expected %s to be raised, but got %s: %s',
      [AClass.ClassName, E.ClassName, E.Message]), Addr);
end;

procedure AssertRaises(AClass: ExceptClass; AProc: TTestProc; const Msg: string);
var
  Addr: CodePointer;
begin
  Addr := get_caller_addr(get_frame);
  try
    AProc();
  except
    on E: Exception do
    begin
      CheckRaised(E, AClass, Msg, Addr);
      Exit;
    end;
  end;
  CheckRaised(nil, AClass, Msg, Addr);
end;

procedure AssertRaises(AClass: ExceptClass; AMethod: TTestMethod; const Msg: string);
var
  Addr: CodePointer;
begin
  Addr := get_caller_addr(get_frame);
  try
    AMethod();
  except
    on E: Exception do
    begin
      CheckRaised(E, AClass, Msg, Addr);
      Exit;
    end;
  end;
  CheckRaised(nil, AClass, Msg, Addr);
end;

procedure Fail(const Msg: string);
begin
  RaiseFailure('', Msg, get_caller_addr(get_frame));
end;

procedure Skip(const Reason: string);
begin
  raise ETestSkipped.Create(Reason);
end;

{ ---- running ---- }

type
  TOutcome = (toPass, toFail, toError, toSkip);

function JsonStr(const S: string): string;
var
  I: Integer;
begin
  Result := '"';
  for I := 1 to Length(S) do
    case S[I] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
    else
      if S[I] < ' ' then
        Result := Result + '\u' + IntToHex(Ord(S[I]), 4)
      else
        Result := Result + S[I];
    end;
  Result := Result + '"';
end;

function UseColor: Boolean;
begin
  Result := (GetEnv('NO_COLOR') = '') and (GetEnv('PASTEL_COLOR') = '1');
end;

function Paint(const Code, S: string): string;
begin
  if UseColor then
    Result := #27'[' + Code + 'm' + S + #27'[0m'
  else
    Result := S;
end;

{ TGreetingTests.GreetsByName, or the name given to Test() }
function EntryId(E: TTestEntry): string;
begin
  if E.Suite <> nil then
    Result := E.Suite.ClassName + '.' + E.MethodId
  else
    Result := E.TestName;
end;

{ A filter is part of a name ("greet"), or "=" and an exact id
  ("=TGreetingTests.GreetsByName", used by editors). }
function Matches(E: TTestEntry; Filters: TStrings): Boolean;
var
  F, Full: string;
begin
  if Filters.Count = 0 then
    Exit(True);
  Full := LowerCase(E.SuiteName + ' ' + E.TestName + ' ' + E.MethodId + ' ' + EntryId(E));
  for F in Filters do
    if (F <> '') and (F[1] = '=') then
    begin
      if SameText(Copy(F, 2, MaxInt), EntryId(E)) then
        Exit(True);
    end
    else if Pos(LowerCase(F), Full) > 0 then
      Exit(True);
  Result := False;
end;

function RunOne(E: TTestEntry; out Msg, Location: string): TOutcome;
var
  Suite: TTestSuite;
  M: TMethod;
begin
  Msg := '';
  Location := '';
  Suite := nil;
  try
    try
      if E.Suite <> nil then
      begin
        Suite := E.Suite.Create;
        Suite.SetUp;
        try
          M.Code := Suite.MethodAddress(E.MethodId);
          M.Data := Suite;
          TTestMethod(M)();
        finally
          Suite.TearDown;
        end;
      end
      else
        E.Proc();
      Result := toPass;
    except
      on X: ETestSkipped do
      begin
        Msg := X.Message;
        Result := toSkip;
      end;
      on X: ETestFailure do
      begin
        Msg := X.Message;
        Location := X.Location;
        Result := toFail;
      end;
      on X: Exception do
      begin
        Msg := X.ClassName + ': ' + X.Message;
        Location := LocationOf(ExceptAddr);
        Result := toError;
      end;
    end;
  finally
    Suite.Free;
  end;
end;

function RunTests: Integer;
var
  Filters: TStringList;
  Json: Boolean;
  Counts: array[TOutcome] of Integer;
  E: TTestEntry;
  Outcome: TOutcome;
  Msg, Location, Title, LastSuite: string;
  Started, T0, Ms: QWord;
  First: Boolean;
  K: TOutcome;
  N, Total: Integer;
const
  OutcomeName: array[TOutcome] of string = ('passed', 'failed', 'error', 'skipped');
begin
  Filters := TStringList.Create;
  Json := False;
  for N := 1 to ParamCount do
    if ParamStr(N) = '--json' then
      Json := True
    else
      Filters.Add(ParamStr(N));
  for K := Low(TOutcome) to High(TOutcome) do
    Counts[K] := 0;
  Total := 0;
  Started := GetTickCount64;
  LastSuite := #0;
  First := True;
  if Json then
    Write('[');
  try
    for N := 0 to Entries.Count - 1 do
    begin
      E := TTestEntry(Entries[N]);
      if not Matches(E, Filters) then
        Continue;
      Inc(Total);
      T0 := GetTickCount64;
      Outcome := RunOne(E, Msg, Location);
      Ms := GetTickCount64 - T0;
      Inc(Counts[Outcome]);
      if Json then
      begin
        if not First then
          Write(',');
        First := False;
        Write(Format('{"id":%s,"suite":%s,"name":%s,"method":%s,"outcome":%s,"ms":%d,"message":%s,"location":%s}',
          [JsonStr(EntryId(E)), JsonStr(E.SuiteName), JsonStr(E.TestName), JsonStr(E.MethodId),
           JsonStr(OutcomeName[Outcome]), Ms, JsonStr(Msg), JsonStr(Location)]));
        Continue;
      end;
      if E.SuiteName <> LastSuite then
      begin
        if E.SuiteName <> '' then
          WriteLn(Paint('1', E.SuiteName));
        LastSuite := E.SuiteName;
      end;
      Title := E.TestName;
      case Outcome of
        toPass: WriteLn('  ', Paint('32', 'PASS'), ' ', Title, Paint('2', Format(' (%d ms)', [Ms])));
        toSkip: WriteLn('  ', Paint('33', 'SKIP'), ' ', Title, Paint('2', ' - ' + Msg));
        toFail, toError:
          begin
            if Outcome = toFail then
              WriteLn('  ', Paint('31', 'FAIL'), ' ', Title)
            else
              WriteLn('  ', Paint('31', 'ERROR'), ' ', Title);
            WriteLn('       ', Msg);
            if Location <> '' then
              WriteLn(Paint('2', '       at ' + Location));
          end;
      end;
    end;
    if Json then
    begin
      WriteLn(']');
    end
    else
    begin
      if Total = 0 then
      begin
        if Filters.Count > 0 then
          WriteLn('No test matches "', Filters.CommaText, '".')
        else
          WriteLn('No tests found.');
      end
      else
      begin
        WriteLn;
        Write(Paint('1', 'Tests: '));
        if Counts[toFail] + Counts[toError] > 0 then
          Write(Paint('31', Format('%d failed', [Counts[toFail] + Counts[toError]])), ', ');
        Write(Paint('32', Format('%d passed', [Counts[toPass]])));
        if Counts[toSkip] > 0 then
          Write(', ', Paint('33', Format('%d skipped', [Counts[toSkip]])));
        WriteLn(Format(', %d total (%d ms)', [Total, GetTickCount64 - Started]));
      end;
    end;
  finally
    Filters.Free;
  end;
  if Counts[toFail] + Counts[toError] > 0 then
    Result := 1
  else
    Result := 0;
end;

procedure FreeEntries;
var
  I: Integer;
begin
  for I := 0 to Entries.Count - 1 do
    TObject(Entries[I]).Free;
  Entries.Free;
end;

initialization
  Entries := TFPList.Create;

finalization
  FreeEntries;

end.
