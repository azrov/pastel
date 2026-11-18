# Pastel.Notifications.Windows

Notifications on Windows (used by Pastel.Notifications): a message
  from the app's icon in the notification area (Shell_NotifyIcon); Windows 10
  and 11 show it as a toast, older ones as a balloon. The icon stays while the
  app runs and goes when it ends.

`uses Pastel.Notifications.Windows;` · source: [framework/src/pastel.notifications.windows.pas](../../framework/src/pastel.notifications.windows.pas)

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
