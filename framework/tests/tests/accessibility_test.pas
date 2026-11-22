{ Tests of Pastel.Accessibility: what a screen reader is told, and its click. }
unit accessibility_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Controls, Pastel.Accessibility;

type
  TAccessibilityTests = class(TTestSuite)
  private
    FClicks: Integer;
    procedure Clicked(Sender: TObject);
  published
    procedure TreeAndClick;
  end;

implementation

function Same(const R: TRectI): TRectI;
begin
  Result := R;
end;

procedure TAccessibilityTests.Clicked(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TAccessibilityTests.TreeAndClick;
var
  F: TForm;
  B: TButton;
  E: TEdit;
  K: TCheckBox;
  Hidden: TLabel;
  T: string;
  L: TStringList;
  Id: Integer;
begin
  InitFonts;
  F := TForm.Create(nil);
  L := TStringList.Create;
  try
    E := TEdit.Create(F);
    E.Parent := F;
    E.Placeholder := 'Your name';
    B := TButton.Create(F);
    B.Parent := F;
    B.Text := '';
    B.AccessibleName := 'Delete';
    B.OnClick := @Clicked;
    K := TCheckBox.Create(F);
    K.Parent := F;
    K.Text := 'Remember me';
    K.Checked := True;
    Hidden := TLabel.Create(F);
    Hidden.Parent := F;
    Hidden.Text := 'secret';
    Hidden.Visible := False;
    F.Layout(400, 300);
    T := AccessibilityTree(F, @Same);
    L.Text := T;
    AssertEquals(3, L.Count, T);
    AssertTrue(Pos(#9'EditText'#9#9'Your name'#9'et', L[0]) > 0, L[0]);
    AssertTrue(Pos(#9'Button'#9'Delete'#9, L[1]) > 0, L[1]);
    AssertTrue(Pos(#9'CheckBox'#9'Remember me'#9#9'eckl', L[2]) > 0, L[2]);
    AssertFalse(Pos('secret', T) > 0, 'not what is hidden');
    { a double tap of the reader: a click }
    Id := StrToInt(Copy(L[1], 1, Pos(#9, L[1]) - 1));
    AssertTrue(AccessibleControl(Id) = B);
    FClicks := 0;
    AccessibilityAction(F, Id, 16);
    AssertEquals(1, FClicks);
  finally
    L.Free;
    F.Free;
  end;
end;

initialization
  RegisterTests(TAccessibilityTests);

end.
