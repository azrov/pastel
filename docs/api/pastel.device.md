# Pastel.Device

The phone's features: share, open, vibrate, notify, pick a file,
  take a photo, find the place; and the permissions they need.

    ShareText('Your appointment: Monday 10:00');          // Android's share menu
    ShareFile(InvoicePdf);                                // the PDF to WhatsApp, mail...
    OpenUrl('https://maps.google.com/?q=Istanbul');       // the browser (a file: the app for it)
    Vibrate;                                              // a short buzz
    Notify('Sync', '12 appointments came in');            // in the notification bar
    Photo := TakePhoto;                                   // '' when cancelled
    FileName := PickFile('application/pdf');              // '' when cancelled
    if GetLocation(Place) then
      Label1.Text := Format('%.5f, %.5f', [Place.Latitude, Place.Longitude]);

  On Android these use the phone's own apps and services through Pastel's
  activity; the calls that wait (TakePhoto, PickFile, GetLocation,
  RequestPermission) keep the app's window alive while they wait. On a
  computer: OpenUrl opens the browser or the file's app, PickFile shows the
  open dialog, Notify uses the desktop's notifications on Linux; the others
  answer False / '' (no camera, no place).

  The calls that wait have a second form that does not: it returns at once
  and calls a method of yours with the answer — the way for phones:
    TakePhoto(@PhotoTaken);
    ...
    procedure THomeForm.PhotoTaken(Sender: TObject; Ok: Boolean; const FileName: string);
    begin
      if Ok then Image1.LoadFromFile(FileName);
    end;

  Permissions: GetLocation asks for the location itself; an app that uses it
  lists it in pastel.toml: [package.android] permissions = ["location"].

`uses Pastel.Device;` · source: [framework/src/pastel.device.pas](../../framework/src/pastel.device.pas)

**Contents:** [TDevicePermission](#tdevicepermission) · [TPermissionState](#tpermissionstate) · [TPlace](#tplace) · [TSharedContent](#tsharedcontent) · [TShareReceiver](#tsharereceiver) · [TContact](#tcontact) · [TCalendarEvent](#tcalendarevent) · [TAppShortcut](#tappshortcut) · [TLinkReceiver](#tlinkreceiver) · [TAuthKind](#tauthkind) · [ShareText](#sharetext) · [ShareFile](#sharefile) · [OpenUrl](#openurl) · [Vibrate](#vibrate) · [Notify](#notify) · [RequestPermission](#requestpermission) · [PickFile](#pickfile) · [TakePhoto](#takephoto) · [GetLocation](#getlocation) · [RequestPermission](#requestpermission) · [PickFile](#pickfile) · [TakePhoto](#takephoto) · [GetLocation](#getlocation) · [RequestPermissions](#requestpermissions) · [PermissionState](#permissionstate) · [OpenAppSettings](#openappsettings) · [Authenticate](#authenticate) · [CanAuthenticate](#canauthenticate) · [ScanBarcode](#scanbarcode) · [KeepScreenOn](#keepscreenon) · [SaveToGallery](#savetogallery) · [IsMobile](#ismobile) · [TakeSharedContent](#takesharedcontent) · [TakeOpenedLink](#takeopenedlink) · [TakeShortcut](#takeshortcut) · [AppShortcut](#appshortcut) · [SetAppShortcuts](#setappshortcuts) · [PickContact](#pickcontact) · [ReadContacts](#readcontacts) · [AddContact](#addcontact) · [AddToCalendar](#addtocalendar) · [ReadCalendar](#readcalendar) · [EnterPictureInPicture](#enterpictureinpicture) · [InPictureInPicture](#inpictureinpicture) · [AutoPictureInPicture](#autopictureinpicture) · [LinkFromArguments](#linkfromarguments)

## Types

### TDevicePermission

```pascal
type TDevicePermission = (dpLocation, dpNotifications, dpCamera, dpMicrophone, dpContacts, dpCalendar, dpPhone, dpStorage, dpBluetooth)
```

What an app may use on a phone; each must also be in pastel.toml:
[package.android] permissions = ["camera", "location", ...] (the names in
lower case without "dp").

- `dpLocation` What an app may use on a phone; each must also be in pastel.toml: [package.android] permissions = ["camera", "location", ...] (the names in lower case without "dp").
- `dpNotifications` What an app may use on a phone; each must also be in pastel.toml: [package.android] permissions = ["camera", "location", ...] (the names in lower case without "dp").
- `dpCamera` What an app may use on a phone; each must also be in pastel.toml: [package.android] permissions = ["camera", "location", ...] (the names in lower case without "dp").
- `dpMicrophone` What an app may use on a phone; each must also be in pastel.toml: [package.android] permissions = ["camera", "location", ...] (the names in lower case without "dp").
- `dpContacts` What an app may use on a phone; each must also be in pastel.toml: [package.android] permissions = ["camera", "location", ...] (the names in lower case without "dp").
- `dpCalendar` What an app may use on a phone; each must also be in pastel.toml: [package.android] permissions = ["camera", "location", ...] (the names in lower case without "dp").
- `dpPhone`
- `dpStorage`
- `dpBluetooth`
### TPermissionState

```pascal
type TPermissionState = (psGranted, psNotAsked, psDenied, psBlocked)
```

psNotAsked: never asked (asking shows the phone's question); psDenied: refused
once (explain why the app needs it, then ask again); psBlocked: refused for good
(only the app's page in the settings gives it: OpenAppSettings)

- `psGranted` psNotAsked: never asked (asking shows the phone's question); psDenied: refused once (explain why the app needs it, then ask again); psBlocked: refused for good (only the app's page in the settings gives it: OpenAppSettings)
- `psNotAsked` psNotAsked: never asked (asking shows the phone's question); psDenied: refused once (explain why the app needs it, then ask again); psBlocked: refused for good (only the app's page in the settings gives it: OpenAppSettings)
- `psDenied` psNotAsked: never asked (asking shows the phone's question); psDenied: refused once (explain why the app needs it, then ask again); psBlocked: refused for good (only the app's page in the settings gives it: OpenAppSettings)
- `psBlocked` psNotAsked: never asked (asking shows the phone's question); psDenied: refused once (explain why the app needs it, then ask again); psBlocked: refused for good (only the app's page in the settings gives it: OpenAppSettings)
### TPlace

```pascal
type TPlace = record
```

| | |
|---|---|
| `Latitude: Double` |  |
| `Longitude: Double` |  |
| `Accuracy: Double` | meters |

### TSharedContent

```pascal
type TSharedContent = record
```

What another app shared with this one (Android's share menu).

| | |
|---|---|
| `Text: string` |  |
| `Subject: string` |  |
| `MimeType: string` | 'text/plain', 'image/jpeg', 'image/*'... |
| `Files: TStringArray` | the files, copied into the app's cache |

### TShareReceiver

```pascal
type TShareReceiver = class(TComponent)
```

The app in other apps' share menu: put it on the main form (it is not
drawn); OnShareReceived gets what was shared — also what opened the app.
pastel.toml lists the kinds: [package.android] receive_shares = ["text/plain", "image/*"].

| | |
|---|---|
| `property OnShareReceived: TShareReceivedEvent` |  |

### TContact

```pascal
type TContact = record
```

A person of the phone's contacts.

| | |
|---|---|
| `Name: string` |  |
| `Phones: TStringArray` |  |
| `Emails: TStringArray` |  |

### TCalendarEvent

```pascal
type TCalendarEvent = record
```

An event of the phone's calendar; local times (an all-day event: its days, Finish the day after).

| | |
|---|---|
| `Title: string` |  |
| `Place: string` |  |
| `Notes: string` |  |
| `Start: TDateTime` |  |
| `Finish: TDateTime` |  |
| `AllDay: Boolean` |  |

### TAppShortcut

```pascal
type TAppShortcut = record
```

A shortcut of the app's icon (a long press on it): its Id comes back in
TLinkReceiver.OnShortcut; Icon is a built-in icon's name ('add', 'calendar'...).

| | |
|---|---|
| `Id: string` |  |
| `Title: string` |  |
| `Icon: string` |  |

### TLinkReceiver

```pascal
type TLinkReceiver = class(TComponent)
```

Links that open the app and the shortcuts of its icon: put it on the main
form (it is not drawn). OnLink gets the address - also the one that started
the app - for the links in pastel.toml: [package] links = ["shop://",
"https://shop.example.com/app"]. OnShortcut gets the Id of a shortcut
(SetAppShortcuts). On computers a link of the app's own scheme (shop://)
starts it with the address (the .deb and the Windows installer register it).

| | |
|---|---|
| `property OnLink: TLinkEvent` |  |
| `property OnShortcut: TShortcutEvent` |  |

### TAuthKind

```pascal
type TAuthKind = (akNone, akDeviceLock, akBiometric)
```

What the device can check the user with: nothing set up, the screen lock (PIN,
pattern, password), a fingerprint or the face.

- `akNone` What the device can check the user with: nothing set up, the screen lock (PIN, pattern, password), a fingerprint or the face.
- `akDeviceLock` What the device can check the user with: nothing set up, the screen lock (PIN, pattern, password), a fingerprint or the face.
- `akBiometric` What the device can check the user with: nothing set up, the screen lock (PIN, pattern, password), a fingerprint or the face.
## Other types

| | |
|---|---|
| `type TDevicePermissions = set of TDevicePermission` |  |
| `type TShareReceivedEvent = procedure(Sender: TObject; Shared: TSharedContent)` |  |
| `type TContacts = array of TContact` |  |
| `type TContactDoneEvent = procedure(Sender: TObject; Ok: Boolean; Contact: TContact)` | The answer of PickContact: the name and the number (or e-mail) chosen. |
| `type TCalendarEvents = array of TCalendarEvent` |  |
| `type TLinkEvent = procedure(Sender: TObject; Url: string)` |  |
| `type TShortcutEvent = procedure(Sender: TObject; Id: string)` |  |
| `type TPermissionDoneEvent = procedure(Sender: TObject; Granted: Boolean)` | The answer of RequestPermission without waiting. |
| `type TPermissionsDoneEvent = procedure(Sender: TObject; Granted: TDevicePermissions; Blocked: TDevicePermissions)` | The answer of RequestPermissions: those given, and those refused for good. |
| `type TPlaceDoneEvent = procedure(Sender: TObject; Ok: Boolean; Place: TPlace)` | The answer of GetLocation without waiting. |
| `type TAuthDoneEvent = procedure(Sender: TObject; Ok: Boolean; Error: string)` | The answer of Authenticate: Ok, else why not ('canceled' when the user closed it). |
| `type TScanDoneEvent = procedure(Sender: TObject; Ok: Boolean; Text: string; Format: string)` | The answer of ScanBarcode: the code's text and its kind ('QR', 'EAN13', 'Code128'...). |

## Routines

### ShareText

```pascal
function ShareText(const Text: string; const Subject: string = ''): Boolean
```

The share menu (WhatsApp, mail, messages...) with a text; False where there is none.

### ShareFile

```pascal
function ShareFile(const FileName: string; const MimeType: string = ''): Boolean
```

The share menu with a file of the app (a PDF, a photo).

### OpenUrl

```pascal
function OpenUrl(const UrlOrFile: string): Boolean
```

An address in the browser, or a file in the app for it.

### Vibrate

```pascal
procedure Vibrate(Milliseconds: Integer = 40)
```

A short buzz (phones).

### Notify

```pascal
function Notify(const Title: string; const Text: string; Id: Integer = 1): Boolean
```

A message in the notification bar; the same Id replaces the one before
(Pastel.Notifications has more: at a time, again and again, taken back).

### RequestPermission

```pascal
function RequestPermission(Permission: TDevicePermission): Boolean
```

Asks the user for a permission when the app does not have it yet; True when it has it.

### PickFile

```pascal
function PickFile(const MimeType: string = '*/*'): string
```

A file the user picks ('image/*', 'application/pdf', '*/*'): its path ('' when
cancelled). On a phone a copy in the app's cache.

### TakePhoto

```pascal
function TakePhoto: string
```

A photo from the camera app: the path of the .jpg ('' when cancelled or there is no camera).

### GetLocation

```pascal
function GetLocation(out Place: TPlace; TimeoutMs: Integer = 15000): Boolean
```

The place of the device (asks for the permission first).

### RequestPermission

```pascal
procedure RequestPermission(Permission: TDevicePermission; OnDone: TPermissionDoneEvent)
```

The same without waiting: they return at once; the method given is called
with the answer (always later, never inside the call; LastDeviceError says
why when it did not work).

### PickFile

```pascal
procedure PickFile(const MimeType: string; OnDone: TFileDoneEvent)
```

### TakePhoto

```pascal
procedure TakePhoto(OnDone: TFileDoneEvent)
```

### GetLocation

```pascal
procedure GetLocation(OnDone: TPlaceDoneEvent; TimeoutMs: Integer = 15000)
```

### RequestPermissions

```pascal
procedure RequestPermissions(Permissions: TDevicePermissions; OnDone: TPermissionsDoneEvent)
```

Several at once, in one question of the phone (camera and microphone for a video).

### PermissionState

```pascal
function PermissionState(Permission: TDevicePermission): TPermissionState
```

Where a permission stands, without asking (computers: psGranted).

### OpenAppSettings

```pascal
procedure OpenAppSettings
```

The app's page in the phone's settings, where a permission refused for good is given.

### Authenticate

```pascal
procedure Authenticate(const Reason: string; OnDone: TAuthDoneEvent; AllowPin: Boolean = True; const Subtitle: string = '')
```

"Is it you?": the fingerprint, the face or (AllowPin) the phone's PIN, pattern
or password, with Reason shown - before a payment, to open the app's secrets.
Android 9 and newer the system's dialog; older ones the lock screen's check.
Computers: not there (OnDone with False).

### CanAuthenticate

```pascal
function CanAuthenticate: TAuthKind
```

### ScanBarcode

```pascal
procedure ScanBarcode(OnDone: TScanDoneEvent)
```

A QR code or barcode read with the camera: Google's code scanner (its own
screen, no camera permission) with [package.android] libraries =
["com.google.android.gms:play-services-code-scanner:16.1.0"]. Computers: not there.

### KeepScreenOn

```pascal
procedure KeepScreenOn(Enable: Boolean)
```

The screen stays on while the app is open (a recipe, a map, a kiosk); False: it goes dark by itself again. Phones.

### SaveToGallery

```pascal
function SaveToGallery(const FileName: string; const Folder: string = ''): Boolean
```

A picture (a photo of TakePhoto, a chart saved as PNG) into the phone's gallery,
in Pictures/Folder (default: the app's name); False and LastDeviceError when not.
Computers: copied into the user's Pictures folder.

### IsMobile

```pascal
function IsMobile: Boolean
```

True on Android.

### TakeSharedContent

```pascal
function TakeSharedContent(out Shared: TSharedContent): Boolean
```

What another app shared with this one, once (TShareReceiver tells it by itself).

### TakeOpenedLink

```pascal
function TakeOpenedLink(out Url: string): Boolean
```

The link that opened the app, once (TLinkReceiver tells it by itself).

### TakeShortcut

```pascal
function TakeShortcut(out Id: string): Boolean
```

The shortcut of the icon that opened the app, once (TLinkReceiver tells it by itself).

### AppShortcut

```pascal
function AppShortcut(const Id: string; const Title: string; const Icon: string = ''): TAppShortcut
```

### SetAppShortcuts

```pascal
function SetAppShortcuts(const Shortcuts: array of TAppShortcut): Boolean
```

The shortcuts shown by a long press on the app's icon (Android 7.1 and newer;
up to 4 are shown); [] removes them. They stay after the app ends: set them
at every start (in the user's language). False and LastDeviceError where not.

### PickContact

```pascal
procedure PickContact(OnDone: TContactDoneEvent; Email: Boolean = False)
```

The phone's contact list to choose one from (no permission needed): its name
and the number (or with Email the e-mail) chosen, in Phones[0] (Emails[0]).

### ReadContacts

```pascal
function ReadContacts(out Contacts: TContacts; const Search: string = ''): Boolean
```

All contacts with their numbers and e-mails, by name; only those with Search
in their name, number or e-mail. Needs the permission: [package.android]
permissions = ["contacts"] and RequestPermission(dpContacts).

### AddContact

```pascal
function AddContact(const Name: string; const Phone: string = ''; const Email: string = ''): Boolean
```

The contacts app with a new contact filled in: the user saves it (no permission).

### AddToCalendar

```pascal
function AddToCalendar(const Title: string; Start: TDateTime; Finish: TDateTime; const Place: string = ''; const Notes: string = ''; AllDay: Boolean = False): Boolean
```

A new event in the calendar app, filled in: the user saves it (no permission).
Computers: an .ics file, opened by the calendar program (Thunderbird, Outlook...).

### ReadCalendar

```pascal
function ReadCalendar(out Events: TCalendarEvents; From: TDateTime; Till: TDateTime): Boolean
```

The events of the phone's calendars from From till Till. Needs the permission:
[package.android] permissions = ["calendar"] and RequestPermission(dpCalendar).

### EnterPictureInPicture

```pascal
function EnterPictureInPicture(AspectW: Integer = 16; AspectH: Integer = 9): Boolean
```

The app's window small, over other apps, with its video playing (Android 8
and newer, [package.android] picture_in_picture = true). Show only the
video meanwhile: the form gets the small size (OnResize), InPictureInPicture
says why. False and LastDeviceError where not.

### InPictureInPicture

```pascal
function InPictureInPicture: Boolean
```

### AutoPictureInPicture

```pascal
procedure AutoPictureInPicture(Enable: Boolean; AspectW: Integer = 16; AspectH: Integer = 9)
```

Into picture-in-picture by itself when the user goes home while it is on (a
video playing); off again when it stops.

### LinkFromArguments

```pascal
function LinkFromArguments(const Args: array of string): string
```

The address among a program's arguments ('shop://order/42'; not a file), or ''.

## Constants and variables

| | |
|---|---|
| `var LastDeviceError: string` | Why the last call did not work ('' when it did). |
| `var OpenUrlHook: function (const UrlOrFile : string) : Boolean` | Tests: what OpenUrl opens goes here instead (True: opened). |
