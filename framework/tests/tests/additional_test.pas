{ Tests for Pastel.Additional (group box, radio group, shape, bevel, paint box),
  the dialog components and TabOrder. }
unit Additional_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Controls, Pastel.Additional,
  Pastel.Dialogs, Pastel.PForm, Pastel.Forms;

type
  TAdditionalTests = class(TTestSuite)
  private
    Form: TForm;
    Canvas: TCanvas32;
    Changes, Painted, DownX, DownY: Integer;
    procedure Render;
    procedure Changed(Sender: TObject);
    procedure PaintIt(Sender: TObject; C: TCanvas32);
    procedure Down(Sender: TObject; X, Y: Integer);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure GroupBoxHoldsFreePlacedControls;
    procedure RadioGroupChoosesOne;
    procedure ShapesAreDrawn;
    procedure BevelIsALine;
    procedure PaintBoxDrawsAndHearsTheMouse;
    procedure DialogsAreComponents;
    procedure TabFollowsTabOrder;
  end;

implementation

procedure TAdditionalTests.SetUp;
begin
  InitFonts;
  Canvas := TCanvas32.Create;
  Form := TForm.Create(nil);
  TBox(Form).Layout := lkFree;   { TForm.Layout(W, H) is the method that arranges the window }
  Changes := 0;
  Painted := 0;
end;

procedure TAdditionalTests.TearDown;
begin
  Form.Free;
  Canvas.Free;
end;

procedure TAdditionalTests.Render;
begin
  Form.Layout(400, 300);
  Canvas.SetSize(400, 300);
  Canvas.Clear(RGB(255, 255, 255));
  Form.Render(Canvas);
end;

procedure TAdditionalTests.Changed(Sender: TObject);
begin
  Inc(Changes);
end;

procedure TAdditionalTests.PaintIt(Sender: TObject; C: TCanvas32);
var
  B: TRectI;
begin
  Inc(Painted);
  B := TControl(Sender).Bounds;
  C.FillRect(B.X, B.Y, 10, 10, RGB(0, 0, 255));
end;

procedure TAdditionalTests.Down(Sender: TObject; X, Y: Integer);
begin
  DownX := X;
  DownY := Y;
end;

procedure TAdditionalTests.GroupBoxHoldsFreePlacedControls;
var
  G: TGroupBox;
  B: TButton;
begin
  G := TGroupBox.Create(Form);
  G.Parent := Form;
  G.Text := 'Payment';
  G.Left := 20;
  G.Top := 30;
  G.Width := 200;
  G.Height := 120;
  AssertEquals(Ord(lkFree), Ord(G.Layout), 'free placement, like Delphi');
  B := TButton.Create(G);
  B.Parent := G;
  B.Text := 'Pay';
  B.Left := 12;
  B.Top := G.TitleHeight + 8;
  Render;
  AssertEquals(32, B.Bounds.X, 'inside the group');
  AssertEquals(30 + G.TitleHeight + 8, B.Bounds.Y);
  AssertTrue(Canvas.GetPixel(20, 140) <> Canvas.GetPixel(399, 299), 'the frame is drawn');
end;

procedure TAdditionalTests.RadioGroupChoosesOne;
var
  R: TRadioGroup;
  P: TRectI;
begin
  R := TRadioGroup.Create(Form);
  R.Parent := Form;
  R.Text := 'Pay by';
  R.Items.Text := 'Cash'#10'Card'#10'Transfer';
  R.OnChange := @Changed;
  Render;
  AssertEquals(-1, R.ItemIndex);
  AssertEquals('', R.Value);
  P := R.ItemRect(1);
  Form.HandleMouseMove(P.X + 4, P.Y + 4);
  Form.HandleMouseDown(P.X + 4, P.Y + 4, 1, 1);
  Form.HandleMouseUp(P.X + 4, P.Y + 4, 1);
  AssertEquals(1, R.ItemIndex, 'a click chooses');
  AssertEquals('Card', R.Value);
  AssertEquals(1, Changes);
  Form.HandleKeyDown(KEY_DOWN, False, False);
  AssertEquals(2, R.ItemIndex, 'the arrow keys move the choice');
  Form.HandleKeyDown(KEY_DOWN, False, False);
  AssertEquals(2, R.ItemIndex, 'and stop at the last');
  R.Columns := 2;
  Render;
  AssertTrue(R.ItemRect(2).X > R.ItemRect(0).X, 'two columns, filled from top to bottom');
  R.Items.Delete(2);
  AssertEquals(-1, R.ItemIndex, 'the chosen item went away');
end;

procedure TAdditionalTests.ShapesAreDrawn;
var
  S: TShape;
begin
  S := TShape.Create(Form);
  S.Parent := Form;
  S.Shape := skCircle;
  S.Color := RGB(255, 0, 0);
  S.Left := 10;
  S.Top := 10;
  S.Width := 100;
  S.Height := 60;
  Render;
  AssertEquals(Cardinal(RGB(255, 0, 0)), Cardinal(Canvas.GetPixel(60, 40)), 'filled in the middle');
  AssertEquals(Cardinal(Canvas.GetPixel(399, 299)), Cardinal(Canvas.GetPixel(14, 40)), 'a circle, not the whole box');
  S.Shape := skEllipse;
  Render;
  AssertEquals(Cardinal(RGB(255, 0, 0)), Cardinal(Canvas.GetPixel(20, 40)), 'an ellipse is as wide as the box');
end;

procedure TAdditionalTests.BevelIsALine;
var
  B: TBevel;
begin
  B := TBevel.Create(Form);
  B.Parent := Form;
  B.Color := RGB(0, 0, 0);
  B.Left := 0;
  B.Top := 100;
  B.Width := 300;
  Render;
  AssertEquals(Cardinal(RGB(0, 0, 0)), Cardinal(Canvas.GetPixel(150, 104)));
  AssertEquals(Cardinal(Canvas.GetPixel(399, 299)), Cardinal(Canvas.GetPixel(150, 100)), 'only the middle row');
end;

procedure TAdditionalTests.PaintBoxDrawsAndHearsTheMouse;
var
  P: TPaintBox;
begin
  P := TPaintBox.Create(Form);
  P.Parent := Form;
  P.Left := 50;
  P.Top := 40;
  P.OnPaint := @PaintIt;
  P.OnMouseDown := @Down;
  Render;
  AssertEquals(1, Painted);
  AssertEquals(Cardinal(RGB(0, 0, 255)), Cardinal(Canvas.GetPixel(55, 45)), 'drawn where the box is');
  Form.HandleMouseMove(60, 70);
  Form.HandleMouseDown(60, 70, 1, 1);
  AssertEquals(10, DownX, 'the mouse inside the box');
  AssertEquals(30, DownY);
  Form.HandleMouseUp(60, 70, 1);
end;

procedure TAdditionalTests.DialogsAreComponents;
var
  Root: TPFormNode;
  F: TForm;
begin
  Root := ParsePForm('object F: TForm'#10'  object OpenNotes: TOpenDialog'#10'    Filter = ''Notes|*.txt'''#10'  end'#10 +
    '  object SaveNotes: TSaveDialog'#10'    DefaultExt = ''.txt'''#10'  end'#10'  object Pick: TSelectFolderDialog'#10'  end'#10 +
    '  object Kind: TRadioGroup'#10'    Items = (''A'', ''B'')'#10'    ItemIndex = 1'#10'  end'#10'end');
  F := TForm.Create(nil);
  try
    BuildForm(F, Root);
    AssertEquals('Notes|*.txt', TOpenDialog(F.FindComponent('OpenNotes')).Filter);
    AssertEquals('Open', TOpenDialog(F.FindComponent('OpenNotes')).Title, 'a title of its own');
    AssertEquals('Save', TSaveDialog(F.FindComponent('SaveNotes')).Title);
    AssertEquals('.txt', TSaveDialog(F.FindComponent('SaveNotes')).DefaultExt);
    AssertTrue(F.FindComponent('Pick') is TSelectFolderDialog);
    AssertEquals('B', TRadioGroup(F.FindComponent('Kind')).Value, 'items and the choice from the .pform');
  finally
    F.Free;
    Root.Free;
  end;
end;

procedure TAdditionalTests.TabFollowsTabOrder;
var
  A, B, C: TEdit;
begin
  A := TEdit.Create(Form);
  A.Parent := Form;
  B := TEdit.Create(Form);
  B.Parent := Form;
  B.Top := 40;
  C := TEdit.Create(Form);
  C.Parent := Form;
  C.Top := 80;
  C.TabOrder := -1;
  B.TabStop := False;
  Render;
  Form.HandleKeyDown(KEY_TAB, False, False);
  AssertTrue(Form.Focused = C, 'TabOrder -1 comes first');
  Form.HandleKeyDown(KEY_TAB, False, False);
  AssertTrue(Form.Focused = A);
  Form.HandleKeyDown(KEY_TAB, False, False);
  AssertTrue(Form.Focused = C, 'B has TabStop = False');
end;

initialization
  RegisterTests(TAdditionalTests);

end.
