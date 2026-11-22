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

{ sqlite3.dll next to a Windows program that uses Pastel.Db (its compiled
  units are in UnitsDir): Windows has no SQLite of its own, Pastel carries one
  (framework/windows/<x64|x86>/sqlite3.dll). The name copied, or ''. }
function CopyWindowsSqlite(const Target: TTarget; const ExeDir, UnitsDir: string): string;

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
  phone has the real ones). Made with the binutils of the target's CPU, so
  the NDK is not needed: ~/.pastel/android/<arm64|arm|x86_64|x86>/lib/. }
function AndroidLibDir(const T: TTarget): string;
function AndroidLibsReady(const T: TTarget): Boolean;
{ Makes them; '' when it worked, else what went wrong. }
function MakeAndroidLibs(const T: TTarget; const BinPrefix: string): string;

{ The compiler for another CPU (ppcrossarm, ppcross386, ppcrossa64); '' when
  this computer's compiler makes code for the target's CPU itself. }
function CrossCompilerName(const T: TTarget): string;
{ Where "pastel doctor --install" puts cross-compilers it builds:
  ~/.pastel/fpc/<version>/bin/. }
function PastelCompilerDir(const Fpc: string): string;
{ The target's compiler is there (or none is needed). }
function CrossCompilerReady(const Fpc: string; const T: TTarget): Boolean;
{ Options for fpc so it finds a compiler Pastel built ('-Xp<dir>'), or none. }
function CompilerOptions(const Fpc: string; const T: TTarget): TStringArray;
{ Builds the target's cross-compiler from Free Pascal's sources (the compiler
  folder of fpc-source, or of the sources FPCDIR points to) into
  PastelCompilerDir; '' when it worked, else what went wrong. }
function BuildCrossCompiler(const Fpc: string; const T: TTarget): string;

implementation

uses
  Classes, Math, zipper, Pastel.Http, Pastel.Console, Pastel.Builder;

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
    { a Windows release of Pastel carries them next to pastel.exe }
    if not FileExists(Src) and FileExists(ExtractFilePath(ParamStr(0)) + F) and IsWindows(HostTarget) and
      (Target.Name = HostTarget.Name) then
      Src := ExtractFilePath(ParamStr(0)) + F;
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

function CompilerSourcesDir: string;
begin
  Result := FpcSourceDir;
  if (Result <> '') and FileExists(IncludeTrailingPathDelimiter(Result) + 'compiler' + PathDelim + 'pp.pas') then
    Result := IncludeTrailingPathDelimiter(Result) + 'compiler' + PathDelim
  else
    Result := '';
end;

function CopyWindowsSqlite(const Target: TTarget; const ExeDir, UnitsDir: string): string;
var
  Src, Dest, Arch: string;
  S, D: TFileStream;
begin
  Result := '';
  if not IsWindows(Target) or not FileExists(IncludeTrailingPathDelimiter(UnitsDir) + 'pastel.db.ppu') then
    Exit;
  if Target.CPU = 'i386' then
    Arch := 'x86'
  else
    Arch := 'x64';
  Src := ExpandFileName(IncludeTrailingPathDelimiter(FrameworkDir) + '..' + PathDelim + 'windows' + PathDelim + Arch +
    PathDelim + 'sqlite3.dll');
  if not FileExists(Src) then
    Exit;
  Dest := IncludeTrailingPathDelimiter(ExeDir) + 'sqlite3.dll';
  if not FileExists(Dest) or (FileAge(Dest) < FileAge(Src)) then
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
  Result := 'sqlite3.dll';
end;

function CanBuildRtl(const Target: TTarget): Boolean;
var
  Fpc: string;
begin
  { Android: with the compiler for its CPU, which Pastel can build from the sources }
  if Target.OS = 'android' then
  begin
    Fpc := FindFpc;
    Exit((Fpc <> '') and (CrossCompilerReady(Fpc, Target) or (CompilerSourcesDir <> '')));
  end;
  {$IFDEF CPUX86_64}
  Result := (Target.CPU = 'x86_64') and (Target.OS = 'win64');
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function CrossCompilerName(const T: TTarget): string;
const
  HostCPU = {$I %FPCTARGETCPU%};
begin
  if SameText(T.CPU, HostCPU) then
    Exit('');
  if T.CPU = 'aarch64' then
    Result := 'ppcrossa64'
  else if T.CPU = 'arm' then
    Result := 'ppcrossarm'
  else if T.CPU = 'i386' then
    Result := 'ppcross386'
  else if T.CPU = 'x86_64' then
    Result := 'ppcrossx64'
  else
    Result := 'ppcross' + T.CPU;
  {$IFDEF WINDOWS}
  Result := Result + '.exe';
  {$ENDIF}
end;

function PastelCompilerDir(const Fpc: string): string;
begin
  if PastelHome = '' then
    Exit('');
  Result := PastelHome + 'fpc' + PathDelim + FpcVersion(Fpc) + PathDelim + 'bin' + PathDelim;
end;

function CrossCompilerReady(const Fpc: string; const T: TTarget): Boolean;
var
  Name: string;
begin
  Name := CrossCompilerName(T);
  if Name = '' then
    Exit(True);
  Result := (ExeSearch(Name, GetEnvironmentVariable('PATH')) <> '') or
    FileExists(IncludeTrailingPathDelimiter(ExtractFileDir(Fpc)) + Name) or
    ((PastelCompilerDir(Fpc) <> '') and FileExists(PastelCompilerDir(Fpc) + Name));
  { the fpc package's own name for the ARM 64-bit compiler on ARM 64-bit computers }
  if not Result and (T.CPU = 'aarch64') then
    Result := ExeSearch('ppca64', GetEnvironmentVariable('PATH')) <> '';
end;

function CompilerOptions(const Fpc: string; const T: TTarget): TStringArray;
var
  Name: string;
begin
  Result := nil;
  Name := CrossCompilerName(T);
  if (Name = '') or (PastelCompilerDir(Fpc) = '') then
    Exit;
  if (ExeSearch(Name, GetEnvironmentVariable('PATH')) = '') and
    not FileExists(IncludeTrailingPathDelimiter(ExtractFileDir(Fpc)) + Name) and
    FileExists(PastelCompilerDir(Fpc) + Name) then
    Result := ['-Xp' + PastelCompilerDir(Fpc)];
end;

function BuildCrossCompiler(const Fpc: string; const T: TTarget): string;
var
  Src, Out_, Units, Gen, Msg, Output, Name, Ver, Define: string;
  Args: TStringList;
  Candidates: TStringArray;
  C: string;

  function Compile(const Dir: string; const A: array of string): Boolean;
  var
    S: string;
  begin
    Args.Clear;
    for S in A do
      Args.Add(S);
    Result := RunCapture(Fpc, Args, Dir, Output) = 0;
    if not Result then
      BuildCrossCompiler := 'the compiler for ' + T.CPU + ' did not compile:' + LineEnding +
        Trim(Copy(Output, Max(1, Length(Output) - 1500), MaxInt));
  end;

begin
  Result := '';
  Name := CrossCompilerName(T);
  if Name = '' then
    Exit;
  Src := CompilerSourcesDir;
  if Src = '' then
    Exit('the compiler''s sources are needed: sudo apt install fpc-source (or the source archive from ' +
      'freepascal.org, with FPCDIR set to its folder)');
  Ver := FpcVersion(Fpc);
  Out_ := PastelCompilerDir(Fpc);
  if Out_ = '' then
    Exit('the home folder is not known (set PASTEL_CACHE)');
  Units := PastelHome + 'fpc' + PathDelim + Ver + PathDelim + 'compiler-units' + PathDelim + T.CPU + PathDelim;
  Gen := PastelHome + 'fpc' + PathDelim + Ver + PathDelim + 'compiler-units' + PathDelim + 'msg' + PathDelim;
  ForceDirectories(Out_);
  ForceDirectories(Units);
  ForceDirectories(Gen);
  Args := TStringList.Create;
  try
    { the compiler's messages: msgtxt.inc is in the full sources; Debian's fpc-source has only errore.msg }
    if not FileExists(Src + 'msgtxt.inc') and not FileExists(Gen + 'msgtxt.inc') then
    begin
      Candidates := [Src + 'msg' + PathDelim + 'errore.msg',
        ExtractFileDir(ExtractFileDir(Fpc)) + PathDelim + 'lib' + PathDelim + 'fpc' + PathDelim + Ver + PathDelim + 'msg' + PathDelim + 'errore.msg',
        '/usr/lib/x86_64-linux-gnu/fpc/' + Ver + '/msg/errore.msg', '/usr/lib/aarch64-linux-gnu/fpc/' + Ver + '/msg/errore.msg',
        '/usr/lib/fpc/' + Ver + '/msg/errore.msg', '/usr/local/lib/fpc/' + Ver + '/msg/errore.msg'];
      Msg := '';
      for C in Candidates do
        if (Msg = '') and FileExists(C) then
          Msg := C;
      if Msg = '' then
        Exit('the compiler''s messages (errore.msg) were not found in the Free Pascal sources');
      if not Compile(Gen, ['-FU' + Gen, '-FE' + Gen, '-Fu' + Src, '-Fi' + Src, Src + 'utils' + PathDelim + 'msg2inc.pp']) then
        Exit;
      Args.Clear;
      Args.Add(Msg);
      Args.Add('msg');
      Args.Add('msg');
      if RunCapture(Gen + 'msg2inc' {$IFDEF WINDOWS} + '.exe'{$ENDIF}, Args, Gen, Output) <> 0 then
        Exit('the compiler''s messages could not be made: ' + Trim(Output));
    end;
    Status('Compiling', Format('Free Pascal''s compiler for %s (%s) from %s', [T.CPU, Name, Src]));
    if T.CPU = 'aarch64' then
      Define := '-dAARCH64'
    else if T.CPU = 'x86_64' then
      Define := '-dX86_64'
    else
      Define := '-d' + UpperCase(T.CPU);
    Args.Clear;
    Args.Add('-Fi' + Gen);
    Args.Add('-Fu' + T.CPU);
    Args.Add('-Fi' + T.CPU);
    if (T.CPU = 'i386') or (T.CPU = 'x86_64') then
    begin
      Args.Add('-Fux86');
      Args.Add('-Fix86');
    end;
    for C in TStringArray.Create('-Fusystems', '-Fi.', '-Fu.', Define, '-dGDB', '-dBROWSERLOG', '-O2', '-Xs', '-XX', '-CX',
      '-FU' + Units, '-FE' + Out_, '-o' + Name, 'pp.pas') do
      Args.Add(C);
    if RunCapture(Fpc, Args, Src, Output) <> 0 then
      Exit('the compiler for ' + T.CPU + ' did not compile:' + LineEnding + Trim(Copy(Output, Max(1, Length(Output) - 1500), MaxInt)));
    if not FileExists(Out_ + Name) then
      Exit('the compiler for ' + T.CPU + ' was not made: ' + Out_ + Name);
    Status('Built', Out_ + Name);
  finally
    Args.Free;
  end;
end;

function AndroidLibDir(const T: TTarget): string;
var
  Arch: string;
begin
  if PastelHome = '' then
    Exit('');
  if T.CPU = 'aarch64' then
    Arch := 'arm64'
  else if T.CPU = 'i386' then
    Arch := 'x86'
  else
    Arch := T.CPU;
  Result := PastelHome + 'android' + PathDelim + Arch + PathDelim + 'lib' + PathDelim;
end;

function AndroidLibsReady(const T: TTarget): Boolean;
var
  F: string;
begin
  Result := AndroidLibDir(T) <> '';
  if Result then
    for F in TStringArray.Create('dllprt0.o', 'crtbegin_so.o', 'crtend_so.o', 'libc.so', 'libm.so', 'libdl.so', 'liblog.so',
      'libandroid.so') do
      if not FileExists(AndroidLibDir(T) + F) then
        Exit(False);
end;

function MakeAndroidLibs(const T: TTarget; const BinPrefix: string): string;
const
  NL = LineEnding;
  NoExecStack = #9'.section .note.GNU-stack,"",%progbits' + NL;
  { __dso_handle (this library's handle) }
  DsoHandle64 =
    #9'.data' + NL + #9'.p2align 3' + NL +
    #9'.globl __dso_handle' + NL + #9'.hidden __dso_handle' + NL + #9'.type __dso_handle,%object' + NL +
    '__dso_handle:' + NL + #9'.quad __dso_handle' + NL;
  DsoHandle32 =
    #9'.data' + NL + #9'.p2align 2' + NL +
    #9'.globl __dso_handle' + NL + #9'.hidden __dso_handle' + NL + #9'.type __dso_handle,%object' + NL +
    '__dso_handle:' + NL + #9'.long __dso_handle' + NL;
  AtExitHead =
    #9'.text' + NL + #9'.p2align 2' + NL +
    #9'.globl atexit' + NL + #9'.hidden atexit' + NL + #9'.type atexit,%function' + NL;
  { atexit(f) = __cxa_atexit(f, nil, &__dso_handle), for each CPU }
  AtExitA64 =
    'atexit:' + NL + #9'mov x1, xzr' + NL + #9'adrp x2, __dso_handle' + NL +
    #9'add x2, x2, :lo12:__dso_handle' + NL + #9'b __cxa_atexit' + NL;
  AtExitArm =
    #9'.arm' + NL +
    'atexit:' + NL + #9'mov r1, #0' + NL + #9'ldr r2, .Ldso' + NL + '.Lpc:' + NL + #9'add r2, pc, r2' + NL +
    #9'b __cxa_atexit(PLT)' + NL + '.Ldso:' + NL + #9'.word __dso_handle-(.Lpc+8)' + NL;
  AtExitX64 =
    'atexit:' + NL + #9'xorl %esi, %esi' + NL + #9'leaq __dso_handle(%rip), %rdx' + NL +
    #9'jmp __cxa_atexit@PLT' + NL;
  AtExitX86 =
    'atexit:' + NL + #9'pushl %ebx' + NL + #9'call .Lpc' + NL + '.Lpc:' + NL + #9'popl %ebx' + NL +
    #9'addl $_GLOBAL_OFFSET_TABLE_+(.-.Lpc), %ebx' + NL + #9'leal __dso_handle@GOTOFF(%ebx), %eax' + NL +
    #9'pushl %eax' + NL + #9'pushl $0' + NL + #9'pushl 16(%esp)' + NL + #9'call __cxa_atexit@PLT' + NL +
    #9'addl $12, %esp' + NL + #9'popl %ebx' + NL + #9'ret' + NL;
var
  Dir, Output, Lib, CrtBegin, DllPrt0: string;
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
  Dir := AndroidLibDir(T);
  if Dir = '' then
    Exit('the home folder is not known (set PASTEL_CACHE)');
  { the libc start of a library: __dso_handle, and atexit for this library;
    Free Pascal's start of an Android library, run by the system's loader }
  if T.CPU = 'aarch64' then
  begin
    CrtBegin := DsoHandle64 + AtExitHead + AtExitA64;
    DllPrt0 := #9'.section .init_array,"aw"' + NL + #9'.p2align 3' + NL + #9'.quad FPC_LIB_START_ANDROID' + NL;
  end
  else if T.CPU = 'x86_64' then
  begin
    CrtBegin := DsoHandle64 + AtExitHead + AtExitX64;
    DllPrt0 := #9'.section .init_array,"aw"' + NL + #9'.p2align 3' + NL + #9'.quad FPC_LIB_START_ANDROID' + NL;
  end
  else if T.CPU = 'arm' then
  begin
    CrtBegin := DsoHandle32 + AtExitHead + AtExitArm;
    DllPrt0 := #9'.section .init_array,"aw"' + NL + #9'.p2align 2' + NL + #9'.long FPC_LIB_START_ANDROID' + NL;
  end
  else if T.CPU = 'i386' then
  begin
    CrtBegin := DsoHandle32 + AtExitHead + AtExitX86;
    DllPrt0 := #9'.section .init_array,"aw"' + NL + #9'.p2align 2' + NL + #9'.long FPC_LIB_START_ANDROID' + NL;
  end
  else
    Exit('Android on ' + T.CPU + ' is not supported');
  ForceDirectories(Dir);
  Save('crtbegin_so.s', CrtBegin + NoExecStack);
  Save('crtend_so.s', NoExecStack);
  Save('dllprt0.s', DllPrt0 + NoExecStack);
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
  if Target.OS = 'android' then
  begin
    BinPrefix := FindBinutilsPrefix(Target, HaveBinutils);
    if not HaveBinutils then
      Exit('the binutils for ' + Target.Name + ' are needed: sudo apt install ' + Target.BinutilsPackage);
    if not CrossCompilerReady(Fpc, Target) then
    begin
      Result := BuildCrossCompiler(Fpc, Target);
      if Result <> '' then
        Exit;
    end;
    Status('Compiling', Format('Free Pascal''s RTL for %s into %s', [Target.Name, Out_]));
    Base := ['-T' + Target.OS, '-P' + Target.CPU, '-XP' + BinPrefix, '-n', '-O2', '-Ur', '-Xs', '-vew',
      '-FU' + Out_, '-Fu' + Out_, '-Fi../inc', '-Fi../' + Target.CPU, '-Fi../unix', '-Fi' + Target.CPU, '-Fi../linux',
      '-Fi../linux/' + Target.CPU, '-Fu../inc', '-Fu../' + Target.CPU, '-Fu../unix', '-Fu../linux', '-Fu../common',
      '-Fu../objpas', '-Fi../objpas', '-Fi../objpas/sysutils', '-Fi../objpas/classes'];
    { O_LARGEFILE and a few others are only defined for "aarch64" in Free Pascal 3.2.2 }
    if Target.CPU = 'aarch64' then
      Base := Concat(Base, ['-dAARCH64']);
    Base := Concat(Base, SplitOptions(Target.Options), CompilerOptions(Fpc, Target));
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
  Status('Compiling', Format('Free Pascal''s RTL for %s into %s', [Target.Name, Out_]));
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
