# Pastel.PForm

Reader for .pform files.

  A .pform file describes a form as a tree of objects, like Delphi's .dfm:

    object MainForm: TMainForm
      Title = 'Hello'
      object SendButton: TButton
        Text = 'Send'
        OnClick = SendClick
      end
    end

  Values are 'strings' (with '' for a quote), numbers, or identifiers
  (True/False, enum values, event handler names). Comments: // and braces.
  Used both by the pastel tool (code generation) and by apps (loading).
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.

`uses Pastel.PForm;` · source: [framework/src/pastel.pform.pas](../../framework/src/pastel.pform.pas)

**Contents:** [EPFormError](#epformerror) · [TPFormValueKind](#tpformvaluekind) · [TPFormProp](#tpformprop) · [TPFormNode](#tpformnode) · [ParsePForm](#parsepform) · [ParsePFormFile](#parsepformfile) · [VisitPForm](#visitpform)

## Types

### EPFormError

```pascal
type EPFormError = class(Exception)
```

| | |
|---|---|
| `constructor CreateAt(ALine: Integer; const Msg: string)` |  |

### TPFormValueKind

```pascal
type TPFormValueKind = (pvString, pvNumber, pvIdent, pvList)
```

pvList: ('a', 'b'); Value holds the items, one per line (#10 between)

- `pvString` pvList: ('a', 'b'); Value holds the items, one per line (#10 between)
- `pvNumber` pvList: ('a', 'b'); Value holds the items, one per line (#10 between)
- `pvIdent` pvList: ('a', 'b'); Value holds the items, one per line (#10 between)
- `pvList` pvList: ('a', 'b'); Value holds the items, one per line (#10 between)
### TPFormProp

```pascal
type TPFormProp = class
```

### TPFormNode

```pascal
type TPFormNode = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `function Prop(Index: Integer): TPFormProp` |  |
| `function Child(Index: Integer): TPFormNode` |  |
| `function FindProp(const AName: string): TPFormProp` |  |

## Other types

| | |
|---|---|
| `type TPFormVisitor = procedure(Node: TPFormNode; Data: Pointer)` |  |

## Routines

### ParsePForm

```pascal
function ParsePForm(const Src: string): TPFormNode
```

Parses a .pform source. Raises EPFormError with a line number on errors.

### ParsePFormFile

```pascal
function ParsePFormFile(const FileName: string): TPFormNode
```

### VisitPForm

```pascal
procedure VisitPForm(Root: TPFormNode; Proc: TPFormVisitor; Data: Pointer)
```

