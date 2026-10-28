{ Pastel - command-line tool.
  Part of the Pastel project, MIT License. }
program pastel;

{$mode objfpc}{$H+}

uses
  SysUtils,
  Pastel.Console, Pastel.Toml, Pastel.Project, Pastel.Targets,
  Pastel.Builder, Pastel.Templates, Pastel.Doctor;

const
  ExitOk = 0;
  ExitError = 1;
  ExitUsage = 2;

type
  TCommandLine = record
    Command: string;
    Positional: TStringArray;   { arguments that are not options }
    PassThrough: TStringArray;  { everything after "--" }
    Target: string;
    Release, Verbose, All, Help: Boolean;
  end;

procedure Append(var A: TStringArray; const S: string);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := S;
end;

procedure ShowHelp;
begin
  WriteLn(Bold('Pastel ' + PastelVersion), ' - modern cross-platform toolkit for Object Pascal');
  WriteLn;
  WriteLn(Bold('Usage:'), ' pastel <command> [options]');
  WriteLn;
  WriteLn(Bold('Commands:'));
  WriteLn('  new <kind> <name>    Create a new project (kinds: console)');
  WriteLn('  build                Compile the project');
  WriteLn('  run [-- args]        Compile and run on this computer');
  WriteLn('  clean                Remove the build folder');
  WriteLn('  targets              List the platforms Pastel can build for');
  WriteLn('  doctor               Check your setup');
  WriteLn('  version              Show the Pastel version');
  WriteLn('  help                 Show this help');
  WriteLn;
  WriteLn(Bold('Build options:'));
  WriteLn('  -t, --target <name>  Build for another platform (e.g. windows, rpi)');
  WriteLn('  -r, --release        Optimized build without debug information');
  WriteLn('      --all            Build every platform listed in pastel.toml');
  WriteLn('  -v, --verbose        Show the full compiler command and output');
  WriteLn;
  WriteLn(Bold('Examples:'));
  WriteLn('  pastel new console hello');
  WriteLn('  cd hello && pastel run');
  WriteLn('  pastel build --target windows --release');
end;

function ParseCommandLine(out CL: TCommandLine): Boolean;
var
  I: Integer;
  A: string;
begin
  Result := True;
  CL := Default(TCommandLine);
  I := 1;
  while I <= ParamCount do
  begin
    A := ParamStr(I);
    if A = '--' then
    begin
      Inc(I);
      while I <= ParamCount do
      begin
        Append(CL.PassThrough, ParamStr(I));
        Inc(I);
      end;
      Break;
    end
    else if (A = '-t') or (A = '--target') then
    begin
      Inc(I);
      if I > ParamCount then
      begin
        Fail('--target needs a platform name, e.g. --target windows');
        Exit(False);
      end;
      CL.Target := ParamStr(I);
    end
    else if A.StartsWith('--target=') then
      CL.Target := Copy(A, Length('--target=') + 1, MaxInt)
    else if (A = '-r') or (A = '--release') then
      CL.Release := True
    else if (A = '-v') or (A = '--verbose') then
      CL.Verbose := True
    else if A = '--all' then
      CL.All := True
    else if (A = '-h') or (A = '--help') then
      CL.Help := True
    else if A = '--version' then
      CL.Command := 'version'
    else if (A <> '') and (A[1] = '-') then
    begin
      Fail(Format('unknown option "%s"', [A]));
      Hint('see "pastel help"');
      Exit(False);
    end
    else if CL.Command = '' then
      CL.Command := LowerCase(A)
    else
      Append(CL.Positional, A);
    Inc(I);
  end;
end;

{ Loads the project around the current folder, or explains what is wrong. }
function OpenProject: TPastelProject;
var
  Root: string;
begin
  Result := nil;
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if Root = '' then
  begin
    Fail('no ' + ProjectFileName + ' found here or in any parent folder');
    Hint('create a project with "pastel new console myapp"');
    Exit;
  end;
  try
    Result := TPastelProject.Load(Root);
  except
    on E: EProjectError do
      Fail(E.Message);
  end;
end;

function CmdNew(const CL: TCommandLine): Integer;
begin
  case Length(CL.Positional) of
    1: if CreateProject('console', CL.Positional[0], GetCurrentDir) then Exit(ExitOk);
    2: if CreateProject(LowerCase(CL.Positional[0]), CL.Positional[1], GetCurrentDir) then Exit(ExitOk);
  else
    Fail('usage: pastel new <kind> <name>');
    Hint('for example: pastel new console hello');
    Exit(ExitUsage);
  end;
  Result := ExitError;
end;

function ResolveTarget(const Name: string; out T: TTarget): Boolean;
begin
  if Name = '' then
  begin
    T := HostTarget;
    Exit(True);
  end;
  Result := FindTarget(Name, T);
  if not Result then
  begin
    Fail(Format('unknown target "%s"', [Name]));
    Hint('see "pastel targets" for the list');
  end;
end;

function CmdBuild(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  Opts: TBuildOptions;
  ExePath, Name: string;
  Failed: Integer;
begin
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
    Opts.Release := CL.Release;
    Opts.Verbose := CL.Verbose;
    if CL.All then
    begin
      if Length(Project.Platforms) = 0 then
      begin
        Fail('--all needs a list of platforms in ' + ProjectFileName);
        Hint('add: [targets] platforms = ["linux", "windows"]');
        Exit(ExitError);
      end;
      Failed := 0;
      for Name in Project.Platforms do
      begin
        if not ResolveTarget(Name, Opts.Target) then
        begin
          Inc(Failed);
          Continue;
        end;
        if not BuildProject(Project, Opts, ExePath) then
          Inc(Failed);
        WriteLn;
      end;
      if Failed > 0 then
      begin
        Fail(Format('%d of %d platform(s) failed', [Failed, Length(Project.Platforms)]));
        Exit(ExitError);
      end;
      Status('Done', Format('all %d platform(s) built', [Length(Project.Platforms)]));
      Exit(ExitOk);
    end;
    if not ResolveTarget(CL.Target, Opts.Target) then
      Exit(ExitUsage);
    if BuildProject(Project, Opts, ExePath) then
      Result := ExitOk
    else
      Result := ExitError;
  finally
    Project.Free;
  end;
end;

function CmdRun(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  T: TTarget;
begin
  if (CL.Target <> '') and FindTarget(CL.Target, T) and not IsHost(T) then
  begin
    Fail(Format('cannot run a %s program on this computer', [T.Name]));
    Hint(Format('use "pastel build --target %s" and copy the program to that device', [CL.Target]));
    Exit(ExitUsage);
  end;
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
    Result := RunProject(Project, CL.Release, CL.Verbose, CL.PassThrough);
  finally
    Project.Free;
  end;
end;

function CmdClean: Integer;
var
  Project: TPastelProject;
begin
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
    CleanProject(Project);
    Result := ExitOk;
  finally
    Project.Free;
  end;
end;

function CmdTargets: Integer;
var
  I: Integer;
  Host: TTarget;
begin
  Host := HostTarget;
  WriteLn(Bold('Targets'));
  for I := Low(KnownTargets) to High(KnownTargets) do
  begin
    Write('  ', Format('%-12s', [KnownTargets[I].Name]), ' ', KnownTargets[I].Description);
    if KnownTargets[I].Name = Host.Name then
      Write(Dim(' (this computer)'));
    WriteLn;
  end;
  WriteLn;
  WriteLn(Bold('Short names'));
  for I := Low(TargetAliases) to High(TargetAliases) do
    WriteLn('  ', Format('%-12s', [TargetAliases[I, 0]]), ' = ', TargetAliases[I, 1]);
  WriteLn;
  WriteLn('Run "pastel doctor" to see which ones this computer can build.');
  Result := ExitOk;
end;

var
  CL: TCommandLine;
begin
  InitConsole;
  if not ParseCommandLine(CL) then
    Halt(ExitUsage);
  if CL.Help or (CL.Command = '') or (CL.Command = 'help') then
  begin
    ShowHelp;
    Halt(ExitOk);
  end;
  try
    case CL.Command of
      'new':     ExitCode := CmdNew(CL);
      'build':   ExitCode := CmdBuild(CL);
      'run':     ExitCode := CmdRun(CL);
      'clean':   ExitCode := CmdClean;
      'targets': ExitCode := CmdTargets;
      'doctor':  if RunDoctor then ExitCode := ExitOk else ExitCode := ExitError;
      'version': WriteLn('pastel ', PastelVersion);
    else
      Fail(Format('unknown command "%s"', [CL.Command]));
      Hint('see "pastel help"');
      ExitCode := ExitUsage;
    end;
  except
    on E: Exception do
    begin
      Fail(E.Message);
      ExitCode := ExitError;
    end;
  end;
end.
