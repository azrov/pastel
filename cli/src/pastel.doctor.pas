{ Pastel - "pastel doctor": checks the setup and which targets can be built.
  Part of the Pastel project, MIT License. }
unit Pastel.Doctor;

{$mode objfpc}{$H+}

interface

function RunDoctor: Boolean;
function CanBuildTarget(const Fpc: string; Index: Integer): Boolean;

implementation

uses
  Classes, SysUtils, dynlibs, Pastel.Console, Pastel.Project, Pastel.Targets, Pastel.Builder, Pastel.Runtime;

function CanLoad(const Names: array of string): Boolean;
var
  N: string;
  H: TLibHandle;
begin
  for N in Names do
  begin
    H := LoadLibrary(N);
    if H <> NilHandle then
    begin
      UnloadLibrary(H);
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure CheckAppLibraries;
const
  {$IF defined(WINDOWS)}
  SdlNames: array[0..0] of string = ('SDL2.dll');
  FtNames: array[0..2] of string = ('freetype.dll', 'libfreetype.dll', 'libfreetype-6.dll');
  {$ELSEIF defined(DARWIN)}
  SdlNames: array[0..0] of string = ('libSDL2-2.0.0.dylib');
  FtNames: array[0..0] of string = ('libfreetype.6.dylib');
  {$ELSE}
  SdlNames: array[0..0] of string = ('libSDL2-2.0.so.0');
  FtNames: array[0..0] of string = ('libfreetype.so.6');
  {$ENDIF}
var
  Fw: string;
begin
  WriteLn(Bold('GUI apps'));
  Fw := FrameworkDir;
  if Fw <> '' then
    WriteLn('  ', MarkOk, ' Pastel framework  ', Dim(Fw))
  else
    WriteLn('  ', MarkFail, ' Pastel framework not found ', Dim('(set PASTEL_HOME)'));
  if CanLoad(SdlNames) then
    WriteLn('  ', MarkOk, ' SDL2 (windows, input)')
  else
  begin
    WriteLn('  ', MarkFail, ' SDL2 not found');
    {$IFDEF LINUX}
    WriteLn('      ', Dim('sudo apt install libsdl2-2.0-0'));
    {$ELSE}
    WriteLn('      ', Dim('put SDL2.dll next to your program (https://libsdl.org)'));
    {$ENDIF}
  end;
  if CanLoad(FtNames) then
    WriteLn('  ', MarkOk, ' FreeType (text)')
  else
  begin
    WriteLn('  ', MarkFail, ' FreeType not found');
    {$IFDEF LINUX}
    WriteLn('      ', Dim('sudo apt install libfreetype6'));
    {$ENDIF}
  end;
  WriteLn;
end;

procedure CheckNetLibraries;
const
  {$IF defined(WINDOWS)}
  SslNames: array[0..3] of string = ('libssl-3-x64.dll', 'libssl-3.dll', 'libssl-1_1-x64.dll', 'libssl-1_1.dll');
  {$ELSEIF defined(DARWIN)}
  SslNames: array[0..1] of string = ('libssl.3.dylib', 'libssl.1.1.dylib');
  {$ELSE}
  SslNames: array[0..2] of string = ('libssl.so.3', 'libssl.so.1.1', 'libssl.so');
  {$ENDIF}
begin
  WriteLn(Bold('Network'));
  {$IFDEF WINDOWS}
  { Pastel.Http uses Windows' own HTTP (WinINet): its certificates and proxy, nothing to install }
  WriteLn('  ', MarkOk, ' HTTP and HTTPS through Windows (Pastel.Http)');
  WriteLn;
  Exit;
  {$ENDIF}
  if CanLoad(SslNames) then
    WriteLn('  ', MarkOk, ' OpenSSL (HTTPS in Pastel.Http)')
  else
  begin
    WriteLn('  ', MarkFail, ' OpenSSL not found: plain HTTP works, HTTPS does not');
    {$IFDEF LINUX}
    WriteLn('      ', Dim('sudo apt install libssl3'));
    {$ELSE}
    WriteLn('      ', Dim('put libssl-3-x64.dll and libcrypto-3-x64.dll next to your program'));
    {$ENDIF}
  end;
  WriteLn;
end;

function VersionAtLeast(const V: string; Major, Minor: Integer): Boolean;
var
  Parts: TStringArray;
  A, B: Integer;
begin
  Parts := V.Split(['.']);
  if Length(Parts) < 2 then
    Exit(False);
  A := StrToIntDef(Parts[0], 0);
  B := StrToIntDef(Parts[1], 0);
  Result := (A > Major) or ((A = Major) and (B >= Minor));
end;

{ The only reliable test: compile an empty program for that target. }
function CanBuildTarget(const Fpc: string; Index: Integer): Boolean;
var
  Tmp, Src, Opt, Output, Prefix: string;
  Args, Code: TStringList;
  T: TTarget;
  HaveBinutils: Boolean;
begin
  T := KnownTargets[Index];
  Tmp := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('pastel-doctor-%d-%s', [GetProcessID, T.Name]) + PathDelim;
  ForceDirectories(Tmp);
  Src := Tmp + 'probe.pas';
  Code := TStringList.Create;
  Args := TStringList.Create;
  try
    if T.OS = 'android' then
    begin
      { an Android app is a library, linked with Pastel's stand-ins for the system libraries }
      if not AndroidLibsReady(T) or not CrossCompilerReady(Fpc, T) then
        Exit(False);
      Code.Text := 'library probe; uses SysUtils; procedure P; cdecl; begin end; exports P; begin end.';
      Args.Add('-Fl' + AndroidLibDir(T));
      Args.Add('-Fo' + AndroidLibDir(T));
    end
    else
      Code.Text := 'program probe; uses SysUtils; begin end.';
    Code.SaveToFile(Src);
    Args.Add('-P' + T.CPU);
    Args.Add('-T' + T.OS);
    for Opt in SplitOptions(T.Options) do
      Args.Add(Opt);
    Opt := UserRtlDir(Fpc, T);
    if (Opt <> '') and FileExists(Opt + 'system.ppu') then
      Args.Add('-Fu' + Opt);
    Prefix := FindBinutilsPrefix(T, HaveBinutils);
    if Prefix <> '' then
      Args.Add('-XP' + Prefix);
    for Opt in CompilerOptions(Fpc, T) do
      Args.Add(Opt);
    Args.Add('-FU' + Tmp);
    if T.OS = 'android' then
      Args.Add('-o' + Tmp + 'libprobe.so')
    else
      Args.Add('-o' + Tmp + 'probe' + T.ExeExt);
    Args.Add('-vew');
    Args.Add(Src);
    Result := RunCapture(Fpc, Args, Tmp, Output) = 0;
  finally
    Args.Free;
    Code.Free;
    DeleteTree(Tmp);
  end;
end;

function RunDoctor: Boolean;
var
  Fpc, Ver, Note: string;
  I, Ready: Integer;
  Host: TTarget;
  Missing, HaveBinutils: Boolean;
begin
  Result := True;
  Host := HostTarget;
  WriteLn(Bold('Pastel ' + PastelVersion));
  WriteLn('  This computer: ', Host.Name, ' (', Host.Description, ')');
  WriteLn;

  WriteLn(Bold('Compiler'));
  Fpc := FindFpc;
  if Fpc = '' then
  begin
    WriteLn('  ', MarkFail, ' Free Pascal (fpc) not found');
    WriteLn;
    Tip('install Free Pascal 3.2 or newer:');
    WriteLn('    Linux Mint / Ubuntu:  sudo apt install fpc');
    WriteLn('    Windows / macOS:      https://www.freepascal.org/download.html');
    WriteLn('  or point Pastel to it with the PASTEL_FPC environment variable.');
    Exit(False);
  end;
  Ver := FpcVersion(Fpc);
  if Ver = '' then
  begin
    WriteLn('  ', MarkFail, ' Free Pascal does not start: "', Fpc, ' -iV" gave no version  ');
    Tip('check the installation; fpc must find its compiler (ppcx64 / ppc386) next to it');
    Result := False;
  end
  else if VersionAtLeast(Ver, 3, 2) then
    WriteLn('  ', MarkOk, ' Free Pascal ', Ver, '  ', Dim(Fpc))
  else
  begin
    WriteLn('  ', MarkFail, ' Free Pascal ', Ver, ' is too old (3.2 or newer needed)  ', Dim(Fpc));
    Result := False;
  end;

  if ExeSearch({$IFDEF WINDOWS}'gdb.exe'{$ELSE}'gdb'{$ENDIF}, GetEnvironmentVariable('PATH')) <> '' then
    WriteLn('  ', MarkOk, ' gdb debugger')
  else
    WriteLn('  ', Dim('-'), ' gdb debugger not found ', Dim('(optional, needed for debugging in VS Code later)'));
  WriteLn;

  CheckAppLibraries;
  CheckNetLibraries;

  WriteLn(Bold('Targets'));
  Ready := 0;
  Missing := False;
  for I := Low(KnownTargets) to High(KnownTargets) do
  begin
    Note := '';
    if KnownTargets[I].Name = Host.Name then
      Note := Dim(' (this computer)');
    if CanBuildTarget(Fpc, I) then
    begin
      Inc(Ready);
      WriteLn('  ', MarkOk, ' ', Format('%-15s', [KnownTargets[I].Name]), ' ',
        KnownTargets[I].Description, Note);
    end
    else
    begin
      Missing := True;
      WriteLn('  ', MarkFail, ' ', Format('%-15s', [KnownTargets[I].Name]), ' ',
        Dim(KnownTargets[I].Description + ' - not installed'), Note);
      FindBinutilsPrefix(KnownTargets[I], HaveBinutils);
      if not HaveBinutils then
        WriteLn('                     ', Dim(BinutilsHint(KnownTargets[I])))
      else if CanBuildRtl(KnownTargets[I]) then
        WriteLn('                     ', Dim(Format('pastel doctor --install %s sets it up (a minute, once)',
          [KnownTargets[I].Name])));
    end;
  end;
  WriteLn;
  WriteLn(Format('  %d of %d targets ready.', [Ready, Length(KnownTargets)]));

  if Missing then
  begin
    WriteLn;
    Tip('building for other platforms needs Free Pascal cross-compilers.');
    WriteLn('  Today the easiest way is fpcupdeluxe (Cross tab):');
    WriteLn('    https://github.com/LongDirtyAnimAlf/fpcupdeluxe');
    WriteLn('  Windows (from Linux): pastel doctor --install windows');
    WriteLn('  Android (every phone and the emulator): pastel doctor --install android');
    WriteLn('  macOS targets also need Apple''s SDK.');
  end;
end;

end.
