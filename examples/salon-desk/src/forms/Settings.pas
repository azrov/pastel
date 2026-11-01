{ The settings: where the server is, its API key, the VAT rate. They are kept
  in the user's settings folder by TFormMemory (settings.json). }
unit Settings;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.UI, Settings.g;

type
  TSettingsForm = class(TSettingsFormBase)
    procedure FormCreate(Sender: TObject);
  public
    { Shows the dialog; True when OK was pressed (the settings are stored then). }
    function Edit: Boolean;
    function ServerUrl: string;
    function ApiKey: string;
    function VatRate: Integer;
    { The salon's name, and its address on the lines after (for invoices). }
    function Shop: string;
  end;

var
  SettingsForm: TSettingsForm;

implementation

procedure TSettingsForm.FormCreate(Sender: TObject);
begin
  Memory.Restore;      { the settings of the last time }
end;

function TSettingsForm.Edit: Boolean;
begin
  Result := ShowModal = mrOk;
  if Result then
    Memory.Store
  else
    Memory.Restore;      { Cancel: back to what was stored }
end;

function TSettingsForm.ServerUrl: string;
begin
  Result := Trim(ServerEdit.Text);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function TSettingsForm.ApiKey: string;
begin
  Result := Trim(KeyEdit.Text);
end;

function TSettingsForm.VatRate: Integer;
begin
  Result := VatEdit.Value;
end;

function TSettingsForm.Shop: string;
begin
  Result := Trim(StringReplace(ShopMemo.Text, #13, '', [rfReplaceAll]));
  if Result = '' then
    Result := 'Salon';
end;

end.
