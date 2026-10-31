{ Pastel - the libraries a desktop app needs on Windows.

  A Pastel app for Windows needs SDL2.dll (window, input) and freetype.dll
  (text) next to the .exe. "pastel doctor --install windows" downloads them
  once into ~/.pastel/runtime/<target>/; every build of an app for that
  target copies them next to the program, and packages include them.
  Part of the Pastel project, MIT License. }
unit Pastel.Runtime;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Targets;

const
  SdlVersion = '2.30.9';
  FreeTypeVersion = '2.13.3';

{ ~/.pastel/runtime/windows/, or $PASTEL_CACHE/runtime/windows/ ('' when the home folder is unknown). }
function RuntimeDir(const Target: TTarget): string;
{ The DLLs an app for the target needs ('' for targets that need none). }
function RuntimeFiles(const Target: TTarget): TStringArray;
{ All of them are in RuntimeDir. }
function RuntimeInstalled(const Target: TTarget): Boolean;
{ Downloads them; '' when it worked, else what went wrong. }
function InstallRuntime(const Target: TTarget): string;
{ Copies them next to the program (when newer); the names copied or there. }
function CopyRuntime(const Target: TTarget; const ExeDir: string): TStringArray;

implementation

uses
  Classes, zipper, Pastel.Http, Pastel.Console;

function IsWindows(const Target: TTarget): Boolean;
begin
  Result := (Target.OS = 'win64') or (Target.OS = 'win32');
end;

function RuntimeDir(const Target: TTarget): string;
var
  Home: string;
begin
  Home := GetEnvironmentVariable('PASTEL_CACHE');
  if Home = '' then
  begin
    Home := GetUserDir;
    if Home = '' then
      Exit('');
    Home := IncludeTrailingPathDelimiter(Home) + '.pastel';
  end;
  Result := IncludeTrailingPathDelimiter(Home) + 'runtime' + PathDelim + Target.Name + PathDelim;
end;

function RuntimeFiles(const Target: TTarget): TStringArray;
begin
  if IsWindows(Target) then
    Result := ['SDL2.dll', 'freetype.dll']
  else
    Result := nil;
end;

function RuntimeInstalled(const Target: TTarget): Boolean;
var
  F: string;
begin
  for F in RuntimeFiles(Target) do
    if not FileExists(RuntimeDir(Target) + F) then
      Exit(False);
  Result := True;
end;

function InstallRuntime(const Target: TTarget): string;
var
  Dir, Arch, Zip, Url: string;
  Z: TUnZipper;
begin
  Result := '';
  if not IsWindows(Target) then
    Exit(Format('%s needs no extra libraries (they come with the system)', [Target.Name]));
  Dir := RuntimeDir(Target);
  if Dir = '' then
    Exit('the home folder is not known (set PASTEL_CACHE)');
  ForceDirectories(Dir);
  if Target.OS = 'win64' then Arch := 'x64' else Arch := 'x86';
  try
    if not FileExists(Dir + 'SDL2.dll') then
    begin
      Url := Format('https://github.com/libsdl-org/SDL/releases/download/release-%s/SDL2-%s-win32-%s.zip',
        [SdlVersion, SdlVersion, Arch]);
      Status('Downloading', Url);
      Zip := Dir + 'sdl2.zip';
      HttpDownload(Url, Zip);
      Z := TUnZipper.Create;
      try
        Z.FileName := Zip;
        Z.OutputPath := Dir;
        Z.Files.Add('SDL2.dll');
        Z.Files.Add('README-SDL.txt');
        Z.UnZipAllFiles;
      finally
        Z.Free;
      end;
      DeleteFile(Zip);
      if not FileExists(Dir + 'SDL2.dll') then
        Exit('SDL2.dll was not in ' + Url);
    end;
    if not FileExists(Dir + 'freetype.dll') then
    begin
      if Target.OS = 'win64' then Arch := 'win64' else Arch := 'win32';
      Url := Format('https://raw.githubusercontent.com/ubawurinna/freetype-windows-binaries/v%s/release%%20dll/%s/freetype.dll',
        [FreeTypeVersion, Arch]);
      Status('Downloading', Url);
      HttpDownload(Url, Dir + 'freetype.dll.part');
      RenameFile(Dir + 'freetype.dll.part', Dir + 'freetype.dll');
    end;
  except
    on E: Exception do
      Exit(E.Message);
  end;
end;

function CopyRuntime(const Target: TTarget; const ExeDir: string): TStringArray;
var
  F, Src, Dest: string;
  S, D: TFileStream;
begin
  Result := nil;
  for F in RuntimeFiles(Target) do
  begin
    Src := RuntimeDir(Target) + F;
    Dest := IncludeTrailingPathDelimiter(ExeDir) + F;
    if FileExists(Src) and (not FileExists(Dest) or (FileAge(Dest) < FileAge(Src))) then
    begin
      S := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
      try
        D := TFileStream.Create(Dest, fmCreate);
        try
          D.CopyFrom(S, S.Size);
        finally
          D.Free;
        end;
      finally
        S.Free;
      end;
      FileSetDate(Dest, FileAge(Src));
    end;
    if FileExists(Dest) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := F;
    end;
  end;
end;

end.
