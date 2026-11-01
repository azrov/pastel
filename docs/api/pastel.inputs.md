# Pastel.Inputs

Inputs for business apps: dates, amounts of money, numbers and times.

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

`uses Pastel.Inputs;` · source: [framework/src/pastel.inputs.pas](../../framework/src/pastel.inputs.pas)

**Contents:** [TCurrencyEdit](#tcurrencyedit) · [TCalendarView](#tcalendarview) · [TDatePicker](#tdatepicker) · [TNumberEdit](#tnumberedit) · [TTimeEdit](#ttimeedit) · [TryParseMoney](#tryparsemoney) · [FormatMoney](#formatmoney) · [MonthCells](#monthcells) · [MonthTitle](#monthtitle) · [WeekdayShort](#weekdayshort) · [TryIsoToDate](#tryisotodate) · [DateToIso](#datetoiso) · [ParseTimeOfDay](#parsetimeofday)

## Types

### TCurrencyEdit

```pascal
type TCurrencyEdit = class(TEdit)
```

An edit for amounts of money: Value is a Currency; people may type
'1234,5', '1.234,50' or '1234.50', and when they leave the edit it shows
the amount the way their language writes it ('1.234,50 ₺').

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Value: Currency` | The amount; 0 when the text is empty or not an amount (see Valid). |
| `property Valid: Boolean` | The text is empty or an amount. |
| `procedure Reformat` | Writes the text again in the language's way (done when the focus leaves). |
| `property Symbol: string` | Shown after the amount: '₺', '€', 'USD' |
| `property Decimals: Integer` | Digits after the decimal separator. |

### TCalendarView

```pascal
type TCalendarView = class(TControl)
```

The month view in the popup; a control of its own, usable alone too.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure ShowDate(D: TDateTime)` | Shows the month of D, with D chosen (0: today, nothing chosen). |
| `procedure NextMonth` |  |
| `procedure PreviousMonth` |  |
| `property Selected: TDateTime` |  |
| `property Year: Word` |  |
| `property Month: Word` |  |
| `property OnPick: TNotifyEvent` | A day was chosen (click or Enter). |

### TDatePicker

```pascal
type TDatePicker = class(TControl)
```

A date, chosen from a calendar (a TPopup with a TCalendarView). A click,
Enter, Space or Alt+Down opens it: arrows move by days and weeks, Page
Up/Down by months, Enter or a click chooses, Escape closes; Delete empties
it. The date is shown the way the language writes dates.

| | |
|---|---|
| `procedure DropDown` | Opens the calendar. |
| `procedure CloseUp` |  |
| `function DroppedDown: Boolean` |  |
| `procedure Clear` | No date. |
| `function HasDate: Boolean` |  |
| `property Date: TDateTime` | The date (without time); 0 when there is none. |
| `property Calendar: TCalendarView` | The calendar while it is open. |
| `property DateText: string` | The date as '2026-11-01'; '' for none. For .pform files and data binding. |
| `property Placeholder: string` | Shown when there is no date. |
| `property OnChange: TNotifyEvent` | The date changed. |

### TNumberEdit

```pascal
type TNumberEdit = class(TEdit)
```

A whole number in an edit, with ▲▼ at the right edge: Up and Down (and the
mouse wheel) change it by Step; only digits get in; leaving the edit puts
it between Min and Max.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure StepBy(Count: Integer)` | Adds Count * Step, staying between Min and Max. |
| `property Value: Integer` | The number; Min when the text is empty or not a number. |
| `property Min: Integer` |  |
| `property Max: Integer` |  |
| `property Step: Integer` |  |

### TTimeEdit

```pascal
type TTimeEdit = class(TEdit)
```

A time of day as HH:MM. Up and Down change it by Step minutes; '930' or
'9' become 09:30 and 09:00 when the edit is left.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function HasTime: Boolean` | A time is given (the text is a valid HH:MM). |
| `function Time: TDateTime` | The time as a TDateTime fraction (0.5 = 12:00); 0 without a time. |
| `property Minutes: Integer` | Minutes since midnight (570 = 09:30); -1 without a time. |
| `property Step: Integer` | Minutes Up and Down add or take. |

## Other types

| | |
|---|---|
| `type TMonthCells = array [0 ..41] of TDateTime` | 6 weeks x 7 days, Monday first: the month with the end of the one before and the start of the one after |

## Routines

### TryParseMoney

```pascal
function TryParseMoney(const S: string; out Value: Currency): Boolean
```

'1.234,50', '1234.5', '1 234,50 ₺' -> 1234.5; False when it is not an amount. The
last . or , followed by one or two digits is the decimal separator.

### FormatMoney

```pascal
function FormatMoney(Value: Currency; Decimals: Integer = 2; const Symbol: string = ''): string
```

1234.5 -> '1.234,50' with Pastel.Lang's separators, the symbol after it when given.

### MonthCells

```pascal
function MonthCells(Year: Word; Month: Word): TMonthCells
```

### MonthTitle

```pascal
function MonthTitle(Year: Word; Month: Word): string
```

'November 2026' in the language of the program

### WeekdayShort

```pascal
function WeekdayShort(Index: Integer): string
```

'Mo'..'Su'

### TryIsoToDate

```pascal
function TryIsoToDate(const S: string; out D: TDateTime): Boolean
```

'2026-11-01' <-> date; False for anything else

### DateToIso

```pascal
function DateToIso(D: TDateTime): string
```

### ParseTimeOfDay

```pascal
function ParseTimeOfDay(const S: string): Integer
```

'930', '9:30', '09.30', '9' -> 570 (minutes); -1 when it is not a time.

