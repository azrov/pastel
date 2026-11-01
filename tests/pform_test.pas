{ Unit tests for the .pform reader and the code generator. Run with: sh tests/run.sh }
program pform_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Pastel.PForm, Pastel.Codegen;

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const Name: string);
begin
  if Cond then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name);
  end;
end;

function ErrorOf(const Src: string): string;
var
  N: TPFormNode;
begin
  Result := '';
  try
    N := ParsePForm(Src);
    N.Free;
  except
    on E: EPFormError do
      Result := E.Message;
  end;
end;

procedure TestParse;
var
  Root, Row: TPFormNode;
begin
  Root := ParsePForm(
    '// comment' + LineEnding +
    'object HomeForm: THomeForm' + LineEnding +
    '  Title = ''It''''s Pastel''  { block comment }' + LineEnding +
    '  Width = 400' + LineEnding +
    '  object Buttons: TRow' + LineEnding +
    '    Gap = -2' + LineEnding +
    '    object Ok: TButton' + LineEnding +
    '      OnClick = OkClick' + LineEnding +
    '      Enabled = False' + LineEnding +
    '    end' + LineEnding +
    '  end' + LineEnding +
    'end');
  try
    Check(Root.Name = 'HomeForm', 'root name');
    Check(Root.ClassName_ = 'THomeForm', 'root type');
    Check(Root.FindProp('Title').Value = 'It''s Pastel', 'string with quote');
    Check(Root.FindProp('Title').Kind = pvString, 'string kind');
    Check(Root.FindProp('Width').Kind = pvNumber, 'number kind');
    Check(Root.Children.Count = 1, 'one child');
    Row := Root.Child(0);
    Check(Row.FindProp('Gap').Value = '-2', 'negative number');
    Check(Row.Child(0).FindProp('OnClick').Kind = pvIdent, 'identifier value');
    Check(Row.Child(0).Line = 7, 'line numbers');
  finally
    Root.Free;
  end;
end;

procedure TestSets;
var
  Root: TPFormNode;
begin
  Root := ParsePForm('object A: TForm' + LineEnding + '  Anchors = [Left, Top, Right]' + LineEnding +
    '  Empty = []' + LineEnding + 'end');
  try
    Check(Root.FindProp('Anchors').Kind = pvSet, 'set kind');
    Check(Root.FindProp('Anchors').Value = 'Left'#10'Top'#10'Right', 'set names');
    Check(Root.FindProp('Empty').Value = '', 'empty set');
  finally
    Root.Free;
  end;
end;

procedure TestErrors;
begin
  Check(Pos('line 1', ErrorOf('object A TForm' + LineEnding + 'end')) > 0, 'missing colon');
  Check(Pos('has no "end"', ErrorOf('object A: TForm' + LineEnding + '  X = 1')) > 0, 'missing end');
  Check(Pos('line 2: strings use single quotes', ErrorOf('object A: TForm' + LineEnding +
    '  Title = "x"' + LineEnding + 'end')) > 0, 'double quotes');
  Check(Pos('set twice', ErrorOf('object A: TForm' + LineEnding + 'X = 1' + LineEnding +
    'X = 2' + LineEnding + 'end')) > 0, 'duplicate property');
  Check(Pos('unterminated string', ErrorOf('object A: TForm' + LineEnding + 'T = ''abc' +
    LineEnding + 'end')) > 0, 'unterminated string');
  Check(Pos('must start with', ErrorOf('form A: TForm end')) > 0, 'must start with object');
  Check(Pos('after the last "end"', ErrorOf('object A: TForm end end')) > 0, 'text after end');
  Check(Pos('a set holds names', ErrorOf('object A: TForm' + LineEnding + '  Anchors = [Left, 2]' + LineEnding +
    'end')) > 0, 'a number in a set');
  Check(Pos('expected "," or "]"', ErrorOf('object A: TForm' + LineEnding + '  Anchors = [Left Top]' + LineEnding +
    'end')) > 0, 'a set without commas');
end;

procedure TestCodegen;
var
  Code: string;
  Raised: Boolean;
begin
  Code := FormUnitSource('Home',
    'object HomeForm: THomeForm' + LineEnding +
    '  Title = ''Don''''t''' + LineEnding +
    '  object NameEdit: TEdit' + LineEnding +
    '  end' + LineEnding +
    'end', '/tmp/Home.pform');
  Check(Pos('unit Home.g;', Code) > 0, 'unit name');
  Check(Pos('THomeFormBase = class(TForm)', Code) > 0, 'base class');
  Check(Pos('NameEdit: TEdit;', Code) > 0, 'field');
  Check(Pos('NameEdit := TEdit(BindControl(''NameEdit'', TEdit));', Code) > 0, 'binding');
  Check(Pos('RegisterFormSource(''THomeForm''', Code) > 0, 'registration');
  Check(Pos('''  Title = ''''Don''''''''t'''''' + #10', Code) > 0, 'source is escaped');
  Check(Pos('''/tmp/Home.pform'');', Code) > 0, 'file path');

  Raised := False;
  try
    FormUnitSource('X', 'object X: TX' + LineEnding + 'object B: TBogus end' + LineEnding + 'end', '');
  except
    on E: EPFormError do
      Raised := (E.Line = 2) and (Pos('unknown component type "TBogus"', E.Message) > 0);
  end;
  Check(Raised, 'unknown component reported with line');
end;

begin
  Passed := 0;
  Failed := 0;
  TestParse;
  TestSets;
  TestErrors;
  TestCodegen;
  WriteLn(Format('pform: %d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
