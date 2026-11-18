# Pastel.Tray

A desktop app in the system tray, and keys that work everywhere.

    object Tray: TTrayIcon
      Hint = 'Salon - 3 appointments today'
      Menu = ('Open', 'Sync now', '-', 'Quit')
      OnMenuItem = TrayMenuItem
      OnClick = TrayClick                    // Windows: a click on the icon
    end

    RegisterHotKey('Ctrl+Shift+S', @QuickSearch);     // also when another app is in front

  Windows: the notification area (Shell_NotifyIcon), hot keys with RegisterHotKey.
  Linux: the tray of KDE, Xfce, Cinnamon, MATE, Budgie (GNOME with the
  AppIndicator extension) through libayatana-appindicator (or libappindicator);
  its icon opens the menu. Hot keys on X11 (not Wayland, which does not let
  apps take keys of other windows). Phones: nothing.

`uses Pastel.Tray;` · source: [framework/src/pastel.tray.pas](../../framework/src/pastel.tray.pas)

## Types

### TTrayIcon

```pascal
type TTrayIcon = class(TComponent)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure MenuItem(Index: Integer)` |  |
| `function Error: string` | '' or why the tray is not there |
| `property Hint: string` |  |
| `property IconFile: string` | a PNG (Linux) or .ico (Windows); default: the app's icon |
| `property Visible: Boolean` |  |
| `property Menu: TStringList` | the menu's items; '-' a line between them |
| `property OnClick: TNotifyEvent` |  |
| `property OnMenuItem: TTrayMenuEvent` |  |

## Other types

| | |
|---|---|
| `type TTrayMenuEvent = procedure(Sender: TObject; Index: Integer; Caption: string)` |  |

## Routines

### RegisterHotKey

```pascal
function RegisterHotKey(const Keys: string; OnPressed: TNotifyEvent): Integer
```

Keys like 'Ctrl+Shift+K', 'Alt+F9', 'Win+Space': OnPressed even when another
app is in front; its id (0: not taken - another app has it, or Wayland).

### UnregisterHotKey

```pascal
procedure UnregisterHotKey(Id: Integer)
```

