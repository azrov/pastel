unit Term_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.Term;

type
  TTermTests = class(TTestSuite)
  public
    procedure TearDown; override;
  published
    procedure ColorsCanBeTurnedOff;
    procedure ColorsWrapText;
    procedure StripStylesRemovesCodes;
    procedure DisplayWidthCountsCharacters;
    procedure DisplayWidthOfWideCharacters;
    procedure PaddingUsesDisplayWidth;
    procedure TableAlignsColumns;
    procedure TableWithColorsStaysAligned;
    procedure RgbNeedsAHexColor;
  end;

implementation

procedure TTermTests.TearDown;
begin
  SetColors(False);
end;

procedure TTermTests.ColorsCanBeTurnedOff;
begin
  SetColors(False);
  AssertEquals('hi', Red('hi'));
  AssertEquals('hi', Bold('hi'));
end;

procedure TTermTests.ColorsWrapText;
begin
  SetColors(True);
  AssertEquals(#27'[31mhi'#27'[0m', Red('hi'));
  AssertEquals(#27'[38;2;79;70;229mx'#27'[0m', Rgb('#4F46E5', 'x'));
end;

procedure TTermTests.StripStylesRemovesCodes;
begin
  SetColors(True);
  AssertEquals('ok done', StripStyles(Green('ok') + ' ' + Bold(Dim('done'))));
end;

procedure TTermTests.DisplayWidthCountsCharacters;
begin
  AssertEquals(6, DisplayWidth('çğüşıö'));
  SetColors(True);
  AssertEquals(3, DisplayWidth(Red('abc')));
end;

procedure TTermTests.DisplayWidthOfWideCharacters;
begin
  AssertEquals(4, DisplayWidth('漢字'));
  AssertEquals(1, DisplayWidth('é'), 'e + combining accent');
end;

procedure TTermTests.PaddingUsesDisplayWidth;
begin
  AssertEquals('ış   ', PadRight('ış', 5));
  AssertEquals('   ış', PadLeft('ış', 5));
  AssertEquals('toolong', PadRight('toolong', 3));
end;

procedure TTermTests.TableAlignsColumns;
var
  T: TTable;
begin
  SetColors(False);
  T := TTable.Create(['Name', 'Size']);
  try
    T.SetAlign(1, alRight);
    T.AddRow(['rapor.pdf', '1.2 MB']);
    T.AddRow(['çok-uzun-dosya.txt', '12 KB']);
    AssertEquals(
      'Name                  Size' + LineEnding +
      '------------------  ------' + LineEnding +
      'rapor.pdf           1.2 MB' + LineEnding +
      'çok-uzun-dosya.txt   12 KB' + LineEnding, T.ToText);
    AssertEquals(2, T.RowCount);
  finally
    T.Free;
  end;
end;

procedure TTermTests.TableWithColorsStaysAligned;
var
  T: TTable;
  Lines: TStringArray;
begin
  SetColors(True);
  T := TTable.Create(['A', 'B']);
  try
    T.AddRow([Green('ok'), 'x']);
    T.AddRow(['longer', 'y']);
    Lines := StripStyles(T.ToText).Split([LineEnding]);
    AssertEquals('ok      x', Lines[2]);
    AssertEquals('longer  y', Lines[3]);
  finally
    T.Free;
  end;
end;

procedure TTermTests.RgbNeedsAHexColor;
begin
  SetColors(True);
  AssertEquals('x', Rgb('red', 'x'));
end;

initialization
  RegisterTests(TTermTests);
end.
