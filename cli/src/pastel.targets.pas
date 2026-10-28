{ Pastel - build targets (platforms Pastel can compile for).
  Part of the Pastel project, MIT License. }
unit Pastel.Targets;

{$mode objfpc}{$H+}

interface

type
  TTarget = record
    Name: string;          { canonical name, used for build/<name>/ }
    CPU: string;           { fpc -P }
    OS: string;            { fpc -T }
    Options: string;       { extra fpc options, space separated }
    ExeExt: string;
    Description: string;
    { Prefixes of external assembler/linker tools (binutils) to look for when
      cross-compiling, space separated. Empty: FPC's internal linker is used. }
    Binutils: string;
    BinutilsPackage: string;   { Debian/Ubuntu/Mint package providing them }
  end;

const
  KnownTargets: array[0..6] of TTarget = (
    (Name: 'linux';       CPU: 'x86_64';  OS: 'linux';  Options: '';
     ExeExt: '';     Description: 'Linux, 64-bit PC';
     Binutils: 'x86_64-linux-gnu- x86_64-linux-'; BinutilsPackage: 'binutils-x86-64-linux-gnu'),
    (Name: 'linux-arm64'; CPU: 'aarch64'; OS: 'linux';  Options: '';
     ExeExt: '';     Description: 'Linux ARM 64-bit (Raspberry Pi 3/4/5 with 64-bit OS)';
     Binutils: 'aarch64-linux-gnu- aarch64-linux-'; BinutilsPackage: 'binutils-aarch64-linux-gnu'),
    (Name: 'linux-arm';   CPU: 'arm';     OS: 'linux';  Options: '-CaEABIHF -CpARMV6 -CfVFPV2';
     ExeExt: '';     Description: 'Linux ARM 32-bit (Raspberry Pi with 32-bit OS)';
     Binutils: 'arm-linux-gnueabihf- arm-linux-'; BinutilsPackage: 'binutils-arm-linux-gnueabihf'),
    (Name: 'windows';     CPU: 'x86_64';  OS: 'win64';  Options: '';
     ExeExt: '.exe'; Description: 'Windows, 64-bit';
     Binutils: ''; BinutilsPackage: ''),
    (Name: 'windows32';   CPU: 'i386';    OS: 'win32';  Options: '';
     ExeExt: '.exe'; Description: 'Windows, 32-bit';
     Binutils: ''; BinutilsPackage: ''),
    (Name: 'macos';       CPU: 'x86_64';  OS: 'darwin'; Options: '';
     ExeExt: '';     Description: 'macOS, Intel';
     Binutils: 'x86_64-apple-darwin-'; BinutilsPackage: ''),
    (Name: 'macos-arm64'; CPU: 'aarch64'; OS: 'darwin'; Options: '';
     ExeExt: '';     Description: 'macOS, Apple Silicon';
     Binutils: 'aarch64-apple-darwin-'; BinutilsPackage: '')
  );

  { Friendly names people are likely to type. }
  TargetAliases: array[0..5, 0..1] of string = (
    ('rpi',   'linux-arm64'),
    ('rpi64', 'linux-arm64'),
    ('rpi32', 'linux-arm'),
    ('win',   'windows'),
    ('win64', 'windows'),
    ('win32', 'windows32')
  );

function FindTarget(const AName: string; out T: TTarget): Boolean;
function HostTarget: TTarget;
function IsHost(const T: TTarget): Boolean;
{ Binutils prefix to pass as -XP when cross-compiling, '' if none is needed
  or none is installed. Found tells whether a needed toolset exists. }
function FindBinutilsPrefix(const T: TTarget; out Found: Boolean): string;

implementation

uses
  SysUtils;

function FindTarget(const AName: string; out T: TTarget): Boolean;
var
  I: Integer;
  N: string;
begin
  N := LowerCase(Trim(AName));
  for I := Low(TargetAliases) to High(TargetAliases) do
    if TargetAliases[I, 0] = N then
      N := TargetAliases[I, 1];
  for I := Low(KnownTargets) to High(KnownTargets) do
    if KnownTargets[I].Name = N then
    begin
      T := KnownTargets[I];
      Exit(True);
    end;
  Result := False;
end;

function HostTarget: TTarget;
const
  HostCPU = {$I %FPCTARGETCPU%};
  HostOS = {$I %FPCTARGETOS%};
var
  I: Integer;
begin
  for I := Low(KnownTargets) to High(KnownTargets) do
    if SameText(KnownTargets[I].CPU, HostCPU) and SameText(KnownTargets[I].OS, HostOS) then
    begin
      Result := KnownTargets[I];
      { The ARM 32-bit entry carries Raspberry Pi tuning; on an ARM host the
        compiler's own defaults are the right choice. }
      if Result.CPU = 'arm' then
        Result.Options := '';
      Exit;
    end;
  Result.Name := LowerCase(HostOS + '-' + HostCPU);
  Result.CPU := LowerCase(HostCPU);
  Result.OS := LowerCase(HostOS);
  Result.Options := '';
  {$IFDEF WINDOWS}
  Result.ExeExt := '.exe';
  {$ELSE}
  Result.ExeExt := '';
  {$ENDIF}
  Result.Description := 'This computer';
  Result.Binutils := '';
  Result.BinutilsPackage := '';
end;

function IsHost(const T: TTarget): Boolean;
begin
  Result := T.Name = HostTarget.Name;
end;

function FindBinutilsPrefix(const T: TTarget; out Found: Boolean): string;
var
  Prefix, Ext: string;
begin
  Result := '';
  Found := True;
  if IsHost(T) or (T.Binutils = '') then
    Exit;
  {$IFDEF WINDOWS}
  Ext := '.exe';
  {$ELSE}
  Ext := '';
  {$ENDIF}
  for Prefix in T.Binutils.Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if ExeSearch(Prefix + 'as' + Ext, GetEnvironmentVariable('PATH')) <> '' then
      Exit(Prefix);
  Found := False;
end;

end.
