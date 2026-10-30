unit Workers_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Pastel.Testing, Pastel.Workers, Pastel.Log;

type
  TWorkersTests = class(TTestSuite)
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure QueueIsFirstInFirstOut;
    procedure PopWaitsAndTimesOut;
    procedure ClosedQueueEmptiesThenEnds;
    procedure FullQueueRefuses;
    procedure ManyThreadsLoseNothing;
    procedure PoolDoesAllWork;
    procedure FailuresAreCountedAndWorkGoesOn;
    procedure StopFinishesQueuedWork;
    procedure NoWorkAfterStop;
    procedure NeedsAThread;
  end;

implementation

var
  Lock: TCriticalSection;
  Seen: TStringList;
  Sum: Int64;

procedure TWorkersTests.SetUp;
begin
  Log.Console := False;
  Seen.Clear;
  Sum := 0;
end;

procedure TWorkersTests.TearDown;
begin
  Log.Console := True;
end;

procedure TWorkersTests.QueueIsFirstInFirstOut;
var
  Q: TMessageQueue;
  S: string;
  I: Integer;
begin
  Q := TMessageQueue.Create;
  try
    for I := 1 to 100 do       { past the first size, so it grows }
      AssertTrue(Q.Push(IntToStr(I)));
    AssertEquals(100, Q.Count);
    for I := 1 to 100 do
    begin
      AssertTrue(Q.Pop(S, 0));
      AssertEquals(IntToStr(I), S);
    end;
    AssertFalse(Q.Pop(S, 0));
  finally
    Q.Free;
  end;
end;

type
  TLatePusher = class(TThread)
    Q: TMessageQueue;
    procedure Execute; override;
  end;

procedure TLatePusher.Execute;
begin
  Sleep(50);
  Q.Push('late');
end;

procedure TWorkersTests.PopWaitsAndTimesOut;
var
  Q: TMessageQueue;
  S: string;
  T: TLatePusher;
  Start: QWord;
begin
  Q := TMessageQueue.Create;
  try
    Start := GetTickCount64;
    AssertFalse(Q.Pop(S, 60));
    AssertTrue(GetTickCount64 - Start >= 50, 'waited');
    T := TLatePusher.Create(True);
    T.Q := Q;
    T.Start;
    AssertTrue(Q.Pop(S, 5000));
    AssertEquals('late', S);
    T.WaitFor;
    T.Free;
  finally
    Q.Free;
  end;
end;

procedure TWorkersTests.ClosedQueueEmptiesThenEnds;
var
  Q: TMessageQueue;
  S: string;
begin
  Q := TMessageQueue.Create;
  try
    Q.Push('a');
    Q.Close;
    AssertFalse(Q.Push('b'), 'closed');
    AssertTrue(Q.Pop(S, -1));
    AssertEquals('a', S);
    AssertFalse(Q.Pop(S, -1), 'does not wait forever');
  finally
    Q.Free;
  end;
end;

procedure TWorkersTests.FullQueueRefuses;
var
  Q: TMessageQueue;
  S: string;
begin
  Q := TMessageQueue.Create(2);
  try
    AssertTrue(Q.Push('1'));
    AssertTrue(Q.Push('2'));
    AssertFalse(Q.Push('3'));
    Q.Pop(S, 0);
    AssertTrue(Q.Push('3'));
  finally
    Q.Free;
  end;
end;

type
  TProducer = class(TThread)
    Q: TMessageQueue;
    Base: Integer;
    procedure Execute; override;
  end;

  TConsumer = class(TThread)
    Q: TMessageQueue;
    Got: TStringList;
    procedure Execute; override;
  end;

procedure TProducer.Execute;
var
  I: Integer;
begin
  for I := 1 to 1000 do
    Q.Push(IntToStr(Base + I));
end;

procedure TConsumer.Execute;
var
  S: string;
begin
  while Q.Pop(S, -1) do
    Got.Add(S);
end;

procedure TWorkersTests.ManyThreadsLoseNothing;
var
  Q: TMessageQueue;
  P: array[1..4] of TProducer;
  C: array[1..4] of TConsumer;
  All: TStringList;
  I: Integer;
begin
  Q := TMessageQueue.Create;
  All := TStringList.Create;
  try
    for I := 1 to 4 do
    begin
      C[I] := TConsumer.Create(True);
      C[I].Q := Q;
      C[I].Got := TStringList.Create;
      C[I].Start;
    end;
    for I := 1 to 4 do
    begin
      P[I] := TProducer.Create(True);
      P[I].Q := Q;
      P[I].Base := I * 10000;
      P[I].Start;
    end;
    for I := 1 to 4 do
    begin
      P[I].WaitFor;
      P[I].Free;
    end;
    Q.Close;
    for I := 1 to 4 do
    begin
      C[I].WaitFor;
      All.AddStrings(C[I].Got);
      C[I].Got.Free;
      C[I].Free;
    end;
    AssertEquals(4000, All.Count);
    All.Sorted := True;
    All.Duplicates := dupIgnore;
    AssertEquals(4000, All.Count, 'no message twice');
  finally
    All.Free;
    Q.Free;
  end;
end;

procedure AddUp(const Msg: string);
begin
  Lock.Enter;
  try
    Inc(Sum, StrToInt(Msg));
    Seen.Add(Msg);
  finally
    Lock.Leave;
  end;
end;

procedure FailOnOdd(const Msg: string);
begin
  if Odd(StrToInt(Msg)) then
    raise Exception.Create('odd ' + Msg);
  AddUp(Msg);
end;

procedure Slow(const Msg: string);
begin
  Sleep(20);
  AddUp(Msg);
end;

procedure TWorkersTests.PoolDoesAllWork;
var
  Pool: TWorkerPool;
  I: Integer;
begin
  Pool := TWorkerPool.Create('sum', 4, @AddUp);
  try
    for I := 1 to 1000 do
      AssertTrue(Pool.Submit(IntToStr(I)));
    AssertTrue(Pool.WaitIdle(10000));
    AssertEquals(500500, Sum);
    AssertEquals(1000, Pool.Processed);
    AssertEquals(0, Pool.Pending);
  finally
    Pool.Free;
  end;
end;

procedure TWorkersTests.FailuresAreCountedAndWorkGoesOn;
var
  Pool: TWorkerPool;
  I: Integer;
begin
  Pool := TWorkerPool.Create('odd', 2, @FailOnOdd);
  try
    for I := 1 to 10 do
      Pool.Submit(IntToStr(I));
    Pool.WaitIdle(10000);
    AssertEquals(5, Pool.Failed);
    AssertEquals(5, Pool.Processed);
    AssertEquals(30, Sum);
  finally
    Pool.Free;
  end;
end;

procedure TWorkersTests.StopFinishesQueuedWork;
var
  Pool: TWorkerPool;
  I: Integer;
begin
  Pool := TWorkerPool.Create('slow', 2, @Slow);
  for I := 1 to 10 do
    Pool.Submit(IntToStr(I));
  Pool.Free;            { waits for all ten }
  AssertEquals(10, Seen.Count);
  AssertEquals(55, Sum);
end;

procedure TWorkersTests.NoWorkAfterStop;
var
  Pool: TWorkerPool;
begin
  Pool := TWorkerPool.Create('x', 1, @AddUp);
  try
    Pool.Stop;
    AssertFalse(Pool.Submit('1'));
  finally
    Pool.Free;
  end;
end;

procedure TWorkersTests.NeedsAThread;
begin
  try
    TWorkerPool.Create('none', 0, @AddUp).Free;
    Fail('accepted');
  except
    on E: EArgumentException do
      AssertContains('at least 1 thread', E.Message);
  end;
end;

initialization
  Lock := TCriticalSection.Create;
  Seen := TStringList.Create;
  RegisterTests(TWorkersTests);
finalization
  Seen.Free;
  Lock.Free;
end.
