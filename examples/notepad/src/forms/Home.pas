unit Home;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.UI, Pastel.Dialogs, Pastel.Files, TextStats, Home.g;

type
  THomeForm = class(THomeFormBase)
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure WrapClick(Sender: TObject);
    procedure DarkClick(Sender: TObject);
    procedure EditorChange(Sender: TObject);
  private
    FFileName: string;
    FModified: Boolean;
    procedure Load(const AFileName: string);
    function SaveTo(const AFileName: string): Boolean;
    function Save: Boolean;
    { False when the user cancels; asks to save changes first. }
    function MayDiscard: Boolean;
    procedure UpdateTitle;
  end;

var
  HomeForm: THomeForm;

const
  TextFiles = 'Text files|*.txt;*.md|All files|*';

implementation

procedure THomeForm.FormCreate(Sender: TObject);
begin
  if (ParamCount > 0) and FileExists(ParamStr(1)) then
    Load(ParamStr(1));
  Editor.SetFocus;
end;

procedure THomeForm.UpdateTitle;
var
  S: string;
begin
  if FFileName = '' then
    S := 'Untitled'
  else
    S := ExtractFileName(FFileName);
  if FModified then
    S := '*' + S;
  Title := S + ' - Notepad';
end;

procedure THomeForm.Load(const AFileName: string);
begin
  Editor.Text := ReadText(AFileName);
  FFileName := AFileName;
  FModified := False;
  StatusLabel.Text := 'opened ' + ExtractFileName(AFileName);
  UpdateTitle;
end;

function THomeForm.SaveTo(const AFileName: string): Boolean;
begin
  try
    WriteText(AFileName, Editor.Text);
  except
    on E: Exception do
    begin
      ShowMessage(E.Message, 'Cannot save');
      Exit(False);
    end;
  end;
  FFileName := AFileName;
  FModified := False;
  StatusLabel.Text := 'saved ' + ExtractFileName(AFileName);
  UpdateTitle;
  Result := True;
end;

function THomeForm.Save: Boolean;
var
  F: string;
begin
  if FFileName <> '' then
    Exit(SaveTo(FFileName));
  F := 'untitled.txt';
  Result := SaveFileDialog(F, TextFiles, 'Save', '.txt') and SaveTo(F);
end;

function THomeForm.MayDiscard: Boolean;
begin
  if not FModified then
    Exit(True);
  case MessageDlg('Save the changes?', 'Notepad', [mrYes, mrNo, mrCancel]) of
    mrYes: Result := Save;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure THomeForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := MayDiscard;
end;

procedure THomeForm.NewClick(Sender: TObject);
begin
  if not MayDiscard then
    Exit;
  Editor.Text := '';
  FFileName := '';
  FModified := False;
  StatusLabel.Text := 'new file';
  UpdateTitle;
end;

procedure THomeForm.OpenClick(Sender: TObject);
var
  F: string;
begin
  F := FFileName;
  if MayDiscard and OpenFileDialog(F, TextFiles) then
    Load(F);
end;

procedure THomeForm.SaveClick(Sender: TObject);
begin
  Save;
end;

procedure THomeForm.SaveAsClick(Sender: TObject);
var
  F: string;
begin
  F := FFileName;
  if F = '' then
    F := 'untitled.txt';
  if SaveFileDialog(F, TextFiles, 'Save as', '.txt') then
    SaveTo(F);
end;

procedure THomeForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure THomeForm.WrapClick(Sender: TObject);
begin
  WrapItem.Checked := not WrapItem.Checked;
  Editor.WordWrap := WrapItem.Checked;
end;

procedure THomeForm.DarkClick(Sender: TObject);
begin
  DarkItem.Checked := not DarkItem.Checked;
  if DarkItem.Checked then
    Appearance := tmDark
  else
    Appearance := tmLight;
end;

procedure THomeForm.EditorChange(Sender: TObject);
begin
  CountLabel.Text := Format('%d words, %d lines', [WordCount(Editor.Text), LineCount(Editor.Text)]);
  if not FModified then
  begin
    FModified := True;
    UpdateTitle;
  end;
end;

end.
