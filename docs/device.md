# The phone's features

`Pastel.Device` reaches what a phone has and a desktop program usually does not: the share menu, the phone and
browser apps, vibration, notifications, the camera, the place, files from anywhere on the phone — and the
permissions some of them need. On Android it uses the phone's own apps and services; on a computer the calls do
what makes sense there (the browser, the open dialog, desktop notifications) or answer that it is not there.

```pascal
uses
  Pastel.Device;

ShareText('Your appointment: Monday 10:00', 'Salon');      // WhatsApp, mail, messages...
ShareFile(InvoicePdf);                                     // a file of the app, to another app
OpenUrl('tel:05321112233');                                // the phone app, the number typed in
OpenUrl('https://maps.google.com/?q=Kadıköy');             // the browser or the maps app
OpenUrl(ReportFile);                                       // a file: the app for it (a PDF viewer)
Vibrate;                                                   // a short buzz (Vibrate(200): longer)
Notify('Sync', '12 appointments came in');                 // in the notification bar
```

## Calls that wait for the user

These show something of the phone (the camera app, the file picker, a permission question) and come back when
the user is done. The app's window stays alive meanwhile; call them from an event (a button's `OnClick`).
Each has a second form that does not wait — shown after these — which is the better way on a phone.

```pascal
procedure THomeForm.PhotoClick(Sender: TObject);
var
  Photo: string;
begin
  Photo := TakePhoto;                         // '' when cancelled or there is no camera app
  if Photo <> '' then
    Picture.FileName := Photo;                // a .jpg in the app's cache
end;

procedure THomeForm.AttachClick(Sender: TObject);
var
  F: string;
begin
  F := PickFile('application/pdf');           // 'image/*', 'text/*', '*/*'
  if F <> '' then
    Attachments.Items.Add(F);                 // a copy in the app's cache, a normal file
end;

procedure THomeForm.WhereClick(Sender: TObject);
var
  Place: TPlace;
begin
  if GetLocation(Place) then                  // asks for the permission first
    PlaceLabel.Text := Format('%.5f, %.5f (±%.0f m)', [Place.Latitude, Place.Longitude, Place.Accuracy])
  else
    PlaceLabel.Text := LastDeviceError;       // "the app may not know the place (permission refused)"
end;
```

Without waiting, the call returns at once and the answer comes to a method of yours — later, never inside the
call, also when it is there at once (no camera on a computer):

```pascal
procedure THomeForm.PhotoClick(Sender: TObject);
begin
  TakePhoto(@PhotoTaken);
end;

procedure THomeForm.PhotoTaken(Sender: TObject; Ok: Boolean; const FileName: string);
begin
  if Ok then
    Picture.FileName := FileName
  else
    StatusLabel.Text := LastDeviceError;
end;
```

| Waits | Does not wait | The method gets |
|---|---|---|
| `TakePhoto` | `TakePhoto(@Done)` | `Ok`, the file |
| `PickFile(Mime)` | `PickFile(Mime, @Done)` | `Ok`, the file |
| `GetLocation(Place)` | `GetLocation(@Done)` | `Ok`, the `TPlace` |
| `RequestPermission(P)` | `RequestPermission(P, @Done)` | `Granted` |

`TOpenDialog` and `OpenFileDialog` use the same picker on a phone, so code written for the desktop opens files
there too.

| | Android | A computer |
|---|---|---|
| `ShareText`, `ShareFile` | the share menu | False (`LastDeviceError` says why) |
| `OpenUrl` | the app for the address or file (`tel:`, `mailto:`, `https:`, `geo:`) | the browser or the file's app |
| `Vibrate` | a buzz | nothing |
| `Notify` | the notification bar (asks for the permission on Android 13+) | the desktop's notifications ([below](#notifications)) |
| `PickFile` | the phone's picker (files, Drive, gallery) | the open dialog |
| `TakePhoto` | the camera app | '' |
| `GetLocation` | GPS or the network | False |
| `RequestPermission` | asks the user once | True |
| `PickContact`, `ReadContacts`, `AddContact` | the phone's contacts ([below](#contacts-and-the-calendar)) | False |
| `AddToCalendar` | the calendar app, filled in | an `.ics` file in the calendar program |
| `ReadCalendar` | the phone's calendars | False |
| `SetAppShortcuts` | the icon's shortcuts ([below](#links-and-the-icons-shortcuts)) | False |
| `EnterPictureInPicture` | the video in a small window ([below](#picture-in-picture)) | False |
| `IsMobile` | True | False |

## Shared with the app

Other apps' share menu (the gallery, the browser, WhatsApp) can list the app. `pastel.toml` says which kinds it
takes; a [TShareReceiver](controls.md#tsharereceiver) on the main form gets what was shared — also when the share
opened the app:

```toml
[package.android]
receive_shares = ["text/plain", "image/*"]     # "application/pdf", "*/*" (any file)...
```

`TSharedContent` holds `Text` and `Subject` (a link shared from the browser is its `Text`), `MimeType`, and
`Files`: what was shared, copied into the app's cache — one or many photos, a PDF. `TakeSharedContent(Shared)` is
the same without the component.

## Links and the icon's shortcuts

**Links** open the app at the right place: from a QR code, a notification, a mail, a web page. `pastel.toml` lists
them, for every platform:

```toml
[package]
links = ["shop://", "https://shop.example.com/app"]
```

A [TLinkReceiver](controls.md#tlinkreceiver) on the main form gets the address — also the one that started the app:

```pascal
procedure THomeForm.LinksLink(Sender: TObject; const Url: string);
begin
  // shop://order/42 or https://shop.example.com/app/order/42
  if Pos('/order/', Url) > 0 then
    OpenOrder(StrToIntDef(Copy(Url, LastDelimiter('/', Url) + 1, MaxInt), 0));
end;
```

- **The app's own scheme** (`shop://`): any link of it opens the app — on Android, and on computers too: the
  `.deb` and the Windows installer register the scheme, and the app starts with the address (`TakeOpenedLink` and
  `OnLink` find it among the arguments).
- **Its site's addresses** (`https://shop.example.com/app`): links under it open the app instead of the browser
  (Android) once the site says the app is its own. `pastel package apk` writes `dist/assetlinks.json` with the
  key's fingerprint: put it at `https://shop.example.com/.well-known/assetlinks.json`. An app from Google Play is
  signed with Play's key: add its fingerprint (Play Console → App integrity) into the same file. Until then Android
  shows the link in the browser.

**The icon's shortcuts** come with a long press on the app's icon (Android 7.1 and newer) and can be dragged to
the home screen. Set them at every start (they are in the user's language); a tap opens the app and `OnShortcut`
gets the `Id`:

```pascal
SetAppShortcuts([AppShortcut('new', _('New appointment'), 'add'),
                 AppShortcut('today', _('Today'), 'calendar')]);
...
procedure THomeForm.LinksShortcut(Sender: TObject; const Id: string);
begin
  if Id = 'new' then NewAppointment
  else if Id = 'today' then ShowToday;
end;
```

The icon is a built-in icon's name, drawn in the theme's accent; launchers show up to four. `SetAppShortcuts([])`
removes them.

## Contacts and the calendar

```pascal
PickContact(@ContactPicked);                         // the phone's list; no permission needed
...
procedure THomeForm.ContactPicked(Sender: TObject; Ok: Boolean; const Contact: TContact);
begin
  if Ok then
  begin
    NameEdit.Text := Contact.Name;
    PhoneEdit.Text := Contact.Phones[0];             // PickContact(@Done, True): Contact.Emails[0]
  end;
end;

AddContact('Ayşe Yılmaz', '0532 111 22 33', 'ayse@example.com');   // the contacts app, filled in: the user saves it
AddToCalendar('Haircut', Start, Start + EncodeTime(0, 45, 0, 0), 'Salon Kadıköy', 'Ayşe');   // the calendar app, filled in
```

`AddContact` and `AddToCalendar` need no permission: the phone's app opens with the fields filled in and the user
saves. On a computer `AddToCalendar` writes an `.ics` file and opens it in the calendar program (Thunderbird,
Outlook, GNOME Calendar). `AllDay = True` makes it a whole day.

Reading them all needs the permission (`permissions = ["contacts"]`, `["calendar"]` and `RequestPermission`):

```pascal
if RequestPermission(dpContacts) and ReadContacts(People, 'ayşe') then
  for P in People do
    List.Items.Add(P.Name + '  ' + string.Join(', ', P.Phones));

if RequestPermission(dpCalendar) and ReadCalendar(Events, Date, Date + 7) then
  for E in Events do
    List.Items.Add(FormatDateTime('ddd hh:nn', E.Start) + '  ' + E.Title);
```

`TContact`: `Name`, `Phones`, `Emails`. `TCalendarEvent`: `Title`, `Place`, `Notes`, `Start`, `Finish` (local times),
`AllDay`. A repeating event comes once for every time in the range.

## Picture-in-picture

A video goes on in a small window over other apps (Android 8 and newer), like YouTube's:

```toml
[package.android]
picture_in_picture = true
```

```pascal
EnterPictureInPicture(Player.VideoWidth, Player.VideoHeight);   // now (a button)
AutoPictureInPicture(True);           // by itself when the user goes home while it is on: on while a video plays
```

Meanwhile the form has the small window's size: show only the video there (`InPictureInPicture` says when; hide
the buttons around it). [Pastel TV](https://github.com/azrov/pastel-tv) turns it on while its player plays.

## Notifications

`Notify` shows a message in the notification bar. `Pastel.Notifications` has the rest: at a time, again and
again, taken back, and which one the user tapped. Each notification has a name: the same name replaces it.

```pascal
uses Pastel.Notifications;

ShowNotification('Sync', '12 appointments came in');
ScheduleNotification('appt-42', 'Appointment', 'Ayşe at 10:00', IncHour(Start, -1));   // an hour before
ScheduleNotification('backup', 'Backup', 'Time for the weekly backup', NextMonday9, riWeekly);
CancelNotification('appt-42');                     // the appointment was cancelled
```

`riHourly`, `riDaily` and `riWeekly` repeat it; a time that has passed shows it now. For taps, put a
`TNotificationCenter` on the form ([controls.md](controls.md#tnotificationcenter)): its `OnNotificationClick`
gets the name of the notification that opened the app.

| | Android | Linux | Windows | macOS |
|---|---|---|---|---|
| Shown | the notification bar | the desktop's notifications (D-Bus; `notify-send` else) | from the app's icon in the notification area (a toast on Windows 10 and 11) | the Notification Center |
| At a time | also when the app is closed, and after the phone restarted | while the app runs | while the app runs | while the app runs |
| Taken back | yes | yes | the balloon of older Windows | no |
| Taps | `OnNotificationClick` | — | — | — |

On Android an alarm may come a few minutes late while the phone sleeps (exact alarms need a permission the user
gives in the settings). The app lists `permissions = ["notifications"]` (Android 13 and newer ask the user the
first time). The small icon in the status bar is made from `assets/icon.png` — white, the shape of the picture on
the icon's background — or is `assets/notification.png` (white on transparent) when there is one.

In tests, `CapturedNotifications := SomeStringList` keeps them instead of showing them (`'name|title|body'`).

## Permissions

An app may use the network and vibration without asking. For the rest Android asks the user the first time
(`GetLocation`, `Notify` and `TakePhoto` do it themselves). The `.apk` lists what the app may ask for:

```toml
[package.android]
permissions = ["location", "notifications", "camera"]
```

| In `permissions` | `TDevicePermission` | For |
|---|---|---|
| `location` | `dpLocation` | `GetLocation` |
| `notifications` | `dpNotifications` | notifications (Android 13 and newer ask) |
| `camera` | `dpCamera` | the camera in the app itself; `TakePhoto` asks for it when the list names it |
| `microphone` | `dpMicrophone` | recording sound |
| `contacts` | `dpContacts` | reading the phone's contacts |
| `calendar` | `dpCalendar` | the phone's calendar |
| `phone` | `dpPhone` | calling a number directly (dialing with `OpenUrl('tel:...')` needs none) |
| `storage` | `dpStorage` | `SaveToGallery` on Android 9 and older (newer ones need none) |
| `bluetooth` | `dpBluetooth` | Bluetooth devices (Android 12 and newer ask; older ones give it with the app) |
| `biometric` | — | the fingerprint and the face for `Authenticate` (not asked: given with the app) |

Several are asked in one question of the phone, and the answer says which were given:

```pascal
procedure THomeForm.VideoClick(Sender: TObject);
begin
  case PermissionState(dpCamera) of
    psDenied: ShowMessage('The camera is needed to film the work done.');   // refused once: say why, then ask again
    psBlocked:                                                                  // refused for good
      begin
        if Ask('The camera is off for this app. Open its settings?') then
          OpenAppSettings;
        Exit;
      end;
  end;
  RequestPermissions([dpCamera, dpMicrophone], @PermissionsDone);
end;

procedure THomeForm.PermissionsDone(Sender: TObject; Granted, Blocked: TDevicePermissions);
begin
  if [dpCamera, dpMicrophone] <= Granted then
    StartRecording;
end;
```

`PermissionState`: `psGranted`, `psNotAsked`, `psDenied` (refused once — the time to explain why the app needs
it), `psBlocked` (refused for good: only the app's page in the settings gives it, `OpenAppSettings`). On computers
everything is granted.

## The screen and the gallery

```pascal
KeepScreenOn(True);                  // the screen stays on (a recipe, a map, a kiosk); False: dark by itself again
WindowState := wsFullScreen;         // the status and navigation bars hidden; a swipe from the edge shows them
SaveToGallery(PhotoFile, 'Salon');   // a picture into the phone's gallery (Pictures/Salon); computers: the Pictures folder
```

## The clipboard

Copy and paste in edits use the phone's clipboard, like on a computer; nothing to do.

## Background work and jobs

`Pastel.Background`: what the app does when it is not on the screen.

**Background work** — something the user started and waits for: music, a recorded route, an upload. The app keeps
running, with a notification, until `StopBackgroundWork`; its Pascal code goes on as before (timers, threads, the
network).

```pascal
uses
  Pastel.Background;

StartBackgroundWork('Uploading photos', '3 of 20', bkDataSync);   // bkMediaPlayback, bkLocation, bkConnectedDevice
UpdateBackgroundWork('7 of 20');
StopBackgroundWork;
```

**Background jobs** — a function Android runs from time to time, also when the app is closed and after the phone
restarted: a sync, a reminder, a backup. It is registered in a unit's initialization (Android may start the app just
for it, without its window), runs on a thread of its own — data, files, HTTP; no forms — and answers `True` when it
was done (`False`: Android tries again later).

```pascal
function SyncNow: Boolean;
begin
  Result := Store.Sync(ServerUrl);
end;

initialization
  RegisterBackgroundJob('sync', @SyncNow);

// when the user turns sync on:
ScheduleBackgroundJob('sync', 60);          // about every hour (15 minutes at least), when there is a network
CancelBackgroundJob('sync');
RunBackgroundJob('sync');                   // now: a "Sync now" button, a test
```

`pastel.toml` says what the app does in the background — Android asks apps to say it:

```toml
[package.android]
background = ["jobs", "data_sync"]    # "jobs": jobs also after a restart; data_sync, media_playback, location, connected_device
```

Android decides when a job runs (it saves the battery: not more often than every 15 minutes, later when the phone
sleeps). On computers apps run as long as they are open: background work changes nothing, and scheduled jobs run
with a timer while the app is open. `InBackgroundJob` is `True` inside a job.

## Is it you?

The fingerprint, the face or the phone's PIN before something that matters — a payment, the app's secrets:

```pascal
if CanAuthenticate <> akNone then                    // akBiometric, akDeviceLock: something is set up
  Authenticate('Pay 120 TL', @PayChecked);

procedure THomeForm.PayChecked(Sender: TObject; Ok: Boolean; const Error: string);
begin
  if Ok then
    Pay
  else if Error <> 'canceled' then
    ShowMessage(Error);
end;
```

Android 9 and newer show the system's dialog (fingerprint or face; with `AllowPin`, the default, the PIN,
pattern or password as well); older ones the lock screen's own check. `[package.android] permissions =
["biometric"]` (no question to the user). On computers `Authenticate` answers `False`.

## Push messages

A server sends a message to a phone — an order is ready, a new appointment — through Firebase Cloud Messaging:

1. In the [Firebase console](https://console.firebase.google.com) add an Android app with the app's id
   (`[package.android] id`) and put its `google-services.json` next to `pastel.toml`.
2. `pastel.toml`:

   ```toml
   [package.android]
   libraries = ["com.google.firebase:firebase-messaging:24.1.0"]
   permissions = ["notifications"]
   ```

3. A `TPushNotifications` on the main form ([controls.md](controls.md#tpushnotifications)): `RequestToken` gives the
   phone's token in `OnToken` — your server sends to it (Firebase's HTTP v1 API) — or `Subscribe('offers')` and
   the server sends to the topic.

`pastel package apk` puts Pastel's push service in when Firebase's messaging is among the libraries. A message
while the app is on the screen comes to `OnMessage`; when it is not, the phone shows it as a notification, and a
tap opens the app with `OnMessage` (`Msg.Opened`, its `Data`). Android 13 and newer ask the user before showing
notifications: `RequestPermissions([dpNotifications], ...)`. On computers there is no push; `PushTestMessage`
gives `OnMessage` a message, for tests.

## Speaking and listening

```pascal
uses
  Pastel.Speech;

Speak('Your order is ready');                  // the system's voice; Speak('Siparişiniz hazır', 'tr')
StopSpeaking;
Listen(@Heard, 'tr');                          // phones: speech to text, the phone's recognizer

procedure THomeForm.Heard(Sender: TObject; Ok: Boolean; const Text: string);
begin
  if Ok then SearchEdit.Text := Text;
end;
```

Computers speak with `spd-say` or `espeak` (Linux), the Windows voice, `say` (macOS).

## Scanning codes

```pascal
ScanBarcode(@Scanned);         // Google's code scanner: its own camera screen, no camera permission

procedure THomeForm.Scanned(Sender: TObject; Ok: Boolean; const Text, Format: string);
begin
  if Ok then FindProduct(Text);            // Format: 'QR', 'EAN13', 'Code128'...
end;
```

It needs `[package.android] libraries = ["com.google.android.gms:play-services-code-scanner:16.1.0"]` (`pastel
package` then puts Pastel's scanner in). Making codes: `TBarcode` ([controls.md](controls.md#tbarcode)).

