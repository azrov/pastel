{ Pastel - inputs for business apps: dates, amounts of money, numbers and times.

    object DueDate: TDatePicker
      DateText = '2026-11-01'
    end
    object PriceEdit: TCurrencyEdit
      Symbol = '₺'
    end
    object CountEdit: TNumberEdit
      Min = 1
      Max = 99
    end
    object StartEdit: TTimeEdit
      Text = '09:30'
    end

    Total := PriceEdit.Value * CountEdit.Value;      // Currency * Integer
    if DueDate.HasDate then ...

  Also the helpers they use: reading and writing money (TryParseMoney,
  FormatMoney), the cells of a month (MonthCells) and ISO dates.
  Part of the Pastel project, MIT License. }
unit Pastel.Inputs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Pastel.Graphics, Pastel.UI;

{ '1.234,50', '1234.5', '1 234,50 ₺' -> 1234.5; False when it is not an amount. The
  last . or , followed by one or two digits is the decimal separator. }
function TryParseMoney(const S: string; out Value: Currency): Boolean;
{ 1234.5 -> '1.234,50' with Pastel.Lang's separators, the symbol after it when given. }
function FormatMoney(Value: Currency; Decimals: Integer = 2; const Symbol: string = ''): string;

type
  { 6 weeks x 7 days, Monday first: the month with the end of the one before
    and the start of the one after }
  TMonthCells = array[0..41] of TDateTime;

function MonthCells(Year, Month: Word): TMonthCells;
{ 'November 2026' in the language of the program }
function MonthTitle(Year, Month: Word): string;
{ 'Mo'..'Su' }
function WeekdayShort(Index: Integer): string;
{ '2026-11-01' <-> date; False for anything else }
function TryIsoToDate(const S: string; out D: TDateTime): Boolean;
function DateToIso(D: TDateTime): string;

type
  { An edit for amounts of money: Value is a Currency; people may type
    '1234,5', '1.234,50' or '1234.50', and when they leave the edit it shows
    the amount the way their language writes it ('1.234,50 ₺'). }
  TCurrencyEdit = class(TEdit)
  private
    FSymbol: string;
    FDecimals: Integer;
    function GetValue: Currency;
    procedure SetValue(AValue: Currency);
    function GetValid: Boolean;
    procedure SetSymbol(const AValue: string);
    procedure SetDecimals(AValue: Integer);
  protected
    procedure TextInput(const S: string); override;
    procedure FocusLost; override;
  public
    constructor Create(AOwner: TComponent); override;
    { The amount; 0 when the text is empty or not an amount (see Valid). }
    property Value: Currency read GetValue write SetValue;
    { The text is empty or an amount. }
    property Valid: Boolean read GetValid;
    { Writes the text again in the language's way (done when the focus leaves). }
    procedure Reformat;
  published
    { Shown after the amount: '₺', '€', 'USD' }
    property Symbol: string read FSymbol write SetSymbol;
    { Digits after the decimal separator. }
    property Decimals: Integer read FDecimals write SetDecimals default 2;
  end;

  TDatePicker = class;

  { The month view in the popup; a control of its own, usable alone too. }
  TCalendarView = class(TControl)
  private
    FYear, FMonth: Word;
    FCursor: TDateTime;         { the day the keyboard is on }
    FSelected: TDateTime;
    FHover: Integer;
    FOnPick: TNotifyEvent;
    function CellRect(Index: Integer): TRectI;
    function CellAt(X, Y: Integer): Integer;
    function HeaderButton(X, Y: Integer): Integer;
    procedure MoveCursor(D: TDateTime);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Shows the month of D, with D chosen (0: today, nothing chosen). }
    procedure ShowDate(D: TDateTime);
    procedure NextMonth;
    procedure PreviousMonth;
    property Selected: TDateTime read FSelected;
    property Year: Word read FYear;
    property Month: Word read FMonth;
    { A day was chosen (click or Enter). }
    property OnPick: TNotifyEvent read FOnPick write FOnPick;
  end;

  { A date, chosen from a calendar (a TPopup with a TCalendarView). A click,
    Enter, Space or Alt+Down opens it: arrows move by days and weeks, Page
    Up/Down by months, Enter or a click chooses, Escape closes; Delete empties
    it. The date is shown the way the language writes dates. }
  TDatePicker = class(TControl)
  private
    FDate: TDateTime;
    FPlaceholder: string;
    FPopup: TPopup;
    FCalendar: TCalendarView;
    FOnChange: TNotifyEvent;
    procedure SetDate(AValue: TDateTime);
    function GetDateText: string;
    procedure SetDateText(const AValue: string);
    procedure SetPlaceholder(const AValue: string);
    procedure Picked(Sender: TObject);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  public
    { Opens the calendar. }
    procedure DropDown;
    procedure CloseUp;
    function DroppedDown: Boolean;
    { No date. }
    procedure Clear;
    function HasDate: Boolean;
    { The date (without time); 0 when there is none. }
    property Date: TDateTime read FDate write SetDate;
    { The calendar while it is open. }
    property Calendar: TCalendarView read FCalendar;
  published
    { The date as '2026-11-01'; '' for none. For .pform files and data binding. }
    property DateText: string read GetDateText write SetDateText;
    { Shown when there is no date. }
    property Placeholder: string read FPlaceholder write SetPlaceholder;
    { The date changed. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { A whole number in an edit, with ▲▼ at the right edge: Up and Down (and the
    mouse wheel) change it by Step; only digits get in; leaving the edit puts
    it between Min and Max. }
  TNumberEdit = class(TEdit)
  private
    FMin, FMax, FStep: Integer;
    function GetValue: Integer;
    procedure SetValue(AValue: Integer);
    procedure SetMin(AValue: Integer);
    procedure SetMax(AValue: Integer);
  protected
    procedure Paint(C: TCanvas32); override;
    procedure MouseDown(X, Y: Integer); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure TextInput(const S: string); override;
    procedure FocusLost; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Adds Count * Step, staying between Min and Max. }
    procedure StepBy(Count: Integer);
  published
    { The number; Min when the text is empty or not a number. }
    property Value: Integer read GetValue write SetValue default 0;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 1000000;
    property Step: Integer read FStep write FStep default 1;
  end;

  { A time of day as HH:MM. Up and Down change it by Step minutes; '930' or
    '9' become 09:30 and 09:00 when the edit is left. }
  TTimeEdit = class(TEdit)
  private
    FStep: Integer;
    function GetMinutes: Integer;
    procedure SetMinutes(AValue: Integer);
  protected
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    procedure TextInput(const S: string); override;
    procedure FocusLost; override;
  public
    constructor Create(AOwner: TComponent); override;
    { A time is given (the text is a valid HH:MM). }
    function HasTime: Boolean;
    { The time as a TDateTime fraction (0.5 = 12:00); 0 without a time. }
    function Time: TDateTime;
    { Minutes since midnight (570 = 09:30); -1 without a time. }
    property Minutes: Integer read GetMinutes write SetMinutes;
  published
    { Minutes Up and Down add or take. }
    property Step: Integer read FStep write FStep default 15;
  end;

{ '930', '9:30', '09.30', '9' -> 570 (minutes); -1 when it is not a time. }
function ParseTimeOfDay(const S: string): Integer;

implementation

uses
  Math, Pastel.Lang;

{ ---- money ---- }

function TryParseMoney(const S: string; out Value: Currency): Boolean;
var
  T, Digits: string;
  I, Dec: Integer;
  Neg: Boolean;
begin
  Value := 0;
  T := '';
  Neg := False;
  { keep digits and separators; a - anywhere makes it negative }
  for I := 1 to Length(S) do
    case S[I] of
      '0'..'9', '.', ',': T := T + S[I];
      '-': Neg := True;
      ' ', #9: ;
    else
      if Ord(S[I]) < 128 then
        Exit(False);    { letters are not money; UTF-8 bytes (₺, €) are a symbol }
    end;
  if T = '' then
    Exit(False);
  { the decimal separator: the last . or , with at most two digits after it }
  Dec := 0;
  for I := Length(T) downto 1 do
    if T[I] in ['.', ','] then
    begin
      if Length(T) - I <= 2 then
        Dec := I;
      Break;
    end;
  Digits := '';
  for I := 1 to Length(T) do
    if T[I] in ['0'..'9'] then
      Digits := Digits + T[I]
    else if I = Dec then
      Digits := Digits + '.';
  Result := TryStrToCurr(Digits, Value, DefaultFormatSettings) or
    TryStrToCurr(StringReplace(Digits, '.', DefaultFormatSettings.DecimalSeparator, []), Value);
  if Result and Neg then
    Value := -Value;
end;

function FormatMoney(Value: Currency; Decimals: Integer; const Symbol: string): string;
begin
  Result := FormatNumber(Value, Decimals);
  if Symbol <> '' then
    Result := Result + ' ' + Symbol;
end;

{ ---- calendar ---- }

function MonthCells(Year, Month: Word): TMonthCells;
var
  First: TDateTime;
  I: Integer;
begin
  First := EncodeDate(Year, Month, 1);
  { ISO day of week: Monday 1 .. Sunday 7 }
  First := First - (DayOfTheWeek(First) - 1);
  for I := 0 to 41 do
    Result[I] := First + I;
end;

function MonthTitle(Year, Month: Word): string;
begin
  Result := MonthName(Month) + ' ' + IntToStr(Year);      { Pastel.Lang knows the names }
end;

function WeekdayShort(Index: Integer): string;
begin
  Result := DayNameShort(Index mod 7 + 1);
end;

function TryIsoToDate(const S: string; out D: TDateTime): Boolean;
var
  Y, M, Day: Integer;
begin
  Result := (Length(S) = 10) and (S[5] = '-') and (S[8] = '-') and
    TryStrToInt(Copy(S, 1, 4), Y) and TryStrToInt(Copy(S, 6, 2), M) and TryStrToInt(Copy(S, 9, 2), Day) and
    TryEncodeDate(Y, M, Day, D);
end;

function DateToIso(D: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd', D);
end;

{ ---- TCurrencyEdit ---- }

constructor TCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDecimals := 2;
end;

function TCurrencyEdit.GetValue: Currency;
begin
  if not TryParseMoney(Text, Result) then
    Result := 0;
end;

procedure TCurrencyEdit.SetValue(AValue: Currency);
begin
  Text := FormatMoney(AValue, FDecimals, FSymbol);
end;

function TCurrencyEdit.GetValid: Boolean;
var
  V: Currency;
begin
  Result := (Trim(Text) = '') or TryParseMoney(Text, V);
end;

procedure TCurrencyEdit.SetSymbol(const AValue: string);
begin
  FSymbol := AValue;
  Reformat;
end;

procedure TCurrencyEdit.SetDecimals(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > 4 then AValue := 4;
  FDecimals := AValue;
  Reformat;
end;

procedure TCurrencyEdit.Reformat;
var
  V: Currency;
begin
  if (Trim(Text) <> '') and TryParseMoney(Text, V) then
    Value := V;
end;

{ only what can be part of an amount gets in }
procedure TCurrencyEdit.TextInput(const S: string);
var
  I: Integer;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9', '.', ',', '-', ' '] then
      Clean := Clean + S[I];
  if Clean <> '' then
    inherited TextInput(Clean);
end;

procedure TCurrencyEdit.FocusLost;
begin
  inherited FocusLost;
  Reformat;
end;

const
  CellW = 38;
  CellH = 32;
  HeadH = 40;      { month title and arrows }
  DaysH = 24;      { Mo Tu We ... }

{ ---- TCalendarView ---- }

constructor TCalendarView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHover := -1;
  ShowDate(0);
end;

procedure TCalendarView.ShowDate(D: TDateTime);
var
  Dd: Word;
begin
  FSelected := Trunc(D);
  if D = 0 then
    D := SysUtils.Date;
  FCursor := Trunc(D);
  DecodeDate(FCursor, FYear, FMonth, Dd);
  Invalidate;
end;

procedure TCalendarView.MoveCursor(D: TDateTime);
var
  Dd: Word;
begin
  FCursor := Trunc(D);
  DecodeDate(FCursor, FYear, FMonth, Dd);
  Invalidate;
end;

procedure TCalendarView.NextMonth;
begin
  MoveCursor(IncMonth(FCursor, 1));
end;

procedure TCalendarView.PreviousMonth;
begin
  MoveCursor(IncMonth(FCursor, -1));
end;

procedure TCalendarView.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 7 * CellW;
  H := HeadH + DaysH + 6 * CellH;
end;

function TCalendarView.CellRect(Index: Integer): TRectI;
begin
  Result := RectI(Bounds.X + (Index mod 7) * CellW, Bounds.Y + HeadH + DaysH + (Index div 7) * CellH, CellW, CellH);
end;

function TCalendarView.CellAt(X, Y: Integer): Integer;
var
  Col, Row: Integer;
begin
  Result := -1;
  if Y < Bounds.Y + HeadH + DaysH then
    Exit;
  Col := (X - Bounds.X) div CellW;
  Row := (Y - Bounds.Y - HeadH - DaysH) div CellH;
  if (Col >= 0) and (Col < 7) and (Row >= 0) and (Row < 6) then
    Result := Row * 7 + Col;
end;

{ -1 previous month, 1 next month, 0 none }
function TCalendarView.HeaderButton(X, Y: Integer): Integer;
begin
  Result := 0;
  if (Y < Bounds.Y) or (Y >= Bounds.Y + HeadH) then
    Exit;
  if X < Bounds.X + CellW then
    Result := -1
  else if X >= Bounds.X + 6 * CellW then
    Result := 1;
end;

procedure TCalendarView.Paint(C: TCanvas32);
var
  F, B: TPastelFont;
  Cells: TMonthCells;
  I: Integer;
  R: TRectI;
  D: TDateTime;
  S, Title: string;
  Fg, Bg: TColor32;
  Y, M, Dd: Word;
begin
  F := GetFont(Theme.FontSize);
  B := GetFont(Theme.FontSize, True);
  { month title with ‹ and › }
  Title := MonthTitle(FYear, FMonth);
  C.DrawText(B, Bounds.X + (Bounds.W - B.TextWidth(Title)) div 2, Bounds.Y + (HeadH - B.LineHeight) div 2, Title,
    Theme.Text);
  C.DrawText(B, Bounds.X + (CellW - B.TextWidth('‹')) div 2, Bounds.Y + (HeadH - B.LineHeight) div 2, '‹',
    Theme.TextMuted);
  C.DrawText(B, Bounds.X + 6 * CellW + (CellW - B.TextWidth('›')) div 2, Bounds.Y + (HeadH - B.LineHeight) div 2, '›',
    Theme.TextMuted);
  for I := 0 to 6 do
  begin
    S := WeekdayShort(I);
    C.DrawText(F, Bounds.X + I * CellW + (CellW - F.TextWidth(S)) div 2, Bounds.Y + HeadH, S, Theme.TextMuted);
  end;
  Cells := MonthCells(FYear, FMonth);
  for I := 0 to 41 do
  begin
    D := Cells[I];
    R := CellRect(I);
    DecodeDate(D, Y, M, Dd);
    Fg := Theme.Text;
    Bg := 0;
    if M <> FMonth then
      Fg := Theme.Placeholder;
    if D = FSelected then
    begin
      Bg := Theme.Accent;
      Fg := Theme.OnAccent;
    end
    else if (D = FCursor) and IsFocused then
      Bg := Theme.SecondaryPressed
    else if I = FHover then
      Bg := Theme.SecondaryHover;
    if Bg <> 0 then
      C.FillRoundRect(R.X + 2, R.Y + 2, R.W - 4, R.H - 4, 6, Bg);
    if D = Trunc(SysUtils.Date) then
      C.StrokeRoundRect(R.X + 2, R.Y + 2, R.W - 4, R.H - 4, 6, 1, Theme.Accent);
    S := IntToStr(Dd);
    C.DrawText(F, R.X + (R.W - F.TextWidth(S)) div 2, R.Y + (R.H - F.LineHeight) div 2, S, Fg);
  end;
end;

function TCalendarView.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TCalendarView.Cursor: TCursorKind;
begin
  Result := ckHand;
end;

procedure TCalendarView.MouseDown(X, Y: Integer);
var
  I: Integer;
  Cells: TMonthCells;
begin
  case HeaderButton(X, Y) of
    -1: PreviousMonth;
    1: NextMonth;
  else
    I := CellAt(X, Y);
    if I < 0 then
      Exit;
    Cells := MonthCells(FYear, FMonth);
    FSelected := Cells[I];
    MoveCursor(FSelected);
    if Assigned(FOnPick) then
      FOnPick(Self);
  end;
end;

procedure TCalendarView.MouseMove(X, Y: Integer);
var
  I: Integer;
begin
  I := CellAt(X, Y);
  if I <> FHover then
  begin
    FHover := I;
    Invalidate;
  end;
end;

function TCalendarView.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := True;
  case Key of
    KEY_LEFT: MoveCursor(FCursor - 1);
    KEY_RIGHT: MoveCursor(FCursor + 1);
    KEY_UP: MoveCursor(FCursor - 7);
    KEY_DOWN: MoveCursor(FCursor + 7);
    KEY_PAGEUP: PreviousMonth;
    KEY_PAGEDOWN: NextMonth;
    KEY_HOME: MoveCursor(StartOfTheMonth(FCursor));
    KEY_END: MoveCursor(Trunc(EndOfTheMonth(FCursor)));
    KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
      begin
        FSelected := FCursor;
        Invalidate;
        if Assigned(FOnPick) then
          FOnPick(Self);
      end;
  else
    Result := False;
  end;
end;

{ ---- TDatePicker ---- }

procedure TDatePicker.SetDate(AValue: TDateTime);
begin
  AValue := Trunc(AValue);
  if FDate = AValue then
    Exit;
  FDate := AValue;
  Invalidate;
  if Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

function TDatePicker.GetDateText: string;
begin
  if FDate = 0 then
    Result := ''
  else
    Result := DateToIso(FDate);
end;

procedure TDatePicker.SetDateText(const AValue: string);
var
  D: TDateTime;
begin
  if Trim(AValue) = '' then
    Date := 0
  else if TryIsoToDate(Trim(AValue), D) then
    Date := D
  else
    raise EConvertError.CreateFmt('"%s" is not a date like 2026-11-01', [AValue]);
end;

procedure TDatePicker.SetPlaceholder(const AValue: string);
begin
  FPlaceholder := AValue;
  Invalidate;
end;

procedure TDatePicker.Clear;
begin
  Date := 0;
end;

function TDatePicker.HasDate: Boolean;
begin
  Result := FDate <> 0;
end;

procedure TDatePicker.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 180;
  H := GetFont(Theme.FontSize).LineHeight + 20;
end;

procedure TDatePicker.Paint(C: TCanvas32);
var
  F: TPastelFont;
  S: string;
  Col, Border: TColor32;
  IX, IY: Integer;
begin
  F := GetFont(Theme.FontSize);
  if IsFocused then
  begin
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6, Theme.Radius + 3, Theme.FocusRing);
    Border := Theme.Accent;
  end
  else if IsHovered and Enabled then
    Border := Theme.BorderHover
  else
    Border := Theme.Border;
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);
  C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Border);
  if FDate <> 0 then
  begin
    S := FormatDateShort(FDate);
    Col := Theme.Text;
  end
  else
  begin
    S := FPlaceholder;
    Col := Theme.Placeholder;
  end;
  if not Enabled then
    Col := Theme.Disabled;
  C.DrawText(F, Bounds.X + 12, Bounds.Y + (Bounds.H - F.LineHeight) div 2, S, Col);
  { a small calendar icon }
  IX := Bounds.X + Bounds.W - 30;
  IY := Bounds.Y + (Bounds.H - 16) div 2;
  C.StrokeRoundRect(IX, IY + 2, 18, 14, 2, 1.5, Theme.TextMuted);
  C.FillRect(IX, IY + 2, 18, 4, Theme.TextMuted);
  C.FillRect(IX + 4, IY, 2, 4, Theme.TextMuted);
  C.FillRect(IX + 12, IY, 2, 4, Theme.TextMuted);
end;

function TDatePicker.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TDatePicker.Cursor: TCursorKind;
begin
  Result := ckHand;
end;

function TDatePicker.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.Shown and not FPopup.Closed;
end;

procedure TDatePicker.DropDown;
var
  F: TForm;
begin
  F := ParentForm;
  if (F = nil) or DroppedDown or not Enabled then
    Exit;
  if FPopup = nil then
  begin
    FPopup := TPopup.Create(Self);
    FPopup.Padding := 8;
    FCalendar := TCalendarView.Create(FPopup);
    FCalendar.Name := 'Calendar';         { test scripts: click Calendar x y }
    FCalendar.Parent := FPopup;
    FCalendar.OnPick := @Picked;
  end;
  FCalendar.ShowDate(FDate);
  FPopup.Popup(F, Bounds);
  FCalendar.SetFocus;
end;

procedure TDatePicker.CloseUp;
begin
  if DroppedDown then
    FPopup.Close;
  SetFocus;
end;

procedure TDatePicker.Picked(Sender: TObject);
begin
  Date := FCalendar.Selected;
  CloseUp;
end;

procedure TDatePicker.MouseDown(X, Y: Integer);
begin
  if DroppedDown then
    CloseUp
  else
    DropDown;
end;

function TDatePicker.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := True;
  case Key of
    KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F1 + 3: DropDown;
    KEY_DOWN: if KeyAlt then DropDown else if FDate = 0 then Date := SysUtils.Date else Date := FDate + 1;
    KEY_UP: if FDate = 0 then Date := SysUtils.Date else Date := FDate - 1;
    KEY_DELETE, KEY_BACKSPACE: Clear;
  else
    Result := False;
  end;
end;

{ ---- TNumberEdit ---- }

constructor TNumberEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMax := 1000000;
  FStep := 1;
end;

function TNumberEdit.GetValue: Integer;
begin
  Result := StrToIntDef(Trim(Text), FMin);
  Result := EnsureRange(Result, FMin, FMax);
end;

procedure TNumberEdit.SetValue(AValue: Integer);
begin
  Text := IntToStr(EnsureRange(AValue, FMin, FMax));
end;

procedure TNumberEdit.SetMin(AValue: Integer);
begin
  FMin := AValue;
  if FMax < FMin then
    FMax := FMin;
end;

procedure TNumberEdit.SetMax(AValue: Integer);
begin
  FMax := AValue;
  if FMin > FMax then
    FMin := FMax;
end;

procedure TNumberEdit.StepBy(Count: Integer);
begin
  Value := GetValue + Count * FStep;
  SelectAll;
end;

procedure TNumberEdit.Paint(C: TCanvas32);
var
  X, CY: Integer;
  Col: TColor32;
begin
  inherited Paint(C);
  X := Bounds.X + Bounds.W - 20;
  CY := Bounds.Y + Bounds.H div 2;
  if Enabled then Col := Theme.TextMuted else Col := Theme.Disabled;
  C.FillRect(X - 6, Bounds.Y + 4, 1, Bounds.H - 8, Theme.Border);
  { ▲ and ▼ as small lines }
  C.DrawLine(X + 2, CY - 3, X + 6, CY - 7, 1.5, Col);
  C.DrawLine(X + 6, CY - 7, X + 10, CY - 3, 1.5, Col);
  C.DrawLine(X + 2, CY + 3, X + 6, CY + 7, 1.5, Col);
  C.DrawLine(X + 6, CY + 7, X + 10, CY + 3, 1.5, Col);
end;

procedure TNumberEdit.MouseDown(X, Y: Integer);
begin
  if Enabled and not ReadOnly and (X >= Bounds.X + Bounds.W - 26) then
  begin
    SetFocus;
    if Y < Bounds.Y + Bounds.H div 2 then
      StepBy(1)
    else
      StepBy(-1);
    Exit;
  end;
  inherited MouseDown(X, Y);
end;

function TNumberEdit.MouseWheel(DX, DY: Integer): Boolean;
begin
  Result := IsFocused and not ReadOnly and (DY <> 0);
  if Result then
    StepBy(DY);
end;

function TNumberEdit.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := True;
  if not ReadOnly then
    case Key of
      KEY_UP: begin StepBy(1); Exit; end;
      KEY_DOWN: begin StepBy(-1); Exit; end;
      KEY_PAGEUP: begin StepBy(10); Exit; end;
      KEY_PAGEDOWN: begin StepBy(-10); Exit; end;
    end;
  Result := inherited KeyDown(Key, Shift, Ctrl);
end;

procedure TNumberEdit.TextInput(const S: string);
var
  I: Integer;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(S) do
    if (S[I] in ['0'..'9']) or ((S[I] = '-') and (FMin < 0)) then
      Clean := Clean + S[I];
  if Clean <> '' then
    inherited TextInput(Clean);
end;

procedure TNumberEdit.FocusLost;
begin
  inherited FocusLost;
  if Trim(Text) <> '' then
    Value := GetValue;
end;

{ ---- TTimeEdit ---- }

function ParseTimeOfDay(const S: string): Integer;
var
  T, H, M: string;
  P, HH, MM: Integer;
begin
  Result := -1;
  T := Trim(S);
  P := Pos(':', T);
  if P = 0 then
    P := Pos('.', T);
  if P > 0 then
  begin
    H := Copy(T, 1, P - 1);
    M := Copy(T, P + 1, MaxInt);
  end
  else if Length(T) <= 2 then
  begin
    H := T;
    M := '0';
  end
  else
  begin
    H := Copy(T, 1, Length(T) - 2);
    M := Copy(T, Length(T) - 1, 2);
  end;
  if TryStrToInt(H, HH) and TryStrToInt(M, MM) and (HH >= 0) and (HH <= 23) and (MM >= 0) and (MM <= 59) then
    Result := HH * 60 + MM;
end;

constructor TTimeEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStep := 15;
  Placeholder := 'HH:MM';
end;

function TTimeEdit.GetMinutes: Integer;
begin
  Result := ParseTimeOfDay(Text);
end;

procedure TTimeEdit.SetMinutes(AValue: Integer);
begin
  if AValue < 0 then
    Text := ''
  else
  begin
    AValue := AValue mod (24 * 60);
    Text := Format('%.2d:%.2d', [AValue div 60, AValue mod 60]);
  end;
end;

function TTimeEdit.HasTime: Boolean;
begin
  Result := GetMinutes >= 0;
end;

function TTimeEdit.Time: TDateTime;
begin
  if HasTime then
    Result := GetMinutes / (24 * 60)
  else
    Result := 0;
end;

function TTimeEdit.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  M: Integer;
begin
  if not ReadOnly and ((Key = KEY_UP) or (Key = KEY_DOWN)) then
  begin
    M := GetMinutes;
    if M < 0 then
      M := 9 * 60
    else if Key = KEY_UP then
      M := (M div FStep + 1) * FStep
    else
      M := ((M + FStep - 1) div FStep - 1) * FStep;
    if M < 0 then
      Inc(M, 24 * 60);
    Minutes := M;
    SelectAll;
    Exit(True);
  end;
  Result := inherited KeyDown(Key, Shift, Ctrl);
end;

function TTimeEdit.MouseWheel(DX, DY: Integer): Boolean;
begin
  Result := IsFocused and (DY <> 0);
  if Result then
    if DY > 0 then KeyDown(KEY_UP, False, False) else KeyDown(KEY_DOWN, False, False);
end;

procedure TTimeEdit.TextInput(const S: string);
var
  I: Integer;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9', ':', '.'] then
      Clean := Clean + S[I];
  if Clean <> '' then
    inherited TextInput(Clean);
end;

procedure TTimeEdit.FocusLost;
begin
  inherited FocusLost;
  if HasTime then
    Minutes := GetMinutes;
end;

initialization
  RegisterControl(TCurrencyEdit);
  RegisterControl(TDatePicker);
  RegisterControl(TCalendarView);
  RegisterControl(TNumberEdit);
  RegisterControl(TTimeEdit);
end.
