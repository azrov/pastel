# Pastel.Notifications.Mac

Notifications on macOS (used by Pastel.Notifications): the
  Notification Center, through osascript ("display notification").

`uses Pastel.Notifications.Mac;` · source: [framework/src/pastel.notifications.mac.pas](../../framework/src/pastel.notifications.mac.pas)

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
