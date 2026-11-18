# Pastel.Menus

Menus: a menu bar, pop-up (right click) menus and keyboard
  shortcuts.

    object MainMenu: TMenuBar
      object FileMenu: TMenuItem
        Caption = 'File'
        object OpenItem: TMenuItem
          Caption = 'Open...'
          ShortCut = 'Ctrl+O'
          OnClick = OpenClick
        end
        object Sep1: TMenuItem
          Caption = '-'
        end
      end
    end

  A TPopupMenu holds TMenuItems too; a control shows it on a right click
  when its PopupMenu names it. Shortcuts work while the window has the
  keyboard, also when the menu is closed; TAction shortcuts too.

`uses Pastel.Menus;` · source: [framework/src/pastel.menus.pas](../../framework/src/pastel.menus.pas)

**Contents:** [TMenuItem](#tmenuitem) · [TMenuBar](#tmenubar) · [TPopupMenu](#tpopupmenu) · [TMenuView](#tmenuview) · [MenuItemRect](#menuitemrect) · [ParseShortCut](#parseshortcut) · [HandleShortCut](#handleshortcut)

## Types

### TMenuItem

```pascal
type TMenuItem = class(TControl)
```

One command of a menu; items inside it make a submenu. Caption '-' is a line.

| | |
|---|---|
| `procedure Notification(AComponent: TComponent; Operation: TOperation)` |  |
| `procedure Click` | Runs OnClick (or the action). |
| `function IsSeparator: Boolean` |  |
| `function HasSubmenu: Boolean` |  |
| `function DisplayCaption: string` | Caption, ShortCut, Enabled and Checked, from the action when there is one. |
| `function DisplayShortCut: string` |  |
| `function IsEnabled: Boolean` |  |
| `function IsChecked: Boolean` |  |
| `function DisplayIcon: string` | Icon, or the action's icon |
| `property Caption: string` |  |
| `property ShortCut: string` | Like 'Ctrl+S', 'Ctrl+Shift+Z', 'F5', 'Delete'. |
| `property Checked: Boolean` |  |
| `property Icon: string` | A built-in icon before the caption ('save', 'print'...; Pastel.Icons); the action's when empty. |
| `property Action: TBasicAction` |  |
| `property OnClick: TNotifyEvent` |  |

### TMenuBar

```pascal
type TMenuBar = class(TControl)
```

The bar with menus at the top of a window (put it first, in a form with Padding = 0).

| | |
|---|---|
| `class function DesktopOnly: Boolean` |  |
| `destructor Destroy` |  |
| `procedure OpenMenu(Item: TMenuItem)` | Opens the menu of a top-level item (keyboard: Alt and F10 open the first). |
| `procedure CloseMenu` |  |
| `function OpenItem: TMenuItem` |  |

### TPopupMenu

```pascal
type TPopupMenu = class(TControl)
```

A menu shown at the mouse, from a control's PopupMenu or from code.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Popup(Form: TForm; X: Integer; Y: Integer)` | Shows the menu at a point of the form. |

### TMenuView

```pascal
type TMenuView = class(TPopup)
```

The open list of a menu (internal).

| | |
|---|---|
| `constructor CreateFor(AOwner: TComponent; ASource: TControl)` |  |
| `destructor Destroy` |  |
| `procedure CloseAll` | Closes this view, its submenus and the views it came from. |

## Routines

### MenuItemRect

```pascal
function MenuItemRect(Item: TMenuItem; out R: TRectI): Boolean
```

Where an item of an open menu is shown (for test scripts); False when it is not shown.

### ParseShortCut

```pascal
function ParseShortCut(const S: string; out Key: LongInt; out Shift: Boolean; out Ctrl: Boolean; out Alt: Boolean): Boolean
```

Parses 'Ctrl+Shift+S' into a key and modifiers; False when it is not a shortcut.

### HandleShortCut

```pascal
function HandleShortCut(Form: TForm; Key: LongInt; Shift: Boolean; Ctrl: Boolean): Boolean
```

Runs the menu item or action of the form whose shortcut is this key.

