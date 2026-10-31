unit Home;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.UI, Pastel.Dialogs, ContactStore, Home.g;

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
    FRows: TJSONArray;           { the contacts in the list }
    FCurrent: Int64;
    procedure Reload(SelectId: Int64);
    procedure ShowContact(Data: TJSONObject);
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
  if ContactList.RowCount > 0 then
    ContactList.Row := 0
  else
    NewExecute(nil);
end;

destructor THomeForm.Destroy;
begin
  FStore.Free;
  FRows.Free;
  inherited Destroy;
end;

procedure THomeForm.Reload(SelectId: Int64);
var
  I: Integer;
begin
  FreeAndNil(FRows);
  FRows := FStore.ListJson(SearchEdit.Text);
  ContactList.Clear;
  ContactList.LoadJson(FRows);      { the columns take name and phone }
  ContactList.Row := -1;
  for I := 0 to FRows.Count - 1 do
    if FRows.Objects[I].Get('id', Int64(0)) = SelectId then
      ContactList.Row := I;
  case FStore.Count of
    0: CountLabel.Text := 'no contacts';
    1: CountLabel.Text := '1 contact';
  else
    CountLabel.Text := Format('%d contacts', [FStore.Count]);
  end;
end;

{ Data nil: a new, empty contact }
procedure THomeForm.ShowContact(Data: TJSONObject);
begin
  if Data = nil then
  begin
    FCurrent := 0;
    ContactData.Clear;
  end
  else
  begin
    FCurrent := Data.Get('id', Int64(0));
    ContactData.Load(Data);         { NameEdit <- name, PhoneEdit <- phone... }
  end;
  DeleteAction.Enabled := FCurrent <> 0;
end;

procedure THomeForm.NewExecute(Sender: TObject);
begin
  ContactList.Row := -1;
  ShowContact(nil);
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
  Data: TJSONObject;
begin
  Data := ContactData.ToJson;       { name, phone, email, notes }
  try
    Data.Add('id', FCurrent);
    FCurrent := FStore.SaveJson(Data);
  except
    on E: EContactInvalid do
    begin
      Data.Free;
      ShowMessage(E.Message, 'Cannot save');
      Exit;
    end;
  end;
  Data.Free;
  ContactData.MarkSaved;
  Reload(FCurrent);
  DeleteAction.Enabled := True;
end;

procedure THomeForm.SearchChange(Sender: TObject);
begin
  Reload(FCurrent);
end;

procedure THomeForm.ContactListChange(Sender: TObject);
begin
  if (ContactList.Row >= 0) and (ContactList.Row < FRows.Count) then
    ShowContact(FRows.Objects[ContactList.Row]);
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
