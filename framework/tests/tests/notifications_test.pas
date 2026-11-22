{ Tests of Pastel.Notifications: names, times, repeats, cancelling (captured,
  not shown). }
unit notifications_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Pastel.Testing, Pastel.UI, Pastel.Notifications;

type
  TNotificationTests = class(TTestSuite)
  private
    FShown: TStringList;
    procedure Wait;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ShownNow;
    procedure ScheduledWhenItsTimeComes;
    procedure RepeatsAndCancels;
    procedure ScheduledNeedsAName;
  end;

implementation

procedure TNotificationTests.SetUp;
begin
  FShown := TStringList.Create;
  CapturedNotifications := FShown;
end;

procedure TNotificationTests.TearDown;
begin
  CancelAllNotifications;
  CapturedNotifications := nil;
  FShown.Free;
end;

{ the timer of scheduled notifications runs once a second }
procedure TNotificationTests.Wait;
begin
  Sleep(1050);
  ProcessTimers(GetTickCount64);
end;

procedure TNotificationTests.ShownNow;
begin
  AssertTrue(ShowNotification('Sync', '12 came in', 'sync'));
  AssertEquals('sync|Sync|12 came in', FShown.Text.Trim);
  AssertTrue(ShowNotification('Hello', 'without a name'));
  AssertEquals(2, FShown.Count);
  AssertTrue(FShown[1].StartsWith('pastel-'), 'a name of its own');
end;

procedure TNotificationTests.ScheduledWhenItsTimeComes;
begin
  AssertTrue(ScheduleNotification('soon', 'Appointment', 'in a second', IncMilliSecond(Now, 500)));
  AssertTrue(ScheduleNotification('later', 'Later', 'in an hour', IncHour(Now, 1)));
  AssertEquals(0, FShown.Count, 'not yet');
  Wait;
  AssertEquals('soon|Appointment|in a second', FShown.Text.Trim);
  Wait;
  AssertEquals(1, FShown.Count, 'once');
end;

procedure TNotificationTests.RepeatsAndCancels;
begin
  { a time gone by: now, and the next one an hour later }
  AssertTrue(ScheduleNotification('hourly', 'Check', 'again', IncMinute(Now, -1), riHourly));
  AssertTrue(ScheduleNotification('gone', 'Gone', 'taken back', IncMilliSecond(Now, 500)));
  CancelNotification('gone');
  Wait;
  AssertEquals('hourly|Check|again', FShown.Text.Trim);
  Wait;
  AssertEquals(1, FShown.Count, 'next in an hour');
  { the same name replaces it }
  AssertTrue(ScheduleNotification('hourly', 'Check', 'replaced', IncMilliSecond(Now, 300)));
  Wait;
  AssertEquals('hourly|Check|replaced', FShown[1]);
end;

procedure TNotificationTests.ScheduledNeedsAName;
begin
  AssertFalse(ScheduleNotification('', 'x', 'y', Now));
  AssertTrue(Pos('name', LastNotificationError) > 0);
end;

initialization
  RegisterTests(TNotificationTests);

end.
