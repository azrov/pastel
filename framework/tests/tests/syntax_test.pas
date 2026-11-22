{ Tests of syntax highlighting and word completion in edits (Pastel.Syntax, Pastel.UI). }
unit syntax_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Syntax;

type
  TSyntaxTests = class(TTestSuite)
  private
    procedure Columns(Sender: TObject; const Word: string; Items: TStrings);
  published
    procedure SqlParts;
    procedure PascalAndJson;
    procedure MemoPaintsColors;
    procedure CompletesWords;
    procedure CompletesAfterADot;
  end;

implementation

function KindAt(const Spans: TSyntaxSpans; P: Integer): TSyntaxKind;
var
  I: Integer;
begin
  Result := skText;
  for I := 0 to High(Spans) do
    if (P >= Spans[I].Start) and (P < Spans[I].Start + Spans[I].Len) then
      Exit(Spans[I].Kind);
end;

procedure TSyntaxTests.SqlParts;
const
  S = 'select name, 42 from "my table" -- all'#10'where x = ''it''''s'' /* c */ and y';
var
  Sp: TSyntaxSpans;
begin
  Sp := HighlightSql(S);
  AssertTrue(KindAt(Sp, 1) = skKeyword, 'select');
  AssertTrue(KindAt(Sp, Pos('name', S)) = skText, 'a column: plain');
  AssertTrue(KindAt(Sp, Pos('42', S)) = skNumber, 'a number');
  AssertTrue(KindAt(Sp, Pos('"my', S) + 3) = skName, 'a quoted name');
  AssertTrue(KindAt(Sp, Pos('all', S)) = skComment, 'a line comment');
  AssertTrue(KindAt(Sp, Pos('where', S)) = skKeyword, 'the next line is not a comment');
  AssertTrue(KindAt(Sp, Pos('''''s', S) + 2) = skString, 'a doubled quote stays in the string');
  AssertTrue(KindAt(Sp, Pos(' c ', S)) = skComment, 'a block comment');
  AssertTrue(KindAt(Sp, Pos('and', S)) = skKeyword, 'after the block comment');
  AssertTrue(KindAt(Sp, Pos('=', S)) = skSymbol);
  Sp := HighlightSql('select o.to from t');
  AssertTrue(KindAt(Sp, 10) = skText, 'a column called "to": not a keyword');
  Sp := HighlightSql('SELECT ''open');
  AssertTrue(KindAt(Sp, 12) = skString, 'an unclosed string goes to the end');
  AssertTrue(Length(SqlKeywords) > 50);
end;

procedure TSyntaxTests.PascalAndJson;
var
  Sp: TSyntaxSpans;
  S: string;
begin
  S := 'begin { note } X := $FF; // done'#10'end;';
  Sp := HighlightPascal(S);
  AssertTrue(KindAt(Sp, 1) = skKeyword, 'begin');
  AssertTrue(KindAt(Sp, Pos('note', S)) = skComment);
  AssertTrue(KindAt(Sp, Pos('$FF', S)) = skNumber, 'a hex number');
  AssertTrue(KindAt(Sp, Pos('done', S)) = skComment);
  AssertTrue(KindAt(Sp, Pos('end;', S)) = skKeyword);
  S := '{"name": "a \"b\"", "n": 3, "ok": true}';
  Sp := HighlightJson(S);
  AssertTrue(KindAt(Sp, 2) = skName, 'a key');
  AssertTrue(KindAt(Sp, Pos('a \', S)) = skString, 'a value');
  AssertTrue(KindAt(Sp, Pos('", "n', S) + 3) = skName, 'the escaped quote did not end the string');
  AssertTrue(KindAt(Sp, Pos('3', S)) = skNumber);
  AssertTrue(KindAt(Sp, Pos('true', S)) = skKeyword);
end;

procedure TSyntaxTests.MemoPaintsColors;
var
  F: TForm;
  M: TMemo;
  C: TCanvas32;
  X, Y: Integer;
  Found: Boolean;
begin
  InitFonts;
  UseDarkTheme(False);
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    M := TMemo.Create(F);
    M.Parent := F;
    M.Width := 300;
    M.Height := 80;
    M.Text := 'SELECT';
    M.OnHighlight := @Syntax.Sql;
    F.Layout(400, 200);
    C.SetSize(400, 200);
    F.Render(C);
    { the keyword's color is on the screen }
    Found := False;
    for Y := M.Bounds.Y to M.Bounds.Y + M.Bounds.H - 1 do
      for X := M.Bounds.X to M.Bounds.X + 120 do
        if C.GetPixel(X, Y) and $FFFFFF = SyntaxColor(skKeyword) and $FFFFFF then
          Found := True;
    AssertTrue(Found, 'the keyword is drawn in its color');
    M.OnHighlight := nil;
    F.Render(C);
    Found := False;
    for Y := M.Bounds.Y to M.Bounds.Y + M.Bounds.H - 1 do
      for X := M.Bounds.X to M.Bounds.X + 120 do
        if C.GetPixel(X, Y) and $FFFFFF = SyntaxColor(skKeyword) and $FFFFFF then
          Found := True;
    AssertFalse(Found, 'without a highlighter: plain text');
  finally
    C.Free;
    F.Free;
  end;
end;

procedure TSyntaxTests.CompletesWords;
var
  F: TForm;
  M: TMemo;
  C: TCanvas32;
begin
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    M := TMemo.Create(F);
    M.Parent := F;
    M.Width := 300;
    M.Height := 100;
    M.Completions.Text := 'customers'#10'orders'#10'order_items';
    F.Layout(400, 300);
    C.SetSize(400, 300);
    F.Render(C);
    M.SetFocus;
    F.HandleTextInput('select * from or');
    AssertTrue(M.CompletionsShown, 'typing a word shows the list');
    F.Render(C);
    F.HandleKeyDown(KEY_DOWN, False, False);
    F.HandleKeyDown(KEY_ENTER, False, False);
    AssertEquals('select * from order_items', M.Text, 'the second word put in');
    AssertFalse(M.CompletionsShown);
    F.HandleTextInput(' ');
    AssertFalse(M.CompletionsShown, 'a space: no list');
    F.HandleTextInput('CU');
    AssertTrue(M.CompletionsShown, 'any case');
    F.HandleKeyDown(KEY_ESCAPE, False, False);
    AssertFalse(M.CompletionsShown, 'Escape closes it');
    AssertEquals('select * from order_items CU', M.Text, 'and keeps the text');
    F.HandleKeyDown(KEY_SPACE, False, True);
    AssertTrue(M.CompletionsShown, 'Ctrl+Space shows it');
    F.HandleKeyDown(KEY_TAB, False, False);
    AssertEquals('select * from order_items customers', M.Text, 'Tab puts it in');
    F.HandleTextInput(#10'xyz');
    AssertFalse(M.CompletionsShown, 'nothing begins so');
    { a click on a word }
    F.HandleKeyDown(KEY_BACKSPACE, False, False);
    F.HandleKeyDown(KEY_BACKSPACE, False, False);
    F.HandleKeyDown(KEY_BACKSPACE, False, False);
    F.HandleTextInput('o');
    AssertTrue(M.CompletionsShown);
    F.Render(C);
    F.HandleMouseDown(M.Bounds.X + 300 + 50, 0);   { outside: closes it }
    AssertFalse(M.CompletionsShown, 'a click outside closes it');
  finally
    C.Free;
    F.Free;
  end;
end;

procedure TSyntaxTests.Columns(Sender: TObject; const Word: string; Items: TStrings);
begin
  if SameText(Word, 'orders.') or SameText(Copy(Word, 1, 7), 'orders.') then
  begin
    Items.Clear;
    Items.Add('id');
    Items.Add('customer_id');
    Items.Add('total');
  end;
end;

procedure TSyntaxTests.CompletesAfterADot;
var
  F: TForm;
  M: TEdit;
  C: TCanvas32;
begin
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    M := TEdit.Create(F);
    M.Parent := F;
    M.Width := 300;
    M.Completions.Text := 'orders';
    M.OnCompletions := @Columns;
    F.Layout(400, 300);
    C.SetSize(400, 300);
    F.Render(C);
    M.SetFocus;
    F.HandleTextInput('orders.');
    AssertTrue(M.CompletionsShown, 'a dot shows the columns');
    F.HandleTextInput('to');
    F.HandleKeyDown(KEY_ENTER, False, False);
    AssertEquals('orders.total', M.Text, 'the part after the dot is completed');
  finally
    C.Free;
    F.Free;
  end;
end;

initialization
  RegisterTests(TSyntaxTests);

end.
