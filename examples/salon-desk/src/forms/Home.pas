{ The salon's desktop app: a day of appointments, the customers, the invoices.
  The data lives in a SQLite file on this computer (SalonStore from
  examples/salon-core); File > Sync exchanges it with the server. }
unit Home;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, fpjson, Pastel.App, Pastel.UI, Pastel.Controls, Pastel.Dialogs, Pastel.Lang, Pastel.Json, Pastel.Db, Pastel.Files,
  SalonStore, SalonSync, SalonMoney, SalonPrint, Pastel.Inputs, Pastel.Report, Pastel.Sheets, Pastel.Print,
  Settings, Home.g;

type
  THomeForm = class(THomeFormBase)
    procedure FormCreate(Sender: TObject);
    procedure PagesChange(Sender: TObject);
    procedure SyncExecute(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    { appointments }
    procedure DayChange(Sender: TObject);
    procedure PrevDayClick(Sender: TObject);
    procedure NextDayClick(Sender: TObject);
    procedure TodayClick(Sender: TObject);
    procedure DayListChange(Sender: TObject);
    procedure NewAppointmentClick(Sender: TObject);
    procedure SaveAppointmentClick(Sender: TObject);
    procedure DoneClick(Sender: TObject);
    procedure CancelAppointmentClick(Sender: TObject);
    { customers }
    procedure SearchChange(Sender: TObject);
    procedure CustomerListChange(Sender: TObject);
    procedure NewCustomerClick(Sender: TObject);
    procedure SaveCustomerClick(Sender: TObject);
    procedure DeleteCustomerClick(Sender: TObject);
    { invoices }
    procedure InvoiceCustomerChange(Sender: TObject);
    procedure InvoiceSearchChange(Sender: TObject);
    procedure CreateInvoiceClick(Sender: TObject);
    procedure InvoiceListChange(Sender: TObject);
    procedure PaidClick(Sender: TObject);
    procedure PdfClick(Sender: TObject);
    procedure PrintClick(Sender: TObject);
    procedure ExcelClick(Sender: TObject);
  private
    FStore: TSalonStore;
    FDayRows, FCustomerRows, FInvoiceRows, FAllCustomers: TJSONArray;
    FAppointmentId, FCustomerId: string;
    FLastSync: string;
    procedure LoadCustomerChoices;
    function ChosenCustomerId(Combo: TComboBox): string;
    procedure LoadDay;
    procedure LoadCustomers(const SelectId: string);
    procedure LoadInvoices;
    procedure ShowAppointment(A: TJSONObject);
    procedure SetStatus(const Id, Status: string);
    procedure UpdateCounts;
    function SyncFile: string;
    { the selected invoice as a PDF file in the invoices folder; '' when none is selected }
    function SaveInvoicePdf: string;
    { the invoice of the selected row (the list may be filtered); nil when none }
    function SelectedInvoice: TJSONData;
  public
    destructor Destroy; override;
  end;

var
  HomeForm: THomeForm;

{ The database: SALON_DB, or salon.db in the user's settings folder. }
function DatabaseUrl: string;

implementation

{ booked, done, cancelled, invoiced in the user's language }
function StatusText(const Status: string): string;
begin
  case Status of
    'booked': Result := _('booked');
    'done': Result := _('done');
    'cancelled': Result := _('cancelled');
    'invoiced': Result := _('invoiced');
  else
    Result := Status;
  end;
end;

function DatabaseUrl: string;
begin
  Result := GetEnvironmentVariable('SALON_DB');
  if Result = '' then
  begin
    ForceDirectories(GetAppConfigDir(False));
    Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'salon.db';
  end;
  Result := 'sqlite:' + Result;
end;

function THomeForm.SyncFile: string;
begin
  Result := ChangeFileExt(Copy(DatabaseUrl, 8, MaxInt), '.sync');
end;

procedure THomeForm.FormCreate(Sender: TObject);
var
  T: Integer;
begin
  FStore := TSalonStore.Create(TDatabase.Open(DatabaseUrl, 1), True);
  FStore.CreateTables;
  if FileExists(SyncFile) then
    FLastSync := Trim(ReadText(SyncFile));
  { 09:00, 09:30, ... 19:30 }
  for T := 18 to 39 do
    TimeCombo.Items.Add(Format('%.2d:%.2d', [T div 2, (T mod 2) * 30]));
  DayPicker.Date := Date;           { calls DayChange }
  LoadCustomerChoices;
  NewAppointmentClick(nil);
  LoadCustomers('');
  LoadInvoices;
  UpdateCounts;
end;

destructor THomeForm.Destroy;
begin
  FDayRows.Free;
  FCustomerRows.Free;
  FInvoiceRows.Free;
  FAllCustomers.Free;
  FStore.Free;
  inherited Destroy;
end;

procedure THomeForm.UpdateCounts;
begin
  CountsLabel.Text := Format(_('%d customers, %d invoices'), [FStore.Count(skCustomer), FStore.Count(skInvoice)]);
end;

procedure THomeForm.PagesChange(Sender: TObject);
begin
  if Pages.ActiveSheet = InvoicesPage then
    LoadInvoices;
end;

{ ---- customers in the combo boxes ---- }

procedure THomeForm.LoadCustomerChoices;
var
  I: Integer;
  Keep, KeepInvoice: string;
begin
  Keep := CustomerCombo.Text;
  KeepInvoice := InvoiceCustomerCombo.Text;
  FreeAndNil(FAllCustomers);
  FAllCustomers := FStore.List(skCustomer);
  CustomerCombo.Items.Clear;
  InvoiceCustomerCombo.Items.Clear;
  for I := 0 to FAllCustomers.Count - 1 do
  begin
    CustomerCombo.Items.Add(JStr(FAllCustomers[I], 'name'));
    InvoiceCustomerCombo.Items.Add(JStr(FAllCustomers[I], 'name'));
  end;
  CustomerCombo.Text := Keep;
  InvoiceCustomerCombo.Text := KeepInvoice;
end;

function THomeForm.ChosenCustomerId(Combo: TComboBox): string;
begin
  if (Combo.ItemIndex >= 0) and (Combo.ItemIndex < FAllCustomers.Count) then
    Result := JStr(FAllCustomers[Combo.ItemIndex], 'id')
  else
    Result := '';
end;

{ ---- appointments ---- }

procedure THomeForm.LoadDay;
var
  I: Integer;
  A: TJSONData;
  Total: Int64;
begin
  FreeAndNil(FDayRows);
  FDayRows := FStore.Day(DayPicker.DateText);
  DayList.Clear;
  Total := 0;
  for I := 0 to FDayRows.Count - 1 do
  begin
    A := FDayRows[I];
    DayList.AddRow([Copy(JStr(A, 'starts_at'), 12, 5), JStr(A, 'customer_name'), JStr(A, 'service'),
      CentsToText(JInt(A, 'price_cents')), StatusText(JStr(A, 'status'))]);
    if JStr(A, 'status') <> 'cancelled' then
      Inc(Total, JInt(A, 'price_cents'));
    if JStr(A, 'id') = FAppointmentId then
      DayList.Row := I;
  end;
  DayTotalLabel.Text := Format(_('%d appointments, %s'), [FDayRows.Count, CentsToText(Total)]);
end;

procedure THomeForm.DayChange(Sender: TObject);
begin
  if not DayPicker.HasDate then
    DayPicker.Date := Date;
  LoadDay;
end;

procedure THomeForm.PrevDayClick(Sender: TObject);
begin
  DayPicker.Date := DayPicker.Date - 1;
end;

procedure THomeForm.NextDayClick(Sender: TObject);
begin
  DayPicker.Date := DayPicker.Date + 1;
end;

procedure THomeForm.TodayClick(Sender: TObject);
begin
  DayPicker.Date := Date;
end;

procedure THomeForm.ShowAppointment(A: TJSONObject);
begin
  if A = nil then
  begin
    FAppointmentId := '';
    AppointmentTitle.Text := _('New appointment');
    ServiceEdit.Text := '';
    PriceEdit.Text := '';
    TimeCombo.ItemIndex := -1;
    MinutesCombo.Text := '30 min';
    CustomerCombo.ItemIndex := -1;
    DoneButton.Enabled := False;
    CancelAppointmentButton.Enabled := False;
    Exit;
  end;
  FAppointmentId := JStr(A, 'id');
  AppointmentTitle.Text := Format(_('Appointment: %s'), [StatusText(JStr(A, 'status'))]);
  CustomerCombo.Text := JStr(A, 'customer_name');
  TimeCombo.Text := Copy(JStr(A, 'starts_at'), 12, 5);
  MinutesCombo.Text := Format('%d min', [JInt(A, 'minutes', 30)]);
  ServiceEdit.Text := JStr(A, 'service');
  PriceEdit.Value := JInt(A, 'price_cents') / 100;
  DoneButton.Enabled := JStr(A, 'status') = 'booked';
  CancelAppointmentButton.Enabled := JStr(A, 'status') = 'booked';
end;

procedure THomeForm.DayListChange(Sender: TObject);
begin
  if (DayList.Row >= 0) and (DayList.Row < FDayRows.Count) then
    ShowAppointment(FDayRows.Objects[DayList.Row]);
end;

procedure THomeForm.NewAppointmentClick(Sender: TObject);
begin
  DayList.Row := -1;
  ShowAppointment(nil);
end;

procedure THomeForm.SaveAppointmentClick(Sender: TObject);
var
  A: TJSONObject;
  Cents: Int64;
begin
  if ChosenCustomerId(CustomerCombo) = '' then
  begin
    ShowMessage(_('Choose the customer (new ones: on the Customers page).'), _('Appointment'));
    Exit;
  end;
  if TimeCombo.Text = '' then
  begin
    ShowMessage(_('Choose the time.'), _('Appointment'));
    Exit;
  end;
  if not TryTextToCents(PriceEdit.Text, Cents) then
    Cents := 0;
  A := JObject(['customer_id', ChosenCustomerId(CustomerCombo), 'starts_at',
    DayPicker.DateText + ' ' + TimeCombo.Text, 'minutes', StrToIntDef(Copy(MinutesCombo.Text, 1,
    Pos(' ', MinutesCombo.Text) - 1), 30), 'service', Trim(ServiceEdit.Text), 'price_cents', Cents]);
  try
    if FAppointmentId <> '' then
      A.Strings['id'] := FAppointmentId;
    try
      FAppointmentId := FStore.Save(skAppointment, A);
    except
      on E: ESalonInvalid do
      begin
        ShowMessage(E.Message, _('Cannot save'));
        Exit;
      end;
    end;
  finally
    A.Free;
  end;
  LoadDay;
  StatusLabel.Text := _('Saved.');
end;

procedure THomeForm.SetStatus(const Id, Status: string);
var
  A: TJSONObject;
begin
  if Id = '' then
    Exit;
  A := JObject(['id', Id, 'status', Status]);
  try
    FStore.Save(skAppointment, A);
  finally
    A.Free;
  end;
  LoadDay;
  DayListChange(nil);
end;

procedure THomeForm.DoneClick(Sender: TObject);
begin
  SetStatus(FAppointmentId, 'done');
end;

procedure THomeForm.CancelAppointmentClick(Sender: TObject);
begin
  if Ask(_('Cancel this appointment?'), _('Appointment')) then
    SetStatus(FAppointmentId, 'cancelled');
end;

{ ---- customers ---- }

procedure THomeForm.LoadCustomers(const SelectId: string);
var
  I: Integer;
begin
  FreeAndNil(FCustomerRows);
  FCustomerRows := FStore.List(skCustomer, SearchEdit.Text);
  CustomerList.Clear;
  CustomerList.LoadJson(FCustomerRows);      { the columns take name and phone }
  CustomerList.Row := -1;
  for I := 0 to FCustomerRows.Count - 1 do
    if JStr(FCustomerRows[I], 'id') = SelectId then
      CustomerList.Row := I;
end;

procedure THomeForm.SearchChange(Sender: TObject);
begin
  LoadCustomers(FCustomerId);
end;

procedure THomeForm.CustomerListChange(Sender: TObject);
begin
  if (CustomerList.Row >= 0) and (CustomerList.Row < FCustomerRows.Count) then
  begin
    FCustomerId := JStr(FCustomerRows[CustomerList.Row], 'id');
    CustomerData.Load(FCustomerRows.Objects[CustomerList.Row]);
  end;
end;

procedure THomeForm.NewCustomerClick(Sender: TObject);
begin
  CustomerList.Row := -1;
  FCustomerId := '';
  CustomerData.Clear;
  NameEdit.SetFocus;
end;

procedure THomeForm.SaveCustomerClick(Sender: TObject);
var
  C: TJSONObject;
begin
  C := CustomerData.ToJson;           { name, phone, email, notes }
  try
    if FCustomerId <> '' then
      C.Strings['id'] := FCustomerId;
    try
      FCustomerId := FStore.Save(skCustomer, C);
    except
      on E: ESalonInvalid do
      begin
        ShowMessage(E.Message, _('Cannot save'));
        Exit;
      end;
    end;
  finally
    C.Free;
  end;
  LoadCustomers(FCustomerId);
  LoadCustomerChoices;
  UpdateCounts;
  StatusLabel.Text := _('Saved.');
end;

procedure THomeForm.DeleteCustomerClick(Sender: TObject);
begin
  if (FCustomerId = '') or not Ask(Format(_('Delete %s?'), [NameEdit.Text]), _('Delete customer')) then
    Exit;
  FStore.Delete(skCustomer, FCustomerId);
  NewCustomerClick(nil);
  LoadCustomers('');
  LoadCustomerChoices;
  UpdateCounts;
end;

{ ---- invoices ---- }

{ '2026-11-01' the way the language writes dates }
function IssuedText(const Iso: string): string;
var
  D: TDateTime;
begin
  if TryIsoToDate(Iso, D) then
    Result := FormatDateShort(D)
  else
    Result := Iso;
end;

procedure THomeForm.LoadInvoices;
var
  I: Integer;
  Inv: TJSONData;
  NumberFormat: TFormatSettings;
begin
  NumberFormat := DefaultFormatSettings;
  NumberFormat.DecimalSeparator := '.';
  FreeAndNil(FInvoiceRows);
  FInvoiceRows := FStore.List(skInvoice);
  InvoiceList.Clear;
  for I := 0 to FInvoiceRows.Count - 1 do
  begin
    Inv := FInvoiceRows[I];
    { Total is a money column, Paid a check box column: they get values, and show them }
    InvoiceList.AddRow([JStr(Inv, 'number'), IssuedText(JStr(Inv, 'issued_on')),
      JStr(Inv, 'customer_name'), FloatToStr(JInt(Inv, 'total_cents') / 100, NumberFormat),
      IntToStr(JInt(Inv, 'paid'))]);
  end;
  InvoiceLinesLabel.Text := '';
  InvoiceSearch.Text := '';
  InvoiceCustomerChange(nil);
end;

function THomeForm.SelectedInvoice: TJSONData;
var
  I: Integer;
begin
  Result := nil;
  if (InvoiceList.Row < 0) or (InvoiceList.Row >= InvoiceList.RowCount) then
    Exit;
  for I := 0 to FInvoiceRows.Count - 1 do
    if JStr(FInvoiceRows[I], 'number') = InvoiceList.Cells[0, InvoiceList.Row] then
      Exit(FInvoiceRows[I]);
end;

procedure THomeForm.InvoiceSearchChange(Sender: TObject);
begin
  InvoiceList.Filter(Trim(InvoiceSearch.Text));
end;

procedure THomeForm.InvoiceCustomerChange(Sender: TObject);
var
  Open: TJSONArray;
begin
  if ChosenCustomerId(InvoiceCustomerCombo) = '' then
  begin
    OpenLabel.Text := '';
    CreateInvoiceButton.Enabled := False;
    Exit;
  end;
  Open := FStore.Uninvoiced(ChosenCustomerId(InvoiceCustomerCombo));
  try
    OpenLabel.Text := Format(_('%d done appointment(s) not invoiced'), [Open.Count]);
    CreateInvoiceButton.Enabled := Open.Count > 0;
  finally
    Open.Free;
  end;
end;

procedure THomeForm.CreateInvoiceClick(Sender: TObject);
var
  Open: TJSONArray;
  Ids: array of string;
  I: Integer;
  Id: string;
begin
  Open := FStore.Uninvoiced(ChosenCustomerId(InvoiceCustomerCombo));
  try
    Ids := nil;
    SetLength(Ids, Open.Count);
    for I := 0 to Open.Count - 1 do
      Ids[I] := JStr(Open[I], 'id');
  finally
    Open.Free;
  end;
  try
    Id := FStore.Invoice(ChosenCustomerId(InvoiceCustomerCombo), Ids, SettingsForm.VatRate);
  except
    on E: ESalonInvalid do
    begin
      ShowMessage(E.Message, _('Invoice'));
      Exit;
    end;
  end;
  LoadInvoices;
  for I := 0 to FInvoiceRows.Count - 1 do
    if JStr(FInvoiceRows[I], 'id') = Id then
      InvoiceList.Row := I;
  UpdateCounts;
  StatusLabel.Text := _('Invoice created.');
end;

procedure THomeForm.InvoiceListChange(Sender: TObject);
var
  Inv: TJSONData;
  Lines: TJSONData;
  S: string;
  I: Integer;
begin
  Inv := SelectedInvoice;
  if Inv = nil then
    Exit;
  S := '';
  Lines := GetJSON(JStr(Inv, 'lines', '[]'));
  try
    for I := 0 to Lines.Count - 1 do
      S := S + JStr(Lines.Items[I], 'description') + ': ' + CentsToText(JInt(Lines.Items[I], 'cents')) + LineEnding;
  finally
    Lines.Free;
  end;
  S := S + Format(_('Net %s + VAT %d%% %s = %s'), [CentsToText(JInt(Inv, 'net_cents')), JInt(Inv, 'vat_rate'),
    CentsToText(JInt(Inv, 'vat_cents')), CentsToText(JInt(Inv, 'total_cents'))]);
  InvoiceLinesLabel.Text := S;
  PaidButton.Enabled := JInt(Inv, 'paid') = 0;
end;

procedure THomeForm.PaidClick(Sender: TObject);
var
  P: TJSONObject;
  Number: string;
begin
  if SelectedInvoice = nil then
    Exit;
  Number := JStr(SelectedInvoice, 'number');
  P := JObject(['id', JStr(SelectedInvoice, 'id'), 'paid', 1]);
  try
    FStore.Save(skInvoice, P);
  finally
    P.Free;
  end;
  LoadInvoices;
  InvoiceList.Row := InvoiceList.FindRow(0, Number);
end;

{ ---- sync, settings ---- }

procedure THomeForm.SyncExecute(Sender: TObject);
var
  R: TSyncResult;
begin
  if SettingsForm.ServerUrl = '' then
  begin
    if not SettingsForm.Edit or (SettingsForm.ServerUrl = '') then
      Exit;
  end;
  StatusLabel.Text := _('Syncing...');
  Application.ProcessMessages;     { show the text before waiting }
  try
    R := SyncWithServer(FStore, SettingsForm.ServerUrl, SettingsForm.ApiKey, FLastSync);
  except
    on E: Exception do
    begin
      StatusLabel.Text := _('Sync failed.');
      ShowMessage(Format(_('The server did not answer: %s'), [E.Message]) + LineEnding +
        _('Nothing is lost; try again later.'), _('Sync'));
      Exit;
    end;
  end;
  WriteText(SyncFile, FLastSync);
  StatusLabel.Text := Format(_('Synced: %d sent, %d received.'), [R.Sent, R.Received]);
  LoadCustomerChoices;
  LoadDay;
  LoadCustomers(FCustomerId);
  LoadInvoices;
  UpdateCounts;
end;

procedure THomeForm.SettingsClick(Sender: TObject);
begin
  SettingsForm.Edit;
end;

procedure THomeForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure THomeForm.AboutClick(Sender: TObject);
begin
  ShowMessage(_('Salon - customers, appointments and invoices.') + LineEnding +
    _('An example of Pastel: a desktop app and a server that share their code.'), _('About'));
end;

function THomeForm.SaveInvoicePdf: string;
var
  R: TReport;
  Inv: TJSONData;
  Dir: string;
begin
  Result := '';
  Inv := SelectedInvoice;
  if Inv = nil then
    Exit;
  { next to the database: <settings folder>/invoices/2026-0001.pdf }
  Dir := JoinPath([ExtractFileDir(Copy(DatabaseUrl, 8, MaxInt)), 'invoices']);
  ForceDirectories(Dir);
  Result := JoinPath([Dir, JStr(Inv, 'number') + '.pdf']);
  R := InvoiceReport(FStore, JStr(Inv, 'id'), SettingsForm.Shop);
  try
    R.SaveToFile(Result);
  finally
    R.Free;
  end;
end;

procedure THomeForm.PdfClick(Sender: TObject);
var
  F: string;
begin
  F := SaveInvoicePdf;
  if F = '' then
    Exit;
  StatusLabel.Text := Format(_('Saved %s'), [ExtractFileName(F)]);
  try
    OpenDocument(F);
  except
    on E: EPrintError do
      StatusLabel.Text := Format(_('Saved %s'), [F]);
  end;
end;

procedure THomeForm.PrintClick(Sender: TObject);
var
  F: string;
begin
  F := SaveInvoicePdf;
  if F = '' then
    Exit;
  try
    PrintFile(F);
    StatusLabel.Text := Format(_('%s goes to the printer.'), [ExtractFileName(F)]);
  except
    on E: EPrintError do
      ShowMessage(E.Message, _('Print'));
  end;
end;

procedure THomeForm.ExcelClick(Sender: TObject);
var
  F: string;
  S: TSpreadsheet;
begin
  F := _('invoices') + '.xlsx';
  if not SaveFileDialog(F, _('Excel files') + '|*.xlsx') then
    Exit;
  if ExtractFileExt(F) = '' then
    F := F + '.xlsx';
  S := InvoicesSheet(FInvoiceRows);
  try
    S.SaveToFile(F);
  finally
    S.Free;
  end;
  StatusLabel.Text := Format(_('Saved %s'), [ExtractFileName(F)]);
end;

end.
