{ Pastel - command-line tool.
  Part of the Pastel project, MIT License. }
program pastel;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  Pastel.Console, Pastel.Toml, Pastel.Project, Pastel.Targets,
  Pastel.Builder, Pastel.Templates, Pastel.Doctor, Pastel.Inspect, Pastel.TestCmd,
  Pastel.Watch, Pastel.FmtCmd, Pastel.Package, Pastel.MigrateCmd, Pastel.LangCmd, Pastel.Runtime, Pastel.CustomCtl, Pastel.Upgrade, Pastel.UI, RegExpr;

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
    Release, Verbose, All, Help, Watch, Check, NoBuild, Dark, Install: Boolean;
    Json, Stdin, NoRun: Boolean;
    Output, Layout, Database: string;
    Width, Height: Integer;
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
  WriteLn('  new <kind> <name>      Create a new project (kinds: console, app, lib, service, api)');
  WriteLn('  new form <Name>        Add a window to an app');
  WriteLn('  new control <Name>     Add a control of your own (src/controls/)');
  WriteLn('  build                  Compile the project');
  WriteLn('  run [-- args]          Compile and run on this computer (--watch: again on every save)');
  WriteLn('  test [filter]          Run the tests in tests/ (only names matching filter; --watch, --json)');
  WriteLn('  fmt [files]            Format the code (--check: only report)');
  WriteLn('  package [kind]         An archive; deb, docker, appimage, installer (--target, --all, --no-build)');
  WriteLn('  migrate [status|new]   Database migrations in database/migrations (--database URL)');
  WriteLn('  lang [add <code>]      Texts to translate in assets/lang/*.json');
  WriteLn('  upgrade [--check]      Bring a project from an older Pastel up to date');
  WriteLn('  clean                  Remove the build folder');
  WriteLn('  targets                List the platforms Pastel can build for');
  WriteLn('  doctor                 Check your setup (--install windows: set up building for Windows)');
  WriteLn('  check [file]           Check .pform files (and .pas files) for mistakes');
  WriteLn('  preview <file>         Draw a .pform file into a PNG (-o out.png, --dark)');
  WriteLn('  schema                 Controls and properties as JSON (for editors)');
  WriteLn('  version                Show the Pastel version');
  WriteLn('  help                   Show this help');
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
  WriteLn('  pastel run --watch');
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
    else if A = '--no-build' then
      CL.NoBuild := True
    else if A = '--dark' then
      CL.Dark := True
    else if A = '--install' then
      CL.Install := True
    else if (A = '-w') or (A = '--watch') then
      CL.Watch := True
    else if A = '--no-run' then
      CL.NoRun := True
    else if A = '--check' then
      CL.Check := True
    else if A = '--json' then
      CL.Json := True
    else if A = '--stdin' then
      CL.Stdin := True
    else if (A = '-o') or (A = '--output') or (A = '--width') or (A = '--height') or (A = '--layout') or
            (A = '--database') then
    begin
      Inc(I);
      if I > ParamCount then
      begin
        Fail(A + ' needs a value');
        Exit(False);
      end;
      if (A = '-o') or (A = '--output') then
        CL.Output := ParamStr(I)
      else if A = '--layout' then
        CL.Layout := ParamStr(I)
      else if A = '--database' then
        CL.Database := ParamStr(I)
      else if A = '--width' then
        CL.Width := StrToIntDef(ParamStr(I), 0)
      else
        CL.Height := StrToIntDef(ParamStr(I), 0);
    end
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
var
  Root: string;
begin
  if (Length(CL.Positional) = 2) and SameText(CL.Positional[0], 'form') then
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('"pastel new form" adds a form to an app: run it in the app''s folder');
      Exit(ExitError);
    end;
    if CreateFormFiles(Root, CL.Positional[1]) then Exit(ExitOk) else Exit(ExitError);
  end;
  if (Length(CL.Positional) = 2) and SameText(CL.Positional[0], 'control') then
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('"pastel new control" adds a control to an app: run it in the app''s folder');
      Exit(ExitError);
    end;
    if CreateControlFile(Root, CL.Positional[1]) then Exit(ExitOk) else Exit(ExitError);
  end;
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
    Opts := Default(TBuildOptions);
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

{ the projects next to a library (in the folder above it) that depend on it:
  '../salon-desk, ../salon-api' }
function ProgramsUsing(const LibRoot: string): string;
var
  SR: TSearchRec;
  Parent, Dir: string;
  P: TPastelProject;
  D: TDependency;
begin
  Result := '';
  Parent := ExtractFileDir(ExcludeTrailingPathDelimiter(LibRoot));
  if FindFirst(Parent + PathDelim + '*', faDirectory, SR) = 0 then
  try
    repeat
      Dir := IncludeTrailingPathDelimiter(Parent + PathDelim + SR.Name);
      if (SR.Name = '.') or (SR.Name = '..') or not FileExists(Dir + ProjectFileName) then
        Continue;
      try
        P := TPastelProject.Load(Dir);
      except
        Continue;
      end;
      try
        if P.Kind <> 'lib' then
          for D in P.Dependencies do
            if SameText(ExcludeTrailingPathDelimiter(D.Root), ExcludeTrailingPathDelimiter(ExpandFileName(LibRoot))) then
            begin
              if Result <> '' then
                Result := Result + ', ';
              Result := Result + '../' + SR.Name;
            end;
      finally
        P.Free;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function CmdRun(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  T: TTarget;
  Users: string;
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
    if Project.Kind = 'lib' then
    begin
      Fail('a library has no program to run');
      Users := ProgramsUsing(Project.Root);
      if Users <> '' then
        Hint('these programs use it: ' + Users + '; run one of them (cd there, then pastel run)')
      else
        Hint('"pastel test" runs its tests; other projects use it as a dependency');
      Exit(ExitUsage);
    end;
    if CL.Watch then
      Exit(WatchRun(Project.Root, CL.Release, CL.Verbose, CL.PassThrough));
    Result := RunProject(Project, CL.Release, CL.Verbose, CL.PassThrough);
  finally
    Project.Free;
  end;
end;

function CmdTest(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
begin
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
    if CL.Watch then
      Exit(WatchTests(Project.Root, CL.Positional, CL.Verbose));
    Result := RunProjectTests(Project, CL.Positional, CL.Json, CL.Verbose, CL.NoRun);
  finally
    Project.Free;
  end;
end;

function CmdPackage(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  T: TTarget;
  Name, Kind: string;
  Failed: Integer;

  function PackageOne(const Target: TTarget): Boolean;
  begin
    if Kind = 'deb' then
      Result := PackageDeb(Project, Target, CL.Verbose) <> ''
    else if Kind = 'docker' then
      Result := PackageDocker(Project, Target, CL.Verbose, not CL.NoBuild) <> ''
    else if Kind = 'installer' then
      Result := PackageInstaller(Project, Target, CL.Verbose) <> ''
    else if Kind = 'appimage' then
      Result := PackageAppImage(Project, Target, CL.Verbose) <> ''
    else
      Result := PackageProject(Project, Target, CL.Verbose) <> '';
  end;

begin
  Kind := '';
  if Length(CL.Positional) > 0 then
    Kind := LowerCase(CL.Positional[0]);
  if (Kind <> '') and (Kind <> 'deb') and (Kind <> 'docker') and (Kind <> 'installer') and (Kind <> 'appimage') then
  begin
    Fail(Format('unknown package kind "%s"', [Kind]));
    Hint('use: pastel package, pastel package deb, docker, appimage, installer --target windows');
    Exit(ExitUsage);
  end;
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
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
        { a .deb, an image or an AppImage only for the Linux platforms, an installer for Windows }
        if (Kind = 'installer') and (Copy(Name, 1, 7) <> 'windows') then
          Continue;
        if (Kind <> '') and (Kind <> 'installer') and (Copy(Name, 1, 5) <> 'linux') then
          Continue;
        if not ResolveTarget(Name, T) or not PackageOne(T) then
          Inc(Failed);
        WriteLn;
      end;
      if Failed > 0 then
      begin
        Fail(Format('%d of %d platform(s) failed', [Failed, Length(Project.Platforms)]));
        Exit(ExitError);
      end;
      Exit(ExitOk);
    end;
    if not ResolveTarget(CL.Target, T) then
      Exit(ExitUsage);
    if (Kind <> '') and (CL.Target = '') and (T.OS <> 'linux') then
      ResolveTarget('linux', T);       { a .deb or an image is for Linux, also when made elsewhere }
    if PackageOne(T) then
      Result := ExitOk
    else
      Result := ExitError;
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

function ReadStdin: string;
var
  Buf: array[0..4095] of Char;
  N: LongInt;
  Chunk: string;
  F: THandle;
begin
  Result := '';
  F := GetFileHandle(Input);
  repeat
    N := FileRead(F, Buf, SizeOf(Buf));
    if N > 0 then
    begin
      SetString(Chunk, PChar(@Buf[0]), N);
      Result := Result + Chunk;
    end;
  until N <= 0;
end;

function ReadText(const FileName: string; FromStdin: Boolean; out Text: string): Boolean;
var
  L: TStringList;
begin
  Result := True;
  if FromStdin then
  begin
    Text := ReadStdin;
    Exit;
  end;
  if not FileExists(FileName) then
  begin
    Fail(Format('file "%s" not found', [FileName]));
    Exit(False);
  end;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Text := L.Text;
  finally
    L.Free;
  end;
end;

function HasErrors(const Issues: TIssues): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Issues) do
    if Issues[I].Severity = 'error' then
      Exit(True);
  Result := False;
end;

{ "pastel check src/x.pas --stdin --json": the compiler's errors for the
  project with the unsaved text of one file }
function CheckPascal(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  Opts: TBuildOptions;
  Text, ExePath, Line, F, Json, Sev, Msg: string;
  Messages: TStringList;
  M: TRegExpr;
  First: Boolean;
begin
  if not ReadText(CL.Positional[0], CL.Stdin, Text) then
    Exit(ExitError);
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  Messages := TStringList.Create;
  M := TRegExpr.Create('^(.+?)\((\d+)(?:,(\d+))?\) (Error|Fatal|Warning|Note|Hint): (.*)$');
  try
    Opts := Default(TBuildOptions);
    ResolveTarget('', Opts.Target);
    Opts.CheckOnly := True;
    Opts.Quiet := True;
    Opts.OverlayFile := ExpandFileName(CL.Positional[0]);
    Opts.OverlayText := Text;
    Opts.Messages := Messages;
    BuildProject(Project, Opts, ExePath);
    Json := '';
    First := True;
    for Line in Messages do
      if M.Exec(Line) then
      begin
        F := M.Match[1];
        if ExtractFileDrive(F) + Copy(F, 1, 1) = '' then
          F := ExpandFileName(Project.Root + F)
        else if (Copy(F, 1, 1) <> PathDelim) and (ExtractFileDrive(F) = '') then
          F := ExpandFileName(Project.Root + F);
        Sev := LowerCase(M.Match[4]);
        if Sev = 'fatal' then
          Sev := 'error';
        Msg := M.Match[5];
        if (Sev = 'note') or (Sev = 'hint') then
          Sev := 'info';
        { "Compilation aborted" and friends say nothing about the code }
        if Pos('There were', Msg) = 1 then
          Continue;
        if CL.Json then
        begin
          if not First then
            Json := Json + ',';
          First := False;
          Json := Json + Format('{"file":%s,"line":%s,"column":%s,"severity":"%s","message":%s}',
            [JsonStr(F), M.Match[2], IntToStr(StrToIntDef(M.Match[3], 1)), Sev, JsonStr(Msg)]);
        end
        else
          WriteLn(Line);
      end;
    if CL.Json then
      WriteLn('[' + Json + ']');
    Result := ExitOk;
  finally
    M.Free;
    Messages.Free;
    Project.Free;
  end;
end;

function CmdCheck(const CL: TCommandLine): Integer;
var
  Issues: TIssues;
  Root, Text: string;
begin
  if (Length(CL.Positional) > 0) and (LowerCase(ExtractFileExt(CL.Positional[0])) <> '.pform') then
    Exit(CheckPascal(CL));
  if Length(CL.Positional) > 0 then
  begin
    if not ReadText(CL.Positional[0], CL.Stdin, Text) then
      Exit(ExitError);
    Issues := CheckFormText(CL.Positional[0], Text);
  end
  else
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('no ' + ProjectFileName + ' found; give a .pform file: pastel check src/forms/Home.pform');
      Exit(ExitError);
    end;
    Issues := CheckProject(Root);
  end;
  PrintIssues(Issues, CL.Json);
  if not CL.Json and (Length(Issues) = 0) then
    Status('Checked', 'no problems found');
  if HasErrors(Issues) then
    Result := ExitError
  else
    Result := ExitOk;
end;

function CmdDoctor(const CL: TCommandLine): Integer;
var
  T: TTarget;
  Name, Err, Fpc: string;
  I, Index: Integer;
begin
  if not CL.Install then
  begin
    if RunDoctor then Exit(ExitOk) else Exit(ExitError);
  end;
  if Length(CL.Positional) = 0 then
  begin
    Fail('install what? for example: pastel doctor --install windows');
    Exit(ExitUsage);
  end;
  Result := ExitOk;
  for Name in CL.Positional do
  begin
    if not FindTarget(Name, T) then
    begin
      Fail(Format('unknown target "%s"; see "pastel targets"', [Name]));
      Exit(ExitUsage);
    end;
    { the compiler's units for the target, when this compiler can make them }
    Fpc := FindFpc;
    Index := -1;
    for I := Low(KnownTargets) to High(KnownTargets) do
      if KnownTargets[I].Name = T.Name then
        Index := I;
    if (Fpc <> '') and (Index >= 0) and not CanBuildTarget(Fpc, Index) then
    begin
      Err := BuildRtl(Fpc, T);
      if Err = '' then
        Err := BoolToStr(CanBuildTarget(Fpc, Index), '',
          'the RTL was compiled, but a test program for ' + T.Name + ' still does not build');
      if Err <> '' then
      begin
        Fail(Err);
        Result := ExitError;
        Continue;
      end;
      Status('Ready', 'the compiler can build for ' + T.Name);
    end;
    if Length(RuntimeFiles(T)) = 0 then
      Continue;
    if RuntimeInstalled(T) then
    begin
      Status('Ready', Format('%s for %s in %s', [string.Join(', ', RuntimeFiles(T)), T.Name, RuntimeDir(T)]));
      Continue;
    end;
    Err := InstallRuntime(T);
    if Err <> '' then
    begin
      Fail(Err);
      Result := ExitError;
    end
    else
      Status('Installed', Format('%s for %s in %s', [string.Join(', ', RuntimeFiles(T)), T.Name, RuntimeDir(T)]));
  end;
end;

function CmdPreview(const CL: TCommandLine): Integer;
var
  Text, OutFile, Err: string;
begin
  if Length(CL.Positional) = 0 then
  begin
    Fail('usage: pastel preview <file.pform> [-o out.png] [--width W] [--height H]');
    Exit(ExitUsage);
  end;
  if not ReadText(CL.Positional[0], CL.Stdin, Text) then
    Exit(ExitError);
  OutFile := CL.Output;
  if OutFile = '' then
    OutFile := ChangeFileExt(ExtractFileName(CL.Positional[0]), '.png');
  if CL.Dark then
    UseDarkTheme(True);
  Err := PreviewForm(CL.Positional[0], Text, OutFile, CL.Layout, CL.Width, CL.Height);
  if Err <> '' then
  begin
    WriteLn(StdErr, Err);
    Exit(ExitError);
  end;
  if not CL.Json then
    Status('Saved', OutFile);
  Result := ExitOk;
end;

var
  CL: TCommandLine;
  HostCode: Integer;
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
    { the project's own controls: a pastel built with them answers }
    if ((CL.Command = 'schema') or (CL.Command = 'preview') or ((CL.Command = 'check') and
      ((Length(CL.Positional) = 0) or SameText(ExtractFileExt(CL.Positional[0]), '.pform')))) and
      RunInDesignerHost('', HostCode) then
      Halt(HostCode);
    case CL.Command of
      'new':     ExitCode := CmdNew(CL);
      'build':   ExitCode := CmdBuild(CL);
      'run':     ExitCode := CmdRun(CL);
      'clean':   ExitCode := CmdClean;
      'test':    ExitCode := CmdTest(CL);
      'targets': ExitCode := CmdTargets;
      'doctor':  ExitCode := CmdDoctor(CL);
      'check':   ExitCode := CmdCheck(CL);
      'migrate': ExitCode := RunMigrate(CL.Positional, CL.Database);
      'lang':    ExitCode := RunLang(CL.Positional);
      'upgrade': ExitCode := RunUpgrade(CL.Check);
      'fmt':     ExitCode := RunFormat(CL.Positional, CL.Check, CL.Stdin);
      'package': ExitCode := CmdPackage(CL);
      'preview': ExitCode := CmdPreview(CL);
      'schema':  WriteLn(SchemaJson);
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
