{ Pastel - syntax highlighting for TMemo (and TEdit): SQL, Pascal, JSON.

    SqlMemo.OnHighlight := @Syntax.Sql;
    SqlMemo.Completions.AddStrings(SqlKeywords);

  The spans are worked out by a small scanner (keywords, strings, numbers,
  comments); HighlightCode does it for another language's words.
  Part of the Pastel project, MIT License. }
unit Pastel.Syntax;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Pastel.UI;

type
  { How a language is written, for HighlightCode. }
  TCodeLanguage = record
    Keywords: TStringList;          { case-insensitive when CaseSensitive is False }
    CaseSensitive: Boolean;
    LineComment, LineComment2: string;   { '--', '//' }
    BlockOpen, BlockClose: string;       { '/*' '*/' }
    BlockOpen2, BlockClose2: string;     // Pascal's braces and (* *)
    Quotes: string;                      { the characters strings begin with: '''"' }
    NameQuotes: string;                  { names in quotes: SQL's "name" and `name` }
    Doubled: Boolean;                    { a quote doubled is one in the string ('it''s') }
    Backslash: Boolean;                  { \" escapes }
  end;

  { The highlighters as events: Memo.OnHighlight := @Syntax.Sql. }
  TSyntax = class
  public
    procedure Sql(Sender: TObject; const AText: string; var Spans: TSyntaxSpans);
    procedure Pascal(Sender: TObject; const AText: string; var Spans: TSyntaxSpans);
    procedure Json(Sender: TObject; const AText: string; var Spans: TSyntaxSpans);
  end;

function HighlightCode(const Lang: TCodeLanguage; const S: string): TSyntaxSpans;
function HighlightSql(const S: string): TSyntaxSpans;
function HighlightPascal(const S: string): TSyntaxSpans;
function HighlightJson(const S: string): TSyntaxSpans;

{ SQL's words (upper case), for Completions. }
function SqlKeywords: TStringArray;

var
  Syntax: TSyntax;

implementation

const
  SqlWords: array[0..105] of string = (
    'ADD', 'ALL', 'ALTER', 'AND', 'ANY', 'AS', 'ASC', 'AUTOINCREMENT', 'AUTO_INCREMENT',
    'BEGIN', 'BETWEEN', 'BIGINT', 'BLOB', 'BOOLEAN', 'BY', 'CASCADE', 'CASE', 'CAST',
    'CHECK', 'COLUMN', 'COMMIT', 'CONSTRAINT', 'COUNT', 'CREATE', 'CROSS', 'DATABASE',
    'DATE', 'DEFAULT', 'DELETE', 'DESC', 'DISTINCT', 'DROP', 'ELSE', 'END', 'EXCEPT',
    'EXISTS', 'EXPLAIN', 'FALSE', 'FOREIGN', 'FROM', 'FULL', 'GROUP', 'HAVING', 'IF',
    'IN', 'INDEX', 'INNER', 'INSERT', 'INTEGER', 'INTERSECT', 'INTO', 'IS', 'JOIN',
    'KEY', 'LEFT', 'LIKE', 'LIMIT', 'NOT', 'NULL', 'NUMERIC', 'OFFSET', 'ON', 'OR',
    'ORDER', 'OUTER', 'OVER', 'PARTITION', 'PRAGMA', 'PRIMARY', 'REAL', 'REFERENCES',
    'RENAME', 'REPLACE', 'RETURNING', 'RIGHT', 'ROLLBACK', 'SELECT', 'SERIAL', 'SET',
    'SHOW', 'TABLE', 'TEXT', 'THEN', 'TIMESTAMP', 'TO', 'TRANSACTION', 'TRIGGER', 'TRUE',
    'TRUNCATE', 'UNION', 'UNIQUE', 'UPDATE', 'USING', 'VALUES', 'VARCHAR', 'VIEW',
    'WHEN', 'WHERE', 'WITH', 'AVG', 'SUM', 'MIN', 'MAX', 'COALESCE', 'IFNULL', 'VACUUM');

  PascalWords: array[0..79] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'div', 'do', 'downto', 'else', 'end', 'except', 'exit', 'false',
    'file', 'finalization', 'finally', 'for', 'function', 'generic', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline', 'interface', 'is',
    'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'on', 'or', 'out',
    'override', 'packed', 'private', 'procedure', 'program', 'property', 'protected',
    'public', 'published', 'raise', 'record', 'repeat', 'set', 'shl', 'shr',
    'specialize', 'string', 'then', 'threadvar', 'to', 'true', 'try', 'type', 'unit',
    'until', 'uses', 'var', 'virtual', 'while', 'with', 'xor', 'abstract', 'overload',
    'reintroduce', 'strict', 'helper', 'self');

  JsonWords: array[0..2] of string = ('true', 'false', 'null');

var
  SqlLang, PascalLang, JsonLang: TCodeLanguage;

function MakeLanguage(const Words: array of string; ACase: Boolean): TCodeLanguage;
var
  W: string;
begin
  Result := Default(TCodeLanguage);
  Result.Keywords := TStringList.Create;
  Result.Keywords.CaseSensitive := ACase;
  Result.Keywords.Sorted := True;
  Result.Keywords.Duplicates := dupIgnore;
  for W in Words do
    Result.Keywords.Add(W);
  Result.CaseSensitive := ACase;
end;

function HighlightCode(const Lang: TCodeLanguage; const S: string): TSyntaxSpans;
var
  N, Count, I, J: Integer;
  Q: Char;
  W: string;

  procedure Add(Start, Len: Integer; Kind: TSyntaxKind);
  begin
    if Len <= 0 then
      Exit;
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 16);
    Result[Count].Start := Start;
    Result[Count].Len := Len;
    Result[Count].Kind := Kind;
    Inc(Count);
  end;

  function At(const T: string): Boolean;
  begin
    Result := (T <> '') and (Copy(S, I, Length(T)) = T);
  end;

  { a block comment from I: to its close (or the text's end) }
  procedure Block(const Close: string; OpenLen: Integer);
  begin
    J := Pos(Close, S, I + OpenLen);
    if J = 0 then J := N + 1 else J := J + Length(Close);
    Add(I, J - I, skComment);
    I := J;
  end;

  { a string or a quoted name from I to its closing quote }
  procedure Quoted(Kind: TSyntaxKind);
  begin
    Q := S[I];
    J := I + 1;
    while J <= N do
    begin
      if Lang.Backslash and (S[J] = '\') then
        Inc(J, 2)
      else if S[J] = Q then
      begin
        if Lang.Doubled and (J < N) and (S[J + 1] = Q) then
          Inc(J, 2)
        else
          Break;
      end
      else
        Inc(J);
    end;
    { unclosed: to the text's end }
    J := Min(J + 1, N + 1);
    Add(I, J - I, Kind);
    I := J;
  end;

begin
  Result := nil;
  Count := 0;
  N := Length(S);
  I := 1;
  while I <= N do
  begin
    if At(Lang.LineComment) or At(Lang.LineComment2) then
    begin
      J := I;
      while (J <= N) and (S[J] <> #10) do
        Inc(J);
      Add(I, J - I, skComment);
      I := J;
    end
    else if At(Lang.BlockOpen) then
      Block(Lang.BlockClose, Length(Lang.BlockOpen))
    else if At(Lang.BlockOpen2) then
      Block(Lang.BlockClose2, Length(Lang.BlockOpen2))
    else if Pos(S[I], Lang.Quotes) > 0 then
      Quoted(skString)
    else if Pos(S[I], Lang.NameQuotes) > 0 then
      Quoted(skName)
    else if (S[I] in ['0'..'9']) or ((S[I] = '$') and (I < N) and (S[I + 1] in ['0'..'9', 'A'..'F', 'a'..'f']) and
            (Lang.BlockOpen2 = '{')) then
    begin
      J := I + 1;
      while (J <= N) and (S[J] in ['0'..'9', '.', 'A'..'F', 'a'..'f', 'x', 'X', '_']) do
        Inc(J);
      Add(I, J - I, skNumber);
      I := J;
    end
    else if S[I] in ['A'..'Z', 'a'..'z', '_', #128..#255] then
    begin
      J := I + 1;
      while (J <= N) and (S[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', #128..#255]) do
        Inc(J);
      W := Copy(S, I, J - I);
      { after a dot it is a name (o.to, Self.end): no keyword }
      if ((I = 1) or (S[I - 1] <> '.')) and (Lang.Keywords.IndexOf(W) >= 0) then
        Add(I, J - I, skKeyword);
      I := J;
    end
    else if S[I] in ['(', ')', ',', ';', '=', '<', '>', '+', '-', '*', '/', '%', '|', ':', '[', ']', '.', '^', '@'] then
    begin
      Add(I, 1, skSymbol);
      Inc(I);
    end
    else
      Inc(I);
  end;
  SetLength(Result, Count);
end;

function HighlightSql(const S: string): TSyntaxSpans;
begin
  Result := HighlightCode(SqlLang, S);
end;

function HighlightPascal(const S: string): TSyntaxSpans;
begin
  Result := HighlightCode(PascalLang, S);
end;

function HighlightJson(const S: string): TSyntaxSpans;
var
  I, J: Integer;
begin
  Result := HighlightCode(JsonLang, S);
  { a string followed by ':' is a key: a name }
  for I := 0 to High(Result) do
    if Result[I].Kind = skString then
    begin
      J := Result[I].Start + Result[I].Len;
      while (J <= Length(S)) and (S[J] in [' ', #9, #10, #13]) do
        Inc(J);
      if (J <= Length(S)) and (S[J] = ':') then
        Result[I].Kind := skName;
    end;
end;

function SqlKeywords: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(SqlWords));
  for I := 0 to High(SqlWords) do
    Result[I] := SqlWords[I];
end;

procedure TSyntax.Sql(Sender: TObject; const AText: string; var Spans: TSyntaxSpans);
begin
  Spans := HighlightSql(AText);
end;

procedure TSyntax.Pascal(Sender: TObject; const AText: string; var Spans: TSyntaxSpans);
begin
  Spans := HighlightPascal(AText);
end;

procedure TSyntax.Json(Sender: TObject; const AText: string; var Spans: TSyntaxSpans);
begin
  Spans := HighlightJson(AText);
end;

initialization
  SqlLang := MakeLanguage(SqlWords, False);
  SqlLang.LineComment := '--';
  SqlLang.BlockOpen := '/*';
  SqlLang.BlockClose := '*/';
  SqlLang.Quotes := '''';
  SqlLang.NameQuotes := '"`';
  SqlLang.Doubled := True;

  PascalLang := MakeLanguage(PascalWords, False);
  PascalLang.LineComment := '//';
  PascalLang.BlockOpen := '(*';
  PascalLang.BlockClose := '*)';
  PascalLang.BlockOpen2 := '{';
  PascalLang.BlockClose2 := '}';
  PascalLang.Quotes := '''';
  PascalLang.Doubled := True;

  JsonLang := MakeLanguage(JsonWords, True);
  JsonLang.Quotes := '"';
  JsonLang.Backslash := True;

  Syntax := TSyntax.Create;

finalization
  Syntax.Free;
  SqlLang.Keywords.Free;
  PascalLang.Keywords.Free;
  JsonLang.Keywords.Free;
end.
