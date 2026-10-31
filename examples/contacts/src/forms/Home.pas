unit Home;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.UI, Pastel.Dialogs, ContactStore, Home.g;

type
  THomeForm = class(THomeFormBase)
    procedure FormCreate(Sender: TObject);
    procedure NewExecute(Sender: TObject);
    procedure DeleteExecute(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure ContactListChange(Sender: TObject);
    procedure SaveClick(Sender: TObject);
  private
    FStore: TContactStore;
    FShown: TContactArray;
    FCurrent: Int64;
    procedure Reload(SelectId: Int64);
    procedure ShowContact(const C: TContact);
  public
    destructor Destroy; override;
  end;

var
  HomeForm: THomeForm;

implementation

procedure THomeForm.FormCreate(Sender: TObject);
begin
  FStore := TContactStore.Create(DefaultDatabaseUrl);
  Reload(0);
  if Length(FShown) > 0 then
    ContactList.ItemIndex := 0
  else
    NewExecute(nil);
end;

destructor THomeForm.Destroy;
begin
  FStore.Free;
  inherited Destroy;
end;

procedure THomeForm.Reload(SelectId: Int64);
var
  I: Integer;
begin
  FShown := FStore.List(SearchEdit.Text);
  ContactList.Items.BeginUpdate;
  try
    ContactList.Items.Clear;
    for I := 0 to High(FShown) do
      ContactList.Items.Add(FShown[I].Name);
  finally
    ContactList.Items.EndUpdate;
  end;
  ContactList.ItemIndex := -1;
  for I := 0 to High(FShown) do
    if FShown[I].Id = SelectId then
      ContactList.ItemIndex := I;
  case FStore.Count of
    0: CountLabel.Text := 'no contacts';
    1: CountLabel.Text := '1 contact';
  else
    CountLabel.Text := Format('%d contacts', [FStore.Count]);
  end;
end;

procedure THomeForm.ShowContact(const C: TContact);
begin
  FCurrent := C.Id;
  NameEdit.Text := C.Name;
  PhoneEdit.Text := C.Phone;
  EmailEdit.Text := C.Email;
  NotesMemo.Text := C.Notes;
  DeleteAction.Enabled := C.Id <> 0;
end;

procedure THomeForm.NewExecute(Sender: TObject);
begin
  ContactList.ItemIndex := -1;
  ShowContact(NewContact('', '', ''));
  NameEdit.SetFocus;
end;

procedure THomeForm.DeleteExecute(Sender: TObject);
begin
  if (FCurrent = 0) or not Ask(Format('Delete %s?', [NameEdit.Text]), 'Delete contact') then
    Exit;
  FStore.Delete(FCurrent);
  Reload(0);
  NewExecute(nil);
end;

procedure THomeForm.SaveClick(Sender: TObject);
var
  C: TContact;
begin
  C := NewContact(NameEdit.Text, PhoneEdit.Text, EmailEdit.Text, NotesMemo.Text);
  C.Id := FCurrent;
  try
    FCurrent := FStore.Save(C);
  except
    on E: EContactInvalid do
    begin
      ShowMessage(E.Message, 'Cannot save');
      Exit;
    end;
  end;
  Reload(FCurrent);
  DeleteAction.Enabled := True;
end;

procedure THomeForm.SearchChange(Sender: TObject);
begin
  Reload(FCurrent);
end;

procedure THomeForm.ContactListChange(Sender: TObject);
begin
  if (ContactList.ItemIndex >= 0) and (ContactList.ItemIndex <= High(FShown)) then
    ShowContact(FShown[ContactList.ItemIndex]);
end;

procedure THomeForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure THomeForm.AboutClick(Sender: TObject);
begin
  ShowMessage('Contacts - a Pastel example.' + LineEnding + 'The contacts are kept in a SQLite file.', 'About');
end;

end.
