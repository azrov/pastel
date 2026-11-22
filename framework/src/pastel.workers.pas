{ Pastel - background work: a thread-safe queue and a pool of worker threads.

    Mail := TWorkerPool.Create('mail', 4, @SendMail);     // 4 threads
    Mail.Submit(JObject(['to', 'ayse@example.com']).AsJSON);
    ...
    Mail.Free;       // takes no new work, finishes what is queued, then stops

    procedure TApi.SendMail(const Msg: string);
    begin
      ...                     // runs in one of the worker threads
    end;

  Messages are strings (often JSON), so nothing is shared between threads
  by accident. An exception in a handler is logged and counted; the worker
  goes on with the next message. TMessageQueue on its own passes messages
  between any threads.
  Part of the Pastel project, MIT License. }
unit Pastel.Workers;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  { First in, first out; any number of threads may push and pop. }
  TMessageQueue = class
  private
    FItems: array of string;
    FHead, FCount, FMax: Integer;
    FClosed: Boolean;
    FLock: TCriticalSection;
    FEvent: PRTLEvent;
  public
    { MaxCount 0: no limit }
    constructor Create(MaxCount: Integer = 0);
    destructor Destroy; override;
    { False when the queue is closed or full }
    function Push(const Msg: string): Boolean;
    { waits up to TimeoutMs (-1: until there is a message or the queue is
      closed); False after the time, or when closed and empty }
    function Pop(out Msg: string; TimeoutMs: Integer = -1): Boolean;
    { no new messages; Pop still returns the ones queued }
    procedure Close;
    function Count: Integer;
    property Closed: Boolean read FClosed;
  end;

  TWorkHandler = procedure(const Msg: string) of object;
  TWorkHandlerProc = procedure(const Msg: string);

  TWorkerPool = class
  private
    FName: string;
    FQueue: TMessageQueue;
    FThreads: array of TThread;
    FHandler: TWorkHandler;
    FHandlerProc: TWorkHandlerProc;
    FProcessed, FFailed, FBusy: Integer;
    FStopped: Boolean;
    procedure Start(Count: Integer);
    procedure Handle(const Msg: string);
    function GetPending: Integer;
  public
    constructor Create(const AName: string; Count: Integer; Handler: TWorkHandler; MaxQueue: Integer = 0);
    constructor Create(const AName: string; Count: Integer; Handler: TWorkHandlerProc; MaxQueue: Integer = 0);
    { Stop, then free }
    destructor Destroy; override;
    { queue a message; False after Stop or when the queue is full }
    function Submit(const Msg: string): Boolean;
    { no new work; waits until the queued work is done (a warning in the
      log when it takes longer than WarnAfterMs) }
    procedure Stop(WarnAfterMs: Integer = 30000);
    { waits until the queue is empty and no worker is busy; False after TimeoutMs }
    function WaitIdle(TimeoutMs: Integer = 30000): Boolean;
    property Name: string read FName;
    property Pending: Integer read GetPending;
    property Processed: Integer read FProcessed;
    property Failed: Integer read FFailed;
  end;

type
  { Long work of a window app (a slow query, a download) that would make the
    window wait: Work runs on a thread of its own, then Done on the main thread;
    the window stays alive meanwhile.

      RunInBackground(@LoadRows, @RowsLoaded);

      procedure TMainForm.LoadRows(Sender: TObject);        // its own thread: no controls here
      begin
        TBackgroundTask(Sender).Data := Db.Query(...);
      end;

      procedure TMainForm.RowsLoaded(Sender: TObject);      // the main thread
      begin
        with TBackgroundTask(Sender) do
          if Error <> '' then ShowMessage(Error) else Grid.LoadJson(TJSONArray(Data));
      end;

    The task frees itself after Done (forget it there); Cancel before that: Done
    is not called and Data is freed (the work itself runs to its end). }
  TBackgroundTask = class(TThread)
  private
    FWork, FDone: TNotifyEvent;
    FError: string;
    FCancelled, FDoneCalled: Boolean;
    FData: TObject;
    FTag: PtrInt;
    procedure CallDone;
  protected
    procedure Execute; override;
  public
    constructor Create(AWork, ADone: TNotifyEvent; AData: TObject; ATag: PtrInt);
    procedure Cancel;
    { the message of the exception Work raised; '' when it went well }
    property Error: string read FError;
    property Cancelled: Boolean read FCancelled;
    { what Work leaves for Done (Done frees it or keeps it) }
    property Data: TObject read FData write FData;
    property Tag: PtrInt read FTag write FTag;
  end;

{ Data: what Work needs (and leaves its results in), there before Work starts. }
function RunInBackground(Work, Done: TNotifyEvent; Data: TObject = nil; Tag: PtrInt = 0): TBackgroundTask;

implementation

uses
  Pastel.Log;

{ ---------------- TMessageQueue ---------------- }

constructor TMessageQueue.Create(MaxCount: Integer);
begin
  inherited Create;
  FMax := MaxCount;
  FLock := TCriticalSection.Create;
  FEvent := RTLEventCreate;
  SetLength(FItems, 16);
end;

destructor TMessageQueue.Destroy;
begin
  RTLEventDestroy(FEvent);
  FLock.Free;
  inherited Destroy;
end;

function TMessageQueue.Push(const Msg: string): Boolean;
var
  NewItems: array of string;
  I: Integer;
begin
  FLock.Enter;
  try
    if FClosed or ((FMax > 0) and (FCount >= FMax)) then
      Exit(False);
    if FCount = Length(FItems) then
    begin
      SetLength(NewItems, Length(FItems) * 2);
      for I := 0 to FCount - 1 do
        NewItems[I] := FItems[(FHead + I) mod Length(FItems)];
      FItems := NewItems;
      FHead := 0;
    end;
    FItems[(FHead + FCount) mod Length(FItems)] := Msg;
    Inc(FCount);
    Result := True;
  finally
    FLock.Leave;
  end;
  RTLEventSetEvent(FEvent);
end;

function TMessageQueue.Pop(out Msg: string; TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
  Left: Int64;
begin
  Msg := '';
  if TimeoutMs >= 0 then
    Deadline := GetTickCount64 + QWord(TimeoutMs)
  else
    Deadline := 0;
  repeat
    FLock.Enter;
    try
      if FCount > 0 then
      begin
        Msg := FItems[FHead];
        FItems[FHead] := '';
        FHead := (FHead + 1) mod Length(FItems);
        Dec(FCount);
        if FCount > 0 then
          RTLEventSetEvent(FEvent);      { wake the next waiting thread }
        Exit(True);
      end;
      if FClosed then
      begin
        RTLEventSetEvent(FEvent);        { the other waiting threads end too }
        Exit(False);
      end;
    finally
      FLock.Leave;
    end;
    if TimeoutMs < 0 then
      RTLEventWaitFor(FEvent)
    else
    begin
      Left := Int64(Deadline) - Int64(GetTickCount64);
      if Left <= 0 then
        Exit(False);
      RTLEventWaitFor(FEvent, Left);
    end;
  until False;
end;

procedure TMessageQueue.Close;
begin
  FLock.Enter;
  try
    FClosed := True;
  finally
    FLock.Leave;
  end;
  RTLEventSetEvent(FEvent);
end;

function TMessageQueue.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FCount;
  finally
    FLock.Leave;
  end;
end;

{ ---------------- TWorkerPool ---------------- }

type
  TWorkerThread = class(TThread)
  private
    FPool: TWorkerPool;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TWorkerPool);
  end;

constructor TWorkerThread.Create(APool: TWorkerPool);
begin
  FPool := APool;
  inherited Create(False);
end;

procedure TWorkerThread.Execute;
var
  Msg: string;
begin
  while FPool.FQueue.Pop(Msg, -1) do
  begin
    InterLockedIncrement(FPool.FBusy);
    try
      FPool.Handle(Msg);
    finally
      InterLockedDecrement(FPool.FBusy);
    end;
  end;
end;

constructor TWorkerPool.Create(const AName: string; Count: Integer; Handler: TWorkHandler; MaxQueue: Integer);
begin
  inherited Create;
  FName := AName;
  FHandler := Handler;
  FQueue := TMessageQueue.Create(MaxQueue);
  Start(Count);
end;

constructor TWorkerPool.Create(const AName: string; Count: Integer; Handler: TWorkHandlerProc; MaxQueue: Integer);
begin
  inherited Create;
  FName := AName;
  FHandlerProc := Handler;
  FQueue := TMessageQueue.Create(MaxQueue);
  Start(Count);
end;

procedure TWorkerPool.Start(Count: Integer);
var
  I: Integer;
begin
  if Count < 1 then
    raise EArgumentException.CreateFmt('worker pool "%s" needs at least 1 thread', [FName]);
  SetLength(FThreads, Count);
  for I := 0 to Count - 1 do
    FThreads[I] := TWorkerThread.Create(Self);
end;

procedure TWorkerPool.Handle(const Msg: string);
begin
  try
    if Assigned(FHandler) then
      FHandler(Msg)
    else
      FHandlerProc(Msg);
    InterLockedIncrement(FProcessed);
  except
    on E: Exception do
    begin
      InterLockedIncrement(FFailed);
      Log.Error(E, 'worker ' + FName);
    end;
  end;
end;

function TWorkerPool.Submit(const Msg: string): Boolean;
begin
  Result := FQueue.Push(Msg);
end;

function TWorkerPool.GetPending: Integer;
begin
  Result := FQueue.Count;
end;

function TWorkerPool.WaitIdle(TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while (FQueue.Count > 0) or (FBusy > 0) do
  begin
    if GetTickCount64 >= Deadline then
      Exit(False);
    Sleep(5);
  end;
  Result := True;
end;

procedure TWorkerPool.Stop(WarnAfterMs: Integer);
var
  T: TThread;
  Deadline: QWord;
  Warned: Boolean;
begin
  if FStopped then
    Exit;
  FStopped := True;
  FQueue.Close;
  Deadline := GetTickCount64 + QWord(WarnAfterMs);
  Warned := False;
  for T in FThreads do
  begin
    while not T.Finished do
    begin
      if not Warned and (GetTickCount64 >= Deadline) then
      begin
        Warned := True;
        Log.Warn('workers %s: still busy after %d s (%d queued), waiting', [FName, WarnAfterMs div 1000,
          FQueue.Count]);
      end;
      Sleep(5);
    end;
    T.WaitFor;
  end;
end;

destructor TWorkerPool.Destroy;
var
  T: TThread;
begin
  Stop;
  for T in FThreads do
    T.Free;
  FQueue.Free;
  inherited Destroy;
end;

{ ---- TBackgroundTask ---- }

constructor TBackgroundTask.Create(AWork, ADone: TNotifyEvent; AData: TObject; ATag: PtrInt);
begin
  FWork := AWork;
  FDone := ADone;
  FData := AData;
  FTag := ATag;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TBackgroundTask.Execute;
begin
  try
    FWork(Self);
  except
    on E: Exception do
      FError := E.Message;
  end;
  if not FCancelled and Assigned(FDone) then
    Synchronize(@CallDone);
  { cancelled: nobody takes what the work left }
  if not FDoneCalled then
    FreeAndNil(FData);
end;

procedure TBackgroundTask.CallDone;
begin
  if FCancelled then
    Exit;
  FDoneCalled := True;
  FDone(Self);
end;

procedure TBackgroundTask.Cancel;
begin
  FCancelled := True;
end;

function RunInBackground(Work, Done: TNotifyEvent; Data: TObject; Tag: PtrInt): TBackgroundTask;
begin
  Result := TBackgroundTask.Create(Work, Done, Data, Tag);
end;

end.
