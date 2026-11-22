{ Pastel - the phone's features: share, open, vibrate, notify, pick a file,
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
  Part of the Pastel project, MIT License. }
unit Pastel.Device;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Dialogs;

type
  { What an app may use on a phone; each must also be in pastel.toml:
    [package.android] permissions = ["camera", "location", ...] (the names in
    lower case without "dp"). }
  TDevicePermission = (dpLocation, dpNotifications, dpCamera, dpMicrophone, dpContacts, dpCalendar,
    dpPhone, dpStorage, dpBluetooth);
  TDevicePermissions = set of TDevicePermission;

  { psNotAsked: never asked (asking shows the phone's question); psDenied: refused
    once (explain why the app needs it, then ask again); psBlocked: refused for good
    (only the app's page in the settings gives it: OpenAppSettings) }
  TPermissionState = (psGranted, psNotAsked, psDenied, psBlocked);

  TPlace = record
    Latitude, Longitude: Double;
    { meters }
    Accuracy: Double;
  end;

  { What another app shared with this one (Android's share menu). }
  TSharedContent = record
    Text, Subject: string;
    { 'text/plain', 'image/jpeg', 'image/*'... }
    MimeType: string;
    { the files, copied into the app's cache }
    Files: TStringArray;
  end;

  TShareReceivedEvent = procedure(Sender: TObject; const Shared: TSharedContent) of object;

  { The app in other apps' share menu: put it on the main form (it is not
    drawn); OnShareReceived gets what was shared — also what opened the app.
    pastel.toml lists the kinds: [package.android] receive_shares = ["text/plain", "image/*"]. }
  TShareReceiver = class(TComponent)
  private
    FOnShareReceived: TShareReceivedEvent;
    FTimer: TComponent;
    procedure SetOnShareReceived(AValue: TShareReceivedEvent);
    procedure Tick(Sender: TObject);
  published
    property OnShareReceived: TShareReceivedEvent read FOnShareReceived write SetOnShareReceived;
  end;

  { A person of the phone's contacts. }
  TContact = record
    Name: string;
    Phones, Emails: TStringArray;
  end;
  TContacts = array of TContact;
  { The answer of PickContact: the name and the number (or e-mail) chosen. }
  TContactDoneEvent = procedure(Sender: TObject; Ok: Boolean; const Contact: TContact) of object;

  { An event of the phone's calendar; local times (an all-day event: its days, Finish the day after). }
  TCalendarEvent = record
    Title, Place, Notes: string;
    Start, Finish: TDateTime;
    AllDay: Boolean;
  end;
  TCalendarEvents = array of TCalendarEvent;

  { A shortcut of the app's icon (a long press on it): its Id comes back in
    TLinkReceiver.OnShortcut; Icon is a built-in icon's name ('add', 'calendar'...). }
  TAppShortcut = record
    Id, Title, Icon: string;
  end;

  TLinkEvent = procedure(Sender: TObject; const Url: string) of object;
  TShortcutEvent = procedure(Sender: TObject; const Id: string) of object;

  { Links that open the app and the shortcuts of its icon: put it on the main
    form (it is not drawn). OnLink gets the address - also the one that started
    the app - for the links in pastel.toml: [package] links = ["shop://",
    "https://shop.example.com/app"]. OnShortcut gets the Id of a shortcut
    (SetAppShortcuts). On computers a link of the app's own scheme (shop://)
    starts it with the address (the .deb and the Windows installer register it). }
  TLinkReceiver = class(TComponent)
  private
    FOnLink: TLinkEvent;
    FOnShortcut: TShortcutEvent;
    FTimer: TComponent;
    procedure SetOnLink(AValue: TLinkEvent);
    procedure SetOnShortcut(AValue: TShortcutEvent);
    procedure Start;
    procedure Tick(Sender: TObject);
  published
    property OnLink: TLinkEvent read FOnLink write SetOnLink;
    property OnShortcut: TShortcutEvent read FOnShortcut write SetOnShortcut;
  end;

  { The answer of RequestPermission without waiting. }
  TPermissionDoneEvent = procedure(Sender: TObject; Granted: Boolean) of object;
  { The answer of RequestPermissions: those given, and those refused for good. }
  TPermissionsDoneEvent = procedure(Sender: TObject; Granted, Blocked: TDevicePermissions) of object;
  { The answer of GetLocation without waiting. }
  TPlaceDoneEvent = procedure(Sender: TObject; Ok: Boolean; const Place: TPlace) of object;
  { The answer of Authenticate: Ok, else why not ('canceled' when the user closed it). }
  TAuthDoneEvent = procedure(Sender: TObject; Ok: Boolean; const Error: string) of object;
  { What the device can check the user with: nothing set up, the screen lock (PIN,
    pattern, password), a fingerprint or the face. }
  TAuthKind = (akNone, akDeviceLock, akBiometric);
  { The answer of ScanBarcode: the code's text and its kind ('QR', 'EAN13', 'Code128'...). }
  TScanDoneEvent = procedure(Sender: TObject; Ok: Boolean; const Text, Format: string) of object;

{ The share menu (WhatsApp, mail, messages...) with a text; False where there is none. }
function ShareText(const Text: string; const Subject: string = ''): Boolean;
{ The share menu with a file of the app (a PDF, a photo). }
function ShareFile(const FileName: string; const MimeType: string = ''): Boolean;
{ An address in the browser, or a file in the app for it. }
function OpenUrl(const UrlOrFile: string): Boolean;
{ A short buzz (phones). }
procedure Vibrate(Milliseconds: Integer = 40);
{ A message in the notification bar; the same Id replaces the one before
  (Pastel.Notifications has more: at a time, again and again, taken back). }
function Notify(const Title, Text: string; Id: Integer = 1): Boolean;
{ Asks the user for a permission when the app does not have it yet; True when it has it. }
function RequestPermission(Permission: TDevicePermission): Boolean; overload;
{ A file the user picks ('image/*', 'application/pdf', '*/*'): its path ('' when
  cancelled). On a phone a copy in the app's cache. }
function PickFile(const MimeType: string = '*/*'): string; overload;
{ A photo from the camera app: the path of the .jpg ('' when cancelled or there is no camera). }
function TakePhoto: string; overload;
{ The place of the device (asks for the permission first). }
function GetLocation(out Place: TPlace; TimeoutMs: Integer = 15000): Boolean; overload;

{ The same without waiting: they return at once; the method given is called
  with the answer (always later, never inside the call; LastDeviceError says
  why when it did not work). }
procedure RequestPermission(Permission: TDevicePermission; OnDone: TPermissionDoneEvent); overload;
procedure PickFile(const MimeType: string; OnDone: TFileDoneEvent); overload;
procedure TakePhoto(OnDone: TFileDoneEvent); overload;
procedure GetLocation(OnDone: TPlaceDoneEvent; TimeoutMs: Integer = 15000); overload;
{ Several at once, in one question of the phone (camera and microphone for a video). }
procedure RequestPermissions(Permissions: TDevicePermissions; OnDone: TPermissionsDoneEvent);
{ Where a permission stands, without asking (computers: psGranted). }
function PermissionState(Permission: TDevicePermission): TPermissionState;
{ The app's page in the phone's settings, where a permission refused for good is given. }
procedure OpenAppSettings;
{ "Is it you?": the fingerprint, the face or (AllowPin) the phone's PIN, pattern
  or password, with Reason shown - before a payment, to open the app's secrets.
  Android 9 and newer the system's dialog; older ones the lock screen's check.
  Computers: not there (OnDone with False). }
procedure Authenticate(const Reason: string; OnDone: TAuthDoneEvent; AllowPin: Boolean = True;
  const Subtitle: string = '');
function CanAuthenticate: TAuthKind;
{ A QR code or barcode read with the camera: Google's code scanner (its own
  screen, no camera permission) with [package.android] libraries =
  ["com.google.android.gms:play-services-code-scanner:16.1.0"]. Computers: not there. }
procedure ScanBarcode(OnDone: TScanDoneEvent);
{ The screen stays on while the app is open (a recipe, a map, a kiosk); False: it goes dark by itself again. Phones. }
procedure KeepScreenOn(Enable: Boolean);
{ A picture (a photo of TakePhoto, a chart saved as PNG) into the phone's gallery,
  in Pictures/Folder (default: the app's name); False and LastDeviceError when not.
  Computers: copied into the user's Pictures folder. }
function SaveToGallery(const FileName: string; const Folder: string = ''): Boolean;
{ True on Android. }
function IsMobile: Boolean;
{ What another app shared with this one, once (TShareReceiver tells it by itself). }
function TakeSharedContent(out Shared: TSharedContent): Boolean;

{ ---- links and the icon's shortcuts ---- }

{ The link that opened the app, once (TLinkReceiver tells it by itself). }
function TakeOpenedLink(out Url: string): Boolean;
{ The shortcut of the icon that opened the app, once (TLinkReceiver tells it by itself). }
function TakeShortcut(out Id: string): Boolean;
function AppShortcut(const Id, Title: string; const Icon: string = ''): TAppShortcut;
{ The shortcuts shown by a long press on the app's icon (Android 7.1 and newer;
  up to 4 are shown); [] removes them. They stay after the app ends: set them
  at every start (in the user's language). False and LastDeviceError where not. }
function SetAppShortcuts(const Shortcuts: array of TAppShortcut): Boolean;

{ ---- contacts and the calendar ---- }

{ The phone's contact list to choose one from (no permission needed): its name
  and the number (or with Email the e-mail) chosen, in Phones[0] (Emails[0]). }
procedure PickContact(OnDone: TContactDoneEvent; Email: Boolean = False);
{ All contacts with their numbers and e-mails, by name; only those with Search
  in their name, number or e-mail. Needs the permission: [package.android]
  permissions = ["contacts"] and RequestPermission(dpContacts). }
function ReadContacts(out Contacts: TContacts; const Search: string = ''): Boolean;
{ The contacts app with a new contact filled in: the user saves it (no permission). }
function AddContact(const Name: string; const Phone: string = ''; const Email: string = ''): Boolean;
{ A new event in the calendar app, filled in: the user saves it (no permission).
  Computers: an .ics file, opened by the calendar program (Thunderbird, Outlook...). }
function AddToCalendar(const Title: string; Start, Finish: TDateTime; const Place: string = '';
  const Notes: string = ''; AllDay: Boolean = False): Boolean;
{ The events of the phone's calendars from From till Till. Needs the permission:
  [package.android] permissions = ["calendar"] and RequestPermission(dpCalendar). }
function ReadCalendar(out Events: TCalendarEvents; From, Till: TDateTime): Boolean;

{ ---- picture-in-picture ---- }

{ The app's window small, over other apps, with its video playing (Android 8
  and newer, [package.android] picture_in_picture = true). Show only the
  video meanwhile: the form gets the small size (OnResize), InPictureInPicture
  says why. False and LastDeviceError where not. }
function EnterPictureInPicture(AspectW: Integer = 16; AspectH: Integer = 9): Boolean;
function InPictureInPicture: Boolean;
{ Into picture-in-picture by itself when the user goes home while it is on (a
  video playing); off again when it stops. }
procedure AutoPictureInPicture(Enable: Boolean; AspectW: Integer = 16; AspectH: Integer = 9);

{ The address among a program's arguments ('shop://order/42'; not a file), or ''. }
function LinkFromArguments(const Args: array of string): string;

var
  { Why the last call did not work ('' when it did). }
  LastDeviceError: string;
  { Tests: what OpenUrl opens goes here instead (True: opened). }
  OpenUrlHook: function(const UrlOrFile: string): Boolean = nil;

implementation

uses
  Process, Pastel.UI, Pastel.Env, Pastel.Graphics, Pastel.Icons, Pastel.Notifications{$IFDEF ANDROID}, Pastel.Android{$ENDIF};

{ ---- links and the icon's shortcuts ---- }

{$IFNDEF ANDROID}
var
  LinkTaken: Boolean = False;
{$ENDIF}

function LinkFromArguments(const Args: array of string): string;
var
  P: Integer;
  A: string;
begin
  Result := '';
  for A in Args do
  begin
    P := Pos('://', A);
    if (P > 1) and (A[1] in ['a'..'z', 'A'..'Z']) and (LowerCase(Copy(A, 1, P - 1)) <> 'file') and
      not FileExists(A) then
      Exit(A);
  end;
end;

function TakeOpenedLink(out Url: string): Boolean;
{$IFNDEF ANDROID}
var
  I: Integer;
  Args: array of string;
{$ENDIF}
begin
  Url := '';
  {$IFDEF ANDROID}
  Url := AndroidCallString('takeLink', '()Ljava/lang/String;', []);
  {$ELSE}
  { computers: the desktop or Windows started the app with the address (its own scheme) }
  if not LinkTaken then
  begin
    LinkTaken := True;
    Args := nil;
    SetLength(Args, ParamCount);
    for I := 1 to ParamCount do
      Args[I - 1] := ParamStr(I);
    Url := LinkFromArguments(Args);
  end;
  {$ENDIF}
  Result := Url <> '';
end;

function TakeShortcut(out Id: string): Boolean;
begin
  Id := '';
  {$IFDEF ANDROID}
  Id := AndroidCallString('takeShortcut', '()Ljava/lang/String;', []);
  {$ENDIF}
  Result := Id <> '';
end;

function AppShortcut(const Id, Title: string; const Icon: string): TAppShortcut;
begin
  Result.Id := Id;
  Result.Title := Title;
  Result.Icon := Icon;
end;

{$IFDEF ANDROID}
{ a built-in icon as a PNG for the launcher: white on the accent, in a circle }
function ShortcutIconFile(const Name: string): string;
const
  Size = 96;
var
  C: TCanvas32;
begin
  Result := '';
  if not HasIcon(Name) then
    Exit;
  C := TCanvas32.Create;
  try
    C.SetSize(Size, Size);
    C.Clear(0);
    C.FillCircle(Size / 2, Size / 2, Size / 2, Theme.Accent);
    DrawIcon(C, Name, Size div 4, Size div 4, Size div 2, Theme.OnAccent);
    Result := IncludeTrailingPathDelimiter(GetTempDir) + 'shortcut-' + Name + '.png';
    C.SaveToPNG(Result);
  finally
    C.Free;
  end;
end;
{$ENDIF}

function SetAppShortcuts(const Shortcuts: array of TAppShortcut): Boolean;
{$IFDEF ANDROID}
var
  Spec, Err: string;
  S: TAppShortcut;
{$ENDIF}
begin
  LastDeviceError := '';
  {$IFDEF ANDROID}
  Spec := '';
  for S in Shortcuts do
  begin
    if Spec <> '' then
      Spec := Spec + #2;
    Spec := Spec + S.Id + #1 + S.Title + #1 + ShortcutIconFile(S.Icon);
  end;
  Err := AndroidCallString('setShortcuts', '(Ljava/lang/String;)Ljava/lang/String;', [Spec]);
  LastDeviceError := Err;
  Result := Err = '';
  {$ELSE}
  if Length(Shortcuts) = 0 then ;
  LastDeviceError := 'the icon''s shortcuts are for phones';
  Result := False;
  {$ENDIF}
end;

procedure TLinkReceiver.Start;
begin
  if (FTimer = nil) and not (csDesigning in ComponentState) then
  begin
    FTimer := TTimer.Create(Self);
    TTimer(FTimer).Interval := 250;
    TTimer(FTimer).OnTimer := @Tick;
    TTimer(FTimer).Enabled := True;
  end;
end;

procedure TLinkReceiver.SetOnLink(AValue: TLinkEvent);
begin
  FOnLink := AValue;
  if Assigned(FOnLink) then
    Start;
end;

procedure TLinkReceiver.SetOnShortcut(AValue: TShortcutEvent);
begin
  FOnShortcut := AValue;
  if Assigned(FOnShortcut) then
    Start;
end;

procedure TLinkReceiver.Tick(Sender: TObject);
var
  S: string;
begin
  if Assigned(FOnLink) and TakeOpenedLink(S) then
    FOnLink(Self, S);
  if Assigned(FOnShortcut) and TakeShortcut(S) then
    FOnShortcut(Self, S);
end;

{ ---- contacts and the calendar ---- }

function LocalText(D: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', D);
end;

function LocalTime(const S: string): TDateTime;
var
  Y, M, D, H, N, Sec: Integer;
begin
  Result := 0;
  if (Length(S) < 19) or not TryStrToInt(Copy(S, 1, 4), Y) or not TryStrToInt(Copy(S, 6, 2), M) or
    not TryStrToInt(Copy(S, 9, 2), D) or not TryStrToInt(Copy(S, 12, 2), H) or
    not TryStrToInt(Copy(S, 15, 2), N) or not TryStrToInt(Copy(S, 18, 2), Sec) then
    Exit;
  if not TryEncodeDate(Y, M, D, Result) then
    Exit(0);
  Result := Result + EncodeTime(H mod 24, N mod 60, Sec mod 60, 0);
end;

function ContactOf(const Text: string): TContact;
var
  P: TStringArray;
begin
  Result := Default(TContact);
  P := Text.Split([#1]);
  if Length(P) < 1 then
    Exit;
  Result.Name := P[0];
  if (Length(P) > 1) and (P[1] <> '') then
    Result.Phones := P[1].Split([#2]);
  if (Length(P) > 2) and (P[2] <> '') then
    Result.Emails := P[2].Split([#2]);
end;

function ReadContacts(out Contacts: TContacts; const Search: string): Boolean;
{$IFDEF ANDROID}
var
  S, L: string;
{$ENDIF}
begin
  Contacts := nil;
  LastDeviceError := '';
  {$IFDEF ANDROID}
  S := AndroidCallString('readContacts', '(Ljava/lang/String;)Ljava/lang/String;', [Search]);
  if (S <> '') and (S[1] = '!') then
  begin
    LastDeviceError := Copy(S, 2, MaxInt);
    Exit(False);
  end;
  for L in S.Split([#10]) do
    if L <> '' then
    begin
      SetLength(Contacts, Length(Contacts) + 1);
      Contacts[High(Contacts)] := ContactOf(L);
    end;
  Result := True;
  {$ELSE}
  if Search = '' then ;
  LastDeviceError := 'the contacts are the phone''s';
  Result := False;
  {$ENDIF}
end;

function AddContact(const Name: string; const Phone: string; const Email: string): Boolean;
begin
  {$IFDEF ANDROID}
  LastDeviceError := AndroidCallString('addContact', '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
    [Name, Phone, Email]);
  {$ELSE}
  if (Name = '') and (Phone = '') and (Email = '') then ;
  LastDeviceError := 'the contacts are the phone''s';
  {$ENDIF}
  Result := LastDeviceError = '';
end;

{$IFNDEF ANDROID}
{ the event as an .ics file: the computer's calendar program opens it }
function CalendarFile(const Title: string; Start, Finish: TDateTime; const Place, Notes: string;
  AllDay: Boolean): string;

  function Esc(const S: string): string;
  begin
    Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
    Result := StringReplace(Result, ';', '\;', [rfReplaceAll]);
    Result := StringReplace(Result, ',', '\,', [rfReplaceAll]);
    Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
    Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  end;

var
  L: TStringList;
  Stamp: string;
begin
  L := TStringList.Create;
  try
    L.LineBreak := #13#10;
    Stamp := FormatDateTime('yyyymmdd"T"hhnnss', Now);
    L.Add('BEGIN:VCALENDAR');
    L.Add('VERSION:2.0');
    L.Add('PRODID:-//Pastel//Pastel.Device//EN');
    L.Add('BEGIN:VEVENT');
    L.Add('UID:' + Stamp + '-' + IntToStr(Random(MaxInt)) + '@pastel');
    L.Add('DTSTAMP:' + Stamp);
    if AllDay then
    begin
      if Trunc(Finish) <= Trunc(Start) then
        Finish := Trunc(Start) + 1;
      L.Add('DTSTART;VALUE=DATE:' + FormatDateTime('yyyymmdd', Start));
      L.Add('DTEND;VALUE=DATE:' + FormatDateTime('yyyymmdd', Finish));
    end
    else
    begin
      L.Add('DTSTART:' + FormatDateTime('yyyymmdd"T"hhnnss', Start));
      L.Add('DTEND:' + FormatDateTime('yyyymmdd"T"hhnnss', Finish));
    end;
    L.Add('SUMMARY:' + Esc(Title));
    if Place <> '' then
      L.Add('LOCATION:' + Esc(Place));
    if Notes <> '' then
      L.Add('DESCRIPTION:' + Esc(Notes));
    L.Add('END:VEVENT');
    L.Add('END:VCALENDAR');
    Result := IncludeTrailingPathDelimiter(GetTempDir) + 'event-' + Stamp + '.ics';
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;
{$ENDIF}

function AddToCalendar(const Title: string; Start, Finish: TDateTime; const Place: string;
  const Notes: string; AllDay: Boolean): Boolean;
{$IFNDEF ANDROID}
var
  F: string;
{$ENDIF}
begin
  LastDeviceError := '';
  if Finish < Start then
    Finish := Start;
  {$IFDEF ANDROID}
  LastDeviceError := AndroidCallString('addEvent',
    '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZLjava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
    [Title, LocalText(Start), LocalText(Finish), AllDay, Place, Notes]);
  Result := LastDeviceError = '';
  {$ELSE}
  try
    F := CalendarFile(Title, Start, Finish, Place, Notes, AllDay);
  except
    on E: Exception do
    begin
      LastDeviceError := E.Message;
      Exit(False);
    end;
  end;
  Result := OpenUrl(F);
  {$ENDIF}
end;

function ReadCalendar(out Events: TCalendarEvents; From, Till: TDateTime): Boolean;
{$IFDEF ANDROID}
var
  S, L: string;
  P: TStringArray;
  E: TCalendarEvent;
{$ENDIF}
begin
  Events := nil;
  LastDeviceError := '';
  {$IFDEF ANDROID}
  S := AndroidCallString('readEvents', '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
    [LocalText(From), LocalText(Till)]);
  if (S <> '') and (S[1] = '!') then
  begin
    LastDeviceError := Copy(S, 2, MaxInt);
    Exit(False);
  end;
  for L in S.Split([#10]) do
  begin
    P := L.Split([#1]);
    if Length(P) < 6 then
      Continue;
    E.Title := P[0];
    E.Place := P[1];
    E.Notes := P[2];
    E.Start := LocalTime(P[3]);
    E.Finish := LocalTime(P[4]);
    E.AllDay := P[5] = '1';
    SetLength(Events, Length(Events) + 1);
    Events[High(Events)] := E;
  end;
  Result := True;
  {$ELSE}
  if From > Till then ;
  LastDeviceError := 'the calendar is the phone''s (AddToCalendar works on computers too)';
  Result := False;
  {$ENDIF}
end;

{ ---- picture-in-picture ---- }

function EnterPictureInPicture(AspectW: Integer; AspectH: Integer): Boolean;
begin
  {$IFDEF ANDROID}
  LastDeviceError := AndroidCallString('enterPip', '(II)Ljava/lang/String;', [AspectW, AspectH]);
  {$ELSE}
  if AspectW = AspectH then ;
  LastDeviceError := 'picture-in-picture is for phones';
  {$ENDIF}
  Result := LastDeviceError = '';
end;

function InPictureInPicture: Boolean;
begin
  {$IFDEF ANDROID}
  Result := AndroidCallString('inPip', '()Ljava/lang/String;', []) = '1';
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure AutoPictureInPicture(Enable: Boolean; AspectW: Integer; AspectH: Integer);
begin
  {$IFDEF ANDROID}
  AndroidCall('setPipAuto', '(ZII)V', [Enable, AspectW, AspectH]);
  {$ELSE}
  if Enable and (AspectW = AspectH) then ;
  {$ENDIF}
end;

function TakeSharedContent(out Shared: TSharedContent): Boolean;
{$IFDEF ANDROID}
var
  S: string;
  Parts: TStringArray;
{$ENDIF}
begin
  Shared := Default(TSharedContent);
  Result := False;
  {$IFDEF ANDROID}
  S := AndroidCallString('takeShared', '()Ljava/lang/String;', []);
  if S = '' then
    Exit;
  Parts := S.Split([#1]);
  if Length(Parts) < 4 then
    Exit;
  Shared.Subject := Parts[0];
  Shared.Text := Parts[1];
  Shared.MimeType := Parts[2];
  if Parts[3] <> '' then
    Shared.Files := Parts[3].Split([#2]);
  Result := True;
  {$ENDIF}
end;

procedure TShareReceiver.SetOnShareReceived(AValue: TShareReceivedEvent);
begin
  FOnShareReceived := AValue;
  if Assigned(FOnShareReceived) and (FTimer = nil) and not (csDesigning in ComponentState) then
  begin
    FTimer := TTimer.Create(Self);
    TTimer(FTimer).Interval := 300;
    TTimer(FTimer).OnTimer := @Tick;
  end;
end;

procedure TShareReceiver.Tick(Sender: TObject);
var
  S: TSharedContent;
begin
  if Assigned(FOnShareReceived) and TakeSharedContent(S) then
    FOnShareReceived(Self, S);
end;

function IsMobile: Boolean;
begin
  {$IFDEF ANDROID}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

{$IFDEF ANDROID}
{ waits for the answer to a request, keeping the window alive }
function WaitFor(Code: Integer; out Text: string): Boolean;
begin
  while not AndroidTakeResult(Code, Result, Text) do
  begin
    if Assigned(ModalStep) then
      ModalStep
    else
      Sleep(20);
    if AndroidDestroyRequested then
      Exit(False);
  end;
end;

const
  { Android's names: several for one, a line each (the phone asks once) }
  PermissionNames: array[TDevicePermission] of string = (
    'android.permission.ACCESS_FINE_LOCATION'#10'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO',
    'android.permission.READ_CONTACTS',
    'android.permission.READ_CALENDAR'#10'android.permission.WRITE_CALENDAR',
    'android.permission.CALL_PHONE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.BLUETOOTH_CONNECT'#10'android.permission.BLUETOOTH_SCAN');
{$ENDIF}

function ShareText(const Text: string; const Subject: string): Boolean;
begin
  LastDeviceError := '';
  {$IFDEF ANDROID}
  Result := AndroidCall('shareText', '(Ljava/lang/String;Ljava/lang/String;)V', [Text, Subject]);
  {$ELSE}
  LastDeviceError := 'there is no share menu on this computer';
  Result := False;
  {$ENDIF}
end;

function ShareFile(const FileName: string; const MimeType: string): Boolean;
begin
  LastDeviceError := '';
  if not FileExists(FileName) then
  begin
    LastDeviceError := FileName + ' does not exist';
    Exit(False);
  end;
  {$IFDEF ANDROID}
  Result := AndroidCall('shareFile', '(Ljava/lang/String;Ljava/lang/String;)V', [ExpandFileName(FileName), MimeType]);
  {$ELSE}
  LastDeviceError := 'there is no share menu on this computer';
  Result := False;
  {$ENDIF}
end;

function OpenUrl(const UrlOrFile: string): Boolean;
{$IFNDEF ANDROID}
var
  P: TProcess;
{$ENDIF}
begin
  LastDeviceError := '';
  if Assigned(OpenUrlHook) then
    Exit(OpenUrlHook(UrlOrFile));
  {$IFDEF ANDROID}
  if FileExists(UrlOrFile) then
    Result := AndroidCall('openUrl', '(Ljava/lang/String;)Z', [ExpandFileName(UrlOrFile)])
  else
    Result := AndroidCall('openUrl', '(Ljava/lang/String;)Z', [UrlOrFile]);
  {$ELSE}
  P := TProcess.Create(nil);
  try
    {$IFDEF WINDOWS}
    P.Executable := 'cmd';
    P.Parameters.Add('/c');
    P.Parameters.Add('start');
    P.Parameters.Add('');
    {$ELSE}
    {$IFDEF DARWIN}
    P.Executable := 'open';
    {$ELSE}
    P.Executable := 'xdg-open';
    {$ENDIF}
    {$ENDIF}
    P.Parameters.Add(UrlOrFile);
    P.Options := [poNoConsole];
    try
      P.Execute;
      Result := True;
    except
      on E: Exception do
      begin
        LastDeviceError := E.Message;
        Result := False;
      end;
    end;
  finally
    P.Free;
  end;
  {$ENDIF}
end;

procedure Vibrate(Milliseconds: Integer);
begin
  {$IFDEF ANDROID}
  AndroidCall('vibrate', '(I)V', [Milliseconds]);
  {$ENDIF}
end;

function Notify(const Title, Text: string; Id: Integer): Boolean;
begin
  { Pastel.Notifications does it (each platform its own way) }
  Result := ShowNotification(Title, Text, 'notify-' + IntToStr(Id));
  LastDeviceError := LastNotificationError;
end;

function RequestPermission(Permission: TDevicePermission): Boolean;
{$IFDEF ANDROID}
var
  Code: Integer;
  Text: string;
{$ENDIF}
begin
  LastDeviceError := '';
  {$IFDEF ANDROID}
  Code := AndroidNewRequest;
  if not AndroidCall('requestPermission', '(ILjava/lang/String;)V', [Code, PermissionNames[Permission]]) then
    Exit(False);
  Result := WaitFor(Code, Text);
  if not Result then
    LastDeviceError := 'the permission was not given';
  {$ELSE}
  Result := True;
  {$ENDIF}
end;

function PickFile(const MimeType: string): string;
{$IFDEF ANDROID}
var
  Code: Integer;
{$ENDIF}
begin
  LastDeviceError := '';
  Result := '';
  {$IFDEF ANDROID}
  Code := AndroidNewRequest;
  if AndroidCall('pickFile', '(ILjava/lang/String;)V', [Code, MimeType]) then
    if not WaitFor(Code, Result) then
    begin
      LastDeviceError := Result;
      Result := '';
    end;
  {$ELSE}
  if not OpenFileDialog(Result) then
    Result := '';
  {$ENDIF}
end;

function TakePhoto: string;
{$IFDEF ANDROID}
var
  Code: Integer;
{$ENDIF}
begin
  LastDeviceError := '';
  Result := '';
  {$IFDEF ANDROID}
  Code := AndroidNewRequest;
  if AndroidCall('takePhoto', '(I)V', [Code]) then
    if not WaitFor(Code, Result) then
    begin
      LastDeviceError := 'no photo was taken';
      Result := '';
    end;
  {$ELSE}
  LastDeviceError := 'there is no camera app on this computer';
  {$ENDIF}
end;

function GetLocation(out Place: TPlace; TimeoutMs: Integer): Boolean;
{$IFDEF ANDROID}
var
  Code: Integer;
  Text: string;
  Parts: TStringArray;
  FS: TFormatSettings;
{$ENDIF}
begin
  LastDeviceError := '';
  Place := Default(TPlace);
  Result := False;
  {$IFDEF ANDROID}
  if not RequestPermission(dpLocation) then
  begin
    LastDeviceError := 'the app may not know the place (permission refused)';
    Exit;
  end;
  Code := AndroidNewRequest;
  if not AndroidCall('location', '(II)V', [Code, TimeoutMs]) then
    Exit;
  if not WaitFor(Code, Text) then
  begin
    LastDeviceError := Text;
    Exit;
  end;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Parts := Text.Split([',']);
  if Length(Parts) >= 2 then
  begin
    Place.Latitude := StrToFloatDef(Parts[0], 0, FS);
    Place.Longitude := StrToFloatDef(Parts[1], 0, FS);
    if Length(Parts) >= 3 then
      Place.Accuracy := StrToFloatDef(Parts[2], 0, FS);
    Result := True;
  end;
  {$ELSE}
  LastDeviceError := 'this computer does not know its place';
  {$ENDIF}
end;

{ ---- without waiting ---- }

type
  TRequestKind = (rkPermission, rkFile, rkPhoto, rkLocationPermission, rkLocation, rkPermissions, rkAuth, rkScan,
    rkContact);

  { a request to the phone waiting for its answer (or an answer there at once) }
  TRequest = class
    Kind: TRequestKind;
    Code, TimeoutMs: Integer;
    Done, Ok: Boolean;
    Text, Error: string;
    OnPermission: TPermissionDoneEvent;
    OnPermissions: TPermissionsDoneEvent;
    Asked: TDevicePermissions;
    OnFile: TFileDoneEvent;
    OnPlace: TPlaceDoneEvent;
    OnAuth: TAuthDoneEvent;
    OnScan: TScanDoneEvent;
    OnContact: TContactDoneEvent;
  end;

  { looks for the answers a few times a second while there are requests }
  TRequests = class(TComponent)
  private
    FList: TFPList;
    FTimer: TTimer;
    procedure Tick(Sender: TObject);
    procedure Give(R: TRequest);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Add(R: TRequest);
  end;

var
  Requests: TRequests = nil;

constructor TRequests.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FList := TFPList.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 30;
  FTimer.Enabled := False;
  FTimer.OnTimer := @Tick;
end;

destructor TRequests.Destroy;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    TObject(FList[I]).Free;
  FList.Free;
  inherited Destroy;
end;

procedure TRequests.Add(R: TRequest);
begin
  FList.Add(R);
  FTimer.Enabled := True;
end;

function NewRequest(Kind: TRequestKind): TRequest;
begin
  if Requests = nil then
    Requests := TRequests.Create(nil);
  Result := TRequest.Create;
  Result.Kind := Kind;
end;

{ an answer that is there at once (no camera on a computer...), given later like the others }
procedure AnswerNow(R: TRequest; Ok: Boolean; const Text, Error: string);
begin
  R.Done := True;
  R.Ok := Ok;
  R.Text := Text;
  R.Error := Error;
  Requests.Add(R);
end;

{$IFDEF ANDROID}
{ asks Android: Method(code) or Method(code, Arg); False when the call did not work }
function Start(R: TRequest; const Method: string; const Arg: string = #0): Boolean;
begin
  R.Code := AndroidNewRequest;
  if Arg = #0 then
    Result := AndroidCall(Method, '(I)V', [R.Code])
  else
    Result := AndroidCall(Method, '(ILjava/lang/String;)V', [R.Code, Arg]);
  if Result then
    Requests.Add(R)
  else
    AnswerNow(R, False, '', LastDeviceError);
end;

function StartLocation(R: TRequest): Boolean;
begin
  R.Kind := rkLocation;
  R.Done := False;
  R.Code := AndroidNewRequest;
  Result := AndroidCall('location', '(II)V', [R.Code, R.TimeoutMs]);
end;
{$ENDIF}

function ParsePlace(const Text: string; out Place: TPlace): Boolean;
var
  Parts: TStringArray;
  FS: TFormatSettings;
begin
  Place := Default(TPlace);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Parts := Text.Split([',']);
  Result := Length(Parts) >= 2;
  if Result then
  begin
    Place.Latitude := StrToFloatDef(Parts[0], 0, FS);
    Place.Longitude := StrToFloatDef(Parts[1], 0, FS);
    if Length(Parts) >= 3 then
      Place.Accuracy := StrToFloatDef(Parts[2], 0, FS);
  end;
end;

{ the answer's lines: android.permission.CAMERA=granted|denied|blocked }
function StateIn(const Text, Names: string): TPermissionState;
var
  N, L, V: string;
begin
  Result := psGranted;
  for N in Names.Split([#10]) do
  begin
    V := 'denied';
    for L in Text.Split([#10]) do
      if Copy(L, 1, Length(N) + 1) = N + '=' then
        V := Copy(L, Length(N) + 2, MaxInt);
    if V = 'blocked' then
      Exit(psBlocked);
    if V <> 'granted' then
      Result := psDenied;
  end;
end;

function GrantedOf(R: TRequest): TDevicePermissions;
var
  P: TDevicePermission;
begin
  Result := [];
  for P in R.Asked do
    {$IFDEF ANDROID}
    if R.Ok or (StateIn(R.Text, PermissionNames[P]) = psGranted) then
    {$ENDIF}
      Include(Result, P);
end;

function BlockedOf(R: TRequest): TDevicePermissions;
{$IFDEF ANDROID}
var
  P: TDevicePermission;
{$ENDIF}
begin
  Result := [];
  {$IFDEF ANDROID}
  if not R.Ok then
    for P in R.Asked do
      if StateIn(R.Text, PermissionNames[P]) = psBlocked then
        Include(Result, P);
  {$ENDIF}
end;

procedure TRequests.Tick(Sender: TObject);
var
  I: Integer;
  R: TRequest;
  Ready: TFPList;
begin
  Ready := TFPList.Create;
  try
    for I := FList.Count - 1 downto 0 do
    begin
      R := TRequest(FList[I]);
      {$IFDEF ANDROID}
      if not R.Done then
        if AndroidTakeResult(R.Code, R.Ok, R.Text) then
        begin
          R.Done := True;
          { the place: first the permission, then the place itself }
          if (R.Kind = rkLocationPermission) and R.Ok then
            if not StartLocation(R) then
            begin
              R.Done := True;
              R.Ok := False;
              R.Error := 'the place could not be asked for';
            end;
        end
        else if AndroidDestroyRequested then
        begin
          R.Done := True;
          R.Ok := False;
        end;
      {$ENDIF}
      if R.Done then
      begin
        FList.Delete(I);
        Ready.Insert(0, R);
      end;
    end;
    FTimer.Enabled := FList.Count > 0;
    for I := 0 to Ready.Count - 1 do
      Give(TRequest(Ready[I]));
  finally
    Ready.Free;
  end;
end;

procedure TRequests.Give(R: TRequest);
var
  Place: TPlace;
begin
  try
    LastDeviceError := R.Error;
    case R.Kind of
      rkScan:
        begin
          if not R.Ok and (R.Error = '') then
            R.Error := R.Text;
          LastDeviceError := R.Error;
          if Assigned(R.OnScan) then
            if R.Ok then
              R.OnScan(nil, True, Copy(R.Text, Pos(#9, R.Text) + 1, MaxInt), Copy(R.Text, 1, Pos(#9, R.Text) - 1))
            else
              R.OnScan(nil, False, '', '');
        end;
      rkAuth:
        begin
          if not R.Ok and (R.Error = '') then
            R.Error := R.Text;
          LastDeviceError := R.Error;
          if Assigned(R.OnAuth) then
            R.OnAuth(nil, R.Ok, R.Error);
        end;
      rkPermissions:
        if Assigned(R.OnPermissions) then
          R.OnPermissions(nil, GrantedOf(R), BlockedOf(R));
      rkPermission:
        begin
          if not R.Ok and (LastDeviceError = '') then
            LastDeviceError := 'the permission was not given';
          if Assigned(R.OnPermission) then
            R.OnPermission(nil, R.Ok);
        end;
      rkFile, rkPhoto:
        begin
          if not R.Ok then
          begin
            if (LastDeviceError = '') and (R.Kind = rkPhoto) then
              LastDeviceError := 'no photo was taken'
            else if LastDeviceError = '' then
              LastDeviceError := R.Text;
            R.Text := '';
          end;
          if Assigned(R.OnFile) then
            R.OnFile(nil, R.Ok, R.Text);
        end;
      rkContact:
        begin
          if not R.Ok then
          begin
            if LastDeviceError = '' then
              LastDeviceError := R.Text;
            R.Text := '';
          end;
          if Assigned(R.OnContact) then
            R.OnContact(nil, R.Ok, ContactOf(R.Text));
        end;
      rkLocationPermission, rkLocation:
        begin
          Place := Default(TPlace);
          if R.Ok and (R.Kind = rkLocation) then
            R.Ok := ParsePlace(R.Text, Place)
          else
          begin
            R.Ok := False;
            if (LastDeviceError = '') and (R.Kind = rkLocationPermission) then
              LastDeviceError := 'the app may not know the place (permission refused)'
            else if LastDeviceError = '' then
              LastDeviceError := R.Text;
          end;
          if Assigned(R.OnPlace) then
            R.OnPlace(nil, R.Ok, Place);
        end;
    end;
  finally
    R.Free;
  end;
end;

procedure RequestPermission(Permission: TDevicePermission; OnDone: TPermissionDoneEvent);
var
  R: TRequest;
begin
  LastDeviceError := '';
  R := NewRequest(rkPermission);
  R.OnPermission := OnDone;
  {$IFDEF ANDROID}
  Start(R, 'requestPermission', PermissionNames[Permission]);
  {$ELSE}
  AnswerNow(R, True, '', '');
  {$ENDIF}
end;

procedure RequestPermissions(Permissions: TDevicePermissions; OnDone: TPermissionsDoneEvent);
var
  R: TRequest;
  {$IFDEF ANDROID}
  P: TDevicePermission;
  Names: string;
  {$ENDIF}
begin
  LastDeviceError := '';
  R := NewRequest(rkPermissions);
  R.OnPermissions := OnDone;
  R.Asked := Permissions;
  {$IFDEF ANDROID}
  Names := '';
  for P in Permissions do
    Names := Names + PermissionNames[P] + #10;
  Start(R, 'requestPermissions', Names);
  {$ELSE}
  AnswerNow(R, True, '', '');
  {$ENDIF}
end;

function PermissionState(Permission: TDevicePermission): TPermissionState;
{$IFDEF ANDROID}
var
  N, S: string;
{$ENDIF}
begin
  Result := psGranted;
  {$IFDEF ANDROID}
  for N in PermissionNames[Permission].Split([#10]) do
  begin
    S := AndroidCallString('permissionState', '(Ljava/lang/String;)Ljava/lang/String;', [N]);
    if S = 'blocked' then
      Exit(psBlocked)
    else if (S = 'denied') and (Result <> psBlocked) then
      Result := psDenied
    else if (S = 'unknown') and (Result = psGranted) then
      Result := psNotAsked;
  end;
  {$ENDIF}
end;

procedure Authenticate(const Reason: string; OnDone: TAuthDoneEvent; AllowPin: Boolean; const Subtitle: string);
var
  R: TRequest;
begin
  LastDeviceError := '';
  R := NewRequest(rkAuth);
  R.OnAuth := OnDone;
  {$IFDEF ANDROID}
  R.Code := AndroidNewRequest;
  if AndroidCall('authenticate', '(ILjava/lang/String;Ljava/lang/String;Z)V', [R.Code, Reason, Subtitle, AllowPin]) then
    Requests.Add(R)
  else
    AnswerNow(R, False, '', 'the check cannot be started');
  {$ELSE}
  if (Reason = '') and AllowPin and (Subtitle = '') then ;
  AnswerNow(R, False, '', 'there is no fingerprint or PIN check on this computer');
  {$ENDIF}
end;

procedure ScanBarcode(OnDone: TScanDoneEvent);
var
  R: TRequest;
begin
  LastDeviceError := '';
  R := NewRequest(rkScan);
  R.OnScan := OnDone;
  {$IFDEF ANDROID}
  Start(R, 'scanBarcode');
  {$ELSE}
  AnswerNow(R, False, '', 'scanning with the camera is there on phones');
  {$ENDIF}
end;

function CanAuthenticate: TAuthKind;
{$IFDEF ANDROID}
var
  S: string;
{$ENDIF}
begin
  Result := akNone;
  {$IFDEF ANDROID}
  S := AndroidCallString('authAvailable', '()Ljava/lang/String;', []);
  if S = 'biometric' then
    Result := akBiometric
  else if S = 'credential' then
    Result := akDeviceLock;
  {$ENDIF}
end;

procedure KeepScreenOn(Enable: Boolean);
begin
  {$IFDEF ANDROID}
  AndroidCall('keepScreenOn', '(Z)V', [Enable]);
  {$ELSE}
  if Enable then ;
  {$ENDIF}
end;

procedure OpenAppSettings;
begin
  {$IFDEF ANDROID}
  AndroidCall('openAppSettings', '()V', []);
  {$ENDIF}
end;

function SaveToGallery(const FileName: string; const Folder: string): Boolean;
var
  Dir, F, Ext, Mime: string;
  {$IFNDEF ANDROID}
  Src, Dst: TFileStream;
  {$ENDIF}
begin
  LastDeviceError := '';
  F := Folder;
  if F = '' then
    F := ApplicationName;
  if F = '' then
    F := 'Pastel';
  if not FileExists(FileName) then
  begin
    LastDeviceError := 'there is no file ' + FileName;
    Exit(False);
  end;
  Ext := LowerCase(ExtractFileExt(FileName));
  case Ext of
    '.png': Mime := 'image/png';
    '.gif': Mime := 'image/gif';
    '.webp': Mime := 'image/webp';
  else
    Mime := 'image/jpeg';
  end;
  {$IFDEF ANDROID}
  Dir := AndroidCallString('saveToGallery', '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
    [FileName, F, Mime]);
  Result := (Dir <> '') and (Dir[1] <> '!');
  if not Result then
  begin
    LastDeviceError := Copy(Dir, 2, MaxInt);
    if LastDeviceError = '' then
      LastDeviceError := 'the picture could not be saved';
  end;
  {$ELSE}
  { a computer: the Pictures folder (XDG on Linux, the user's on Windows and macOS) }
  Dir := GetEnv('XDG_PICTURES_DIR');
  if Dir = '' then
    Dir := IncludeTrailingPathDelimiter(GetUserDir) + 'Pictures';
  Dir := IncludeTrailingPathDelimiter(Dir) + F;
  try
    ForceDirectories(Dir);
    Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      Dst := TFileStream.Create(IncludeTrailingPathDelimiter(Dir) + ExtractFileName(FileName), fmCreate);
      try
        Dst.CopyFrom(Src, 0);
      finally
        Dst.Free;
      end;
    finally
      Src.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      LastDeviceError := E.Message;
      Result := False;
    end;
  end;
  if Mime = '' then ;
  {$ENDIF}
end;

procedure PickFile(const MimeType: string; OnDone: TFileDoneEvent);
var
  R: TRequest;
begin
  LastDeviceError := '';
  {$IFDEF ANDROID}
  R := NewRequest(rkFile);
  R.OnFile := OnDone;
  Start(R, 'pickFile', MimeType);
  {$ELSE}
  R := nil;
  if R <> nil then ;
  OpenFileDialog('', '', 'Open', OnDone);
  {$ENDIF}
end;

procedure PickContact(OnDone: TContactDoneEvent; Email: Boolean);
var
  R: TRequest;
begin
  LastDeviceError := '';
  R := NewRequest(rkContact);
  R.OnContact := OnDone;
  {$IFDEF ANDROID}
  R.Code := AndroidNewRequest;
  if AndroidCall('pickContact', '(IZ)V', [R.Code, Email]) then
    Requests.Add(R)
  else
    AnswerNow(R, False, '', LastDeviceError);
  {$ELSE}
  if Email then ;
  AnswerNow(R, False, '', 'the contacts are the phone''s');
  {$ENDIF}
end;

procedure TakePhoto(OnDone: TFileDoneEvent);
var
  R: TRequest;
begin
  LastDeviceError := '';
  R := NewRequest(rkPhoto);
  R.OnFile := OnDone;
  {$IFDEF ANDROID}
  Start(R, 'takePhoto');
  {$ELSE}
  AnswerNow(R, False, '', 'there is no camera app on this computer');
  {$ENDIF}
end;

procedure GetLocation(OnDone: TPlaceDoneEvent; TimeoutMs: Integer);
var
  R: TRequest;
begin
  LastDeviceError := '';
  R := NewRequest(rkLocationPermission);
  R.OnPlace := OnDone;
  R.TimeoutMs := TimeoutMs;
  {$IFDEF ANDROID}
  Start(R, 'requestPermission', PermissionNames[dpLocation]);
  {$ELSE}
  R.Kind := rkLocation;
  AnswerNow(R, False, '', 'this computer does not know its place');
  {$ENDIF}
end;

initialization
  RegisterNonVisual(TShareReceiver);
  RegisterNonVisual(TLinkReceiver);

finalization
  FreeAndNil(Requests);

end.
