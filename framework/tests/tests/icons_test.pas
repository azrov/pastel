{ Tests for Pastel.Icons. }
unit Icons_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.Icons;

type
  TIconsTests = class(TTestSuite)
  published
    procedure BuiltInIconsExist;
    procedure AnIconIsDrawn;
    procedure OwnIconsCanBeAdded;
  end;

implementation

procedure TIconsTests.BuiltInIconsExist;
begin
  AssertTrue(HasIcon('save'));
  AssertTrue(HasIcon('Delete'), 'names are not case sensitive');
  AssertFalse(HasIcon('no-such-icon'));
  AssertFalse(HasIcon(''));
  AssertTrue(Length(IconNames) >= 30);
end;

procedure TIconsTests.AnIconIsDrawn;
var
  C: TCanvas32;
  X, Y, Drawn: Integer;
begin
  C := TCanvas32.Create;
  try
    C.SetSize(24, 24);
    C.Clear(RGB(255, 255, 255));
    AssertTrue(DrawIcon(C, 'close', 0, 0, 24, RGB(0, 0, 0)));
    Drawn := 0;
    for Y := 0 to 23 do
      for X := 0 to 23 do
        if C.GetPixel(X, Y) <> RGB(255, 255, 255) then
          Inc(Drawn);
    AssertTrue(Drawn > 20, 'the two lines of the cross');
    AssertTrue(C.GetPixel(12, 12) <> RGB(255, 255, 255), 'they cross in the middle');
    AssertFalse(DrawIcon(C, 'nothing', 0, 0, 24, RGB(0, 0, 0)));
  finally
    C.Free;
  end;
end;

procedure TIconsTests.OwnIconsCanBeAdded;
begin
  RegisterIcon('bell', 'l 6 17 6 10; a 12 10 6 180 360; l 18 10 18 17; l 4 17 20 17; f 12 20 1.5');
  AssertTrue(HasIcon('bell'));
end;

initialization
  RegisterTests(TIconsTests);

end.
