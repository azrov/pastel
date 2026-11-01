{ TDatePicker - a date, chosen from a calendar.

    object DueDate: TDatePicker
      DateText = '2026-11-01'           // or empty: no date yet
      Placeholder = 'Due date'
      OnChange = DueDateChange
    end

    if DueDate.HasDate then
      Days := DaysBetween(Date, DueDate.Date);
    DueDate.Date := Date + 30;

  A click, Enter, Space or Alt+Down opens the calendar: arrows move by days
  and weeks, Page Up/Down by months, Enter or a click chooses, Escape closes.
  Delete empties it. The date is shown the way the language writes dates.
  An example of a control with a popup: TDatePicker opens a TPopup with a
  TCalendarView in it. }
unit DatePicker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Pastel.Graphics, Pastel.UI;

type
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

implementation

uses
  Calendar, Pastel.Lang;

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

initialization
  RegisterControl(TDatePicker);
  RegisterControl(TCalendarView);
end.
