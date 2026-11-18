# Pastel.Notifications

Notifications: a message in the system's notification area, now or
  at a time, once or again and again; taken back; which one the user tapped.

    ShowNotification('Sync', '12 appointments came in');
    ScheduleNotification('appt-42', 'Appointment', 'Ayşe at 10:00', Start - OneHour);
    ScheduleNotification('backup', 'Backup', 'Time for the weekly backup', NextMonday9, riWeekly);
    CancelNotification('appt-42');

  Or as a component on the form (TNotificationCenter), with an event for taps:
    procedure THomeForm.NotificationsNotificationClick(Sender: TObject; const AName: string);
    begin
      if AName = 'appt-42' then OpenAppointment(42);
    end;

  A notification has a name: the same name replaces it (shown or scheduled),
  CancelNotification takes it back. Times are local (Now, EncodeDateTime...).

  Each platform does it its own way, in its own unit:
    Android  Pastel.Notifications.Android: the notification bar; scheduled ones
             come also when the app is closed and after a restart of the phone
             (AlarmManager; a few minutes late at most while the phone sleeps);
             taps are told (OnNotificationClick). Needs [package.android]
             permissions = ["notifications"] (Android 13 and newer ask the user).
    Linux    Pastel.Notifications.Linux: the desktop's notifications (D-Bus
             through gdbus, else notify-send).
    Windows  Pastel.Notifications.Windows: a message from the app's icon in the
             notification area (Windows 10 and 11 show it as a toast).
    macOS    Pastel.Notifications.Mac: the Notification Center (osascript).
  On computers, scheduled notifications come while the app is running.

`uses Pastel.Notifications;` · source: [framework/src/pastel.notifications.pas](../../framework/src/pastel.notifications.pas)

**Contents:** [TRepeatInterval](#trepeatinterval) · [TNotificationCenter](#tnotificationcenter) · [ShowNotification](#shownotification) · [ScheduleNotification](#schedulenotification) · [CancelNotification](#cancelnotification) · [CancelAllNotifications](#cancelallnotifications) · [TakeClickedNotification](#takeclickednotification)

## Types

### TRepeatInterval

```pascal
type TRepeatInterval = (riNone, riHourly, riDaily, riWeekly)
```

How often a scheduled notification comes again.

- `riNone` How often a scheduled notification comes again.
- `riHourly` How often a scheduled notification comes again.
- `riDaily` How often a scheduled notification comes again.
- `riWeekly` How often a scheduled notification comes again.
### TNotificationCenter

```pascal
type TNotificationCenter = class(TComponent)
```

The notifications as a component: put it on the form (it is not drawn) for
the event of taps.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Show(const Title: string; const Body: string; const AName: string = ''): Boolean` |  |
| `function Schedule(const AName: string; const Title: string; const Body: string; At: TDateTime; Repeats: TRepeatInterval = riNone): Boolean` |  |
| `procedure Cancel(const AName: string)` |  |
| `procedure CancelAll` |  |
| `property OnNotificationClick: TNotificationClickEvent` | The user tapped a notification of the app (on Android; the app was opened by it). |

## Other types

| | |
|---|---|
| `type TNotificationClickEvent = procedure(Sender: TObject; AName: string)` | AName: the notification's name (not Name: a form has a Name of its own). |

## Routines

### ShowNotification

```pascal
function ShowNotification(const Title: string; const Body: string; const Name: string = ''): Boolean
```

Shows a notification now; the same Name replaces the one before ('' : a new one each time).

### ScheduleNotification

```pascal
function ScheduleNotification(const Name: string; const Title: string; const Body: string; At: TDateTime; Repeats: TRepeatInterval = riNone): Boolean
```

Shows it at the time At (local), and again every hour, day or week. A time
that has passed: now. The same Name replaces it.

### CancelNotification

```pascal
procedure CancelNotification(const Name: string)
```

Takes back a notification: the scheduled one and the one shown.

### CancelAllNotifications

```pascal
procedure CancelAllNotifications
```

### TakeClickedNotification

```pascal
function TakeClickedNotification: string
```

The name of the notification the user tapped last (that opened the app), once; ''
when none. TNotificationCenter.OnNotificationClick tells it by itself.

## Constants and variables

| | |
|---|---|
| `var LastNotificationError: string` | Why the last call did not work ('' when it did). |
| `var CapturedNotifications: TStrings` | For tests: when set, notifications are not shown but added here as 'name|title|body' lines; scheduled ones too, when their time comes (ProcessTimers; none kept by the system). |
