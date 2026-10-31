{ Pastel - dialogs: messages, questions, input, choosing files and folders.

    ShowMessage('Saved.');
    if Ask('Delete this note?') then ...
    Name := InputBox('New file', 'Name:', 'notes.txt');
    if OpenFileDialog(FileName, 'Text files|*.txt;*.md|All files|*') then ...
    if SaveFileDialog(FileName, 'Notes|*.txt') then ...

  The dialogs are drawn by Pastel inside the window (the same on every
  platform, and test scripts can click them). They wait until the user
  answered, like Delphi's. Their controls have names a test script can use:
  OkButton, CancelButton, YesButton, NoButton, InputEdit, FileList,
  FileNameEdit, PathEdit.
  Part of the Pastel project, MIT License. }
unit Pastel.Dialogs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI;

{ A message with an OK button. }
procedure ShowMessage(const Msg: string; const Title: string = '');
{ A question with Yes and No; True for Yes. }
function Ask(const Msg: string; const Title: string = ''): Boolean;
{ A message with the buttons given (mrOk, mrCancel, mrYes, mrNo, mrAbort,
  mrRetry, mrIgnore, mrClose); the result is the button chosen, or mrCancel
  for Escape. The first button is the default (Enter). Danger: the first
  button is red (for deleting and the like). }
function MessageDlg(const Msg, Title: string; const Buttons: array of Integer;
  Danger: Boolean = False): Integer;
{ Asks for a line of text; Default when cancelled. }
function InputBox(const Title, Prompt, Default: string): string;
{ The same; False when cancelled (Value is not changed then). }
function InputQuery(const Title, Prompt: string; var Value: string): Boolean;

{ Filter: 'Pictures|*.png;*.jpg|All files|*'. FileName: where to start
  (a file or a folder); on True the chosen file. }
function OpenFileDialog(var FileName: string; const Filter: string = '';
  const Title: string = 'Open'): Boolean;
{ Asks before replacing a file that exists. DefaultExt ('.txt') is added
  when the name has none. }
function SaveFileDialog(var FileName: string; const Filter: string = '';
  const Title: string = 'Save'; const DefaultExt: string = ''): Boolean;
function SelectFolderDialog(var Folder: string; const Title: string = 'Choose a folder'): Boolean;

{ The caption of a modal result: 'OK', 'Cancel', 'Yes'... }
function ModalResultCaption(R: Integer): string;

implementation

uses
  Math, StrUtils, Pastel.Controls;

function ModalResultCaption(R: Integer): string;
begin
  case R of
    mrOk: Result := 'OK';
    mrCancel: Result := 'Cancel';
    mrAbort: Result := 'Abort';
    mrRetry: Result := 'Retry';
    mrIgnore: Result := 'Ignore';
    mrYes: Result := 'Yes';
    mrNo: Result := 'No';
    mrClose: Result := 'Close';
  else
    Result := IntToStr(R);
  end;
end;

function ButtonName(R: Integer): string;
begin
  case R of
    mrOk: Result := 'OkButton';
    mrCancel: Result := 'CancelButton';
    mrAbort: Result := 'AbortButton';
    mrRetry: Result := 'RetryButton';
    mrIgnore: Result := 'IgnoreButton';
    mrYes: Result := 'YesButton';
    mrNo: Result := 'NoButton';
    mrClose: Result := 'CloseButton';
  else
    Result := 'Button' + IntToStr(R);
  end;
end;

function CheckForm: TForm;
begin
  Result := MainForm;
  if Result = nil then
    raise Exception.Create('dialogs need a window: show them after Application.Run started');
end;

{ a dialog: title, content, then a row of buttons on the right }
function NewDialog(const Title: string; MinWidth: Integer; out Content: TColumn): TPopup;
var
  T: TLabel;
begin
  Result := TPopup.Create(nil);
  Result.Padding := 20;
  Result.Gap := 14;
  Result.Width := MinWidth;
  if Title <> '' then
  begin
    T := TLabel.Create(Result);
    T.Name := 'DialogTitle';
    T.Text := Title;
    T.Bold := True;
    T.FontSize := 16;
    T.Parent := Result;
  end;
  Content := TColumn.Create(Result);
  Content.Gap := 10;
  Content.Parent := Result;
end;

function AddButtons(P: TPopup; const Buttons: array of Integer; Danger: Boolean): TRow;
var
  I: Integer;
  B: TButton;
begin
  Result := TRow.Create(P);
  Result.Gap := 8;
  Result.Justify := jsEnd;
  Result.Parent := P;
  { the default first in the list, but on the right, like most systems }
  for I := High(Buttons) downto 0 do
  begin
    B := TButton.Create(P);
    B.Name := ButtonName(Buttons[I]);
    B.Text := ModalResultCaption(Buttons[I]);
    B.ModalResult := Buttons[I];
    if I = 0 then
    begin
      B.Default := True;
      if Danger then B.Style := bsDanger;
    end
    else
      B.Style := bsSecondary;
    B.Cancel := (Buttons[I] = mrCancel) or (Buttons[I] = mrNo) or (Buttons[I] = mrClose) or
      ((Length(Buttons) = 1) and (I = 0));
    B.Parent := Result;
  end;
end;

function MessageDlg(const Msg, Title: string; const Buttons: array of Integer; Danger: Boolean): Integer;
var
  P: TPopup;
  Content: TColumn;
  L: TLabel;
  B: TControl;
begin
  P := NewDialog(Title, 380, Content);
  try
    L := TLabel.Create(P);
    L.Name := 'MessageText';
    L.Text := Msg;
    L.WordWrap := True;
    L.Parent := Content;
    if Length(Buttons) = 0 then
      AddButtons(P, [mrOk], Danger)
    else
      AddButtons(P, Buttons, Danger);
    Result := P.ShowModal(CheckForm);
    if Result = mrNone then
      Result := mrCancel;
    B := nil;
    if B <> nil then ;
  finally
    P.Free;
  end;
end;

procedure ShowMessage(const Msg: string; const Title: string);
begin
  MessageDlg(Msg, Title, [mrOk]);
end;

function Ask(const Msg: string; const Title: string): Boolean;
begin
  Result := MessageDlg(Msg, Title, [mrYes, mrNo]) = mrYes;
end;

function InputQuery(const Title, Prompt: string; var Value: string): Boolean;
var
  P: TPopup;
  Content: TColumn;
  L: TLabel;
  E: TEdit;
begin
  P := NewDialog(Title, 380, Content);
  try
    if Prompt <> '' then
    begin
      L := TLabel.Create(P);
      L.Name := 'MessageText';
      L.Text := Prompt;
      L.WordWrap := True;
      L.Parent := Content;
    end;
    E := TEdit.Create(P);
    E.Name := 'InputEdit';
    E.Text := Value;
    E.SelectAll;
    E.Parent := Content;
    AddButtons(P, [mrOk, mrCancel], False);
    Result := P.ShowModal(CheckForm) = mrOk;
    if Result then
      Value := E.Text;
  finally
    P.Free;
  end;
end;

function InputBox(const Title, Prompt, Default: string): string;
begin
  Result := Default;
  if not InputQuery(Title, Prompt, Result) then
    Result := Default;
end;

{ ---- file dialogs ---- }

type
  TFileDialogKind = (fdOpen, fdSave, fdFolder);

  TFileDialog = class(TComponent)
  private
    FKind: TFileDialogKind;
    FPopup: TPopup;
    FPath: TEdit;
    FList: TListBox;
    FName: TEdit;
    FFilter: TComboBox;
    FFilters: TStringList;    { Name=patterns }
    FDir: string;
    FResult, FDefaultExt: string;
    procedure Fill;
    procedure GoTo_(const Dir: string);
    function Matches(const FileName: string): Boolean;
    function EntryPath(Index: Integer): string;
    function IsFolderEntry(Index: Integer): Boolean;
    procedure ListChanged(Sender: TObject);
    procedure ListActivated(Sender: TObject);
    procedure UpClicked(Sender: TObject);
    procedure PathSubmitted(Sender: TObject);
    procedure FilterChanged(Sender: TObject);
    procedure AcceptClicked(Sender: TObject);
    procedure NameSubmitted(Sender: TObject);
    function TryAccept: Boolean;
  public
    constructor CreateKind(AKind: TFileDialogKind; const Title, Filter, Start, DefaultExt: string);
    destructor Destroy; override;
    function Execute(out FileName: string): Boolean;
  end;

const
  FolderMark = '/';

constructor TFileDialog.CreateKind(AKind: TFileDialogKind; const Title, Filter, Start, DefaultExt: string);
var
  Content: TColumn;
  Top, Bottom: TRow;
  Up, OkBtn, CancelBtn: TButton;
  Parts: TStringArray;
  I: Integer;
begin
  inherited Create(nil);
  FKind := AKind;
  FDefaultExt := DefaultExt;
  FFilters := TStringList.Create;
  Parts := Filter.Split(['|']);
  I := 0;
  while I + 1 <= High(Parts) do
  begin
    FFilters.Add(Parts[I] + '=' + Parts[I + 1]);
    Inc(I, 2);
  end;
  if FFilters.Count = 0 then
    FFilters.Add('All files=*');

  FPopup := NewDialog(Title, 560, Content);
  Top := TRow.Create(FPopup);
  Top.Gap := 8;
  Top.Parent := Content;
  Up := TButton.Create(FPopup);
  Up.Name := 'UpButton';
  Up.Text := '↑';
  Up.Hint := 'The folder above';
  Up.Style := bsSecondary;
  Up.OnClick := @UpClicked;
  Up.Parent := Top;
  FPath := TEdit.Create(FPopup);
  FPath.Name := 'PathEdit';
  FPath.Grow := 1;
  FPath.OnSubmit := @PathSubmitted;
  FPath.Parent := Top;

  FList := TListBox.Create(FPopup);
  FList.Name := 'FileList';
  FList.Height := 260;
  FList.OnChange := @ListChanged;
  FList.OnDblClick := @ListActivated;
  FList.Parent := Content;

  Bottom := TRow.Create(FPopup);
  Bottom.Gap := 8;
  Bottom.Parent := Content;
  FName := TEdit.Create(FPopup);
  FName.Name := 'FileNameEdit';
  FName.Placeholder := 'File name';
  FName.Grow := 1;
  FName.OnSubmit := @NameSubmitted;
  FName.Visible := FKind <> fdFolder;
  FName.Parent := Bottom;
  FFilter := TComboBox.Create(FPopup);
  FFilter.Name := 'FilterCombo';
  for I := 0 to FFilters.Count - 1 do
    FFilter.Items.Add(FFilters.Names[I]);
  FFilter.ItemIndex := 0;
  FFilter.OnChange := @FilterChanged;
  FFilter.Visible := (FKind <> fdFolder) and (FFilters.Count > 1);
  FFilter.Parent := Bottom;

  Top := TRow.Create(FPopup);
  Top.Gap := 8;
  Top.Justify := jsEnd;
  Top.Parent := FPopup;
  CancelBtn := TButton.Create(FPopup);
  CancelBtn.Name := 'CancelButton';
  CancelBtn.Text := 'Cancel';
  CancelBtn.Style := bsSecondary;
  CancelBtn.ModalResult := mrCancel;
  CancelBtn.Cancel := True;
  CancelBtn.Parent := Top;
  OkBtn := TButton.Create(FPopup);
  OkBtn.Name := 'OkButton';
  case FKind of
    fdOpen: OkBtn.Text := 'Open';
    fdSave: OkBtn.Text := 'Save';
  else
    OkBtn.Text := 'Choose';
  end;
  OkBtn.OnClick := @AcceptClicked;
  OkBtn.Parent := Top;

  { where to start }
  if (Start <> '') and DirectoryExists(Start) then
    FDir := Start
  else if (Start <> '') and DirectoryExists(ExtractFileDir(ExpandFileName(Start))) then
  begin
    FDir := ExtractFileDir(ExpandFileName(Start));
    FName.Text := ExtractFileName(Start);
  end
  else
    FDir := GetCurrentDir;
  GoTo_(FDir);
end;

destructor TFileDialog.Destroy;
begin
  FPopup.Free;
  FFilters.Free;
  inherited Destroy;
end;

function TFileDialog.Matches(const FileName: string): Boolean;
var
  Pat: string;
begin
  if FKind = fdFolder then
    Exit(False);
  for Pat in FFilters.ValueFromIndex[Math.Max(0, FFilter.ItemIndex)].Split([';']) do
    if (Trim(Pat) = '*') or (Trim(Pat) = '*.*') or IsWild(FileName, Trim(Pat), True) then
      Exit(True);
  Result := False;
end;

procedure TFileDialog.Fill;
var
  SR: TSearchRec;
  Dirs, Files: TStringList;
begin
  Dirs := TStringList.Create;
  Files := TStringList.Create;
  try
    Dirs.Sorted := True;
    Files.Sorted := True;
    Dirs.CaseSensitive := False;
    Files.CaseSensitive := False;
    if FindFirst(IncludeTrailingPathDelimiter(FDir) + AllFilesMask, faAnyFile or faDirectory, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then
          Continue;
        if (SR.Attr and faDirectory) <> 0 then
          Dirs.Add(SR.Name + FolderMark)
        else if Matches(SR.Name) then
          Files.Add(SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    FList.Items.BeginUpdate;
    try
      FList.Items.Assign(Dirs);
      FList.Items.AddStrings(Files);
    finally
      FList.Items.EndUpdate;
    end;
    FList.ItemIndex := -1;
  finally
    Dirs.Free;
    Files.Free;
  end;
end;

procedure TFileDialog.GoTo_(const Dir: string);
begin
  if not DirectoryExists(Dir) then
    Exit;
  FDir := ExcludeTrailingPathDelimiter(ExpandFileName(Dir));
  if FDir = '' then
    FDir := PathDelim;
  FPath.Text := FDir;
  Fill;
end;

function TFileDialog.IsFolderEntry(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and AnsiEndsStr(FolderMark, FList.Items[Index]);
end;

function TFileDialog.EntryPath(Index: Integer): string;
var
  N: string;
begin
  N := FList.Items[Index];
  if IsFolderEntry(Index) then
    N := Copy(N, 1, Length(N) - Length(FolderMark));
  Result := IncludeTrailingPathDelimiter(FDir) + N;
end;

procedure TFileDialog.ListChanged(Sender: TObject);
begin
  if (FList.ItemIndex >= 0) and not IsFolderEntry(FList.ItemIndex) then
    FName.Text := FList.Items[FList.ItemIndex];
end;

procedure TFileDialog.ListActivated(Sender: TObject);
begin
  if FList.ItemIndex < 0 then
    Exit;
  if IsFolderEntry(FList.ItemIndex) then
    GoTo_(EntryPath(FList.ItemIndex))
  else if TryAccept then
    FPopup.Close(mrOk);
end;

procedure TFileDialog.UpClicked(Sender: TObject);
begin
  GoTo_(ExtractFileDir(FDir));
end;

procedure TFileDialog.PathSubmitted(Sender: TObject);
begin
  if DirectoryExists(FPath.Text) then
    GoTo_(FPath.Text)
  else
    FPath.Text := FDir;
end;

procedure TFileDialog.FilterChanged(Sender: TObject);
begin
  Fill;
end;

function TFileDialog.TryAccept: Boolean;
var
  N, F: string;
begin
  Result := False;
  if FKind = fdFolder then
  begin
    if (FList.ItemIndex >= 0) and IsFolderEntry(FList.ItemIndex) then
      FResult := EntryPath(FList.ItemIndex)
    else
      FResult := FDir;
    Exit(True);
  end;
  N := Trim(FName.Text);
  if N = '' then
    Exit;
  if (ExtractFilePath(N) <> '') and DirectoryExists(ExpandFileName(N)) then
  begin
    GoTo_(N);
    FName.Text := '';
    Exit;
  end;
  if ExtractFilePath(N) = '' then
    F := IncludeTrailingPathDelimiter(FDir) + N
  else
    F := ExpandFileName(N);
  if DirectoryExists(F) then
  begin
    GoTo_(F);
    FName.Text := '';
    Exit;
  end;
  if FKind = fdOpen then
  begin
    if not FileExists(F) then
    begin
      MessageDlg(Format('"%s" was not found.', [N]), 'Open', [mrOk]);
      Exit;
    end;
  end
  else
  begin
    if (ExtractFileExt(F) = '') and (FDefaultExt <> '') then
      F := F + FDefaultExt;
    if FileExists(F) and (MessageDlg(Format('"%s" exists already. Replace it?', [ExtractFileName(F)]),
      'Save', [mrYes, mrNo]) <> mrYes) then
      Exit;
  end;
  FResult := F;
  Result := True;
end;

procedure TFileDialog.AcceptClicked(Sender: TObject);
begin
  if (FKind <> fdFolder) and (FList.ItemIndex >= 0) and IsFolderEntry(FList.ItemIndex) and
     ((CheckForm.Focused = FList) or (Trim(FName.Text) = '')) then
  begin
    GoTo_(EntryPath(FList.ItemIndex));
    Exit;
  end;
  if TryAccept then
    FPopup.Close(mrOk);
end;

procedure TFileDialog.NameSubmitted(Sender: TObject);
begin
  AcceptClicked(Sender);
end;

function TFileDialog.Execute(out FileName: string): Boolean;
begin
  if FKind = fdFolder then
    FPopup.ActiveControl := FList
  else
  begin
    FPopup.ActiveControl := FName;
    FName.SelectAll;         { typing replaces the suggested name }
  end;
  Result := FPopup.ShowModal(CheckForm) = mrOk;
  if Result then
    FileName := FResult;
end;

function OpenFileDialog(var FileName: string; const Filter: string; const Title: string): Boolean;
var
  D: TFileDialog;
  F: string;
begin
  D := TFileDialog.CreateKind(fdOpen, Title, Filter, FileName, '');
  try
    Result := D.Execute(F);
    if Result then
      FileName := F;
  finally
    D.Free;
  end;
end;

function SaveFileDialog(var FileName: string; const Filter: string; const Title: string;
  const DefaultExt: string): Boolean;
var
  D: TFileDialog;
  F: string;
begin
  D := TFileDialog.CreateKind(fdSave, Title, Filter, FileName, DefaultExt);
  try
    Result := D.Execute(F);
    if Result then
      FileName := F;
  finally
    D.Free;
  end;
end;

function SelectFolderDialog(var Folder: string; const Title: string): Boolean;
var
  D: TFileDialog;
  F: string;
begin
  D := TFileDialog.CreateKind(fdFolder, Title, '', Folder, '');
  try
    Result := D.Execute(F);
    if Result then
      Folder := F;
  finally
    D.Free;
  end;
end;

end.
