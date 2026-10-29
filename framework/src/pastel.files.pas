(* Pastel - files, folders and paths.

    Text := ReadText('notes.txt');
    WriteText('out/report.txt', Text);        // creates out/, never leaves half a file
    for F in ListFiles('photos', '*.jpg', True) do ...
    CopyFile('a.txt', 'backup/a.txt');
    WriteLn(FormatSize(FileSize('video.mp4')));   // 1.4 GB
    Path := JoinPath(['data', 'users', 'ali.json']);

  All text is UTF-8. Errors raise EFileError with the file name and the
  reason in plain words.
  Part of the Pastel project, MIT License. *)
unit Pastel.Files;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Env;

type
  EFileError = class(Exception);

{ ---- reading and writing ---- }
function ReadText(const FileName: string): string;
{ Writes through a temporary file that replaces FileName at the end, so a
  crash or full disk never leaves a half-written file. Creates folders. }
procedure WriteText(const FileName, Text: string);
procedure AppendText(const FileName, Text: string);
function ReadLines(const FileName: string): TStringArray;
procedure WriteLines(const FileName: string; const Lines: array of string);
function ReadBytes(const FileName: string): TBytes;
procedure WriteBytes(const FileName: string; const Data: TBytes);

{ ---- folders and files ---- }
{ Files in Dir matching Pattern ('*.txt', '*'); full paths, sorted. }
function ListFiles(const Dir: string; const Pattern: string = '*'; Recursive: Boolean = False): TStringArray;
function ListDirs(const Dir: string): TStringArray;
procedure EnsureDir(const Dir: string);
procedure CopyFile(const Source, Dest: string; Overwrite: Boolean = True);
procedure MoveFile(const Source, Dest: string);
procedure DeleteFileIfExists(const FileName: string);
{ Deletes a folder with everything in it. }
procedure DeleteDir(const Dir: string);
function FileSize(const FileName: string): Int64;
function FileModified(const FileName: string): TDateTime;

{ ---- paths ---- }
function JoinPath(const Parts: array of string): string;
{ The program's own folder. }
function AppDir: string;
function HomeDir: string;
{ A new, empty folder for temporary files. }
function MakeTempDir(const Prefix: string = 'pastel'): string;
{ Path of FileName relative to BaseDir, with / or \ for this system. }
function RelativePath(const FileName, BaseDir: string): string;

{ 1536 -> '1.5 KB', 1300000000 -> '1.2 GB' }
function FormatSize(Bytes: Int64): string;

implementation

function Reason(E: Exception): string;
begin
  if E is EFOpenError then
    Result := 'cannot open it (does it exist, and may this program read it?)'
  else if E is EFCreateError then
    Result := 'cannot create it (does the folder exist, and may this program write there?)'
  else
    Result := E.Message;
end;

function ReadText(const FileName: string): string;
var
  F: TFileStream;
begin
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then
        F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  except
    on E: Exception do
      raise EFileError.CreateFmt('cannot read "%s": %s', [FileName, Reason(E)]);
  end;
  if Copy(Result, 1, 3) = #$EF#$BB#$BF then
    Delete(Result, 1, 3);
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

procedure WriteRaw(const FileName: string; P: Pointer; Count: Int64);
var
  F: TFileStream;
  Tmp: string;
begin
  EnsureDir(ExtractFileDir(ExpandFileName(FileName)));
  Tmp := FileName + '.tmp' + IntToStr(GetProcessID);
  try
    F := TFileStream.Create(Tmp, fmCreate);
    try
      if Count > 0 then
        F.WriteBuffer(P^, Count);
    finally
      F.Free;
    end;
    {$IFDEF WINDOWS}
    if FileExists(FileName) then
      SysUtils.DeleteFile(FileName);
    {$ENDIF}
    if not RenameFile(Tmp, FileName) then
      raise EFileError.Create('the file could not be replaced');
  except
    on E: Exception do
    begin
      SysUtils.DeleteFile(Tmp);
      raise EFileError.CreateFmt('cannot write "%s": %s', [FileName, Reason(E)]);
    end;
  end;
end;

procedure WriteText(const FileName, Text: string);
begin
  WriteRaw(FileName, PChar(Text), Length(Text));
end;

procedure AppendText(const FileName, Text: string);
var
  F: TFileStream;
begin
  try
    if FileExists(FileName) then
      F := TFileStream.Create(FileName, fmOpenWrite or fmShareDenyWrite)
    else
    begin
      EnsureDir(ExtractFileDir(ExpandFileName(FileName)));
      F := TFileStream.Create(FileName, fmCreate);
    end;
    try
      F.Seek(0, soEnd);
      if Text <> '' then
        F.WriteBuffer(Text[1], Length(Text));
    finally
      F.Free;
    end;
  except
    on E: EFileError do
      raise;
    on E: Exception do
      raise EFileError.CreateFmt('cannot write "%s": %s', [FileName, Reason(E)]);
  end;
end;

function ReadLines(const FileName: string): TStringArray;
var
  L: TStringList;
  I: Integer;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.Text := ReadText(FileName);
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
      Result[I] := L[I];
  finally
    L.Free;
  end;
end;

procedure WriteLines(const FileName: string; const Lines: array of string);
var
  S: string;
  I: Integer;
begin
  S := '';
  for I := 0 to High(Lines) do
    S := S + Lines[I] + LineEnding;
  WriteText(FileName, S);
end;

function ReadBytes(const FileName: string): TBytes;
var
  F: TFileStream;
begin
  Result := nil;
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then
        F.ReadBuffer(Result[0], F.Size);
    finally
      F.Free;
    end;
  except
    on E: Exception do
      raise EFileError.CreateFmt('cannot read "%s": %s', [FileName, Reason(E)]);
  end;
end;

procedure WriteBytes(const FileName: string; const Data: TBytes);
begin
  if Length(Data) = 0 then
    WriteRaw(FileName, nil, 0)
  else
    WriteRaw(FileName, @Data[0], Length(Data));
end;

procedure Collect(const Dir, Pattern: string; Recursive: Boolean; List: TStrings);
var
  SR: TSearchRec;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Base + Pattern, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        List.Add(Base + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  if Recursive and (FindFirst(Base + AllFilesMask, faDirectory, SR) = 0) then
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') then
        Collect(Base + SR.Name, Pattern, True, List);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function ToArray(L: TStringList): TStringArray;
var
  I: Integer;
begin
  Result := nil;
  L.Sort;
  SetLength(Result, L.Count);
  for I := 0 to L.Count - 1 do
    Result[I] := L[I];
end;

function ListFiles(const Dir, Pattern: string; Recursive: Boolean): TStringArray;
var
  L: TStringList;
begin
  if not DirectoryExists(Dir) then
    raise EFileError.CreateFmt('folder "%s" does not exist', [Dir]);
  L := TStringList.Create;
  try
    Collect(Dir, Pattern, Recursive, L);
    Result := ToArray(L);
  finally
    L.Free;
  end;
end;

function ListDirs(const Dir: string): TStringArray;
var
  L: TStringList;
  SR: TSearchRec;
  Base: string;
begin
  if not DirectoryExists(Dir) then
    raise EFileError.CreateFmt('folder "%s" does not exist', [Dir]);
  Base := IncludeTrailingPathDelimiter(Dir);
  L := TStringList.Create;
  try
    if FindFirst(Base + AllFilesMask, faDirectory, SR) = 0 then
    try
      repeat
        if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') then
          L.Add(Base + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    Result := ToArray(L);
  finally
    L.Free;
  end;
end;

procedure EnsureDir(const Dir: string);
begin
  if (Dir <> '') and not DirectoryExists(Dir) and not ForceDirectories(Dir) then
    raise EFileError.CreateFmt('cannot create folder "%s"', [Dir]);
end;

procedure CopyFile(const Source, Dest: string; Overwrite: Boolean);
var
  Src, Dst: TFileStream;
begin
  if not FileExists(Source) then
    raise EFileError.CreateFmt('cannot copy "%s": it does not exist', [Source]);
  if FileExists(Dest) and not Overwrite then
    raise EFileError.CreateFmt('cannot copy to "%s": it already exists', [Dest]);
  EnsureDir(ExtractFileDir(ExpandFileName(Dest)));
  try
    Src := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
    try
      Dst := TFileStream.Create(Dest, fmCreate);
      try
        if Src.Size > 0 then
          Dst.CopyFrom(Src, Src.Size);
      finally
        Dst.Free;
      end;
    finally
      Src.Free;
    end;
    FileSetDate(Dest, FileAge(Source));
  except
    on E: Exception do
      raise EFileError.CreateFmt('cannot copy "%s" to "%s": %s', [Source, Dest, Reason(E)]);
  end;
end;

procedure MoveFile(const Source, Dest: string);
begin
  if not FileExists(Source) then
    raise EFileError.CreateFmt('cannot move "%s": it does not exist', [Source]);
  EnsureDir(ExtractFileDir(ExpandFileName(Dest)));
  if FileExists(Dest) then
    SysUtils.DeleteFile(Dest);
  if not RenameFile(Source, Dest) then
  begin
    { another drive: copy, then delete }
    CopyFile(Source, Dest);
    SysUtils.DeleteFile(Source);
  end;
end;

procedure DeleteFileIfExists(const FileName: string);
begin
  if FileExists(FileName) and not SysUtils.DeleteFile(FileName) then
    raise EFileError.CreateFmt('cannot delete "%s" (is it open in another program?)', [FileName]);
end;

procedure DeleteDir(const Dir: string);
var
  SR: TSearchRec;
  Base: string;
begin
  if not DirectoryExists(Dir) then
    Exit;
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Base + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        DeleteDir(Base + SR.Name)
      else
        DeleteFileIfExists(Base + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  if not RemoveDir(Dir) then
    raise EFileError.CreateFmt('cannot delete folder "%s"', [Dir]);
end;

function FileSize(const FileName: string): Int64;
var
  SR: TSearchRec;
begin
  if FindFirst(FileName, faAnyFile, SR) <> 0 then
    raise EFileError.CreateFmt('"%s" does not exist', [FileName]);
  Result := SR.Size;
  FindClose(SR);
end;

function FileModified(const FileName: string): TDateTime;
var
  Age: LongInt;
begin
  Age := FileAge(FileName);
  if Age = -1 then
    raise EFileError.CreateFmt('"%s" does not exist', [FileName]);
  Result := FileDateToDateTime(Age);
end;

function JoinPath(const Parts: array of string): string;
var
  I: Integer;
  P: string;
begin
  Result := '';
  for I := 0 to High(Parts) do
  begin
    P := SetDirSeparators(Parts[I]);
    if P = '' then
      Continue;
    if Result = '' then
      Result := P
    else
    begin
      while (P <> '') and (P[1] = PathDelim) do
        Delete(P, 1, 1);
      Result := IncludeTrailingPathDelimiter(Result) + P;
    end;
  end;
end;

function AppDir: string;
begin
  Result := ExtractFilePath(ExpandFileName(ParamStr(0)));
end;

function HomeDir: string;
begin
  {$IFDEF WINDOWS}
  Result := GetEnv('USERPROFILE');
  {$ELSE}
  Result := GetEnv('HOME');
  {$ENDIF}
  Result := IncludeTrailingPathDelimiter(Result);
end;

function MakeTempDir(const Prefix: string): string;
var
  N: Integer;
begin
  N := 0;
  repeat
    Result := IncludeTrailingPathDelimiter(GetTempDir(False)) +
      Format('%s-%d-%d', [Prefix, GetProcessID, Random(1000000) + N]);
    Inc(N);
  until not DirectoryExists(Result);
  EnsureDir(Result);
  Result := IncludeTrailingPathDelimiter(Result);
end;

function RelativePath(const FileName, BaseDir: string): string;
begin
  Result := ExtractRelativePath(IncludeTrailingPathDelimiter(ExpandFileName(BaseDir)),
    ExpandFileName(FileName));
end;

function FormatSize(Bytes: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  V: Double;
  I: Integer;
  FS: TFormatSettings;
begin
  if Bytes < 1024 then
    Exit(IntToStr(Bytes) + ' B');
  V := Bytes;
  I := 0;
  while (V >= 1024) and (I < High(Units)) do
  begin
    V := V / 1024;
    Inc(I);
  end;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if V < 10 then
    Result := FormatFloat('0.0', V, FS) + ' ' + Units[I]
  else
    Result := FormatFloat('0', V, FS) + ' ' + Units[I];
end;

initialization
  Randomize;
end.
