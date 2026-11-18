# Pastel.Binding

Data binding: fills a form's controls from a record and back.

    object PersonData: TDataBinding
      Fields = ('NameEdit', 'EmailEdit', 'ActiveCheck', 'AgeSlider=age_years')
    end

    PersonData.Load(Db.QueryOne('select * from people where id = ?', [Id]));
    ...
    Row := TJSONObject.Create;
    PersonData.Save(Row);            // name, email, active, age_years
    if PersonData.Modified then ...

  Rules check the values before they are saved:

    object PersonData: TDataBinding
      Fields = ('NameEdit', 'EmailEdit', 'AgeEdit')
      Rules = ('NameEdit=required', 'EmailEdit=email', 'AgeEdit=number, range 0..120')
      ErrorLabel = ProblemLabel
    end

    if not PersonData.Validate then Exit;      // the first wrong control is focused

  'NameEdit' alone binds the field 'name' (the name without the control's
  kind, in snake_case: FullNameEdit -> full_name). An edit or memo shows the
  value as text, a check box or switch a boolean, a slider or progress bar
  a number, a combo box its text, a list box the selected item.
  Load and Save also work with objects (their published properties) and
  with a row of a TGrid (columns by Field or Title).

`uses Pastel.Binding;` · source: [framework/src/pastel.binding.pas](../../framework/src/pastel.binding.pas)

## Types

### EBindingError

```pascal
type EBindingError = class(Exception)
```

### TDataBinding

```pascal
type TDataBinding = class(TComponent)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `function ControlOf(Index: Integer): TControl` | The control of a binding line. |
| `function FieldOf(Index: Integer): string` | The field of a binding line. |
| `procedure Bind(Control: TControl; const Field: string = '')` | Adds a binding from code; Field '' derives it from the name. |
| `function GetValue(Control: TControl): string` | The control's value as text / sets it from text. |
| `procedure SetValue(Control: TControl; const Value: string)` |  |
| `procedure Load(Data: TJSONObject)` | Fills the controls from the object's fields (missing ones: empty). |
| `procedure Save(Data: TJSONObject)` | Writes the controls into Data, replacing those fields. |
| `procedure LoadObject(Obj: TObject)` | The same with an object's published properties. |
| `procedure SaveObject(Obj: TObject)` |  |
| `procedure LoadRow(Grid: TControl; Row: Integer)` | The same with a row of a grid (Pastel.Grids). |
| `procedure SaveRow(Grid: TControl; Row: Integer)` |  |
| `procedure Clear` | Empties all bound controls (a new record). |
| `function ToJson: TJSONObject` | A new JSON object with the controls' values; the caller frees it. |
| `procedure MarkSaved` | The current values count as saved: Modified is False. |
| `property Modified: Boolean` | The user changed a value since the last Load or MarkSaved. |
| `function Validate: Boolean` | Checks every control that has Rules (and OnValidate): the wrong ones get a red border and the problem as their tooltip, the first one the focus, and ErrorLabel its message. False when something is wrong. |
| `property Problems: TStringList` | After Validate: ControlName=message for every problem. |
| `procedure Notification(AComponent: TComponent; Operation: TOperation)` |  |
| `property Rules: TStrings` | 'ControlName=rule, rule', one per control: required, email, number, integer, range 1..10, min 3 (characters), max 50, pattern ^[A-Z][A-Z]\d+$ (last, as it may have commas). |
| `property ErrorLabel: TControl` | A label that shows the first problem (and is emptied when all is fine). |
| `property OnValidate: TValidateEvent` |  |
| `property Fields: TStrings` | 'ControlName' or 'ControlName=field', one per line. |
| `property OnLoad: TNotifyEvent` |  |

## Other types

| | |
|---|---|
| `type TValidateEvent = procedure(Sender: TObject; Control: TControl; Value: string; Message: string)` | A check of one's own: set Message to what is wrong ('' when it is fine). |

## Routines

### FieldFromControlName

```pascal
function FieldFromControlName(const Name: string): string
```

FullNameEdit -> full_name

