(* Pastel - HTML pages from templates, in the style of Laravel's Blade.

  A template is an .html file in views/ (views/home.html is 'home',
  views/shop/list.html is 'shop.list'):

    @extends('layout')

    @section('title', 'Products')

    @section('content')
      <h1>{{ title }}</h1>
      @if(user.admin)
        <a href="/new">New product</a>
      @endif
      <ul>
      @forelse(products as product)
        <li class="{{ loop.first ? 'first' : '' }}">{{ product.name }} — {{ product.price | number:2 }}</li>
      @empty
        <li>No products yet.</li>
      @endforelse
      </ul>
    @endsection

  And the code:

    Res.Html(View('products', JObject(['title', 'Products', 'user', User, 'products', List])));

  {{ x }} writes x with < > & " ' made safe for HTML; {!! x !!} writes it as it is.
  Values come from the data (a JSON object), names inside it with dots
  (user.name, items.0.title). See docs/pages.md for everything.

  Part of the Pastel project, MIT License. *)
unit Pastel.Pages;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  EPageError = class(Exception);

  // A filter: {{ name | upper }}, {{ price | number:2 }}. Value is what is
  // left of the bar, Arg what follows the colon ('' when there is none).
  TPageFilter = function(const Value, Arg: string): string;

  { The templates of one folder, read once and again when a file changes. }
  TPages = class
  private
    FFolder: string;
    FCache: TStringList;
    FOld: TFPList;            { replaced templates: a page being rendered on another thread may still use one }
    FLock: TRTLCriticalSection;
    function Compiled(const Name: string): TObject;
  public
    constructor Create(const AFolder: string);
    destructor Destroy; override;
    { The page Name ('home', 'shop.list') with the data (not freed). }
    function Render(const Name: string; Data: TJSONObject): string;
    { A template given as text (no @extends or @include of files needed). }
    function RenderText(const Template: string; Data: TJSONObject): string;
    property Folder: string read FFolder;
  end;

{ The page Name from the app's views/ folder (next to the program, or in the
  folder it runs in). The data is freed. }
function View(const Name: string; Data: TJSONObject = nil): string;
{ The folder View uses: set it when the views are somewhere else. }
procedure SetViewsFolder(const Folder: string);
{ A folder of the app (views, public): next to the program (on a server), in the
  folder it runs in (pastel run), or in the project when the program is in
  build/<platform>/<mode>/. }
function FindAppFolder(const Name: string): string;
{ A template as text, with the data (freed). }
function RenderPage(const Template: string; Data: TJSONObject = nil): string;
// Adds a filter for {{ value | name }} and {{ value | name:arg }}.
procedure RegisterPageFilter(const Name: string; Filter: TPageFilter);
{ < > & " ' as HTML entities. }
function HtmlEscape(const S: string): string;

implementation

uses
  Math, StrUtils, Pastel.Text, Pastel.Lang;

type
  TNodeKind = (nkText, nkEcho, nkRaw, nkIf, nkFor, nkYield, nkInclude, nkSection, nkJson);

  TNode = class;
  TNodeList = class(TFPList)
  public
    destructor Destroy; override;
    function Node(I: Integer): TNode;
  end;

  { one piece of a template }
  TNode = class
  public
    Kind: TNodeKind;
    Text: string;             { text; the expression; the section, yield or include name }
    Line: Integer;
    Branches: array of record Cond: string; Body: TNodeList; end;   { if, elseif..., else (Cond '') }
    Body, Empty: TNodeList;   { foreach: the loop and @empty }
    VarName, KeyName: string; { foreach: as [key =>] item }
    Default: string;          { yield: what shows when no section fills it }
    destructor Destroy; override;
  end;

  { a parsed template: its body, the layout it extends and its sections }
  TTemplate = class
  public
    Name, Extends: string;
    Body: TNodeList;
    Sections: TStringList;    { name -> TNodeList }
    Age: LongInt;
    Size: Int64;
    constructor Create;
    destructor Destroy; override;
  end;

  TValueKind = (vkNull, vkBool, vkNumber, vkString, vkJson);
  TValue = record
    Kind: TValueKind;
    B: Boolean;
    N: Double;
    S: string;
    J: TJSONData;     { not owned }
  end;

  { the data while rendering: the page's data and the loop variables }
  TScope = class
  public
    Root: TJSONObject;
    Names: TStringList;       { name -> TJSONData (not owned) }
    Owned: TFPList;           { loop objects made while rendering }
    SectionNames, SectionTexts: TStringList;   { the rendered sections, side by side }
    Pages: TPages;
    Depth: Integer;
    constructor Create(ARoot: TJSONObject; APages: TPages);
    destructor Destroy; override;
  end;

var
  Filters: TStringList = nil;
  DefaultPages: TPages = nil;
  ViewsFolder: string = '';

{ ---- helpers ---- }

function HtmlEscape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '&': Result := Result + '&amp;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&#39;';
    else
      Result := Result + S[I];
    end;
end;

function PointFormat: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

function NumberText(N: Double): string;
begin
  if (Frac(N) = 0) and (Abs(N) < 1e15) then
    Result := IntToStr(Trunc(N))
  else
    Result := FloatToStr(N, PointFormat);
end;

function MkNull: TValue;
begin
  Result := Default(TValue);
end;

function MkStr(const S: string): TValue;
begin
  Result := Default(TValue);
  Result.Kind := vkString;
  Result.S := S;
end;

function MkNum(N: Double): TValue;
begin
  Result := Default(TValue);
  Result.Kind := vkNumber;
  Result.N := N;
end;

function MkBool(B: Boolean): TValue;
begin
  Result := Default(TValue);
  Result.Kind := vkBool;
  Result.B := B;
end;

function FromJson(J: TJSONData): TValue;
begin
  Result := Default(TValue);
  if J = nil then
    Exit;
  case J.JSONType of
    jtNull, jtUnknown: Result := MkNull;
    jtBoolean: Result := MkBool(J.AsBoolean);
    jtNumber: Result := MkNum(J.AsFloat);
    jtString: Result := MkStr(J.AsString);
  else
    Result.Kind := vkJson;
    Result.J := J;
  end;
end;

function ValueText(const V: TValue): string;
begin
  case V.Kind of
    vkNull: Result := '';
    vkBool: Result := BoolToStr(V.B, 'true', 'false');
    vkNumber: Result := NumberText(V.N);
    vkString: Result := V.S;
  else
    Result := V.J.FormatJSON([foSingleLineArray, foSingleLineObject, foSkipWhiteSpace], 0);
  end;
end;

function Truthy(const V: TValue): Boolean;
begin
  case V.Kind of
    vkNull: Result := False;
    vkBool: Result := V.B;
    vkNumber: Result := V.N <> 0;
    vkString: Result := V.S <> '';
  else
    Result := V.J.Count > 0;
  end;
end;

function IsNumber(const V: TValue; out N: Double): Boolean;
begin
  Result := V.Kind = vkNumber;
  if Result then
    N := V.N
  else if V.Kind = vkString then
    Result := TryStrToFloat(V.S, N, PointFormat);
end;

{ ---- templates and scopes ---- }

destructor TNodeList.Destroy;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    TNode(Items[I]).Free;
  inherited Destroy;
end;

function TNodeList.Node(I: Integer): TNode;
begin
  Result := TNode(Items[I]);
end;

destructor TNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Branches) do
    Branches[I].Body.Free;
  Body.Free;
  Empty.Free;
  inherited Destroy;
end;

constructor TTemplate.Create;
begin
  inherited Create;
  Body := TNodeList.Create;
  Sections := TStringList.Create;
  Sections.OwnsObjects := True;
end;

destructor TTemplate.Destroy;
begin
  Body.Free;
  Sections.Free;
  inherited Destroy;
end;

constructor TScope.Create(ARoot: TJSONObject; APages: TPages);
begin
  inherited Create;
  Root := ARoot;
  Pages := APages;
  Names := TStringList.Create;
  Owned := TFPList.Create;
  SectionNames := TStringList.Create;
  SectionTexts := TStringList.Create;
end;

destructor TScope.Destroy;
var
  I: Integer;
begin
  for I := 0 to Owned.Count - 1 do
    TObject(Owned[I]).Free;
  Owned.Free;
  Names.Free;
  SectionNames.Free;
  SectionTexts.Free;
  inherited Destroy;
end;

{ ---- expressions ---- }

type
  TExprParser = class
  private
    S: string;
    P: Integer;
    Scope: TScope;
    procedure Fail(const Msg: string);
    procedure Space;
    function Peek(const Word: string): Boolean;
    function Take(const Word: string): Boolean;
    function IsWordAt(const Word: string): Boolean;
    function Lookup(const Path: string): TValue;
    function Primary: TValue;
    function Filtered: TValue;
    function Compare: TValue;
    function NotExpr: TValue;
    function AndExpr: TValue;
    function OrExpr: TValue;
    function Ternary: TValue;
  public
    function Eval(const AText: string; AScope: TScope): TValue;
  end;

procedure TExprParser.Fail(const Msg: string);
begin
  raise EPageError.CreateFmt('%s in "%s"', [Msg, S]);
end;

procedure TExprParser.Space;
begin
  while (P <= Length(S)) and (S[P] in [' ', #9, #10, #13]) do
    Inc(P);
end;

function TExprParser.Peek(const Word: string): Boolean;
begin
  Space;
  Result := Copy(S, P, Length(Word)) = Word;
end;

{ a word (and, or, not) only when it is not the start of a longer name }
function TExprParser.IsWordAt(const Word: string): Boolean;
begin
  Space;
  Result := SameText(Copy(S, P, Length(Word)), Word) and
    ((P + Length(Word) > Length(S)) or not (S[P + Length(Word)] in ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

function TExprParser.Take(const Word: string): Boolean;
begin
  if Word[1] in ['a'..'z'] then
    Result := IsWordAt(Word)
  else
    Result := Peek(Word);
  if Result then
    Inc(P, Length(Word));
end;

function TExprParser.Lookup(const Path: string): TValue;
var
  Parts: TStringArray;
  Cur: TJSONData;
  I, K, Idx: Integer;
  Part: string;
begin
  Parts := Path.Split(['.']);
  Cur := nil;
  { the innermost loop's names first }
  K := Scope.Names.Count - 1;
  while (K >= 0) and (Scope.Names[K] <> Parts[0]) do
    Dec(K);
  if K >= 0 then
    Cur := TJSONData(Scope.Names.Objects[K])
  else if Scope.Root <> nil then
    Cur := Scope.Root.Find(Parts[0]);
  for I := 1 to High(Parts) do
  begin
    Part := Parts[I];
    if Cur = nil then
      Exit(MkNull);
    { count and length of a list or a text }
    if ((Part = 'count') or (Part = 'length')) and (I = High(Parts)) then
    begin
      if Cur.JSONType = jtArray then
        Exit(MkNum(Cur.Count));
      if Cur.JSONType = jtString then
        Exit(MkNum(Length(UTF8Decode(Cur.AsString))));
    end;
    case Cur.JSONType of
      jtObject: Cur := TJSONObject(Cur).Find(Part);
      jtArray:
        if TryStrToInt(Part, Idx) and (Idx >= 0) and (Idx < Cur.Count) then
          Cur := TJSONArray(Cur).Items[Idx]
        else
          Cur := nil;
    else
      Cur := nil;
    end;
  end;
  Result := FromJson(Cur);
end;

function TExprParser.Primary: TValue;
var
  Start: Integer;
  Q: Char;
  T: string;
  N: Double;
begin
  Space;
  if P > Length(S) then
    Fail('a value is missing');
  if S[P] = '(' then
  begin
    Inc(P);
    Result := Ternary;
    if not Take(')') then
      Fail('")" is missing');
    Exit;
  end;
  if S[P] in ['''', '"'] then
  begin
    Q := S[P];
    Inc(P);
    T := '';
    while (P <= Length(S)) and (S[P] <> Q) do
    begin
      if (S[P] = '\') and (P < Length(S)) then
        Inc(P);
      T := T + S[P];
      Inc(P);
    end;
    if P > Length(S) then
      Fail('a quote is not closed');
    Inc(P);
    Exit(MkStr(T));
  end;
  if S[P] in ['0'..'9', '-'] then
  begin
    Start := P;
    Inc(P);
    while (P <= Length(S)) and (S[P] in ['0'..'9', '.']) do
      Inc(P);
    if not TryStrToFloat(Copy(S, Start, P - Start), N, PointFormat) then
      Fail('not a number');
    Exit(MkNum(N));
  end;
  if S[P] in ['A'..'Z', 'a'..'z', '_'] then
  begin
    Start := P;
    while (P <= Length(S)) and (S[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      Inc(P);
    T := Copy(S, Start, P - Start);
    if T = 'true' then Exit(MkBool(True));
    if T = 'false' then Exit(MkBool(False));
    if T = 'null' then Exit(MkNull);
    Exit(Lookup(T));
  end;
  Fail(Format('"%s" is not understood', [S[P]]));
end;

{ value | filter | filter:arg }
function TExprParser.Filtered: TValue;
var
  Start, K: Integer;
  Name, Arg: string;
  A: TValue;
  N: Double;
begin
  Result := Primary;
  while Peek('|') and not Peek('||') do
  begin
    Inc(P);
    Space;
    Start := P;
    while (P <= Length(S)) and (S[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      Inc(P);
    Name := LowerCase(Copy(S, Start, P - Start));
    Arg := '';
    if Peek(':') then
    begin
      Inc(P);
      A := Primary;
      Arg := ValueText(A);
    end;
    if Name = 'default' then
    begin
      if not Truthy(Result) then
        Result := MkStr(Arg);
    end
    else if (Name = 'length') or (Name = 'count') then
    begin
      if Result.Kind = vkJson then
        Result := MkNum(Result.J.Count)
      else
        Result := MkNum(Length(UTF8Decode(ValueText(Result))));
    end
    { the rules of the app's language (Turkish i -> İ), or of the one given: upper:'tr' }
    else if Name = 'upper' then
      Result := MkStr(Upper(ValueText(Result), IfThen(Arg <> '', Arg, Language)))
    else if Name = 'lower' then
      Result := MkStr(Lower(ValueText(Result), IfThen(Arg <> '', Arg, Language)))
    else if Name = 'trim' then
      Result := MkStr(Trim(ValueText(Result)))
    else if Name = 'number' then
    begin
      if IsNumber(Result, N) then
        Result := MkStr(FormatFloat('#,##0' + IfThen(StrToIntDef(Arg, 0) > 0, '.' + DupeString('0', StrToIntDef(Arg, 0)), ''),
          N, PointFormat));
    end
    else if Name = 'json' then
      Result := MkStr(IfThen(Result.Kind = vkJson, ValueText(Result),
        IfThen(Result.Kind = vkString, '"' + StringToJSONString(Result.S) + '"', IfThen(Result.Kind = vkNull, 'null', ValueText(Result)))))
    else
    begin
      K := Filters.IndexOf(Name);
      if K < 0 then
        Fail(Format('there is no filter "%s"', [Name]));
      Result := MkStr(TPageFilter(Pointer(Filters.Objects[K]))(ValueText(Result), Arg));
    end;
  end;
end;

function TExprParser.Compare: TValue;
var
  L, R: TValue;
  Op: string;
  A, B: Double;
  C: Integer;
begin
  L := Filtered;
  Space;
  if Peek('==') then Op := '=='
  else if Peek('!=') then Op := '!='
  else if Peek('<=') then Op := '<='
  else if Peek('>=') then Op := '>='
  else if Peek('<') then Op := '<'
  else if Peek('>') then Op := '>'
  else
    Exit(L);
  Inc(P, Length(Op));
  R := Filtered;
  if IsNumber(L, A) and IsNumber(R, B) then
    C := CompareValue(A, B)
  else if (L.Kind = vkNull) or (R.Kind = vkNull) then
    C := Ord(L.Kind <> R.Kind)
  else
    C := CompareStr(ValueText(L), ValueText(R));
  case Op of
    '==': Result := MkBool(C = 0);
    '!=': Result := MkBool(C <> 0);
    '<': Result := MkBool(C < 0);
    '<=': Result := MkBool(C <= 0);
    '>': Result := MkBool(C > 0);
  else
    Result := MkBool(C >= 0);
  end;
end;

function TExprParser.NotExpr: TValue;
begin
  if Take('not') or (Peek('!') and not Peek('!=')) then
  begin
    if Peek('!') then
      Inc(P);
    Exit(MkBool(not Truthy(NotExpr())));
  end;
  Result := Compare;
end;

function TExprParser.AndExpr: TValue;
var
  R: TValue;
begin
  Result := NotExpr;
  while Take('and') or Take('&&') do
  begin
    R := NotExpr;
    Result := MkBool(Truthy(Result) and Truthy(R));
  end;
end;

function TExprParser.OrExpr: TValue;
var
  R: TValue;
begin
  Result := AndExpr;
  while Take('or') or Take('||') do
  begin
    R := AndExpr;
    Result := MkBool(Truthy(Result) or Truthy(R));
  end;
end;

{ cond ? a : b }
function TExprParser.Ternary: TValue;
var
  A, B: TValue;
begin
  Result := OrExpr;
  if Peek('?') then
  begin
    Inc(P);
    A := Ternary();     { () : a call, not the result }
    if not Take(':') then
      Fail('":" is missing after "?"');
    B := Ternary();
    if Truthy(Result) then Result := A else Result := B;
  end;
end;

function TExprParser.Eval(const AText: string; AScope: TScope): TValue;
begin
  S := AText;
  P := 1;
  Scope := AScope;
  Result := Ternary;
  Space;
  if P <= Length(S) then
    Fail(Format('"%s" is not understood', [Copy(S, P, MaxInt)]));
end;

function Evaluate(const Expr: string; Scope: TScope): TValue;
var
  E: TExprParser;
begin
  E := TExprParser.Create;
  try
    Result := E.Eval(Expr, Scope);
  finally
    E.Free;
  end;
end;

{ ---- parsing a template ---- }

type
  TTemplateParser = class
  private
    Src, FileName: string;
    P, Line: Integer;
    T: TTemplate;
    procedure Fail(const Msg: string);
    function Starts(const S: string): Boolean;
    procedure Skip(N: Integer);
    function Args: string;
    function Directive(out Name: string): Boolean;
    function Quoted(const S: string): string;
    { the nodes up to one of the end directives; which one ended it }
    function Nodes(const Ends: array of string; out EndedBy: string): TNodeList;
  public
    function Parse(const ASrc, AName: string): TTemplate;
  end;

procedure TTemplateParser.Fail(const Msg: string);
begin
  raise EPageError.CreateFmt('%s(%d): %s', [FileName, Line, Msg]);
end;

function TTemplateParser.Starts(const S: string): Boolean;
begin
  Result := Copy(Src, P, Length(S)) = S;
end;

procedure TTemplateParser.Skip(N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do
  begin
    if (P <= Length(Src)) and (Src[P] = #10) then
      Inc(Line);
    Inc(P);
  end;
end;

{ (...) after a directive, with nested brackets and quotes; '' when there is none }
function TTemplateParser.Args: string;
var
  Depth, Start: Integer;
  Q: Char;
begin
  Result := '';
  if (P > Length(Src)) or (Src[P] <> '(') then
    Exit;
  Depth := 0;
  Start := P + 1;
  Q := #0;
  repeat
    if P > Length(Src) then
      Fail('")" is missing');
    if Q <> #0 then
    begin
      if Src[P] = Q then Q := #0;
    end
    else
      case Src[P] of
        '''', '"': Q := Src[P];
        '(': Inc(Depth);
        ')': Dec(Depth);
      end;
    Skip(1);
  until Depth = 0;
  Result := Trim(Copy(Src, Start, P - Start - 1));
end;

const
  Directives: array[0..20] of string = ('if', 'elseif', 'else', 'endif', 'unless', 'endunless', 'foreach',
    'endforeach', 'forelse', 'empty', 'endforelse', 'extends', 'section', 'endsection', 'yield', 'include',
    'isset', 'endisset', 'json', 'show', 'stop');

{ @name at P (a known directive); P moves past the name }
function TTemplateParser.Directive(out Name: string): Boolean;
var
  Q: Integer;
  D: string;
begin
  Result := False;
  if (P > Length(Src)) or (Src[P] <> '@') then
    Exit;
  Q := P + 1;
  while (Q <= Length(Src)) and (Src[Q] in ['a'..'z']) do
    Inc(Q);
  Name := Copy(Src, P + 1, Q - P - 1);
  { in an e-mail address (a@b.com) the @ follows a letter: not a directive }
  if (P > 1) and (Src[P - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '_']) then
    Exit;
  if (Q <= Length(Src)) and (Src[Q] in ['A'..'Z', '0'..'9', '_']) then
    Exit;
  for D in Directives do
    if D = Name then
    begin
      Skip(Q - P);
      Exit(True);
    end;
end;

function TTemplateParser.Quoted(const S: string): string;
begin
  Result := Trim(S);
  if (Length(Result) >= 2) and (Result[1] in ['''', '"']) and (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2)
  else
    Fail(Format('a name in quotes is needed: (''%s'')', [Result]));
end;

{ 'name', 'text' -> the two parts }
procedure SplitTwo(const S: string; out A, B: string);
var
  I: Integer;
  Q: Char;
begin
  Q := #0;
  for I := 1 to Length(S) do
  begin
    if Q <> #0 then
    begin
      if S[I] = Q then Q := #0;
    end
    else if S[I] in ['''', '"'] then
      Q := S[I]
    else if S[I] = ',' then
    begin
      A := Trim(Copy(S, 1, I - 1));
      B := Trim(Copy(S, I + 1, MaxInt));
      Exit;
    end;
  end;
  A := Trim(S);
  B := '';
end;

function TTemplateParser.Nodes(const Ends: array of string; out EndedBy: string): TNodeList;
var
  Buf, Name, A, B, E, Ended: string;
  N: TNode;
  Close: Integer;
  List: TNodeList;

  procedure Flush;
  var
    TextNode: TNode;
  begin
    if Buf = '' then
      Exit;
    TextNode := TNode.Create;
    TextNode.Kind := nkText;
    TextNode.Text := Buf;
    List.Add(TextNode);
    Buf := '';
  end;

  function NewNode(K: TNodeKind; const Text: string): TNode;
  begin
    Flush;
    Result := TNode.Create;
    Result.Kind := K;
    Result.Text := Text;
    Result.Line := Line;
    List.Add(Result);
  end;

  function IsEnd(const S: string): Boolean;
  var
    X: string;
  begin
    for X in Ends do
      if X = S then
        Exit(True);
    Result := False;
  end;

  { a directive on a line of its own takes its line break with it }
  procedure EatLineBreak;
  begin
    if Starts(#13#10) then
      Skip(2)
    else if Starts(#10) then
      Skip(1);
  end;

begin
  Result := TNodeList.Create;
  List := Result;
  Buf := '';
  EndedBy := '';
  try
    while P <= Length(Src) do
    begin
      if Starts('@{{') then
      begin
        // @{{ x }} is written as {{ x }} (for JavaScript frameworks)
        Skip(1);
        Buf := Buf + '{{';
        Skip(2);
        Continue;
      end;
      if Starts('{{--') then
      begin
        Close := PosEx('--}}', Src, P);
        if Close = 0 then
          Fail('"--}}" is missing after "{{--"');
        Skip(Close + 4 - P);
        Continue;
      end;
      if Starts('{!!') or Starts('{{') then
      begin
        if Starts('{!!') then
        begin
          Close := PosEx('!!}', Src, P);
          if Close = 0 then
            Fail('"!!}" is missing');
          N := NewNode(nkRaw, Trim(Copy(Src, P + 3, Close - P - 3)));
          Skip(Close + 3 - P);
        end
        else
        begin
          Close := PosEx('}}', Src, P);
          if Close = 0 then
            Fail('"}}" is missing');
          N := NewNode(nkEcho, Trim(Copy(Src, P + 2, Close - P - 2)));
          Skip(Close + 2 - P);
        end;
        if N.Text = '' then
          Fail('an empty {{ }}');
        Continue;
      end;
      if (Src[P] = '@') and Directive(Name) then
      begin
        if IsEnd(Name) then
        begin
          Flush;
          EndedBy := Name;
          Exit;
        end;
        case Name of
          'if', 'unless', 'isset':
            begin
              N := NewNode(nkIf, '');
              A := Args;
              if A = '' then
                Fail(Format('@%s needs a condition: @%s(...)', [Name, Name]));
              if Name = 'unless' then A := 'not (' + A + ')';
              if Name = 'isset' then A := '(' + A + ') != null';
              EatLineBreak;
              SetLength(N.Branches, 1);
              N.Branches[0].Cond := A;
              if Name = 'if' then
                N.Branches[0].Body := Nodes(['elseif', 'else', 'endif'], Ended)
              else
                N.Branches[0].Body := Nodes(['else', 'end' + Name], Ended);
              while (Ended = 'elseif') or (Ended = 'else') do
              begin
                SetLength(N.Branches, Length(N.Branches) + 1);
                if Ended = 'elseif' then
                begin
                  N.Branches[High(N.Branches)].Cond := Args;
                  EatLineBreak;
                  N.Branches[High(N.Branches)].Body := Nodes(['elseif', 'else', 'endif'], Ended);
                end
                else
                begin
                  N.Branches[High(N.Branches)].Cond := '';
                  EatLineBreak;
                  N.Branches[High(N.Branches)].Body := Nodes(['end' + IfThen(Name = 'if', 'if', Name)], Ended);
                  Break;
                end;
              end;
              if Ended = '' then
                Fail(Format('@%s is not closed with @end%s', [Name, Name]));
              EatLineBreak;
            end;
          'foreach', 'forelse':
            begin
              N := NewNode(nkFor, '');
              A := Args;
              Close := Pos(' as ', A);
              if Close = 0 then
                Fail(Format('@%s needs (items as item)', [Name]));
              N.Text := Trim(Copy(A, 1, Close - 1));
              B := Trim(Copy(A, Close + 4, MaxInt));
              Close := Pos('=>', B);
              if Close > 0 then
              begin
                N.KeyName := Trim(Copy(B, 1, Close - 1));
                B := Trim(Copy(B, Close + 2, MaxInt));
              end;
              N.VarName := B;
              EatLineBreak;
              if Name = 'foreach' then
                N.Body := Nodes(['endforeach'], Ended)
              else
              begin
                N.Body := Nodes(['empty', 'endforelse'], Ended);
                if Ended = 'empty' then
                begin
                  EatLineBreak;
                  N.Empty := Nodes(['endforelse'], Ended);
                end;
              end;
              if Ended = '' then
                Fail(Format('@%s is not closed with @end%s', [Name, Name]));
              EatLineBreak;
            end;
          'extends':
            begin
              T.Extends := Quoted(Args);
              EatLineBreak;
            end;
          'section':
            begin
              SplitTwo(Args, A, B);
              A := Quoted(A);
              Flush;
              if B <> '' then
              begin
                { @section('title', 'Products'): a short one }
                N := TNode.Create;
                N.Kind := nkEcho;
                N.Text := B;
                N.Line := Line;
                T.Sections.AddObject(A, TNodeList.Create);
                TNodeList(T.Sections.Objects[T.Sections.Count - 1]).Add(N);
                EatLineBreak;
              end
              else
              begin
                EatLineBreak;
                T.Sections.AddObject(A, Nodes(['endsection', 'show', 'stop'], Ended));
                if Ended = '' then
                  Fail(Format('@section(''%s'') is not closed with @endsection', [A]));
                EatLineBreak;
                { @show: the section is also written here (in a layout) }
                if Ended = 'show' then
                  NewNode(nkYield, A);
              end;
            end;
          'yield':
            begin
              SplitTwo(Args, A, B);
              N := NewNode(nkYield, Quoted(A));
              N.Default := B;
            end;
          'include':
            begin
              SplitTwo(Args, A, B);
              NewNode(nkInclude, Quoted(A));
            end;
          'json':
            NewNode(nkJson, Args);
        else
          Fail(Format('@%s is not expected here', [Name]));
        end;
        Continue;
      end;
      Buf := Buf + Src[P];
      Skip(1);
    end;
    Flush;
    if Length(Ends) > 0 then
    begin
      E := '';
      for A in Ends do
        if (E = '') and (Copy(A, 1, 3) = 'end') then
          E := A;
      Fail(Format('@%s is missing', [E]));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TTemplateParser.Parse(const ASrc, AName: string): TTemplate;
var
  Ended: string;
  Body: TNodeList;
begin
  Src := ASrc;
  FileName := AName;
  P := 1;
  Line := 1;
  T := TTemplate.Create;
  try
    T.Name := AName;
    Body := Nodes([], Ended);
    T.Body.Free;
    T.Body := Body;
  except
    T.Free;
    raise;
  end;
  Result := T;
end;

{ ---- rendering ---- }

procedure RenderNodes(L: TNodeList; Scope: TScope; Out_: TStringBuilder; const FileName: string); forward;

function TemplateFile(Pages: TPages; const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Pages.Folder) +
    StringReplace(Name, '.', PathDelim, [rfReplaceAll]) + '.html';
end;

procedure RenderTemplate(T: TTemplate; Scope: TScope; Out_: TStringBuilder);
var
  I: Integer;
  Part: TStringBuilder;
  Layout: TTemplate;
begin
  Inc(Scope.Depth);
  try
    if Scope.Depth > 20 then
      raise EPageError.CreateFmt('%s: too many @extends or @include inside each other', [T.Name]);
    { the sections; a page's own ones win over the layout's (it renders first) }
    for I := 0 to T.Sections.Count - 1 do
      if Scope.SectionNames.IndexOf(T.Sections[I]) < 0 then
      begin
        Part := TStringBuilder.Create;
        try
          RenderNodes(TNodeList(T.Sections.Objects[I]), Scope, Part, T.Name);
          Scope.SectionNames.Add(T.Sections[I]);
          Scope.SectionTexts.Add(Part.ToString);
        finally
          Part.Free;
        end;
      end;
    if T.Extends <> '' then
    begin
      if Scope.Pages = nil then
        raise EPageError.CreateFmt('%s: @extends(''%s'') needs a views folder', [T.Name, T.Extends]);
      Layout := TTemplate(Scope.Pages.Compiled(T.Extends));
      RenderTemplate(Layout, Scope, Out_);
    end
    else
      RenderNodes(T.Body, Scope, Out_, T.Name);
  finally
    Dec(Scope.Depth);
  end;
end;

procedure RenderNodes(L: TNodeList; Scope: TScope; Out_: TStringBuilder; const FileName: string);
var
  I, J, K: Integer;
  N: TNode;
  V: TValue;
  Items: TJSONData;
  Loop: TJSONObject;
  SavedNames: Integer;
  Inc_: TTemplate;
begin
  for I := 0 to L.Count - 1 do
  begin
    N := L.Node(I);
    try
      case N.Kind of
        nkText: Out_.Append(N.Text);
        nkEcho: Out_.Append(HtmlEscape(ValueText(Evaluate(N.Text, Scope))));
        nkRaw: Out_.Append(ValueText(Evaluate(N.Text, Scope)));
        nkJson:
          begin
            V := Evaluate(N.Text, Scope);
            case V.Kind of
              vkNull: Out_.Append('null');
              vkString: Out_.Append('"' + StringToJSONString(V.S) + '"');
            else
              Out_.Append(ValueText(V));
            end;
          end;
        nkIf:
          for J := 0 to High(N.Branches) do
            if (N.Branches[J].Cond = '') or Truthy(Evaluate(N.Branches[J].Cond, Scope)) then
            begin
              RenderNodes(N.Branches[J].Body, Scope, Out_, FileName);
              Break;
            end;
        nkFor:
          begin
            V := Evaluate(N.Text, Scope);
            Items := nil;
            if V.Kind = vkJson then
              Items := V.J;
            if (Items = nil) or (Items.Count = 0) then
            begin
              if N.Empty <> nil then
                RenderNodes(N.Empty, Scope, Out_, FileName);
              Continue;
            end;
            SavedNames := Scope.Names.Count;
            try
              for K := 0 to Items.Count - 1 do
              begin
                while Scope.Names.Count > SavedNames do
                  Scope.Names.Delete(Scope.Names.Count - 1);
                { loop.index, loop.iteration, loop.first, loop.last, loop.count }
                Loop := TJSONObject.Create(['index', K, 'iteration', K + 1, 'first', K = 0,
                  'last', K = Items.Count - 1, 'count', Items.Count]);
                Scope.Owned.Add(Loop);
                Scope.Names.AddObject('loop', Loop);
                Scope.Names.AddObject(N.VarName, Items.Items[K]);
                if N.KeyName <> '' then
                begin
                  if Items.JSONType = jtObject then
                    Loop.Add('key', TJSONObject(Items).Names[K])
                  else
                    Loop.Add('key', K);
                  Scope.Names.AddObject(N.KeyName, Loop.Find('key'));
                end;
                RenderNodes(N.Body, Scope, Out_, FileName);
              end;
            finally
              while Scope.Names.Count > SavedNames do
                Scope.Names.Delete(Scope.Names.Count - 1);
            end;
          end;
        nkYield:
          begin
            K := Scope.SectionNames.IndexOf(N.Text);
            if K >= 0 then
              Out_.Append(Scope.SectionTexts[K])
            else if N.Default <> '' then
              Out_.Append(HtmlEscape(ValueText(Evaluate(N.Default, Scope))));
          end;
        nkInclude:
          begin
            if Scope.Pages = nil then
              raise EPageError.CreateFmt('@include(''%s'') needs a views folder', [N.Text]);
            Inc_ := TTemplate(Scope.Pages.Compiled(N.Text));
            Inc(Scope.Depth);
            try
              if Scope.Depth > 20 then
                raise EPageError.Create('too many @include inside each other');
              RenderNodes(Inc_.Body, Scope, Out_, Inc_.Name);
            finally
              Dec(Scope.Depth);
            end;
          end;
      end;
    except
      on E: EPageError do
      begin
        { the place, once }
        if (Pos('): ', E.Message) = 0) and (N.Line > 0) then
          E.Message := Format('%s(%d): %s', [FileName, N.Line, E.Message]);
        raise;
      end;
    end;
  end;
end;

{ ---- TPages ---- }

constructor TPages.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := AFolder;
  FCache := TStringList.Create;
  FCache.OwnsObjects := True;
  FCache.Sorted := True;
  FOld := TFPList.Create;
  InitCriticalSection(FLock);
end;

destructor TPages.Destroy;
var
  I: Integer;
begin
  FCache.Free;
  for I := 0 to FOld.Count - 1 do
    TObject(FOld[I]).Free;
  FOld.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

{ the parsed template; parsed again when its file changed }
function FileSizeOf(const F: string): Int64;
var
  SR: TSearchRec;
begin
  Result := -1;
  if FindFirst(F, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

function TPages.Compiled(const Name: string): TObject;
var
  F: string;
  I: Integer;
  Age: LongInt;
  Size: Int64;
  L: TStringList;
  P: TTemplateParser;
  T: TTemplate;
begin
  F := TemplateFile(Self, Name);
  if not FileExists(F) then
    raise EPageError.CreateFmt('there is no page "%s" (%s)', [Name, F]);
  { the web server renders pages on several threads at once }
  EnterCriticalSection(FLock);
  try
    Age := FileAge(F);
    Size := FileSizeOf(F);
    I := FCache.IndexOf(Name);
    if (I >= 0) and (TTemplate(FCache.Objects[I]).Age = Age) and (TTemplate(FCache.Objects[I]).Size = Size) then
      Exit(FCache.Objects[I]);
    L := TStringList.Create;
    P := TTemplateParser.Create;
    try
      L.LoadFromFile(F);
      T := P.Parse(L.Text, Name);
      T.Age := Age;
      T.Size := Size;
    finally
      P.Free;
      L.Free;
    end;
    if I >= 0 then
    begin
      FCache.OwnsObjects := False;
      FOld.Add(FCache.Objects[I]);
      FCache.Delete(I);
      FCache.OwnsObjects := True;
    end;
    FCache.AddObject(Name, T);
    Result := T;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TPages.Render(const Name: string; Data: TJSONObject): string;
var
  Scope: TScope;
  Out_: TStringBuilder;
begin
  Scope := TScope.Create(Data, Self);
  Out_ := TStringBuilder.Create;
  try
    RenderTemplate(TTemplate(Compiled(Name)), Scope, Out_);
    Result := Out_.ToString;
  finally
    Out_.Free;
    Scope.Free;
  end;
end;

function TPages.RenderText(const Template: string; Data: TJSONObject): string;
var
  Scope: TScope;
  Out_: TStringBuilder;
  P: TTemplateParser;
  T: TTemplate;
begin
  P := TTemplateParser.Create;
  try
    T := P.Parse(Template, 'template');
  finally
    P.Free;
  end;
  Scope := TScope.Create(Data, Self);
  Out_ := TStringBuilder.Create;
  try
    RenderTemplate(T, Scope, Out_);
    Result := Out_.ToString;
  finally
    Out_.Free;
    Scope.Free;
    T.Free;
  end;
end;

{ ---- the app's views ---- }

{ next to the program (a server), in the folder it runs in (pastel run), or in the
  project when the program is in build/<platform>/<mode>/ }
function FindAppFolder(const Name: string): string;
var
  D, F: string;
begin
  D := ExtractFilePath(ParamStr(0));
  for F in TStringArray.Create(D + Name, Name, D + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim + Name) do
    if DirectoryExists(F) then
      Exit(ExpandFileName(F));
  Result := ExpandFileName(Name);
end;

function FindViewsFolder: string;
begin
  if ViewsFolder <> '' then
    Exit(ViewsFolder);
  Result := FindAppFolder('views');
end;

procedure SetViewsFolder(const Folder: string);
begin
  ViewsFolder := Folder;
  FreeAndNil(DefaultPages);
end;

function View(const Name: string; Data: TJSONObject): string;
begin
  if DefaultPages = nil then
    DefaultPages := TPages.Create(FindViewsFolder);
  try
    Result := DefaultPages.Render(Name, Data);
  finally
    Data.Free;
  end;
end;

function RenderPage(const Template: string; Data: TJSONObject): string;
var
  Pages: TPages;
begin
  Pages := TPages.Create(FindViewsFolder);
  try
    Result := Pages.RenderText(Template, Data);
  finally
    Pages.Free;
    Data.Free;
  end;
end;

procedure RegisterPageFilter(const Name: string; Filter: TPageFilter);
var
  I: Integer;
begin
  I := Filters.IndexOf(LowerCase(Name));
  if I >= 0 then
    Filters.Objects[I] := TObject(Pointer(Filter))
  else
    Filters.AddObject(LowerCase(Name), TObject(Pointer(Filter)));
end;

initialization
  Filters := TStringList.Create;
  Filters.Sorted := True;

finalization
  Filters.Free;
  DefaultPages.Free;

end.
