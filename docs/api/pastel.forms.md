# Pastel.Forms

Building forms from .pform data.

  The code Pastel generates for each .pform file registers the form's source
  here. When a form is created, its controls are built from that source and
  properties and events are set through RTTI, like Delphi does with .dfm.
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.

`uses Pastel.Forms;` · source: [framework/src/pastel.forms.pas](../../framework/src/pastel.forms.pas)

**Contents:** [TFormSource](#tformsource) · [RegisterFormSource](#registerformsource) · [FindFormSource](#findformsource) · [RegisterFormView](#registerformview) · [ViewForScreen](#viewforscreen) · [ApplyFormView](#applyformview) · [FormViewFilesText](#formviewfilestext) · [CaptureState](#capturestate) · [RestoreState](#restorestate) · [BuildForm](#buildform)

## Types

### TFormSource

```pascal
type TFormSource = class
```

| | |
|---|---|
| `destructor Destroy` |  |

## Routines

### RegisterFormSource

```pascal
procedure RegisterFormSource(const AFormClassName: string; const ASource: string; const AFilePath: string)
```

Called by generated code.

### FindFormSource

```pascal
function FindFormSource(Form: TForm): TFormSource
```

The registered source for a form, searching its class hierarchy.

### RegisterFormView

```pascal
procedure RegisterFormView(const AFormClassName: string; const AView: string; const ASource: string; const AFilePath: string)
```

Called by generated code: a view of a form (Home.tablet.pform): property
values for one kind of screen. View: phone, tablet, desktop or tv.

### ViewForScreen

```pascal
function ViewForScreen(Form: TForm; AClass: TScreenClass): string
```

The view a form uses on a kind of screen ('' for none): its own, or tablet for a TV without one.

### ApplyFormView

```pascal
procedure ApplyFormView(Form: TForm; AClass: TScreenClass)
```

Applies the form's view for the kind of screen: the values the view sets
replace the form's (and come back when another kind of screen has no view).

### FormViewFilesText

```pascal
function FormViewFilesText(Form: TForm): string
```

The texts of the form's view files on disk (hot reload watches them).

### CaptureState

```pascal
function CaptureState(Form: TForm): TStringList
```

What the user changed in the controls (typed text, checked boxes, chosen
items, the page of tabs), by control name; hot reload puts it back.

### RestoreState

```pascal
procedure RestoreState(Form: TForm; State: TStringList)
```

### BuildForm

```pascal
procedure BuildForm(Form: TForm; Root: TPFormNode)
```

Creates the controls described by Root on Form, then binds fields.
Raises EPFormError on problems (unknown type, property or event).

