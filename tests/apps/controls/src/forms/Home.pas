unit Home;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Graphics, Pastel.UI, Pastel.Grids, Pastel.Dialogs, Pastel.Additional, Settings, Home.g;

type
  THomeForm = class(THomeFormBase)
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure RecentClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure QuitExecute(Sender: TObject);
    procedure TickerTimer(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure AgreeChange(Sender: TObject);
    procedure DarkChange(Sender: TObject);
    procedure SizeChange(Sender: TObject);
    procedure VolumeChange(Sender: TObject);
    procedure PeopleDblClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FoldersChange(Sender: TObject);
    procedure TableCellEdit(Sender: TObject; ACol, ARow: Integer; var Value: string; var Accept: Boolean);
    procedure PayByChange(Sender: TObject);
    procedure SketchPaint(Sender: TObject; Canvas: TCanvas32);
    procedure SketchMouseDown(Sender: TObject; X, Y: Integer);
  private
    FTicks: Integer;
  end;

var
  HomeForm: THomeForm;

implementation

procedure THomeForm.NewClick(Sender: TObject);
var
  N: string;
begin
  N := InputBox('New', 'Name of the note:', 'untitled');
  Status.Text := 'new ' + N;
end;

procedure THomeForm.OpenClick(Sender: TObject);
var
  F: string;
begin
  F := GetCurrentDir;
  if OpenFileDialog(F, 'Pascal|*.pas|All files|*') then
    Status.Text := 'open ' + ExtractFileName(F)
  else
    Status.Text := 'open cancelled';
end;

procedure THomeForm.RecentClick(Sender: TObject);
begin
  Status.Text := 'recent';
end;

procedure THomeForm.AboutClick(Sender: TObject);
begin
  ShowMessage('Pastel controls demo', 'About');
  Status.Text := 'about shown';
end;

procedure THomeForm.QuitExecute(Sender: TObject);
begin
  if Ask('Really quit?') then
    Close
  else
    Status.Text := 'stay';
end;

procedure THomeForm.TickerTimer(Sender: TObject);
begin
  Inc(FTicks);
  if FTicks = 3 then
    Status.Text := 'ticked';
end;

procedure THomeForm.ClearClick(Sender: TObject);
begin
  Notes.Text := '';
end;

procedure THomeForm.AgreeChange(Sender: TObject);
begin
  Status.Text := 'agree ' + BoolToStr(Agree.Checked, 'yes', 'no');
end;

procedure THomeForm.DarkChange(Sender: TObject);
begin
  UseDarkTheme(Dark.Checked);
end;

procedure THomeForm.SizeChange(Sender: TObject);
begin
  Status.Text := 'size ' + Size.Text;
end;

procedure THomeForm.VolumeChange(Sender: TObject);
begin
  Progress.Position := Volume.Position;
end;

procedure THomeForm.SettingsClick(Sender: TObject);
begin
  if SettingsForm.ShowModal = mrOk then
    Status.Text := 'settings ok'
  else
    Status.Text := 'settings cancelled';
end;

procedure THomeForm.PeopleDblClick(Sender: TObject);
begin
  Status.Text := 'hello ' + People.SelectedText;
end;

procedure THomeForm.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  Table.AddRow(['Zeynep', '29', 'İzmir']);
  Table.AddRow(['Ali', '41', 'Ankara']);
  Table.AddRow(['Ayşe', '7', 'İstanbul']);
  for I := 1 to 997 do
    Table.AddRow(['Person ' + IntToStr(I), IntToStr(20 + I mod 50), 'Bursa']);
end;

procedure THomeForm.FoldersChange(Sender: TObject);
begin
  Status.Text := 'folder ' + Folders.Text;
end;

procedure THomeForm.TableCellEdit(Sender: TObject; ACol, ARow: Integer; var Value: string; var Accept: Boolean);
begin
  { ages are numbers }
  if ACol = 1 then
    Accept := StrToIntDef(Value, -1) >= 0;
  Value := Trim(Value);
end;

procedure THomeForm.PayByChange(Sender: TObject);
begin
  Status.Text := 'pay ' + PayBy.Value;
  if PayBy.ItemIndex = 1 then Lamp.Color := RGB(22, 163, 74) else Lamp.Color := RGB(220, 38, 38);
end;

procedure THomeForm.SketchPaint(Sender: TObject; Canvas: TCanvas32);
begin
  Canvas.FillRect(Sketch.Bounds.X, Sketch.Bounds.Y, 40, 20, RGB(79, 70, 229));
end;

procedure THomeForm.SketchMouseDown(Sender: TObject; X, Y: Integer);
begin
  Status.Text := Format('sketch %d,%d', [X, Y]);
end;

end.
