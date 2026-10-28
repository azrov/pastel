{ Pastel - "pastel doctor": checks the setup and which targets can be built.
  Part of the Pastel project, MIT License. }
unit Pastel.Doctor;

{$mode objfpc}{$H+}

interface

function RunDoctor: Boolean;
function CanBuildTarget(const Fpc: string; Index: Integer): Boolean;

implementation

uses
  Classes, SysUtils, Pastel.Console, Pastel.Project, Pastel.Targets, Pastel.Builder;

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
    Code.Text := 'program probe; uses SysUtils; begin end.';
    Code.SaveToFile(Src);
    Args.Add('-P' + T.CPU);
    Args.Add('-T' + T.OS);
    for Opt in SplitOptions(T.Options) do
      Args.Add(Opt);
    Prefix := FindBinutilsPrefix(T, HaveBinutils);
    if Prefix <> '' then
      Args.Add('-XP' + Prefix);
    Args.Add('-FU' + Tmp);
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
  if VersionAtLeast(Ver, 3, 2) then
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
      WriteLn('  ', MarkOk, ' ', Format('%-12s', [KnownTargets[I].Name]), ' ',
        KnownTargets[I].Description, Note);
    end
    else
    begin
      Missing := True;
      WriteLn('  ', MarkFail, ' ', Format('%-12s', [KnownTargets[I].Name]), ' ',
        Dim(KnownTargets[I].Description + ' - not installed'), Note);
      FindBinutilsPrefix(KnownTargets[I], HaveBinutils);
      if not HaveBinutils then
        WriteLn('                  ', Dim(BinutilsHint(KnownTargets[I])));
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
    WriteLn('  macOS targets also need Apple''s SDK. Automatic installation');
    WriteLn('  ("pastel doctor --install") is planned.');
  end;
end;

end.
