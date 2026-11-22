unit Log_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Log;

type
  TLogThread = class(TThread)
  protected
    procedure Execute; override;
  public
    Logger: TLogger;
    Id: Integer;
  end;

  TLogTests = class(TTestSuite)
  private
    FLog: TLogger;
    FLines: TStringList;
    FDir: string;
    procedure Capture(Level: TLogLevel; const Line: string);
    function Last: string;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TextLinesHaveTimeLevelAndMessage;
    procedure FormatsArguments;
    procedure LevelFiltersMessages;
    procedure LevelFromText;
    procedure FieldsAreAppended;
    procedure ExceptionsShowTheirClass;
    procedure JsonLines;
    procedure JournalLinesHavePriority;
    procedure WritesAndRotatesFiles;
    procedure SafeFromManyThreads;
  end;

implementation

procedure TLogTests.SetUp;
begin
  FLog := TLogger.Create;
  FLog.Console := False;
  FLog.Format := lfText;
  FLog.Level := llDebug;
  FLines := TStringList.Create;
  FLog.OnLine := @Capture;
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'pastel-log-test' + PathDelim;
end;

procedure TLogTests.TearDown;
var
  SR: TSearchRec;
begin
  FLog.Free;
  FLines.Free;
  if FindFirst(FDir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
        DeleteFile(FDir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(FDir);
end;

procedure TLogTests.Capture(Level: TLogLevel; const Line: string);
begin
  FLines.Add(Line);
end;

function TLogTests.Last: string;
begin
  if FLines.Count = 0 then
    Result := ''
  else
    Result := FLines[FLines.Count - 1];
end;

procedure TLogTests.TextLinesHaveTimeLevelAndMessage;
begin
  FLog.Info('Server started');
  { 2026-10-29 15:04:05.123 INFO  Server started }
  AssertEquals(23, Pos(' INFO  Server started', Last) - 1, Last);
  AssertEquals('-', Copy(Last, 5, 1));
  FLog.Error('Disk full');
  AssertContains(' ERROR Disk full', Last);
end;

procedure TLogTests.FormatsArguments;
begin
  FLog.Warn('Disk is %d%% full on %s', [93, '/var']);
  AssertContains('WARN  Disk is 93% full on /var', Last);
end;

procedure TLogTests.LevelFiltersMessages;
begin
  FLog.Level := llWarn;
  FLog.Debug('a');
  FLog.Info('b');
  FLog.Warn('c');
  FLog.Error('d');
  AssertEquals(2, FLines.Count);
  FLog.Level := llOff;
  FLog.Error('e');
  AssertEquals(2, FLines.Count);
  AssertFalse(FLog.Enabled(llError));
end;

procedure TLogTests.LevelFromText;
begin
  FLog.SetLevel('WARNING');
  AssertTrue(FLog.Level = llWarn);
  FLog.SetLevel('debug');
  AssertTrue(FLog.Level = llDebug);
  try
    FLog.SetLevel('loud');
    Fail('expected an error');
  except
    on E: EConvertError do
      AssertContains('unknown log level "loud"', E.Message);
  end;
end;

procedure TLogTests.FieldsAreAppended;
begin
  FLog.Fields(['user', 'ali', 'items', 3, 'note', 'two words']).Info('order placed');
  AssertContains('order placed user=ali items=3 note="two words"', Last);
end;

procedure TLogTests.ExceptionsShowTheirClass;
var
  E: Exception;
begin
  E := EInOutError.Create('disk not ready');
  try
    FLog.Error(E, 'could not save');
  finally
    E.Free;
  end;
  AssertContains('ERROR could not save: disk not ready error=EInOutError', Last);
end;

procedure TLogTests.JsonLines;
begin
  FLog.Format := lfJson;
  FLog.Fields(['user', 'ayşe "a"']).Warn('slow');
  AssertStartsWith('{"time":"', Last);
  AssertContains('Z","level":"warn","msg":"slow","user":"ayşe \"a\""}', Last);
end;

procedure TLogTests.JournalLinesHavePriority;
begin
  FLog.Format := lfJournal;
  FLog.Error('boom');
  AssertEquals('<3>boom', Last);
  FLog.Info('fine');
  AssertEquals('<6>fine', Last);
end;

procedure TLogTests.WritesAndRotatesFiles;
var
  I: Integer;
  L: TStringList;
begin
  FLog.ToFile(FDir + 'app.log', 1, 2);
  FLog.MaxBytes := 200;
  for I := 1 to 12 do
    FLog.Info('message number %d', [I]);
  AssertTrue(FileExists(FDir + 'app.log'));
  AssertTrue(FileExists(FDir + 'app.log.1'));
  AssertTrue(FileExists(FDir + 'app.log.2'));
  AssertFalse(FileExists(FDir + 'app.log.3'), 'only Keep old files');
  L := TStringList.Create;
  try
    L.LoadFromFile(FDir + 'app.log');
    AssertContains('message number 12', L[L.Count - 1]);
  finally
    L.Free;
  end;
end;

procedure TLogThread.Execute;
var
  I: Integer;
begin
  for I := 1 to 200 do
    Logger.Info('thread %d line %d', [Id, I]);
end;

procedure TLogTests.SafeFromManyThreads;
var
  Threads: array[1..4] of TLogThread;
  I: Integer;
  L: TStringList;
begin
  FLog.OnLine := nil;
  FLog.ToFile(FDir + 'threads.log');
  for I := 1 to 4 do
  begin
    Threads[I] := TLogThread.Create(True);
    Threads[I].Logger := FLog;
    Threads[I].Id := I;
    Threads[I].Start;
  end;
  for I := 1 to 4 do
  begin
    Threads[I].WaitFor;
    Threads[I].Free;
  end;
  L := TStringList.Create;
  try
    L.LoadFromFile(FDir + 'threads.log');
    AssertEquals(800, L.Count, 'every line written, none mixed up');
    for I := 0 to L.Count - 1 do
      AssertContains(' INFO  thread ', L[I]);
  finally
    L.Free;
  end;
end;

initialization
  RegisterTests(TLogTests);
end.
