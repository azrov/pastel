# Pastel.Forms

Building forms from .pform data.

  The code Pastel generates for each .pform file registers the form's source
  here. When a form is created, its controls are built from that source and
  properties and events are set through RTTI, like Delphi does with .dfm.
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.

`uses Pastel.Forms;` · source: [framework/src/pastel.forms.pas](../../framework/src/pastel.forms.pas)

**Contents:** [TFormSource](#tformsource) · [TFrame](#tframe) · [RegisterFormSource](#registerformsource) · [FindFormSource](#findformsource) · [RegisterFormView](#registerformview) · [ViewForScreen](#viewforscreen) · [ApplyFormView](#applyformview) · [FormViewFilesText](#formviewfilestext) · [CaptureState](#capturestate) · [RestoreState](#restorestate) · [FormStateText](#formstatetext) · [RestoreFormStateText](#restoreformstatetext) · [BuildForm](#buildform) · [RefreshFrameSources](#refreshframesources)

## Types

### TFormSource

```pascal
type TFormSource = class
```

| | |
|---|---|
| `destructor Destroy` |  |

### TFrame

```pascal
type TFrame = class(TColumn)
```

A part of forms with a .pform and code of its own, used on many forms:
an address block, a customer card. Its .pform starts like a form's, with a
type whose name ends in Frame:
// Address.pform
object AddressFrame: TAddressFrame
object StreetEdit: TEdit
end
end
and a form puts it where it wants it, as often as it wants:
object Billing: TAddressFrame
end
object Shipping: TAddressFrame
end
Its controls are its own (Billing.StreetEdit, Shipping.StreetEdit); its
events go to its own methods. "pastel new frame Address" makes one.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `constructor CreateFor(AOwner: TComponent; const AClassName: string)` | a frame of a type the program does not have (the designer's preview): built from that type's .pform |
| `procedure BindControls` | Called after the controls are made: the generated code fills its fields. |
| `function BindControl(const AName: string; AClass: TControlClass): TControl` |  |
| `function BindComponent(const AName: string; AClass: TComponentClass): TComponent` |  |
| `function FrameClassName: string` | its type as the .pform says it (TAddressFrame) |

## Other types

| | |
|---|---|
| `type TFormFetcher = function(FilePath: string; Lines: TStrings): Boolean` | reads a .pform file (on a phone: from the computer); False when it cannot |

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

### FormStateText

```pascal
function FormStateText(Form: TForm): string
```

The form's state as one text, for a phone that stops the app in the
background: what is in its controls, and its SaveState (after OnSaveState).

### RestoreFormStateText

```pascal
procedure RestoreFormStateText(Form: TForm; const Text: string)
```

That text back into the form (its controls, its SaveState).

### BuildForm

```pascal
procedure BuildForm(Form: TForm; Root: TPFormNode)
```

Creates the controls described by Root on Form, then binds fields.
Raises EPFormError on problems (unknown type, property or event).

### RefreshFrameSources

```pascal
function RefreshFrameSources(Fetch: TFormFetcher = nil): Boolean
```

Hot reload of frames: reads the .pform files of the frames again (Fetch reads
a file on a phone); True when one changed (their forms are then built again).

