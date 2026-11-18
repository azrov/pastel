# Pastel.Notifications.Android

Notifications on Android (used by Pastel.Notifications): the
  notification bar through Pastel's activity (PastelNotifications.java);
  scheduled ones are kept by AlarmManager, also when the app is closed and
  after a restart of the phone.

`uses Pastel.Notifications.Android;` · source: [framework/src/pastel.notifications.android.pas](../../framework/src/pastel.notifications.android.pas)

## Routines

### PlatformShow

```pascal
function PlatformShow(const Name: string; const Title: string; const Body: string): Boolean
```

### PlatformSchedule

```pascal
function PlatformSchedule(const Name: string; const Title: string; const Body: string; AtUnixMs: Int64; RepeatMs: Int64): Boolean
```

True: the system keeps it (else Pastel.Notifications shows it while the app runs).

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
