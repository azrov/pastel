{ Tests of Pastel.Device on a computer: permissions are there, pictures go to the Pictures folder. }
unit device_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.UI, Pastel.Device;

type
  TDeviceTests = class(TTestSuite)
  private
    FGranted, FBlocked: TDevicePermissions;
    FAnswered, FAuthOk: Boolean;
    FAuthError: string;
    FContactOk: Boolean;
    procedure AuthDone(Sender: TObject; Ok: Boolean; const Error: string);
    procedure ContactDone(Sender: TObject; Ok: Boolean; const Contact: TContact);
    procedure Answered(Sender: TObject; Granted, Blocked: TDevicePermissions);
  published
    procedure PermissionsOnAComputer;
    procedure PicturesIntoThePicturesFolder;
    procedure NoFingerprintOnAComputer;
    procedure CalendarEventsAsIcsFiles;
    procedure LinksAmongTheArguments;
    procedure ContactsAndShortcutsAreThePhones;
  end;

implementation

uses
  Pastel.Files, Pastel.Env;

procedure TDeviceTests.Answered(Sender: TObject; Granted, Blocked: TDevicePermissions);
begin
  FAnswered := True;
  FGranted := Granted;
  FBlocked := Blocked;
end;

procedure TDeviceTests.AuthDone(Sender: TObject; Ok: Boolean; const Error: string);
begin
  FAnswered := True;
  FAuthOk := Ok;
  FAuthError := Error;
end;

procedure TDeviceTests.ContactDone(Sender: TObject; Ok: Boolean; const Contact: TContact);
begin
  FAnswered := True;
  FContactOk := Ok;
end;

var
  Opened: string;

function KeepOpened(const UrlOrFile: string): Boolean;
begin
  Opened := UrlOrFile;
  Result := True;
end;

procedure TDeviceTests.CalendarEventsAsIcsFiles;
var
  Ics: string;
begin
  OpenUrlHook := @KeepOpened;
  try
    Opened := '';
    AssertTrue(AddToCalendar('Haircut; Ayşe, color', EncodeDate(2026, 12, 3) + EncodeTime(10, 30, 0, 0),
      EncodeDate(2026, 12, 3) + EncodeTime(11, 15, 0, 0), 'Salon, Kadıköy', 'line one' + LineEnding + 'line two'), LastDeviceError);
    AssertTrue(ExtractFileExt(Opened) = '.ics', 'the calendar program gets an .ics: ' + Opened);
    Ics := ReadText(Opened);
    AssertTrue(Pos('BEGIN:VEVENT', Ics) > 0);
    AssertTrue(Pos('DTSTART:20261203T103000', Ics) > 0, 'local time');
    AssertTrue(Pos('DTEND:20261203T111500', Ics) > 0);
    AssertTrue(Pos('SUMMARY:Haircut\; Ayşe\, color', Ics) > 0, 'escaped: ' + Ics);
    AssertTrue(Pos('LOCATION:Salon\, Kadıköy', Ics) > 0);
    AssertTrue(Pos('DESCRIPTION:line one\nline two', Ics) > 0, 'one line');
    AssertTrue(Pos(#13#10, Ics) > 0, 'CRLF lines, as the format wants');
    DeleteFile(Opened);
    AssertTrue(AddToCalendar('Holiday', EncodeDate(2026, 12, 24), EncodeDate(2026, 12, 24), '', '', True));
    Ics := ReadText(Opened);
    AssertTrue(Pos('DTSTART;VALUE=DATE:20261224', Ics) > 0);
    AssertTrue(Pos('DTEND;VALUE=DATE:20261225', Ics) > 0, 'a whole day: till the next');
    DeleteFile(Opened);
  finally
    OpenUrlHook := nil;
  end;
end;

procedure TDeviceTests.LinksAmongTheArguments;
begin
  AssertEquals('shop://order/42', LinkFromArguments(['--verbose', 'shop://order/42']));
  AssertEquals('https://shop.example.com/app/x', LinkFromArguments(['https://shop.example.com/app/x']));
  AssertEquals('', LinkFromArguments(['notes.txt', '--x', 'file:///tmp/a', '://nothing', '1://x']));
  AssertEquals('', LinkFromArguments([]));
end;

procedure TDeviceTests.ContactsAndShortcutsAreThePhones;
var
  C: TContacts;
  E: TCalendarEvents;
  Until_: QWord;
begin
  AssertFalse(ReadContacts(C));
  AssertTrue(Pos('phone', LastDeviceError) > 0, LastDeviceError);
  AssertFalse(ReadCalendar(E, Now, Now + 7));
  AssertFalse(AddContact('Ayşe', '0532'));
  AssertFalse(SetAppShortcuts([AppShortcut('new', 'New appointment', 'add')]));
  AssertFalse(EnterPictureInPicture);
  AssertFalse(InPictureInPicture);
  FAnswered := False;
  FContactOk := True;
  PickContact(@ContactDone);
  AssertFalse(FAnswered, 'never inside the call');
  Until_ := GetTickCount64 + 2000;
  while not FAnswered and (GetTickCount64 < Until_) do
  begin
    ProcessTimers(GetTickCount64);
    Sleep(10);
  end;
  AssertTrue(FAnswered);
  AssertFalse(FContactOk);
end;

procedure TDeviceTests.NoFingerprintOnAComputer;
var
  Until_: QWord;
begin
  AssertTrue(CanAuthenticate = akNone);
  FAnswered := False;
  FAuthOk := True;
  Authenticate('Pay 120 TL', @AuthDone);
  AssertFalse(FAnswered, 'never inside the call');
  Until_ := GetTickCount64 + 2000;
  while not FAnswered and (GetTickCount64 < Until_) do
  begin
    ProcessTimers(GetTickCount64);
    Sleep(10);
  end;
  AssertTrue(FAnswered);
  AssertFalse(FAuthOk, 'not passed without a check');
  AssertTrue(Pos('computer', FAuthError) > 0, FAuthError);
end;

procedure TDeviceTests.PermissionsOnAComputer;
var
  Until_: QWord;
begin
  AssertTrue(PermissionState(dpCamera) = psGranted);
  FAnswered := False;
  RequestPermissions([dpCamera, dpMicrophone], @Answered);
  AssertFalse(FAnswered, 'never inside the call');
  Until_ := GetTickCount64 + 2000;
  while not FAnswered and (GetTickCount64 < Until_) do
  begin
    ProcessTimers(GetTickCount64);
    Sleep(10);
  end;
  AssertTrue(FAnswered, 'answered');
  AssertTrue(FGranted = [dpCamera, dpMicrophone]);
  AssertTrue(FBlocked = []);
end;

procedure TDeviceTests.PicturesIntoThePicturesFolder;
var
  Dir, Pic: string;
begin
  Dir := MakeTempDir('pastel-gallery');
  try
    SetEnv('XDG_PICTURES_DIR', Dir);
    Pic := Dir + 'photo-1.jpg';
    WriteText(Pic, 'not really a jpeg');
    AssertTrue(SaveToGallery(Pic, 'Salon'), LastDeviceError);
    AssertTrue(FileExists(JoinPath([Dir, 'Salon', 'photo-1.jpg'])));
    AssertFalse(SaveToGallery(Dir + 'nothing.jpg'));
    AssertTrue(Pos('no file', LastDeviceError) > 0, LastDeviceError);
  finally
    UnsetEnv('XDG_PICTURES_DIR');
    DeleteDir(Dir);
  end;
end;

initialization
  RegisterTests(TDeviceTests);

end.
