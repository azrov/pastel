{ Pastel - source formatter for "pastel fmt".

  What it changes:
  - indentation, from the structure of the code (begin/end, try, case,
    class, var sections, if/then/else, nested routines, ...)
  - reserved words in lower case (option)
  - a space around :=, after commas and after ; inside a line (more
    spaces are kept, for lined-up code); none before , and ;
  - trailing spaces, more than one blank line in a row, tabs at the start
    of lines, the line break at the end of the file

  What it keeps:
  - line breaks: it never joins or splits lines
  - the inside of comments and strings; asm blocks
  - the layout of statements that continue on the next line (their
    indentation moves with the statement)
  - anything between // fmt: off and // fmt: on

  Safety: a file whose begin/end do not match is not touched, and after
  formatting the code is read again and compared token by token with the
  original; if anything but spacing differs, nothing is written.
  Part of the Pastel project, MIT License. }
unit Pastel.Format;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TFormatOptions = record
    IndentSize: Integer;       { default 2 }
    LowerKeywords: Boolean;    { BEGIN -> begin }
    NestedComments: Boolean;   // a comment in curly brackets may hold another (fpc/objfpc mode)
  end;

function DefaultFormatOptions: TFormatOptions;

{ Formats Source. False and Error (with a line number) when the file could
  not be understood; Output is then Source unchanged. }
function FormatPascal(const Source: string; const Options: TFormatOptions;
  out Output, Error: string): Boolean;

implementation

type
  TTokKind = (tkWord, tkNumber, tkString, tkComment, tkDirective, tkSymbol);

  TToken = record
    Kind: TTokKind;
    Text: string;
    Lower: string;
    Line, EndLine: Integer;   { 0-based }
    Space: string;            { whitespace before it on the same line }
    First: Boolean;           { first token on its line }
  end;
  TTokens = array of TToken;

  TFrameKind = (frBlock, frCase, frHang, frSection, frRoutine, frInit);

  TFrame = record
    Kind: TFrameKind;
    Sub: string;     { block: begin, try, repeat, asm, record, class, ...;
                       hang: then, else, do, label; section: var, uses, ... }
    Open: Integer;   { indent of the line that opened it }
    Indent: Integer; { indent of the lines inside }
    Owner: Integer;  { hang: indent of the statement it belongs to }
    Variant, InElse, OfSeen, Body: Boolean;
    Line: Integer;
    PDepth: Integer; { parenthesis depth where it was opened }
  end;

  TUnitPart = (upProgram, upNone, upInterface, upImplementation);

  TState = record
    Frames: array of TFrame;
    Depth: Integer;
    Part: TUnitPart;
    LastSig: Integer;
  end;

  TDirFrame = record
    Saved, Branch1: TState;
    HasElse: Boolean;
    Indent: Integer;
  end;

  EFormatError = class(Exception);

  { pieces of the output, joined once at the end }
  TPieces = object
  private
    FParts: array of string;
    FCount: Integer;
  public
    procedure Add(const S: string);
    function Text: string;
  end;

const
  Reserved: array[0..62] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except',
    'exports', 'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'interface', 'is',
    'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'operator', 'or',
    'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat',
    'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to',
    'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with');
  { 'xor' is added below; kept apart so the array stays readable }

  RoutineDirectives: array[0..41] of string = (
    'cdecl', 'stdcall', 'register', 'pascal', 'safecall', 'inline', 'overload',
    'virtual', 'override', 'abstract', 'reintroduce', 'static', 'dynamic',
    'message', 'export', 'public', 'assembler', 'nostackframe', 'local',
    'varargs', 'deprecated', 'platform', 'experimental', 'unimplemented',
    'iocheck', 'noreturn', 'interrupt', 'compilerproc', 'hardfloat', 'softfloat',
    'ms_abi_default', 'sysv_abi_default', 'vectorcall', 'winapi', 'alias',
    'final', 'mwpascal', 'oldfpccall', 'saveregisters', 'far', 'near', 'cppdecl');

function InList(const S: string; const List: array of string): Boolean;
var
  I: Integer;
begin
  for I := Low(List) to High(List) do
    if List[I] = S then
      Exit(True);
  Result := False;
end;

function IsReserved(const S: string): Boolean;
begin
  Result := InList(S, Reserved) or (S = 'xor');
end;

function DefaultFormatOptions: TFormatOptions;
begin
  Result.IndentSize := 2;
  Result.LowerKeywords := True;
  Result.NestedComments := True;
end;

{ ---------------- tokenizer ---------------- }

// Free Pascal allows a comment in curly brackets inside another one in its
// own modes (fpc, objfpc), not in Delphi or TP mode.
function UsesNestedComments(const Src: string; Default: Boolean): Boolean;
var
  L: string;
  I: Integer;
begin
  L := LowerCase(Src);
  I := Pos('{$mode ', L);
  if I = 0 then
    Exit(Default);
  L := Copy(L, I + 7, 12);
  Result := (Copy(L, 1, 6) = 'objfpc') or (Copy(L, 1, 3) = 'fpc');
end;

procedure Tokenize(const Src: string; NestedDefault: Boolean; out Toks: TTokens);
var
  Nested: Boolean;
  P, Len, Line, Count: Integer;
  Space: string;
  LineHasToken: Boolean;

  procedure Add(Kind: TTokKind; Start, StartLine: Integer);
  var
    T: TToken;
  begin
    T.Kind := Kind;
    T.Text := Copy(Src, Start, P - Start);
    if Kind = tkWord then
      T.Lower := LowerCase(T.Text)
    else
      T.Lower := T.Text;
    T.Line := StartLine;
    T.EndLine := Line;
    T.Space := Space;
    T.First := not LineHasToken;
    if Count = Length(Toks) then
      SetLength(Toks, Count * 2 + 64);
    Toks[Count] := T;
    Inc(Count);
    Space := '';
    LineHasToken := True;
  end;

  procedure SkipBrace(StartLine: Integer);
  var
    Level: Integer;
  begin
    Level := 0;
    while P <= Len do
    begin
      case Src[P] of
        '{':
          if Nested or (Level = 0) then
            Inc(Level);
        '}':
          begin
            Dec(Level);
            if Level = 0 then
            begin
              Inc(P);
              Exit;
            end;
          end;
        #10:
          Inc(Line);
      end;
      Inc(P);
    end;
    raise EFormatError.CreateFmt('line %d: a { comment is not closed', [StartLine + 1]);
  end;

  procedure SkipTo(const Closer: string; const What: string; StartLine: Integer);
  begin
    while (P <= Len) and (Copy(Src, P, Length(Closer)) <> Closer) do
    begin
      if Src[P] = #10 then
        Inc(Line);
      Inc(P);
    end;
    if P > Len then
      raise EFormatError.CreateFmt('line %d: %s is not closed', [StartLine + 1, What]);
    Inc(P, Length(Closer));
  end;

var
  Start, StartLine: Integer;
  C: Char;
begin
  Toks := nil;
  Count := 0;
  Nested := UsesNestedComments(Src, NestedDefault);
  P := 1;
  Len := Length(Src);
  Line := 0;
  Space := '';
  LineHasToken := False;
  if Copy(Src, 1, 3) = #$EF#$BB#$BF then
    P := 4;
  while P <= Len do
  begin
    C := Src[P];
    Start := P;
    StartLine := Line;
    case C of
      #10:
        begin
          Inc(Line);
          Inc(P);
          Space := '';
          LineHasToken := False;
        end;
      #13:
        Inc(P);
      ' ', #9, #12:
        begin
          Space := Space + C;
          Inc(P);
        end;
      '{':
        begin
          SkipBrace(StartLine);
          if Copy(Src, Start, 2) = '{$' then
            Add(tkDirective, Start, StartLine)
          else
            Add(tkComment, Start, StartLine);
        end;
      '''':
        begin
          Inc(P);
          repeat
            while (P <= Len) and not (Src[P] in ['''', #10, #13]) do
              Inc(P);
            if (P > Len) or (Src[P] <> '''') then
              raise EFormatError.CreateFmt('line %d: a string is not closed', [StartLine + 1]);
            Inc(P);
            if (P <= Len) and (Src[P] = '''') then
              Inc(P)        { '' inside a string }
            else
              Break;
          until False;
          Add(tkString, Start, StartLine);
        end;
      '#':
        begin
          Inc(P);
          if (P <= Len) and (Src[P] = '$') then
            Inc(P);
          while (P <= Len) and (Src[P] in ['0'..'9', 'A'..'F', 'a'..'f']) do
            Inc(P);
          Add(tkString, Start, StartLine);
        end;
      '0'..'9', '$', '%':
        begin
          Inc(P);
          while (P <= Len) and (Src[P] in ['0'..'9', 'A'..'F', 'a'..'f', '_']) do
            Inc(P);
          if (C in ['0'..'9']) and (P < Len) and (Src[P] = '.') and (Src[P + 1] in ['0'..'9']) then
          begin
            Inc(P);
            while (P <= Len) and (Src[P] in ['0'..'9']) do
              Inc(P);
          end;
          if (C in ['0'..'9']) and (P <= Len) and (Src[P] in ['e', 'E']) and
             (P < Len) and (Src[P + 1] in ['0'..'9', '+', '-']) then
          begin
            Inc(P, 2);
            while (P <= Len) and (Src[P] in ['0'..'9']) do
              Inc(P);
          end;
          Add(tkNumber, Start, StartLine);
        end;
      'A'..'Z', 'a'..'z', '_', '&':
        begin
          if (C = '&') and ((P >= Len) or not (Src[P + 1] in ['A'..'Z', 'a'..'z', '_', '0'..'7'])) then
          begin
            Inc(P);
            Add(tkSymbol, Start, StartLine);
          end
          else if (C = '&') and (Src[P + 1] in ['0'..'7']) then
          begin
            Inc(P);
            while (P <= Len) and (Src[P] in ['0'..'7']) do
              Inc(P);
            Add(tkNumber, Start, StartLine);
          end
          else
          begin
            Inc(P);
            while (P <= Len) and (Src[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
              Inc(P);
            Add(tkWord, Start, StartLine);
          end;
        end;
    else
      if Copy(Src, P, 2) = '//' then
      begin
        while (P <= Len) and not (Src[P] in [#10, #13]) do
          Inc(P);
        Add(tkComment, Start, StartLine);
      end
      else if Copy(Src, P, 2) = '(*' then
      begin
        SkipTo('*)', 'a (* comment', StartLine);
        if Copy(Src, Start, 3) = '(*$' then
          Add(tkDirective, Start, StartLine)
        else
          Add(tkComment, Start, StartLine);
      end
      else
      begin
        if Pos(Copy(Src, P, 2) + ' ', ':= <= >= <> .. += -= *= /= >< ** @@ ') > 0 then
          Inc(P, 2)
        else
          Inc(P);
        Add(tkSymbol, Start, StartLine);
      end;
    end;
  end;
  SetLength(Toks, Count);
end;

{ ---------------- formatter ---------------- }

type
  TFormatter = class
  private
    Toks: TTokens;
    Lines: array of string;
    Opt: TFormatOptions;
    U: Integer;
    S: TState;
    Dirs: array of TDirFrame;
    LabelColon, CaseOf: array of Boolean;
    AnchorOld, AnchorNew, CurLI: Integer;
    FmtOff: Boolean;
    Output: TPieces;
    function Top: Integer;
    function TopIs(K: TFrameKind): Boolean;
    function TopIsBlock(const Subs: array of string): Boolean;
    procedure Push(Kind: TFrameKind; const Sub: string; Open, Indent, Line: Integer);
    procedure Pop;
    procedure PopHangs;
    procedure PopSections;
    procedure PopAll(Line: Integer);
    function DefaultIndent: Integer;
    function OrigIndent(Line: Integer): Integer;
    function Relative(Line: Integer): Integer;
    function NextSig(K: Integer): Integer;
    function PrevSig(K: Integer): Integer;
    function SigText(K: Integer): string;
    function MatchingParen(K: Integer): Integer;
    function NoBody(K: Integer): Boolean;
    function OpensTypeBlock(K: Integer): Boolean;
    function IsHeader(K: Integer): Boolean;
    function IsSection(K: Integer): Boolean;
    function LastIsContinuation: Boolean;
    function StartsContinuation(K: Integer): Boolean;
    function NeverContinuation(K: Integer): Boolean;
    function CopyState: TState;
    procedure Directive(K: Integer; IsFirst, Cont: Boolean; var LI: Integer);
    procedure Process(K: Integer; IsFirst, Cont: Boolean; var LI: Integer);
    function CommentIndent(K, LI: Integer): Integer;
    function IsBranchDirective(K: Integer): Boolean;
    function InDeclarations: Boolean;
    function InClassSections: Boolean;
    function TokenText(const T: TToken): string;
    function Spacing(K: Integer): string;
    function CommentText(const T: TToken; Delta: Integer): string;
  public
    Eol: string;
    function Run(const Src: string; const Options: TFormatOptions): string;
  end;

procedure TPieces.Add(const S: string);
begin
  if FCount = Length(FParts) then
    SetLength(FParts, FCount * 2 + 256);
  FParts[FCount] := S;
  Inc(FCount);
end;

function TPieces.Text: string;
var
  I, N, P: Integer;
begin
  N := 0;
  for I := 0 to FCount - 1 do
    Inc(N, Length(FParts[I]));
  SetLength(Result, N);
  P := 1;
  for I := 0 to FCount - 1 do
    if FParts[I] <> '' then
    begin
      Move(FParts[I][1], Result[P], Length(FParts[I]));
      Inc(P, Length(FParts[I]));
    end;
end;

function TFormatter.Top: Integer;
begin
  Result := High(S.Frames);
end;

function TFormatter.TopIs(K: TFrameKind): Boolean;
begin
  Result := (Length(S.Frames) > 0) and (S.Frames[Top].Kind = K);
end;

function TFormatter.TopIsBlock(const Subs: array of string): Boolean;
begin
  Result := TopIs(frBlock) and InList(S.Frames[Top].Sub, Subs);
end;

procedure TFormatter.Push(Kind: TFrameKind; const Sub: string; Open, Indent, Line: Integer);
var
  F: TFrame;
begin
  F := Default(TFrame);
  F.Kind := Kind;
  F.Sub := Sub;
  F.Open := Open;
  F.Indent := Indent;
  F.Owner := Open;
  F.Line := Line;
  F.PDepth := S.Depth;
  SetLength(S.Frames, Length(S.Frames) + 1);
  S.Frames[Top] := F;
end;

procedure TFormatter.Pop;
begin
  if Length(S.Frames) > 0 then
    SetLength(S.Frames, Length(S.Frames) - 1);
end;

procedure TFormatter.PopHangs;
begin
  while TopIs(frHang) do
    Pop;
end;

procedure TFormatter.PopSections;
begin
  while TopIs(frSection) do
    Pop;
end;

{ implementation, initialization, ...: only declarations may be open }
procedure TFormatter.PopAll(Line: Integer);
begin
  while Length(S.Frames) > 0 do
  begin
    if not (S.Frames[Top].Kind in [frSection, frInit, frHang]) and
       not ((S.Frames[Top].Kind = frRoutine) and not S.Frames[Top].Body) then
      raise EFormatError.CreateFmt('line %d: "%s" from line %d has no matching "end"',
        [Line + 1, S.Frames[Top].Sub, S.Frames[Top].Line + 1]);
    Pop;
  end;
end;

function TFormatter.DefaultIndent: Integer;
begin
  if Length(S.Frames) = 0 then
    Exit(0);
  if S.Frames[Top].Kind = frRoutine then
    Result := S.Frames[Top].Open
  else
    Result := S.Frames[Top].Indent;
end;

function TFormatter.OrigIndent(Line: Integer): Integer;
var
  I: Integer;
  L: string;
begin
  Result := 0;
  if (Line < 0) or (Line > High(Lines)) then
    Exit;
  L := Lines[Line];
  for I := 1 to Length(L) do
    case L[I] of
      ' ': Inc(Result);
      #9: Inc(Result, U);
    else
      Break;
    end;
end;

function TFormatter.Relative(Line: Integer): Integer;
var
  D: Integer;
begin
  D := OrigIndent(Line) - AnchorOld;
  if D < 0 then
    D := 0;
  Result := AnchorNew + D;
end;

function TFormatter.NextSig(K: Integer): Integer;
begin
  Result := K + 1;
  while (Result <= High(Toks)) and (Toks[Result].Kind in [tkComment, tkDirective]) do
    Inc(Result);
  if Result > High(Toks) then
    Result := -1;
end;

function TFormatter.PrevSig(K: Integer): Integer;
begin
  Result := K - 1;
  while (Result >= 0) and (Toks[Result].Kind in [tkComment, tkDirective]) do
    Dec(Result);
end;

function TFormatter.SigText(K: Integer): string;
begin
  if (K < 0) or (K > High(Toks)) then
    Result := ''
  else
    Result := Toks[K].Lower;
end;

function TFormatter.MatchingParen(K: Integer): Integer;
var
  D: Integer;
begin
  D := 0;
  Result := K;
  while Result <= High(Toks) do
  begin
    if Toks[Result].Kind = tkSymbol then
      if (Toks[Result].Text = '(') or (Toks[Result].Text = '[') then
        Inc(D)
      else if (Toks[Result].Text = ')') or (Toks[Result].Text = ']') then
      begin
        Dec(D);
        if D = 0 then
          Exit;
      end;
    Inc(Result);
  end;
  Result := -1;
end;

{ After a routine header: "forward;" or "external ..." means no body. }
function TFormatter.NoBody(K: Integer): Boolean;
var
  J, D: Integer;
begin
  Result := False;
  J := K;
  D := 0;
  while J <= High(Toks) do
  begin
    if Toks[J].Kind = tkSymbol then
      if Toks[J].Text = '(' then
        Inc(D)
      else if Toks[J].Text = ')' then
        Dec(D)
      else if (Toks[J].Text = ';') and (D = 0) then
        Break;
    Inc(J);
  end;
  repeat
    J := NextSig(J);
    if J < 0 then
      Exit;
    if (Toks[J].Lower = 'forward') or (Toks[J].Lower = 'external') then
      Exit(True);
    if (Toks[J].Kind = tkWord) and InList(Toks[J].Lower, RoutineDirectives) then
    begin
      while (J <= High(Toks)) and (Toks[J].Text <> ';') do
        Inc(J);
    end
    else if Toks[J].Text = '[' then
    begin
      J := MatchingParen(J);
      if J < 0 then
        Exit;
      J := NextSig(J);
      if (J < 0) or (Toks[J].Text <> ';') then
        Exit;
    end
    else
      Exit;
  until False;
end;

{ class/object/interface after "=" start a block, except "class of",
  forward declarations ("= class;") and "= class(TBase);" }
function TFormatter.OpensTypeBlock(K: Integer): Boolean;
var
  P, N: Integer;
begin
  P := PrevSig(K);
  { "TList<T>=class" reads as "TList<T" ">=" "class" }
  if not InList(SigText(P), ['=', 'packed', '>=']) then
    Exit(False);
  N := NextSig(K);
  if (SigText(N) = 'of') or (SigText(N) = ';') then
    Exit(False);
  while InList(SigText(N), ['abstract', 'sealed', 'external', 'name']) or
        ((N >= 0) and (Toks[N].Kind = tkString)) do
    N := NextSig(N);
  if SigText(N) = '(' then
  begin
    N := MatchingParen(N);
    if N < 0 then
      Exit(False);
    if SigText(NextSig(N)) = ';' then
      Exit(False);
  end
  else if SigText(N) = ';' then
    Exit(False);
  Result := True;
end;

function TFormatter.IsHeader(K: Integer): Boolean;
var
  P: string;
begin
  P := SigText(PrevSig(K));
  Result := (S.Depth = 0) and (P <> '=') and (P <> ':') and (P <> 'of') and
    (P <> 'to') and (P <> '(') and (P <> ',');
end;

function TFormatter.IsSection(K: Integer): Boolean;
var
  P: string;
begin
  P := SigText(PrevSig(K));
  Result := (S.Depth = 0) and (P <> 'of') and (P <> 'class') and (P <> '=') and
    (P <> ':') and (P <> 'packed');
end;

function TFormatter.LastIsContinuation: Boolean;
var
  K: Integer;
  T: string;
begin
  K := S.LastSig;
  if K < 0 then
    Exit(False);
  T := Toks[K].Lower;
  if Toks[K].Kind = tkSymbol then
  begin
    if T = ':' then
      Exit(not LabelColon[K]);
    Exit(InList(T, [',', ':=', '+', '-', '*', '/', '=', '<>', '<', '>', '<=', '>=', '(', '[',
      '.', '..', '@', '+=', '-=', '*=', '/=', '^', '**']));
  end;
  if Toks[K].Kind <> tkWord then
    Exit(False);
  if T = 'of' then
    Exit(not CaseOf[K]);
  Result := InList(T, ['and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is',
    'as', 'if', 'while', 'for', 'to', 'downto', 'case', 'with', 'until', 'on', 'array',
    'set', 'packed']);
end;

function TFormatter.StartsContinuation(K: Integer): Boolean;
var
  T: string;
begin
  T := Toks[K].Lower;
  if Toks[K].Kind = tkSymbol then
    Result := InList(T, [')', ']', ',', '.', ':=', '+', '-', '*', '/', '=', '<>', '<', '>',
      '<=', '>=', '..', ';', '^'])
  else if Toks[K].Kind = tkWord then
    Result := InList(T, ['and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as',
      'then', 'do', 'of', 'to', 'downto'])
  else
    Result := False;
end;

function TFormatter.NeverContinuation(K: Integer): Boolean;
begin
  Result := (Toks[K].Kind = tkWord) and InList(Toks[K].Lower, ['begin', 'end', 'else',
    'except', 'finally', 'until', 'try', 'repeat', 'asm', 'if', 'while', 'for', 'with',
    'implementation', 'initialization', 'finalization', 'unit', 'program', 'library',
    'private', 'protected', 'public', 'published', 'strict', 'automated']);
end;

function TFormatter.CopyState: TState;
begin
  Result := S;
  Result.Frames := Copy(S.Frames);
end;

procedure TFormatter.Directive(K: Integer; IsFirst, Cont: Boolean; var LI: Integer);
var
  Name: string;
  I: Integer;
begin
  Name := UpperCase(Toks[K].Text);
  if Copy(Name, 1, 2) = '{$' then
    Delete(Name, 1, 2)
  else
    Delete(Name, 1, 3);
  I := 1;
  while (I <= Length(Name)) and (Name[I] in ['A'..'Z']) do
    Inc(I);
  SetLength(Name, I - 1);

  if IsFirst then
    if Cont then
      LI := Relative(Toks[K].Line)
    else
      LI := DefaultIndent;

  if (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IF') or (Name = 'IFOPT') then
  begin
    SetLength(Dirs, Length(Dirs) + 1);
    Dirs[High(Dirs)].Saved := CopyState;
    Dirs[High(Dirs)].HasElse := False;
    if IsFirst then
      Dirs[High(Dirs)].Indent := LI
    else
      Dirs[High(Dirs)].Indent := CurLI;
  end
  else if (Name = 'ELSE') or (Name = 'ELSEIF') or (Name = 'ELIF') then
  begin
    if Length(Dirs) = 0 then
      Exit;
    with Dirs[High(Dirs)] do
    begin
      if not HasElse then
      begin
        Branch1 := CopyState;
        HasElse := True;
      end;
      S := Saved;
      S.Frames := Copy(Saved.Frames);
      if IsFirst then
        LI := Indent;
    end;
  end
  else if (Name = 'ENDIF') or (Name = 'IFEND') then
  begin
    if Length(Dirs) = 0 then
      Exit;
    with Dirs[High(Dirs)] do
    begin
      if HasElse then
      begin
        S := Branch1;
        S.Frames := Copy(Branch1.Frames);
      end;
      if IsFirst then
        LI := Indent;
    end;
    SetLength(Dirs, Length(Dirs) - 1);
  end;
end;

procedure TFormatter.Process(K: Integer; IsFirst, Cont: Boolean; var LI: Integer);
var
  T: TToken;
  W: string;
  Owner, Open: Integer;
  Found, Variant: Boolean;

  procedure Plain;
  begin
    if IsFirst then
      if Cont then
        LI := Relative(T.Line)
      else
        LI := DefaultIndent;
  end;

  function Here: Integer;
  begin
    if IsFirst then
      Result := LI
    else
      Result := CurLI;
  end;

begin
  T := Toks[K];
  W := T.Lower;

  if T.Kind = tkComment then
  begin
    if Pos('fmt: off', LowerCase(T.Text)) > 0 then
      FmtOff := True
    else if Pos('fmt: on', LowerCase(T.Text)) > 0 then
      FmtOff := False;
    Plain;
    Exit;
  end;
  if T.Kind = tkDirective then
  begin
    Directive(K, IsFirst, Cont, LI);
    Exit;
  end;

  { inside asm only "end" matters }
  if TopIsBlock(['asm']) and (W <> 'end') then
  begin
    Plain;
    Exit;
  end;

  if T.Kind = tkSymbol then
  begin
    Plain;
    if (W = '(') or (W = '[') then
      Inc(S.Depth)
    else if (W = ')') or (W = ']') then
    begin
      if S.Depth > 0 then
        Dec(S.Depth);
      { a nested variant part "(... case X of ...)" ends with its parenthesis }
      while (TopIs(frCase) or TopIs(frHang)) and (S.Frames[Top].PDepth > S.Depth) do
        Pop;
    end
    else if (W = ';') and ((S.Depth = 0) or (TopIs(frHang) and (S.Frames[Top].PDepth = S.Depth))) then
    begin
      PopHangs;
      if TopIs(frSection) and (S.Frames[Top].Sub = 'uses') then
        Pop;
    end
    else if (W = ':') and TopIs(frCase) and (S.Depth = S.Frames[Top].PDepth) and
            not S.Frames[Top].InElse then
    begin
      LabelColon[K] := True;
      Owner := AnchorNew;
      Push(frHang, 'label', Owner, Owner + U, T.Line);
    end;
    S.LastSig := K;
    Exit;
  end;

  if T.Kind <> tkWord then
  begin
    Plain;
    S.LastSig := K;
    Exit;
  end;

  if (W = 'begin') or (W = 'asm') or (W = 'try') then
  begin
    PopSections;
    if IsFirst then
    begin
      if TopIs(frHang) and (S.Frames[Top].Sub = 'label') then
        LI := S.Frames[Top].Indent
      else if TopIs(frHang) then
        LI := S.Frames[Top].Owner
      else
        LI := DefaultIndent;
    end;
    if TopIs(frRoutine) and (W <> 'try') then
      S.Frames[Top].Body := True;
    Open := Here;
    Push(frBlock, W, Open, Open + U, T.Line);
  end
  else if W = 'repeat' then
  begin
    Plain;
    Open := Here;
    Push(frBlock, W, Open, Open + U, T.Line);
  end
  else if W = 'end' then
  begin
    PopHangs;
    Found := False;
    repeat
      if TopIs(frSection) then
        Pop
      else if TopIs(frCase) and S.Frames[Top].Variant then
        Pop
      else if TopIs(frRoutine) and not S.Frames[Top].Body then
        Pop
      else if TopIs(frInit) then
      begin
        Pop;
        Open := 0;
        Found := True;
        Break;
      end
      else
        Break;
    until False;
    if not Found then
    begin
      if TopIs(frBlock) or TopIs(frCase) then
      begin
        Open := S.Frames[Top].Open;
        Pop;
        if TopIs(frRoutine) and S.Frames[Top].Body then
          Pop;
      end
      else if (Length(S.Frames) = 0) and (SigText(NextSig(K)) = '.') then
        Open := 0
      else
        raise EFormatError.CreateFmt('line %d: "end" without a matching begin, try, case, record or class',
          [T.Line + 1]);
    end;
    if IsFirst then
      LI := Open;
  end
  else if W = 'else' then
  begin
    Found := False;
    Owner := 0;
    while TopIs(frHang) do
    begin
      if S.Frames[Top].Sub = 'then' then
      begin
        Owner := S.Frames[Top].Owner;
        Pop;
        Found := True;
        Break;
      end;
      Pop;
    end;
    if Found then
    begin
      if IsFirst then
        LI := Owner;
      Push(frHang, 'else', Owner, Owner + U, T.Line);
    end
    else if TopIs(frCase) then
    begin
      if IsFirst then
        LI := S.Frames[Top].Open;
      S.Frames[Top].InElse := True;
      S.Frames[Top].Indent := S.Frames[Top].Open + U;
    end
    else if TopIsBlock(['try']) then
    begin
      if IsFirst then
        LI := S.Frames[Top].Open;
    end
    else
      Plain;
  end
  else if (W = 'except') or (W = 'finally') then
  begin
    PopHangs;
    if TopIsBlock(['try']) then
    begin
      if IsFirst then
        LI := S.Frames[Top].Open;
    end
    else
      raise EFormatError.CreateFmt('line %d: "%s" without "try"', [T.Line + 1, W]);
  end
  else if W = 'until' then
  begin
    PopHangs;
    if TopIsBlock(['repeat']) then
    begin
      if IsFirst then
        LI := S.Frames[Top].Open;
      Pop;
    end
    else
      raise EFormatError.CreateFmt('line %d: "until" without "repeat"', [T.Line + 1]);
  end
  else if (W = 'then') or (W = 'do') then
  begin
    Plain;
    Owner := AnchorNew;
    Push(frHang, W, Owner, Owner + U, T.Line);
  end
  else if W = 'case' then
  begin
    Plain;
    { a variant part of a record (maybe after "var" or "const" in it) }
    Open := Top;
    while (Open >= 0) and (S.Frames[Open].Kind = frSection) do
      Dec(Open);
    Variant := (S.Depth > 0) or ((Open >= 0) and (S.Frames[Open].Kind = frBlock) and
      InList(S.Frames[Open].Sub, ['record', 'class', 'object']));
    Open := Here;
    Push(frCase, 'case', Open, Open + U, T.Line);
    S.Frames[Top].Variant := Variant;
  end
  else if W = 'of' then
  begin
    Plain;
    if TopIs(frCase) and not S.Frames[Top].OfSeen then
    begin
      S.Frames[Top].OfSeen := True;
      CaseOf[K] := True;
    end;
  end
  else if W = 'record' then
  begin
    Plain;
    Open := Here;
    Push(frBlock, 'record', Open, Open + U, T.Line);
  end
  else if InList(W, ['class', 'object', 'dispinterface', 'objcclass', 'objcprotocol',
          'objccategory', 'cppclass']) and OpensTypeBlock(K) then
  begin
    Plain;
    Open := Here;
    Push(frBlock, W, Open, Open + U, T.Line);
  end
  else if (W = 'helper') and (SigText(PrevSig(K)) = 'type') then
  begin
    Plain;
    Open := Here;
    Push(frBlock, 'helper', Open, Open + U, T.Line);
  end
  else if W = 'interface' then
  begin
    if SigText(PrevSig(K)) = '=' then
    begin
      Plain;
      if OpensTypeBlock(K) then
      begin
        Open := Here;
        Push(frBlock, 'interface', Open, Open + U, T.Line);
      end;
    end
    else
    begin
      PopAll(T.Line);
      S.Part := upInterface;
      if IsFirst then
        LI := 0;
    end;
  end
  else if W = 'implementation' then
  begin
    PopAll(T.Line);
    S.Part := upImplementation;
    if IsFirst then
      LI := 0;
  end
  else if (W = 'initialization') or (W = 'finalization') then
  begin
    PopAll(T.Line);
    if IsFirst then
      LI := 0;
    Push(frInit, W, 0, U, T.Line);
  end
  else if (W = 'unit') or (W = 'program') or (W = 'library') then
  begin
    if IsFirst then
      LI := 0;
    if W = 'unit' then
      S.Part := upNone
    else
      S.Part := upProgram;
  end
  else if InList(W, ['private', 'protected', 'public', 'published', 'strict', 'automated']) and IsFirst and
          (TopIsBlock(['class', 'object', 'record', 'helper']) or
           (TopIs(frSection) and (Length(S.Frames) > 1) and (S.Frames[Top - 1].Kind = frBlock))) then
  begin
    PopSections;
    LI := S.Frames[Top].Open;
  end
  else if InList(W, ['var', 'const', 'type', 'label', 'uses', 'resourcestring', 'threadvar']) and
          IsSection(K) then
  begin
    PopSections;
    if IsFirst then
      LI := DefaultIndent;
    Open := Here;
    Push(frSection, W, Open, Open + U, T.Line);
  end
  else if ((W = 'property') or ((W = 'class') and InList(SigText(NextSig(K)), ['var',
          'procedure', 'function', 'property', 'operator', 'constructor', 'destructor',
          'threadvar']))) and TopIs(frSection) and InClassSections then
  begin
    { a class-level "const" or "type" section ends at the next member }
    PopSections;
    Plain;
  end
  else if InList(W, ['procedure', 'function', 'constructor', 'destructor', 'operator']) and
          IsHeader(K) then
  begin
    PopSections;
    if IsFirst then
      if TopIs(frRoutine) and not S.Frames[Top].Body then
        LI := S.Frames[Top].Open + U
      else
        LI := DefaultIndent;
    Open := Here;
    if (S.Part in [upProgram, upImplementation]) and
       not TopIsBlock(['class', 'object', 'record', 'interface', 'dispinterface', 'helper']) and
       not NoBody(K) then
      Push(frRoutine, W, Open, Open + U, T.Line);
  end
  else
    Plain;
  S.LastSig := K;
end;

function TFormatter.IsBranchDirective(K: Integer): Boolean;
var
  T: string;
begin
  T := UpperCase(Toks[K].Text);
  Result := (Pos('{$ELSE', T) = 1) or (Pos('{$ENDIF', T) = 1) or (Pos('{$IFEND', T) = 1) or
    (Pos('{$ELIF', T) = 1) or (Pos('(*$ELSE', T) = 1) or (Pos('(*$ENDIF', T) = 1);
end;

{ between declarations, not inside statements }
function TFormatter.InDeclarations: Boolean;
begin
  Result := (Length(S.Frames) = 0) or (S.Frames[Top].Kind in [frSection, frRoutine]) or
    TopIsBlock(['class', 'object', 'record', 'interface', 'dispinterface', 'helper']);
end;

function TFormatter.InClassSections: Boolean;
var
  I: Integer;
begin
  I := Top;
  while (I >= 0) and (S.Frames[I].Kind = frSection) do
    Dec(I);
  Result := (I >= 0) and (S.Frames[I].Kind = frBlock) and
    InList(S.Frames[I].Sub, ['class', 'object', 'record', 'helper', 'interface']);
end;

function TFormatter.CommentIndent(K, LI: Integer): Integer;
var
  N, Probe: Integer;
  Saved: TState;
  SavedOff: Boolean;
begin
  Result := LI;
  N := K + 1;
  while (N <= High(Toks)) and (Toks[N].Kind in [tkComment, tkDirective]) do
    Inc(N);
  if (N > High(Toks)) or (Toks[N].Kind <> tkWord) or not Toks[N].First or
     not InList(Toks[N].Lower, ['else', 'except', 'finally', 'begin', 'implementation',
       'interface', 'initialization', 'finalization', 'procedure', 'function',
       'constructor', 'destructor', 'operator', 'var', 'const', 'type', 'uses',
       'resourcestring', 'threadvar', 'private', 'protected', 'public', 'published',
       'strict']) then
    Exit;
  Saved := CopyState;
  SavedOff := FmtOff;
  Probe := LI;
  try
    Process(N, True, False, Probe);
    Result := Probe;
  except
    on EFormatError do
      Result := LI;
  end;
  S := Saved;
  FmtOff := SavedOff;
end;

function TFormatter.TokenText(const T: TToken): string;
begin
  if Opt.LowerKeywords and (T.Kind = tkWord) and IsReserved(T.Lower) then
    Result := T.Lower
  else
    Result := T.Text;
end;

function TFormatter.Spacing(K: Integer): string;
var
  A, B: TToken;
begin
  A := Toks[K - 1];
  B := Toks[K];
  if (A.Kind in [tkComment, tkDirective]) or (B.Kind in [tkComment, tkDirective]) then
    Exit(B.Space);
  Result := B.Space;
  if (B.Kind = tkSymbol) and ((B.Text = ',') or (B.Text = ';')) and
     not InList(A.Lower, [':', 'do', 'then', 'else', ';']) then   { "do ;" is an empty statement }
    Result := ''
  else if ((B.Text = ':=') or (A.Text = ':=') or
           ((A.Kind = tkSymbol) and ((A.Text = ',') or (A.Text = ';')))) and (Result = '') then
    Result := ' ';   { more spaces are kept: people line things up }
end;

{ A comment over several lines moves with its first line. }
function TFormatter.CommentText(const T: TToken; Delta: Integer): string;
var
  Parts: TStringArray;
  I, J, N: Integer;
  L: string;
begin
  if T.Line = T.EndLine then
    Exit(T.Text);
  Parts := StringReplace(T.Text, #13, '', [rfReplaceAll]).Split([#10]);
  Result := TrimRight(Parts[0]);
  for I := 1 to High(Parts) do
  begin
    L := TrimRight(Parts[I]);
    if (Delta > 0) and (L <> '') then
      L := StringOfChar(' ', Delta) + L
    else if Delta < 0 then
    begin
      N := 0;
      J := 1;
      while (J <= Length(L)) and (L[J] = ' ') and (N < -Delta) do
      begin
        Inc(N);
        Inc(J);
      end;
      Delete(L, 1, N);
    end;
    Result := Result + Eol + L;
  end;
end;

function TFormatter.Run(const Src: string; const Options: TFormatOptions): string;
var
  G0, G1, K, LI, Blank, PrevEnd, Delta, L, DirCount: Integer;
  Cont, DirCont, Verbatim, Started: Boolean;
  Line: string;
begin
  Opt := Options;
  U := Opt.IndentSize;
  if U < 1 then
    U := 2;
  if Pos(#13#10, Src) > 0 then
    Eol := #13#10
  else
    Eol := #10;
  Lines := StringReplace(Src, #13, '', [rfReplaceAll]).Split([#10]);
  Tokenize(Src, Opt.NestedComments, Toks);
  SetLength(LabelColon, Length(Toks));
  SetLength(CaseOf, Length(Toks));
  S := Default(TState);
  S.LastSig := -1;
  S.Part := upProgram;
  AnchorOld := 0;
  AnchorNew := 0;
  FmtOff := False;
  PrevEnd := -1;
  Started := False;

  G0 := 0;
  while G0 <= High(Toks) do
  begin
    G1 := G0;
    while (G1 < High(Toks)) and not Toks[G1 + 1].First do
      Inc(G1);

    Verbatim := FmtOff or (TopIsBlock(['asm']) and (Toks[G0].Lower <> 'end'));
    { "cdecl; external 'c';" on the line after a routine header }
    DirCont := (Toks[G0].Kind = tkWord) and (SigText(S.LastSig) = ';') and InDeclarations and
      (InList(Toks[G0].Lower, RoutineDirectives) or (Toks[G0].Lower = 'external') or
       (Toks[G0].Lower = 'forward')) and (Toks[G0].Lower <> 'public') and
      (SigText(NextSig(G0)) <> ':=') and (SigText(NextSig(G0)) <> ':');
    Cont := not NeverContinuation(G0) and
      ((S.Depth > 0) or LastIsContinuation or StartsContinuation(G0) or DirCont);

    LI := 0;
    DirCount := Length(Dirs);
    Process(G0, True, Cont, LI);
    if DirCont and (LI < AnchorNew + U) then
      LI := AnchorNew + U;
    // a comment or a directive above "else", "procedure", "var", ... lines up with it
    if (Toks[G0].Kind = tkComment) and not Cont then
      LI := CommentIndent(G0, LI)
    else if (Toks[G0].Kind = tkDirective) and not Cont and
            ((Length(Dirs) > DirCount) or ((Length(Dirs) = DirCount) and not IsBranchDirective(G0))) then
    begin
      LI := CommentIndent(G0, LI);
      if Length(Dirs) > DirCount then
        Dirs[High(Dirs)].Indent := LI;
    end;
    if LI < 0 then
      LI := 0;
    CurLI := LI;
    if not Cont and not (Toks[G0].Kind in [tkComment, tkDirective]) then
    begin
      AnchorNew := LI;
      AnchorOld := OrigIndent(Toks[G0].Line);
    end;
    for K := G0 + 1 to G1 do
      Process(K, False, False, LI);

    { blank lines between groups: at most one }
    if Started then
    begin
      Blank := Toks[G0].Line - PrevEnd - 1;
      if Blank > 0 then
        Output.Add(Eol);
    end;

    if Verbatim then
    begin
      for L := Toks[G0].Line to Toks[G1].EndLine do
      begin
        if L > Toks[G0].Line then
          Output.Add(Eol);
        Output.Add(TrimRight(Lines[L]));
      end;
    end
    else
    begin
      Delta := LI - OrigIndent(Toks[G0].Line);
      Line := StringOfChar(' ', LI);
      for K := G0 to G1 do
      begin
        if K > G0 then
          Line := Line + Spacing(K);
        if Toks[K].Kind = tkComment then
          Line := Line + CommentText(Toks[K], Delta)
        else
          Line := Line + TokenText(Toks[K]);
      end;
      Output.Add(TrimRight(Line));
    end;
    Output.Add(Eol);
    PrevEnd := Toks[G1].EndLine;
    Started := True;
    G0 := G1 + 1;
  end;

  for K := High(S.Frames) downto 0 do
    if (S.Frames[K].Kind in [frBlock, frCase]) or
       ((S.Frames[K].Kind = frRoutine) and S.Frames[K].Body) then
      raise EFormatError.CreateFmt('line %d: "%s" has no matching "end"',
        [S.Frames[K].Line + 1, S.Frames[K].Sub]);

  Result := Output.Text;
end;

{ The same tokens in the same order, apart from spacing, keyword case and
  the indentation inside comments. }
function SameCode(const A, B: TTokens): Boolean;
var
  I: Integer;

  function Squeeze(const S: string): string;
  var
    C: Char;
  begin
    Result := '';
    for C in S do
      if not (C in [' ', #9, #10, #13]) then
        Result := Result + C;
  end;

begin
  if Length(A) <> Length(B) then
    Exit(False);
  for I := 0 to High(A) do
  begin
    if A[I].Kind <> B[I].Kind then
      Exit(False);
    case A[I].Kind of
      tkWord:
        if A[I].Lower <> B[I].Lower then
          Exit(False);
      tkComment:
        if Squeeze(A[I].Text) <> Squeeze(B[I].Text) then
          Exit(False);
    else
      if A[I].Text <> B[I].Text then
        Exit(False);
    end;
  end;
  Result := True;
end;

function FormatPascal(const Source: string; const Options: TFormatOptions;
  out Output, Error: string): Boolean;
var
  F: TFormatter;
  Before, After: TTokens;
begin
  Output := Source;
  Error := '';
  F := TFormatter.Create;
  try
    try
      Output := F.Run(Source, Options);
      if Trim(Output) = '' then
        Output := '';
      Tokenize(Source, Options.NestedComments, Before);
      Tokenize(Output, Options.NestedComments, After);
      if not SameCode(Before, After) then
        raise EFormatError.Create('internal error: formatting would change the code; the file was left as it is');
      Result := True;
    except
      on E: EFormatError do
      begin
        Output := Source;
        Error := E.Message;
        Result := False;
      end;
    end;
  finally
    F.Free;
  end;
end;

end.
