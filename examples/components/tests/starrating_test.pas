{ Tests for src/controls/starrating.pas. Run them with: pastel test }
unit StarRating_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, StarRating;

type
  TStarRatingTests = class(TTestSuite)
  published
    procedure ValueStaysBetweenZeroAndMax;
    procedure FewerStarsLowerTheValue;
  end;

implementation

procedure TStarRatingTests.ValueStaysBetweenZeroAndMax;
var
  S: TStarRating;
begin
  S := TStarRating.Create(nil);
  try
    S.Value := 9;
    AssertEquals(5, S.Value);
    S.Value := -1;
    AssertEquals(0, S.Value);
  finally
    S.Free;
  end;
end;

procedure TStarRatingTests.FewerStarsLowerTheValue;
var
  S: TStarRating;
begin
  S := TStarRating.Create(nil);
  try
    S.Value := 4;
    S.Max := 3;
    AssertEquals(3, S.Value);
  finally
    S.Free;
  end;
end;

initialization
  RegisterTests(TStarRatingTests);

end.
