{ Tests of dragging between controls (Pastel.UI). }
unit dragdrop_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Controls;

type
  TDragDropTests = class(TTestSuite)
  private
    FDropped, FEnded: string;
    FRefuse: Boolean;
    procedure Over(Sender, Source: TObject; const Data: string; X, Y: Integer; var Accept: Boolean);
    procedure Drop(Sender, Source: TObject; const Data: string; X, Y: Integer);
    procedure Ended(Sender, Target: TObject; const Data: string);
  published
    procedure FromAListToAPanel;
  end;

implementation

procedure TDragDropTests.Over(Sender, Source: TObject; const Data: string; X, Y: Integer; var Accept: Boolean);
begin
  Accept := not FRefuse;
end;

procedure TDragDropTests.Drop(Sender, Source: TObject; const Data: string; X, Y: Integer);
begin
  FDropped := Data + '@' + TControl(Sender).Name;
end;

procedure TDragDropTests.Ended(Sender, Target: TObject; const Data: string);
begin
  if Target = nil then
    FEnded := 'nowhere'
  else
    FEnded := TControl(Target).Name;
end;

procedure TDragDropTests.FromAListToAPanel;
var
  F: TForm;
  Row: TRow;
  L: TListBox;
  P: TPanel;
  C: TCanvas32;

  procedure DragTo(X, Y: Integer);
  begin
    F.HandleMouseMove(L.Bounds.X + 10, L.Bounds.Y + 10);
    F.HandleMouseDown(L.Bounds.X + 10, L.Bounds.Y + 10);
    F.HandleMouseMove(L.Bounds.X + 30, L.Bounds.Y + 12);
    AssertTrue(F.Dragging, 'moved: a drag');
    F.HandleMouseMove(X, Y);
    F.Render(C);
    F.HandleMouseUp(X, Y);
  end;

begin
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    Row := TRow.Create(F);
    Row.Parent := F;
    L := TListBox.Create(F);
    L.Name := 'Tasks';
    L.Parent := Row;
    L.Width := 150;
    L.Height := 200;
    L.Items.Text := 'Paint'#10'Cut';
    L.DragMode := dmAutomatic;
    L.OnEndDrag := @Ended;
    P := TPanel.Create(F);
    P.Name := 'Done';
    P.Parent := Row;
    P.Width := 150;
    P.Height := 200;
    P.OnDragDrop := @Drop;
    P.OnDragOver := @Over;
    F.Layout(400, 300);
    C.SetSize(400, 300);
    F.Render(C);
    DragTo(P.Bounds.X + 50, P.Bounds.Y + 50);
    AssertEquals('Paint@Done', FDropped, 'the item dropped on the panel');
    AssertEquals('Done', FEnded);
    AssertFalse(F.Dragging);
    FDropped := '';
    FRefuse := True;
    DragTo(P.Bounds.X + 50, P.Bounds.Y + 50);
    AssertEquals('', FDropped, 'refused');
    AssertEquals('nowhere', FEnded);
    { a click without moving is a click }
    F.HandleMouseDown(L.Bounds.X + 10, L.Bounds.Y + 30);
    F.HandleMouseUp(L.Bounds.X + 10, L.Bounds.Y + 30);
    AssertFalse(F.Dragging);
  finally
    C.Free;
    F.Free;
  end;
end;

initialization
  RegisterTests(TDragDropTests);

end.
