{ Pastel - crash reports: what went wrong on users' machines, sent to you.

    EnableCrashReports('https://api.example.com/crashes', '1.4.2');
    ...
    try
      Sync;
    except
      on E: Exception do
        ReportError(E, 'sync');          // a caught error worth knowing about
    end;

  An exception nobody caught is written into a file before the program ends
  (with the place it happened, the version, the system); the next start sends
  the waiting reports as JSON (POST, on a thread of its own) and removes them.
  Release builds have no names of functions in them: the report has the
  addresses, which a debug build of the same version can name.
  Part of the Pastel project, MIT License. }
unit Pastel.CrashReport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ Turns them on; also sends the reports of earlier crashes. }
procedure EnableCrashReports(const Url: string; const AppVersion: string = '');
{ Sends a report of a caught exception (at once, on a thread). }
procedure ReportError(E: Exception; const Where: string = '');
{ The folder the waiting reports are in. }
function CrashReportDir: string;
{ The report of an exception as JSON (what is sent). }
function CrashReportJson(Obj: TObject; Addr: CodePointer; FrameCount: Longint; Frame: PCodePointer;
  const Where: string): string;
{ Sends the waiting reports now and waits (tests); how many went. }
function SendCrashReports: Integer;

implementation

uses
  SyncObjs, fpjson, Pastel.Http, Pastel.Files, Pastel.Env;

var
  ReportUrl, Version: string;
  OldExceptProc: TExceptProc = nil;
  Enabled: Boolean = False;
  SendLock: TCriticalSection;

function AppName: string;
begin
  Result := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  if Result = '' then
    Result := 'app';
end;

function CrashReportDir: string;
var
  Dir: string;
begin
  Dir := GetEnv('PASTEL_CRASH_DIR');
  if Dir <> '' then
    Exit(IncludeTrailingPathDelimiter(Dir));
  {$IFDEF WINDOWS}
  Dir := JoinPath([GetEnv('LOCALAPPDATA'), AppName, 'crashes']);
  {$ELSE}
  Dir := GetEnv('XDG_STATE_HOME');
  if Dir = '' then
    Dir := JoinPath([HomeDir, '.local', 'state']);
  Dir := JoinPath([Dir, AppName, 'crashes']);
  {$ENDIF}
  Result := IncludeTrailingPathDelimiter(Dir);
end;

function SystemName: string;
begin
  {$IFDEF ANDROID}
  Result := 'android';
  {$ELSE}{$IFDEF WINDOWS}
  Result := 'windows';
  {$ELSE}{$IFDEF DARWIN}
  Result := 'macos';
  {$ELSE}
  Result := 'linux';
  {$ENDIF}{$ENDIF}{$ENDIF}
  Result := Result + '-' + {$I %FPCTARGETCPU%};
end;

function CrashReportJson(Obj: TObject; Addr: CodePointer; FrameCount: Longint; Frame: PCodePointer;
  const Where: string): string;
var
  J: TJSONObject;
  St: TJSONArray;
  I: Integer;
begin
  J := TJSONObject.Create;
  try
    J.Add('app', AppName);
    J.Add('version', Version);
    J.Add('system', SystemName);
    J.Add('time', FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now));
    if Obj <> nil then
      J.Add('error', Obj.ClassName)
    else
      J.Add('error', 'unknown');
    if Obj is Exception then
      J.Add('message', Exception(Obj).Message)
    else
      J.Add('message', '');
    if Where <> '' then
      J.Add('where', Where);
    St := TJSONArray.Create;
    if Addr <> nil then
      St.Add(Trim(BackTraceStrFunc(Addr)));
    for I := 0 to FrameCount - 1 do
      St.Add(Trim(BackTraceStrFunc(Frame[I])));
    J.Add('stack', St);
    Result := J.AsJSON;
  finally
    J.Free;
  end;
end;

procedure Keep(const Json: string);
begin
  try
    ForceDirectories(CrashReportDir);
    WriteText(CrashReportDir + FormatDateTime('yyyymmdd-hhnnsszzz', Now) + '-' + IntToStr(Random(100000)) + '.json', Json);
  except
    { a report must never make it worse }
  end;
end;

function SendOne(const FileName: string): Boolean;
var
  R: THttpResponse;
begin
  Result := False;
  try
    R := HttpPostJson(ReportUrl, ReadText(FileName));
    if (R.Status >= 200) and (R.Status < 300) then
    begin
      DeleteFile(FileName);
      Result := True;
    end;
  except
    { the network is not there: next time }
  end;
end;

function SendCrashReports: Integer;
var
  F: string;
begin
  Result := 0;
  if (ReportUrl = '') or not DirectoryExists(CrashReportDir) then
    Exit;
  { one sender at a time: a report goes once }
  SendLock.Enter;
  try
    for F in ListFiles(CrashReportDir, '*.json') do
      if FileExists(F) and SendOne(F) then
        Inc(Result);
  finally
    SendLock.Leave;
  end;
end;

type
  TSender = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TSender.Execute;
begin
  SendCrashReports;
end;

procedure SendLater;
begin
  IsMultiThread := True;
  with TSender.Create(True) do
  begin
    FreeOnTerminate := True;
    Start;
  end;
end;

procedure OnCrash(Obj: TObject; Addr: CodePointer; FrameCount: Longint; Frame: PCodePointer);
begin
  if Enabled then
    Keep(CrashReportJson(Obj, Addr, FrameCount, Frame, 'not caught'));
  if Assigned(OldExceptProc) then
    OldExceptProc(Obj, Addr, FrameCount, Frame)
  else
    Halt(1);
end;

procedure EnableCrashReports(const Url: string; const AppVersion: string);
begin
  ReportUrl := Url;
  Version := AppVersion;
  if not Enabled then
  begin
    Enabled := True;
    OldExceptProc := ExceptProc;
    ExceptProc := @OnCrash;
    HandledErrorHook := @ReportError;
  end;
  if (ReportUrl <> '') and DirectoryExists(CrashReportDir) then
    SendLater;
end;

procedure ReportError(E: Exception; const Where: string);
begin
  Keep(CrashReportJson(E, ExceptAddr, ExceptFrameCount, ExceptFrames, Where));
  if ReportUrl <> '' then
    SendLater;
end;

initialization
  SendLock := TCriticalSection.Create;

finalization
  SendLock.Free;
end.
