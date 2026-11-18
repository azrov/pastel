# Pastel.Accessibility

Screen readers: what is on the screen, for people who cannot see it.

  Pastel draws its controls itself, so it tells the system what they are: on
  Android TalkBack reads each control (its kind, its text, checked or not),
  and a double tap clicks it - nothing to do in the app. A control whose text
  does not say what it does gets an AccessibleName:

    object DeleteButton: TButton
      Icon = 'trash'
      AccessibleName = 'Delete the appointment'
    end

  Computers: Windows' Narrator and Linux's Orca are not reached yet.

`uses Pastel.Accessibility;` · source: [framework/src/pastel.accessibility.pas](../../framework/src/pastel.accessibility.pas)

## Other types

| | |
|---|---|
| `type TPixelRectFunc = function(R: TRectI): TRectI` |  |

## Routines

### AccessibilityTree

```pascal
function AccessibilityTree(Form: TForm; Pixels: TPixelRectFunc): string
```

The controls a screen reader sees, a line each:
id, parent's id, x, y, w, h (pixels), role (Android's class), text, hint, flags.

### AccessibleControl

```pascal
function AccessibleControl(Id: Integer): TControl
```

The control of an id of the tree (nil: it is gone).

### AccessibilityAction

```pascal
procedure AccessibilityAction(Form: TForm; Id: Integer; Action: Integer)
```

A screen reader's action: 16 click, 1 focus, 4096 scroll forward, 8192 back (Android's numbers).

### AccessibleInfo

```pascal
procedure AccessibleInfo(C: TControl; out Role: string; out Text: string; out Hint: string; out Flags: string)
```

The role and the text a screen reader gets for a control.

