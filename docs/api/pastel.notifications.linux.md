# Pastel.Notifications.Linux

Notifications on Linux (used by Pastel.Notifications): the
  desktop's notifications (org.freedesktop.Notifications on D-Bus, the same
  for GNOME, KDE, Cinnamon, XFCE...) through gdbus, which can replace and take
  back a notification; else notify-send.

`uses Pastel.Notifications.Linux;` · source: [framework/src/pastel.notifications.linux.pas](../../framework/src/pastel.notifications.linux.pas)

## Routines

### PlatformShow

```pascal
function PlatformShow(const Name: string; const Title: string; const Body: string): Boolean
```

### PlatformSchedule

```pascal
function PlatformSchedule(const Name: string; const Title: string; const Body: string; AtUnixMs: Int64; RepeatMs: Int64): Boolean
```

### PlatformCancel

```pascal
procedure PlatformCancel(const Name: string)
```

### PlatformCancelAll

```pascal
procedure PlatformCancelAll
```

### PlatformTakeClicked

```pascal
function PlatformTakeClicked: string
```

## Constants and variables

| | |
|---|---|
| `var PlatformError: string` |  |
