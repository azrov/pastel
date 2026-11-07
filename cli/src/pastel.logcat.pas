{ Pastel - the log of an Android app, by its package name.

  Android's log (adb logcat) has every app and the system in it. This keeps
  the lines of one app: those of its processes (the process ids are learned
  from the system's "Start proc" lines and from the phone's process list),
  those that name the app (it started, it died), and the crash reports
  (DEBUG, crash_dump: where a program crashed). The whole log is saved too,
  to send along with a question.
  Part of the Pastel project, MIT License. }
unit Pastel.Logcat;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { One line of "adb logcat -v threadtime": 11-07 15:43:01.123  1234  1250 E Tag: text }
  TLogLine = record
    Time, Pid, Level, Tag, Text: string;
    Valid: Boolean;
  end;

  { Something to add to a line ('' for nothing): where a crash was, in the Pascal code. }
  TLogExplain = function(const Text: string): string of object;

  { "#00 pc 0012ab34  /data/app/.../lib/arm/libmain.so": the line of Pascal code,
    from the debug build's libmain.so and the binutils' addr2line. }
  TCrashSymbols = class
  private
    FRoot: string;
    FCache: TStringList;
  public
    constructor Create(const ProjectRoot: string);
    destructor Destroy; override;
    function Explain(const Text: string): string;
  end;

  { What is kept of the log: the app's processes, by its package name. }
  TAppLogFilter = class
  private
    FPackage: string;
    FPids: TStringList;
  public
    constructor Create(const APackage: string);
    destructor Destroy; override;
    procedure AddPid(const Pid: string);
    { The line is the app's (and teaches new process ids of it). }
    function Keep(const Line: TLogLine): Boolean;
    property Pids: TStringList read FPids;
    property Package: string read FPackage;
  end;

function ParseLogLine(const S: string): TLogLine;
{ "15:43:01 E Tag: text", for showing. }
function ShortLogLine(const Line: TLogLine): string;
{ The process ids in the output of "ps" (or "pidof") for the package. }
function PidsOf(const PsOutput, Package: string): TStringArray;
{ Shows the app's lines of "adb logcat" (every line with All) until Ctrl+C,
  and saves every line to SaveTo ('' = nowhere). The exit code of adb. }
function FollowAppLog(const Adb, Package, SaveTo: string; All: Boolean; const FirstPids: array of string;
  Explain: TLogExplain = nil): Integer;
{ The address and the library folder of a crash report line ("pc 0012ab34 .../lib/arm/libmain.so"); False when it is not one. }
function CrashAddress(const Text: string; out Address, AbiDir: string): Boolean;

implementation

uses
  Process, Pastel.Console, Pastel.Targets, Pastel.Builder;

function IsDigits(const S: string): Boolean;
var
  C: Char;
begin
  Result := S <> '';
  for C in S do
    if not (C in ['0'..'9']) then
      Exit(False);
end;

function ParseLogLine(const S: string): TLogLine;
var
  T, Rest: string;
  Fields: array[0..4] of string;
  I, F, Colon: Integer;
begin
  Result := Default(TLogLine);
  T := TrimRight(S);
  Result.Text := T;
  { date, time, pid, tid, level; then "Tag: text" (a tag can be followed by spaces: "Tag   : text") }
  I := 1;
  for F := 0 to 4 do
  begin
    while (I <= Length(T)) and (T[I] = ' ') do
      Inc(I);
    Fields[F] := '';
    while (I <= Length(T)) and (T[I] <> ' ') do
    begin
      Fields[F] := Fields[F] + T[I];
      Inc(I);
    end;
  end;
  if not IsDigits(Fields[2]) or not IsDigits(Fields[3]) or (Length(Fields[4]) <> 1) or (Pos('-', Fields[0]) = 0) then
    Exit;
  Rest := TrimLeft(Copy(T, I, MaxInt));
  Result.Time := Copy(Fields[1], 1, 8);
  Result.Pid := Fields[2];
  Result.Level := Fields[4];
  Colon := Pos(': ', Rest);
  if Colon = 0 then
  begin
    Result.Tag := TrimRight(Rest);
    if Copy(Result.Tag, Length(Result.Tag), 1) = ':' then
      Delete(Result.Tag, Length(Result.Tag), 1);
    Result.Text := '';
  end
  else
  begin
    Result.Tag := Copy(Rest, 1, Colon - 1);
    Result.Text := Copy(Rest, Colon + 2, MaxInt);
  end;
  Result.Tag := Trim(Result.Tag);
  Result.Valid := True;
end;

function ShortLogLine(const Line: TLogLine): string;
begin
  if not Line.Valid then
    Exit(Line.Text);
  Result := Format('%s %s %s: %s', [Line.Time, Line.Level, Line.Tag, Line.Text]);
end;

function PidsOf(const PsOutput, Package: string): TStringArray;
var
  L: TStringList;
  I: Integer;
  Parts: TStringArray;
  S, Name: string;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.Text := PsOutput;
    for I := 0 to L.Count - 1 do
    begin
      S := Trim(L[I]);
      if S = '' then
        Continue;
      { pidof: "1234 1240" }
      if IsDigits(StringReplace(S, ' ', '', [rfReplaceAll])) then
      begin
        for Name in S.Split([' '], TStringSplitOptions.ExcludeEmpty) do
          Result := Concat(Result, [Name]);
        Continue;
      end;
      { ps: "u0_a123  1234  567 ... dev.pastel.shop" (and dev.pastel.shop:remote) }
      Parts := S.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      Name := Parts[High(Parts)];
      if (Length(Parts) >= 2) and IsDigits(Parts[1]) and
        ((Name = Package) or (Copy(Name, 1, Length(Package) + 1) = Package + ':')) then
        Result := Concat(Result, [Parts[1]]);
    end;
  finally
    L.Free;
  end;
end;

{ TAppLogFilter }

constructor TAppLogFilter.Create(const APackage: string);
begin
  inherited Create;
  FPackage := APackage;
  FPids := TStringList.Create;
  FPids.Sorted := True;
  FPids.Duplicates := dupIgnore;
end;

destructor TAppLogFilter.Destroy;
begin
  FPids.Free;
  inherited Destroy;
end;

procedure TAppLogFilter.AddPid(const Pid: string);
begin
  if IsDigits(Pid) then
    FPids.Add(Pid);
end;

function TAppLogFilter.Keep(const Line: TLogLine): Boolean;
var
  P, I: Integer;
  S: string;
begin
  if not Line.Valid then
    Exit(False);
  if Pos(FPackage, Line.Text) > 0 then
  begin
    if Pos('Start proc', Line.Text) > 0 then
    begin
      { "Start proc 1234:dev.pastel.shop/u0a12 for activity ..." (Android 7 and newer) }
      P := Pos(':' + FPackage, Line.Text);
      if P > 0 then
      begin
        I := P - 1;
        while (I > 0) and (Line.Text[I] in ['0'..'9']) do
          Dec(I);
        AddPid(Copy(Line.Text, I + 1, P - I - 1));
      end;
      { "Start proc dev.pastel.shop for activity ...: pid=1234 uid=..." (older) }
      P := Pos('pid=', Line.Text);
      if P > 0 then
      begin
        S := '';
        I := P + 4;
        while (I <= Length(Line.Text)) and (Line.Text[I] in ['0'..'9']) do
        begin
          S := S + Line.Text[I];
          Inc(I);
        end;
        AddPid(S);
      end;
    end;
    Exit(True);
  end;
  if FPids.IndexOf(Line.Pid) >= 0 then
    Exit(True);
  { crash reports: written by another process, about the app }
  Result := (Line.Tag = 'DEBUG') or (Line.Tag = 'crash_dump') or (Line.Tag = 'crash_dump32') or
    (Line.Tag = 'crash_dump64') or (Line.Tag = 'tombstoned');
end;

function CrashAddress(const Text: string; out Address, AbiDir: string): Boolean;
var
  P, I, L: Integer;
begin
  Result := False;
  Address := '';
  AbiDir := '';
  L := Pos('/libmain.so', Text);
  P := Pos(' pc ', Text);
  if (L = 0) or (P = 0) or (P > L) then
    Exit;
  I := P + 4;
  while (I <= Length(Text)) and (Text[I] = ' ') do
    Inc(I);
  while (I <= Length(Text)) and (Text[I] in ['0'..'9', 'a'..'f', 'A'..'F']) do
  begin
    Address := Address + Text[I];
    Inc(I);
  end;
  { ".../lib/arm/libmain.so" or ".../lib/arm64/libmain.so" }
  I := L - 1;
  while (I > 0) and (Text[I] <> '/') do
    Dec(I);
  AbiDir := Copy(Text, I + 1, L - I - 1);
  Result := (Address <> '') and (AbiDir <> '');
end;

constructor TCrashSymbols.Create(const ProjectRoot: string);
begin
  inherited Create;
  FRoot := IncludeTrailingPathDelimiter(ProjectRoot);
  FCache := TStringList.Create;
end;

destructor TCrashSymbols.Destroy;
begin
  FCache.Free;
  inherited Destroy;
end;

function TCrashSymbols.Explain(const Text: string): string;
var
  Address, AbiDir, TargetName, Lib, Prefix, Output, Key: string;
  T: TTarget;
  Found: Boolean;
  Args, Lines: TStringList;
begin
  Result := '';
  if not CrashAddress(Text, Address, AbiDir) then
    Exit;
  if AbiDir = 'arm64' then
    TargetName := 'android-arm64'
  else if AbiDir = 'arm' then
    TargetName := 'android-arm'
  else if AbiDir = 'x86_64' then
    TargetName := 'android-x86_64'
  else if AbiDir = 'x86' then
    TargetName := 'android-x86'
  else
    Exit;
  Key := TargetName + ':' + Address;
  if FCache.IndexOfName(Key) >= 0 then
    Exit(FCache.Values[Key]);
  if not FindTarget(TargetName, T) then
    Exit;
  Lib := FRoot + 'build' + PathDelim + T.Name + PathDelim + 'debug' + PathDelim + 'libmain.so';
  Prefix := FindBinutilsPrefix(T, Found);
  if not FileExists(Lib) or not Found then
    Exit;
  Args := TStringList.Create;
  Lines := TStringList.Create;
  try
    Args.Add('-f');
    Args.Add('-e');
    Args.Add(Lib);
    Args.Add('0x' + Address);
    if RunCapture(Prefix + 'addr2line', Args, FRoot, Output) = 0 then
    begin
      Lines.Text := Output;
      { "FUNCTION" then "file.pas:12"; ?? when it is not known }
      if (Lines.Count >= 2) and (Pos('??', Lines[1]) <> 1) then
        Result := Format('%s (%s)', [Trim(Lines[0]), ExtractFileName(Trim(Lines[1]))])
      else if (Lines.Count >= 1) and (Pos('??', Lines[0]) <> 1) then
        Result := Trim(Lines[0]);
    end;
  finally
    Args.Free;
    Lines.Free;
  end;
  FCache.Add(Key + '=' + Result);
end;

function FollowAppLog(const Adb, Package, SaveTo: string; All: Boolean; const FirstPids: array of string;
  Explain: TLogExplain): Integer;
var
  P: TProcess;
  Filter: TAppLogFilter;
  Pending, Chunk, S: string;
  Save: TFileStream;
  N, NL: Integer;

  procedure Show(const Raw: string);
  var
    Line: TLogLine;
    Text, Saved: string;
  begin
    if Save <> nil then
    begin
      Saved := Raw + LineEnding;
      Save.WriteBuffer(Saved[1], Length(Saved));
    end;
    Line := ParseLogLine(Raw);
    if not All and not Filter.Keep(Line) then
      Exit;
    Text := ShortLogLine(Line);
    if Assigned(Explain) and (Explain(Line.Text) <> '') then
      Text := Text + '   <- ' + Explain(Line.Text);
    if (Line.Level = 'E') or (Line.Level = 'F') then
      WriteLn(Red(Text))
    else if Line.Level = 'W' then
      WriteLn(Yellow(Text))
    else
      WriteLn(Text);
  end;

begin
  Filter := TAppLogFilter.Create(Package);
  Save := nil;
  P := TProcess.Create(nil);
  try
    for S in FirstPids do
      Filter.AddPid(S);
    if SaveTo <> '' then
    begin
      ForceDirectories(ExtractFileDir(SaveTo));
      Save := TFileStream.Create(SaveTo, fmCreate);
    end;
    P.Executable := Adb;
    P.Parameters.Add('logcat');
    P.Parameters.Add('-v');
    P.Parameters.Add('threadtime');
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    Pending := '';
    SetLength(Chunk, 4096);
    while P.Running or (P.Output.NumBytesAvailable > 0) do
    begin
      if P.Output.NumBytesAvailable = 0 then
      begin
        Sleep(20);
        Continue;
      end;
      N := P.Output.Read(Chunk[1], Length(Chunk));
      if N <= 0 then
        Break;
      Pending := Pending + Copy(Chunk, 1, N);
      NL := Pos(#10, Pending);
      while NL > 0 do
      begin
        Show(StringReplace(Copy(Pending, 1, NL - 1), #13, '', [rfReplaceAll]));
        Delete(Pending, 1, NL);
        NL := Pos(#10, Pending);
      end;
    end;
    if Pending <> '' then
      Show(Pending);
    Result := P.ExitStatus;
  finally
    P.Free;
    Save.Free;
    Filter.Free;
  end;
end;

end.
