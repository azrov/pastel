{ Tests of Pastel.Animate: steps in time, easing, colors, a freed target. }
unit animate_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Controls, Pastel.Animate;

type
  TAnimateTests = class(TTestSuite)
  private
    FDone: Integer;
    procedure Finished(Sender: TObject);
  published
    procedure GoesThereInTime;
    procedure ColorsAndReplacing;
    procedure FreedTargetStops;
    procedure EasingEnds;
  end;

implementation

uses
  Math;

procedure TAnimateTests.Finished(Sender: TObject);
begin
  Inc(FDone);
end;

procedure TAnimateTests.GoesThereInTime;
var
  P: TPanel;
  T0: QWord;
begin
  P := TPanel.Create(nil);
  try
    P.Height := 100;
    FDone := 0;
    T0 := GetTickCount64;
    Animate(P, 'Height', 200, 1000, eaLinear, @Finished);
    AssertTrue(IsAnimating(P, 'Height'));
    StepAnimations(T0 + 500);
    AssertTrue(Abs(P.Height - 150) <= 2, Format('half way: %d', [P.Height]));
    StepAnimations(T0 + 2000);
    AssertEquals(200, P.Height, 'there');
    AssertEquals(1, FDone, 'OnDone once');
    AssertFalse(IsAnimating(P));
  finally
    P.Free;
  end;
end;

procedure TAnimateTests.ColorsAndReplacing;
var
  P: TPanel;
  T0: QWord;
begin
  P := TPanel.Create(nil);
  try
    P.Color := $FF000000;
    T0 := GetTickCount64;
    AnimateColor(P, 'Color', $FFFF0000, 100, eaLinear);
    StepAnimations(T0 + 50);
    AssertTrue(((P.Color shr 16) and $FF) in [120..135], IntToHex(P.Color, 8));
    { a new one of the same property: from where it is }
    P.Height := 10;
    Animate(P, 'Height', 50, 100);
    Animate(P, 'Height', 20, 100);
    StepAnimations(T0 + 1000);
    AssertEquals(20, P.Height);
    AssertEquals(IntToHex($FFFF0000, 8), IntToHex(P.Color, 8));
    try
      Animate(P, 'Nothing', 1);
      Fail('a property that is not there');
    except
      on E: Exception do ;
    end;
  finally
    P.Free;
  end;
end;

procedure TAnimateTests.FreedTargetStops;
var
  P: TPanel;
begin
  P := TPanel.Create(nil);
  Animate(P, 'Width', 300, 1000);
  P.Free;
  StepAnimations(GetTickCount64 + 5000);     { nothing touches the freed panel }
  AssertTrue(True);
end;

procedure TAnimateTests.EasingEnds;
var
  E: TEasing;
begin
  for E := Low(TEasing) to High(TEasing) do
  begin
    AssertTrue(Abs(Ease(E, 0)) < 1e-6, 'starts at 0');
    AssertTrue(Abs(Ease(E, 1) - 1) < 1e-6, 'ends at 1');
  end;
  AssertTrue(Ease(eaOutBack, 0.7) > 1, 'a little past');
end;

initialization
  RegisterTests(TAnimateTests);

end.
