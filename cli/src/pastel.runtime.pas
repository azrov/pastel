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

{ Where "pastel doctor --install" puts Free Pascal's basic units (the RTL)
  for a target: ~/.pastel/fpc/<version>/units/<cpu>-<os>/rtl/ ('' when the
  home folder is unknown). Builds use it when it exists. }
function UserRtlDir(const Fpc: string; const Target: TTarget): string;
{ The compiler can make programs for the target without a cross-compiler
  (only its units are missing): x86_64 Linux for 64-bit Windows. }
function CanBuildRtl(const Target: TTarget): Boolean;
{ Compiles the RTL for the target from the Free Pascal sources (fpc-source)
  into UserRtlDir; '' when it worked, else what went wrong. }
function BuildRtl(const Fpc: string; const Target: TTarget): string;
{ ~/.pastel/ (or $PASTEL_CACHE/), '' when the home folder is unknown. }
function PastelHome: string;

{ Android: what an app's libmain.so is linked with — the start of a library
  (dllprt0.o, crtbegin_so.o, crtend_so.o) and stand-ins for the system
  libraries (libc.so, libandroid.so, liblog.so...: only their names, the
  phone has the real ones). Made with the ARM 64-bit binutils, so the NDK is
  not needed: ~/.pastel/android/arm64/lib/. }
function AndroidLibDir: string;
function AndroidLibsReady: Boolean;
{ Makes them; '' when it worked, else what went wrong. }
function MakeAndroidLibs(const BinPrefix: string): string;

implementation

uses
  Classes, zipper, Pastel.Http, Pastel.Console, Pastel.Builder;

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

function PastelHome: string;
begin
  Result := GetEnvironmentVariable('PASTEL_CACHE');
  if Result = '' then
  begin
    Result := GetUserDir;
    if Result = '' then
      Exit('');
    Result := IncludeTrailingPathDelimiter(Result) + '.pastel';
  end;
  Result := IncludeTrailingPathDelimiter(Result);
end;

function UserRtlDir(const Fpc: string; const Target: TTarget): string;
begin
  if PastelHome = '' then
    Exit('');
  Result := PastelHome + 'fpc' + PathDelim + FpcVersion(Fpc) + PathDelim + 'units' + PathDelim +
    Target.CPU + '-' + Target.OS + PathDelim + 'rtl' + PathDelim;
end;

function CanBuildRtl(const Target: TTarget): Boolean;
begin
  { Android: with the ARM 64-bit compiler of the fpc package (ppcrossa64) }
  if (Target.OS = 'android') and (Target.CPU = 'aarch64') then
    Exit((ExeSearch('ppcrossa64', GetEnvironmentVariable('PATH')) <> '') or
      (ExeSearch('ppca64', GetEnvironmentVariable('PATH')) <> ''));
  {$IFDEF CPUX86_64}
  Result := (Target.CPU = 'x86_64') and (Target.OS = 'win64');
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function AndroidLibDir: string;
begin
  if PastelHome = '' then
    Exit('');
  Result := PastelHome + 'android' + PathDelim + 'arm64' + PathDelim + 'lib' + PathDelim;
end;

function AndroidLibsReady: Boolean;
var
  F: string;
begin
  Result := AndroidLibDir <> '';
  if Result then
    for F in TStringArray.Create('dllprt0.o', 'crtbegin_so.o', 'crtend_so.o', 'libc.so', 'libm.so', 'libdl.so', 'liblog.so',
      'libandroid.so') do
      if not FileExists(AndroidLibDir + F) then
        Exit(False);
end;

function MakeAndroidLibs(const BinPrefix: string): string;
const
  NoExecStack = #9'.section .note.GNU-stack,"",%progbits' + LineEnding;
  { the libc start of a library: __dso_handle, and atexit for this library }
  CrtBegin =
    #9'.data' + LineEnding + #9'.align 3' + LineEnding +
    #9'.globl __dso_handle' + LineEnding + #9'.hidden __dso_handle' + LineEnding +
    #9'.type __dso_handle,%object' + LineEnding +
    '__dso_handle:' + LineEnding + #9'.quad __dso_handle' + LineEnding +
    #9'.text' + LineEnding + #9'.align 2' + LineEnding +
    #9'.globl atexit' + LineEnding + #9'.hidden atexit' + LineEnding + #9'.type atexit,%function' + LineEnding +
    'atexit:' + LineEnding +
    #9'mov x1, xzr' + LineEnding +
    #9'adrp x2, __dso_handle' + LineEnding +
    #9'add x2, x2, :lo12:__dso_handle' + LineEnding +
    #9'b __cxa_atexit' + LineEnding + NoExecStack;
  { Free Pascal's start of an Android library: run by the system's loader }
  DllPrt0 =
    #9'.section .init_array,"aw"' + LineEnding + #9'.align 3' + LineEnding +
    #9'.quad FPC_LIB_START_ANDROID' + LineEnding + NoExecStack;
var
  Dir, Output, Lib: string;
  Args: TStringList;

  function Run(const Tool: string; const A: array of string): Boolean;
  var
    S: string;
  begin
    Args.Clear;
    for S in A do
      Args.Add(S);
    Result := RunCapture(BinPrefix + Tool, Args, Dir, Output) = 0;
    if not Result then
      MakeAndroidLibs := Format('%s%s did not work: %s', [BinPrefix, Tool, Trim(Output)]);
  end;

  procedure Save(const Name, Text: string);
  var
    L: TStringList;
  begin
    L := TStringList.Create;
    try
      L.Text := Text;
      L.SaveToFile(Dir + Name);
    finally
      L.Free;
    end;
  end;

begin
  Result := '';
  Dir := AndroidLibDir;
  if Dir = '' then
    Exit('the home folder is not known (set PASTEL_CACHE)');
  ForceDirectories(Dir);
  Save('crtbegin_so.s', CrtBegin);
  Save('crtend_so.s', NoExecStack);
  Save('dllprt0.s', DllPrt0);
  Save('empty.s', NoExecStack);
  Args := TStringList.Create;
  try
    if not Run('as', ['crtbegin_so.s', '-o', 'crtbegin_so.o']) then Exit;
    if not Run('as', ['crtend_so.s', '-o', 'crtend_so.o']) then Exit;
    if not Run('as', ['dllprt0.s', '-o', 'dllprt0.o']) then Exit;
    if not Run('as', ['empty.s', '-o', 'empty.o']) then Exit;
    { the system libraries by name: an app's library may leave their functions open }
    for Lib in TStringArray.Create('c', 'm', 'dl', 'log', 'android') do
      if not Run('ld', ['-shared', '-soname', 'lib' + Lib + '.so', '-o', 'lib' + Lib + '.so', 'empty.o']) then
        Exit;
  finally
    Args.Free;
  end;
end;

function BuildRtl(const Fpc: string; const Target: TTarget): string;
var
  Src, Rtl, OsDir, Out_, Output, BinPrefix, U: string;
  Base: TStringArray;
  HaveBinutils: Boolean;

  { one compiler run in the target's RTL folder; False (and Result set) on errors }
  function Compile(const Extra: array of string): Boolean;
  var
    Args: TStringList;
    A: string;
  begin
    Args := TStringList.Create;
    try
      for A in Base do
        Args.Add(A);
      for A in Extra do
        Args.Add(A);
      Result := RunCapture(Fpc, Args, OsDir, Output) = 0;
      if not Result then
        BuildRtl := 'the RTL for ' + Target.Name + ' did not compile:' + LineEnding + Trim(Output);
    finally
      Args.Free;
    end;
  end;

begin
  Result := '';
  if not CanBuildRtl(Target) then
    Exit(Format('the compiler of this computer cannot make programs for %s; a cross-compiler is needed ' +
      '(fpcupdeluxe installs one)', [Target.Name]));
  Src := FpcSourceDir;
  if Src = '' then
    Exit('the Free Pascal sources are needed: sudo apt install fpc-source');
  Rtl := IncludeTrailingPathDelimiter(Src) + 'rtl' + PathDelim;
  OsDir := Rtl + Target.OS;
  if not DirectoryExists(OsDir) then
    Exit('the Free Pascal sources have no RTL for ' + Target.OS);
  Out_ := UserRtlDir(Fpc, Target);
  if Out_ = '' then
    Exit('the home folder is not known (set PASTEL_CACHE)');
  ForceDirectories(Out_);
  Status('Compiling', Format('Free Pascal''s RTL for %s into %s', [Target.Name, Out_]));
  if Target.OS = 'android' then
  begin
    BinPrefix := FindBinutilsPrefix(Target, HaveBinutils);
    if not HaveBinutils then
      Exit('the ARM 64-bit binutils are needed: sudo apt install ' + Target.BinutilsPackage);
    { O_LARGEFILE and a few others are only defined for "aarch64" in Free Pascal 3.2.2 }
    Base := ['-T' + Target.OS, '-P' + Target.CPU, '-XP' + BinPrefix, '-dAARCH64', '-n', '-O2', '-Ur', '-Xs', '-vew',
      '-FU' + Out_, '-Fu' + Out_, '-Fi../inc', '-Fi../aarch64', '-Fi../unix', '-Fiaarch64', '-Fi../linux',
      '-Fi../linux/aarch64', '-Fu../inc', '-Fu../aarch64', '-Fu../unix', '-Fu../linux', '-Fu../common',
      '-Fu../objpas', '-Fi../objpas', '-Fi../objpas/sysutils', '-Fi../objpas/classes'];
    if not Compile(['-Us', '-Sg', '../linux/system.pp']) then Exit;
    for U in TStringArray.Create('../inc/uuchar.pp', '../objpas/objpas.pp', '../unix/unixtype.pp', '../inc/ctypes.pp',
      '../unix/baseunix.pp', '../inc/strings.pp', '../unix/syscall.pp', '../unix/unixutil.pp',
      '../inc/fpintres.pp', '../inc/heaptrc.pp', '../linux/termio.pp', '../unix/unix.pp', '../linux/linux.pp',
      '../unix/initc.pp', '../inc/cmem.pp', '../objpas/typinfo.pp', '../inc/charset.pp', '../objpas/sysconst.pp',
      '../objpas/sysutils.pp', '../objpas/math.pp', '../objpas/character.pas', '../inc/getopts.pp',
      '../unix/errors.pp', '../unix/dl.pp', '../inc/dynlibs.pas', '../objpas/types.pp', '../unix/cthreads.pp',
      '../objpas/rtlconsts.pp', '../unix/classes.pp', '../objpas/fgl.pp', '../unix/dos.pp', '../unix/unixcp.pp',
      '../objpas/fpwidestring.pp', 'cwstring.pp', '../inc/macpas.pp', '../inc/iso7185.pp', '../inc/extpas.pp',
      '../inc/lineinfo.pp', '../inc/lnfodwrf.pp', '../objpas/unicodedata.pas') do
      if FileExists(OsDir + PathDelim + StringReplace(U, '/', PathDelim, [rfReplaceAll])) then
        if not Compile([U]) then Exit;
    if not Compile(['-Fi../charmaps', '../charmaps/cpall.pas']) then Exit;
    Exit;
  end;
  Base := ['-T' + Target.OS, '-P' + Target.CPU, '-n', '-O2', '-Ur', '-Xs', '-vew', '-FU' + Out_, '-Fu' + Out_,
    '-Fi../inc', '-Fi../' + Target.CPU, '-Fu../inc', '-Fu../' + Target.CPU, '-Fu../common'];
  { the steps of the RTL's Makefile.fpc for Windows }
  if not Compile(['-Us', '-Sg', 'system.pp', '-Fi../win']) then Exit;
  if not Compile(['../inc/uuchar.pp']) then Exit;
  if not Compile(['-I../objpas', '../objpas/objpas.pp']) then Exit;
  if not Compile(['-Fi../objpas/sysutils', '-Fi../objpas/classes', '-I../win', '-I../objpas', '-I../win/wininc',
    '-Fu../win/wininc', '-Fu../win', '-I../inc', '-Fu../objpas', 'buildrtl.pp']) then Exit;
  if not Compile(['../inc/macpas.pp']) then Exit;
  if not Compile(['../inc/iso7185.pp']) then Exit;
  if not Compile(['-Fi../charmaps', '../charmaps/cpall.pas']) then Exit;
  if not Compile(['../inc/lineinfo.pp']) then Exit;
  if not Compile(['../inc/lnfodwrf.pp']) then Exit;
end;

end.
