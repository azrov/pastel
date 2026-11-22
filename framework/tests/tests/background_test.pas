{ Tests of Pastel.Background on a computer: jobs by name, background work. }
unit background_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Background;

type
  TBackgroundTests = class(TTestSuite)
  published
    procedure JobsByName;
    procedure ScheduledAndCancelled;
    procedure WorkOnAComputer;
  end;

implementation

var
  Runs: Integer;
  SawJob: Boolean;
  Answer: Boolean = True;

function CountJob: Boolean;
begin
  Inc(Runs);
  SawJob := InBackgroundJob;
  Result := Answer;
end;

function OtherJob: Boolean;
begin
  Result := False;
end;

procedure TBackgroundTests.JobsByName;
begin
  Runs := 0;
  RegisterBackgroundJob('count', @CountJob);
  AssertFalse(InBackgroundJob);
  AssertTrue(RunBackgroundJob('count'));
  AssertEquals(1, Runs);
  AssertTrue(SawJob, 'InBackgroundJob inside the job');
  AssertFalse(InBackgroundJob, 'and not after it');
  Answer := False;
  AssertFalse(RunBackgroundJob('count'), 'False: again later');
  Answer := True;
  { registered again: the new function }
  RegisterBackgroundJob('other', @OtherJob);
  AssertFalse(RunBackgroundJob('other'));
  RegisterBackgroundJob('other', @CountJob);
  AssertTrue(RunBackgroundJob('other'));
  try
    RunBackgroundJob('nothing');
    Fail('a job that is not registered');
  except
    on E: Exception do
      AssertTrue(Pos('"nothing"', E.Message) > 0, E.Message);
  end;
end;

procedure TBackgroundTests.ScheduledAndCancelled;
begin
  RegisterBackgroundJob('count', @CountJob);
  AssertTrue(ScheduleBackgroundJob('count', 1));
  AssertTrue(ScheduleBackgroundJob('count', 30, False), 'again: a new time');
  CancelBackgroundJob('count');
  CancelBackgroundJob('never-registered');
  try
    ScheduleBackgroundJob('nothing');
    Fail('a job that is not registered');
  except
    on E: Exception do
      AssertTrue(Pos('RegisterBackgroundJob', E.Message) > 0, E.Message);
  end;
end;

procedure TBackgroundTests.WorkOnAComputer;
begin
  AssertFalse(BackgroundWorkRunning);
  StartBackgroundWork('Uploading', '1 of 3', bkDataSync);
  AssertTrue(BackgroundWorkRunning);
  UpdateBackgroundWork('2 of 3');
  StopBackgroundWork;
  AssertFalse(BackgroundWorkRunning);
end;

initialization
  RegisterTests(TBackgroundTests);

end.
