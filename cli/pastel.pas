{ Pastel - command-line tool.
  Part of the Pastel project, MIT License. }
program pastel;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  Pastel.Console, Pastel.Toml, Pastel.Project, Pastel.Targets,
  Pastel.Builder, Pastel.Templates, Pastel.Doctor, Pastel.Inspect, Pastel.TestCmd,
  Pastel.Watch, Pastel.FmtCmd, Pastel.Package, Pastel.MigrateCmd, Pastel.LangCmd, Pastel.Runtime, Pastel.CustomCtl, Pastel.Upgrade, Pastel.Packages, Pastel.ModelGen, Pastel.UI, Pastel.Logcat, Pastel.FormServer, Pastel.Term, Pastel.JavaGen, Pastel.Setup, Pastel.Group, RegExpr, Process, fpjson, Pastel.Crypto, Pastel.Files, Pastel.Explain;

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
    Release, Verbose, All, Help, Watch, Check, NoBuild, Dark, Install, Clear, Yes: Boolean;
    Json, Stdin, NoRun, Phone: Boolean;
    Output, Layout, Database, Git, SubPath, Branch, Style: string;
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
  WriteLn('  new <kind> <name>      Create a new project (kinds: console, app, lib, service, api, site)');
  WriteLn('  new form <Name>        Add a window to an app (--phone: made for phones)');
  WriteLn('  new frame <Name>       Add a part of forms (an address block...) to put on many forms');
  WriteLn('  new group              A group of the projects in the folders here (build, test, run them together)');
  WriteLn('  new control <Name>     Add a control of your own (src/controls/)');
  WriteLn('  new model <Name> f:type  A table: migration, unit, tests (name:string! age:integer)');
  WriteLn('  build                  Compile the project');
  WriteLn('  run [-- args]          Compile and run on this computer (--watch: again on every save)');
  WriteLn('  test [filter]          Run the tests in tests/ (only names matching filter; --watch, --json)');
  WriteLn('  fmt [files]            Format the code (--check: only report)');
  WriteLn('  package [kind]         An archive; deb, docker, appimage, installer, apk, aab (--target, --all, --no-build)');
  WriteLn('  migrate [status|new]   Database migrations in database/migrations (--database URL)');
  WriteLn('  lang [add <code>]      Texts to translate in assets/lang/*.json');
  WriteLn('  add <name>[@version]   Add a package (--git URL, --path folder, --branch name)');
  WriteLn('  remove <name>          Remove a package');
  WriteLn('  update [names]         The newest versions pastel.toml allows (pastel.lock)');
  WriteLn('  search [words]         Look for packages in the registry');
  WriteLn('  deps                   The dependencies, and theirs (--json)');
  WriteLn('  upgrade [--check]      Bring a project from an older Pastel up to date');
  WriteLn('  logcat                 The log of the app on the connected Android phone (--all, --clear)');
  WriteLn('  keystore [name]        An Android app''s release key for Google Play (keys/upload.keystore)');
  WriteLn('  update-manifest <url>  dist/update.json for apps that update themselves (Pastel.Updater)');
  WriteLn('  java [add|remove|search] [classes]  Java classes as Pascal (src/java/javaclasses.pas)');
  WriteLn('  clean                  Remove the build folder');
  WriteLn('  targets                List the platforms Pastel can build for');
  WriteLn('  doctor                 Check your setup (--install windows: set up building for Windows)');
  WriteLn('  setup android          Set up and check making Android apps (--yes: the SDK''s packages too)');
  WriteLn('  check [file]           Check .pform files (and .pas files) for mistakes');
  WriteLn('  preview <file>         Draw a .pform file into a PNG (-o out.png, --dark, --style fluent)');
  WriteLn('  schema                 Controls and properties as JSON (for editors)');
  WriteLn('  version                Show the Pastel version');
  WriteLn('  help                   Show this help');
  WriteLn;
  WriteLn(Bold('Build options:'));
  WriteLn('  -t, --target <name>  Build for another platform (e.g. windows, rpi; several: linux,windows)');
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
    else if A = '--clear' then
      CL.Clear := True
    else if A = '--no-build' then
      CL.NoBuild := True
    else if A = '--phone' then
      CL.Phone := True
    else if A = '--dark' then
      CL.Dark := True
    else if A = '--install' then
      CL.Install := True
    else if (A = '-y') or (A = '--yes') then
      CL.Yes := True
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
            (A = '--database') or (A = '--git') or (A = '--path') or (A = '--branch') or (A = '--style') then
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
      else if A = '--git' then
        CL.Git := ParamStr(I)
      else if A = '--path' then
        CL.SubPath := ParamStr(I)
      else if A = '--branch' then
        CL.Branch := ParamStr(I)
      else if A = '--style' then
        CL.Style := ParamStr(I)
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
  if IsGroupRoot(Root) then
  begin
    Fail('this folder holds a group of projects: run this in one of them');
    Hint('in the group''s folder: pastel build, test, clean, check and run go through its projects');
    Exit;
  end;
  try
    Result := TPastelProject.Load(Root);
  except
    on E: EProjectError do
      Fail(E.Message);
  end;
end;

{ build, test, clean, check, run in a group's folder: through its projects; False when this is not one }
function RunInGroup(const CL: TCommandLine; out Code: Integer): Boolean;
var
  Root: string;
  G: TProjectGroup;
  Args: TStringArray;
  I: Integer;
begin
  Result := False;
  Code := ExitOk;
  if (CL.Command <> 'build') and (CL.Command <> 'test') and (CL.Command <> 'clean') and
     (CL.Command <> 'check') and (CL.Command <> 'run') then
    Exit;
  if (CL.Command = 'check') and (Length(CL.Positional) > 0) then
    Exit;
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if (Root = '') or not IsGroupRoot(Root) then
    Exit;
  Result := True;
  try
    G := LoadGroup(Root);
  except
    on E: Exception do
    begin
      Fail(E.Message);
      Code := ExitError;
      Exit;
    end;
  end;
  Args := nil;
  for I := 2 to ParamCount do
    Args := Concat(Args, [ParamStr(I)]);
  if CL.Command = 'run' then
    Code := RunGroupRun(G, Args)
  else
    Code := RunGroupCommand(G, CL.Command, Args);
end;

{ the type in pastel.toml (app, console, service, api, lib); '' when it cannot be read }
function ProjectKindAt(const Root: string): string;
var
  P: TPastelProject;
begin
  Result := '';
  try
    P := TPastelProject.Load(Root);
    try
      Result := LowerCase(P.Kind);
    finally
      P.Free;
    end;
  except
    on E: EProjectError do
      Result := '';
  end;
end;

function CmdNew(const CL: TCommandLine): Integer;
var
  Root, Kind, Err: string;
  Names: TStringArray;
begin
  PhoneTemplates := CL.Phone;
  if (Length(CL.Positional) = 1) and SameText(CL.Positional[0], 'group') then
  begin
    Err := CreateGroupFile(GetCurrentDir, Names);
    if Err <> '' then
    begin
      Fail(Err);
      Hint('run it in the folder that holds the projects (salon/ with salon-core/, salon-desk/...)');
      Exit(ExitError);
    end;
    Status('Created', Format('%s: a group of %d project(s): %s', [ProjectFileName, Length(Names), string.Join(', ', Names)]));
    Exit(ExitOk);
  end;
  if (Length(CL.Positional) = 2) and SameText(CL.Positional[0], 'form') then
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('"pastel new form" adds a form to an app: run it in the app''s folder');
      Exit(ExitError);
    end;
    { a console program, a service or an API has no window: a form there would not be shown }
    Kind := ProjectKindAt(Root);
    if (Kind <> '') and (Kind <> 'app') then
    begin
      Fail(Format('this is a %s project; forms belong to app projects (type = "app" in pastel.toml)', [Kind]));
      Hint('make the window part as an app that uses this project: pastel new app <name>, then pastel add ' +
        ExtractFileName(ExcludeTrailingPathDelimiter(Root)) + ' --path ../' + ExtractFileName(ExcludeTrailingPathDelimiter(Root)));
      Exit(ExitError);
    end;
    if CreateFormFiles(Root, CL.Positional[1]) then Exit(ExitOk) else Exit(ExitError);
  end;
  if (Length(CL.Positional) = 2) and SameText(CL.Positional[0], 'frame') then
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('"pastel new frame" adds a part of forms to an app: run it in the app''s folder');
      Exit(ExitError);
    end;
    if CreateFrameFiles(Root, CL.Positional[1]) then Exit(ExitOk) else Exit(ExitError);
  end;
  if (Length(CL.Positional) >= 2) and SameText(CL.Positional[0], 'model') then
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('"pastel new model" adds a table to a project: run it in the project''s folder');
      Exit(ExitError);
    end;
    if CreateModel(IncludeTrailingPathDelimiter(Root), CL.Positional[1], Copy(CL.Positional, 2, MaxInt)) then
      Exit(ExitOk)
    else
      Exit(ExitError);
  end;
  if (Length(CL.Positional) = 2) and SameText(CL.Positional[0], 'control') then
  begin
    Root := TPastelProject.FindRoot(GetCurrentDir);
    if Root = '' then
    begin
      Fail('"pastel new control" adds a control to an app: run it in the app''s folder');
      Exit(ExitError);
    end;
    Kind := ProjectKindAt(Root);
    if (Kind <> '') and (Kind <> 'app') and (Kind <> 'lib') then
    begin
      Fail(Format('this is a %s project; controls belong to app and library projects', [Kind]));
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

{ the platforms of --all ([targets] platforms) or of --target linux,windows; none: said why }
function TargetList(const CL: TCommandLine; Project: TPastelProject): TStringArray;
var
  P: string;
begin
  Result := nil;
  if not CL.All then
  begin
    for P in CL.Target.Split([',']) do
      if Trim(P) <> '' then
        Result := Concat(Result, [Trim(P)]);
    if Length(Result) = 0 then
      Fail('--target needs a platform name, e.g. --target linux,windows');
    Exit;
  end;
  Result := Copy(Project.Platforms);
  { in a group's --all, a project without its own platforms is built for this computer }
  if (Length(Result) = 0) and (GetEnvironmentVariable('PASTEL_GROUP') = '1') then
    Exit(TStringArray.Create(HostTarget.Name));
  if Length(Result) = 0 then
  begin
    Fail('--all needs a list of platforms in ' + ProjectFileName);
    Hint('add: [targets] platforms = ["linux", "windows"]');
  end;
end;

function CmdBuild(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  Opts: TBuildOptions;
  ExePath, Name: string;
  Failed: Integer;
  List: TStringArray;
begin
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
    Opts := Default(TBuildOptions);
    Opts.Release := CL.Release;
    Opts.Verbose := CL.Verbose;
    if CL.All or (Pos(',', CL.Target) > 0) then
    begin
      List := TargetList(CL, Project);
      if Length(List) = 0 then
        Exit(ExitError);
      Failed := 0;
      for Name in List do
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
        Fail(Format('%d of %d platform(s) failed', [Failed, Length(List)]));
        Exit(ExitError);
      end;
      Status('Done', Format('all %d platform(s) built', [Length(List)]));
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
      ResolvePackages := False;     { only looked at: no fetching }
      try
        try
          P := TPastelProject.Load(Dir);
        finally
          ResolvePackages := True;
        end;
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

{ pastel run --target android: the app on the phone connected with USB (adb), and its log }
function RunOnAndroid(const CL: TCommandLine; const T: TTarget): Integer;
var
  Project: TPastelProject;
  Apk, Adb, Output, Id, Abi: string;
  Args: TStringList;
  Targets: TTargetArray;
  Device: TTarget;
  Supported: TStringArray;
  Symbols: TCrashSymbols;

  function Adb_(const A: array of string; Show: Boolean): Boolean;
  var
    S: string;
  begin
    Args.Clear;
    for S in A do
      Args.Add(S);
    Result := RunCapture(Adb, Args, Project.Root, Output) = 0;
    if Show or not Result then
      if Trim(Output) <> '' then
        WriteLn(Trim(Output));
  end;

begin
  Result := ExitError;
  Adb := ExeSearch({$IFDEF WINDOWS}'adb.exe'{$ELSE}'adb'{$ENDIF}, GetEnvironmentVariable('PATH'));
  if Adb = '' then
  begin
    Fail('running on a phone needs adb (Android''s device bridge)');
    {$IFDEF LINUX}
    Hint('sudo apt install adb; then turn on USB debugging on the phone (Settings > Developer options)');
    {$ELSE}
    Hint('it comes with Android Studio''s platform-tools; then turn on USB debugging on the phone');
    {$ENDIF}
    Exit;
  end;
  Project := OpenProject;
  if Project = nil then
    Exit;
  Args := TStringList.Create;
  try
    Adb_(['devices'], False);
    if Pos(#9'device', Output) = 0 then
    begin
      Fail('no phone is connected');
      Hint('connect it with USB, allow USB debugging on it, then check with: adb devices (an emulator shows there too)');
      Exit;
    end;
    { the phone's CPU decides the build: arm64-v8a, armeabi-v7a, x86_64, x86 }
    Targets := nil;
    if (CL.Target <> '') and not SameText(CL.Target, 'android') then
      Targets := [T]
    else
    begin
      Adb_(['shell', 'getprop', 'ro.product.cpu.abilist'], False);
      Supported := Trim(Output).Split([',']);
      if (Length(Supported) = 0) or (Trim(Output) = '') then
      begin
        Adb_(['shell', 'getprop', 'ro.product.cpu.abi'], False);   { Android 4 }
        Supported := [Trim(Output)];
      end;
      for Abi in Supported do
        if (Length(Targets) = 0) and FindAndroidTarget(Trim(Abi), Device) and AndroidTargetReady(Device) then
          Targets := [Device];
      if Length(Targets) = 0 then
      begin
        Fail(Format('this computer cannot build for the phone''s CPU yet (%s)', [string.Join(', ', Supported)]));
        if (Length(Supported) > 0) and FindAndroidTarget(Trim(Supported[0]), Device) then
          Hint(Format('pastel doctor --install %s sets it up', [Device.Name]))
        else
          Hint('pastel doctor --install android sets up every Android CPU');
        Exit;
      end;
      Status('Device', Format('%s (%s)', [AndroidAbi(Targets[0]), Targets[0].Name]));
    end;
    Apk := PackageApk(Project, Targets, CL.Verbose, not CL.Release);
    if Apk = '' then
      Exit;
    Id := AndroidAppId(Project);
    Status('Installing', ExtractFileName(Apk) + ' on the phone');
    if not Adb_(['install', '-r', Apk], False) then
    begin
      Fail('the phone did not install it');
      Exit;
    end;
    Adb_(['logcat', '-c'], False);
    { a debug build reloads its forms from here when they are saved (through the USB cable) }
    if not CL.Release then
    begin
      if StartFormServer(Project.Root) and
        Adb_(['reverse', 'tcp:' + IntToStr(FormServerPort), 'tcp:' + IntToStr(FormServerPort)], False) then
        Status('Hot reload', 'save a .pform file: the phone shows it at once (code changes: pastel run again)')
      else
        Hint(Format('hot reload is off: port %d is used by another program (another pastel run?)', [FormServerPort]));
    end;
    Status('Starting', Id);
    if not Adb_(['shell', 'am', 'start', '-n', Id + '/dev.pastel.PastelActivity'], False) then
      Exit;
    Status('Log', Format('of %s (its processes, crashes); Ctrl+C stops showing it, the app keeps running', [Id]));
    Status('Saved', 'the whole log to build/android/logcat.txt (to send with a question)');
    Symbols := TCrashSymbols.Create(Project.Root);
    try
      Result := FollowAppLog(Adb, Id, Project.Root + 'build' + PathDelim + 'android' + PathDelim + 'logcat.txt', CL.All, [],
        @Symbols.Explain);
    finally
      Symbols.Free;
    end;
  finally
    Args.Free;
    Project.Free;
  end;
end;

{ pastel keystore [name]: the app's release key for Google Play (keys/upload.keystore), with keytool }
{ pastel update-manifest https://example.com/shop/ [--notes "..."]: dist/update.json
  with the project's version, each platform's package and its SHA-256 }
function CmdUpdateManifest(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  Base, Dist, F, Name, Plat, Arch: string;
  J, Files, Entry: TJSONObject;
  L: TStringList;
begin
  Result := ExitError;
  if Length(CL.Positional) = 0 then
  begin
    Fail('where the packages will be: pastel update-manifest https://example.com/shop/');
    Exit(ExitUsage);
  end;
  Project := OpenProject;
  if Project = nil then
    Exit;
  Base := CL.Positional[0];
  if (Base <> '') and (Base[Length(Base)] <> '/') then
    Base := Base + '/';
  Dist := Project.Root + 'dist' + PathDelim;
  J := TJSONObject.Create;
  L := TStringList.Create;
  try
    J.Add('version', Project.Version);
    if Length(CL.Positional) > 1 then
      J.Add('notes', CL.Positional[1]);
    Files := TJSONObject.Create;
    J.Add('files', Files);
    for F in ListFiles(Dist, Project.Name + '-' + Project.Version + '*', False) do
    begin
      Name := ExtractFileName(F);
      Plat := '';
      if Pos('aarch64', Name) + Pos('arm64', Name) > 0 then Arch := 'aarch64' else Arch := 'x86_64';
      if SameText(ExtractFileExt(Name), '.apk') and (Pos('-debug', Name) = 0) then
        Plat := 'android'
      else if SameText(ExtractFileExt(Name), '.exe') then
        Plat := 'windows-' + Arch
      else if SameText(ExtractFileExt(Name), '.AppImage') then
        Plat := 'linux-' + Arch;
      if (Plat = '') or (Files.IndexOfName(Plat) >= 0) then
        Continue;
      Entry := TJSONObject.Create;
      Entry.Add('url', Base + Name);
      Entry.Add('sha256', LowerCase(Sha256File(F)));
      Files.Add(Plat, Entry);
      Status('Added', Format('%s: %s', [Plat, Name]));
    end;
    if Files.Count = 0 then
    begin
      Fail(Format('no package of version %s in dist/: pastel package installer, appimage or apk first', [Project.Version]));
      Exit;
    end;
    L.Text := J.FormatJSON;
    L.SaveToFile(Dist + 'update.json');
    Status('Wrote', Format('dist/update.json (%s, %d platform(s)): put it and the packages at %s', [Project.Version,
      Files.Count, Base]));
    Result := ExitOk;
  finally
    L.Free;
    J.Free;
    Project.Free;
  end;
end;

function CmdKeystore(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  Keytool, Name, Rel, FileName, Pass, Again, Output, Who: string;
  Args: TStringList;
begin
  Result := ExitError;
  Keytool := ExeSearch({$IFDEF WINDOWS}'keytool.exe'{$ELSE}'keytool'{$ENDIF}, GetEnvironmentVariable('PATH'));
  if Keytool = '' then
  begin
    Fail('making a key needs Java''s keytool');
    {$IFDEF LINUX}
    Hint('sudo apt install default-jdk-headless');
    {$ELSE}
    Hint('it comes with Java (and Android Studio)');
    {$ENDIF}
    Exit;
  end;
  Project := OpenProject;
  if Project = nil then
    Exit;
  Args := TStringList.Create;
  try
    Name := 'upload';
    if Length(CL.Positional) > 0 then
      Name := CL.Positional[0];
    Rel := 'keys/' + Name + '.keystore';
    FileName := Project.Root + 'keys' + PathDelim + Name + '.keystore';
    if FileExists(FileName) then
    begin
      Fail(Rel + ' exists already: an app keeps the same key for ever (Google Play knows it by that)');
      Exit;
    end;
    Pass := GetEnvironmentVariable('PASTEL_KEYSTORE_PASSWORD');
    if Pass = '' then
    begin
      Pass := AskPassword('A password for the key (at least 6 letters; keep it safe):');
      Again := AskPassword('The same password again:');
      if Pass <> Again then
      begin
        Fail('the two passwords are not the same');
        Exit;
      end;
    end;
    if Length(Pass) < 6 then
    begin
      Fail('the password needs at least 6 letters');
      Exit;
    end;
    Who := Project.Title;
    if Who = '' then
      Who := Project.Name;
    ForceDirectories(ExtractFileDir(FileName));
    Args.Add('-genkeypair');
    Args.Add('-keystore');
    Args.Add(FileName);
    Args.Add('-storepass');
    Args.Add(Pass);
    Args.Add('-keypass');
    Args.Add(Pass);
    Args.Add('-alias');
    Args.Add(Name);
    Args.Add('-keyalg');
    Args.Add('RSA');
    Args.Add('-keysize');
    Args.Add('2048');
    Args.Add('-validity');
    Args.Add('10000');
    Args.Add('-dname');
    Args.Add('CN=' + StringReplace(Who, ',', ' ', [rfReplaceAll]));
    if RunCapture(Keytool, Args, Project.Root, Output) <> 0 then
    begin
      Fail('keytool did not make the key: ' + Trim(Output));
      Exit;
    end;
    SetProjectSetting(Project.Root, 'package.android', 'keystore', TomlStr(Rel));
    SetProjectSetting(Project.Root, 'package.android', 'alias', TomlStr(Name));
    Status('Made', Rel + ' ([package.android] keystore and alias in ' + ProjectFileName + ')');
    Hint('keep the file and its password safe and out of git: an update of the app must be signed with the same key');
    Hint('pastel package aab and apk sign with it, given the password: PASTEL_KEYSTORE_PASSWORD=... pastel package aab');
    { the key is not for git }
    if FileExists(Project.Root + '.gitignore') then
      with TStringList.Create do
      try
        LoadFromFile(Project.Root + '.gitignore');
        if IndexOf('keys/') < 0 then
        begin
          Add('keys/');
          SaveToFile(Project.Root + '.gitignore');
        end;
      finally
        Free;
      end;
    Result := ExitOk;
  finally
    Args.Free;
    Project.Free;
  end;
end;

{ pastel logcat: the log of the app on the connected phone, by its package name }
function CmdLogcat(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  Adb, Output, Id: string;
  Args: TStringList;
  Pids: TStringArray;
  Symbols: TCrashSymbols;

  function Adb_(const A: array of string): Boolean;
  var
    S: string;
  begin
    Args.Clear;
    for S in A do
      Args.Add(S);
    Result := RunCapture(Adb, Args, Project.Root, Output) = 0;
  end;

begin
  Result := ExitError;
  Adb := ExeSearch({$IFDEF WINDOWS}'adb.exe'{$ELSE}'adb'{$ENDIF}, GetEnvironmentVariable('PATH'));
  if Adb = '' then
  begin
    Fail('the log of a phone needs adb (Android''s device bridge)');
    {$IFDEF LINUX}
    Hint('sudo apt install adb; then turn on USB debugging on the phone (Settings > Developer options)');
    {$ELSE}
    Hint('it comes with Android Studio''s platform-tools; then turn on USB debugging on the phone');
    {$ENDIF}
    Exit;
  end;
  Project := OpenProject;
  if Project = nil then
    Exit;
  Args := TStringList.Create;
  try
    Adb_(['devices']);
    if Pos(#9'device', Output) = 0 then
    begin
      Fail('no phone is connected');
      Hint('connect it with USB (or: adb connect <its address>:5555), allow USB debugging, then check with: adb devices');
      Exit;
    end;
    Id := AndroidAppId(Project);
    if CL.Clear then
      Adb_(['logcat', '-c']);
    { the app's processes now: pidof (Android 7 and newer), else the process list }
    Pids := nil;
    if Adb_(['shell', 'pidof', Id]) then
      Pids := PidsOf(Output, Id);
    if Length(Pids) = 0 then
    begin
      Adb_(['shell', 'ps']);
      Pids := PidsOf(Output, Id);
    end;
    if Length(Pids) > 0 then
      Status('Log', Format('of %s (process %s); Ctrl+C stops', [Id, string.Join(', ', Pids)]))
    else
      Status('Log', Format('of %s: it is not running; start it on the phone, its lines show here; Ctrl+C stops', [Id]));
    Status('Saved', 'the whole log to build/android/logcat.txt (to send with a question)');
    Symbols := TCrashSymbols.Create(Project.Root);
    try
      Result := FollowAppLog(Adb, Id, Project.Root + 'build' + PathDelim + 'android' + PathDelim + 'logcat.txt', CL.All, Pids,
        @Symbols.Explain);
    finally
      Symbols.Free;
    end;
  finally
    Args.Free;
    Project.Free;
  end;
end;

function CmdRun(const CL: TCommandLine): Integer;
var
  Project: TPastelProject;
  T: TTarget;
  Users: string;
begin
  if (CL.Target <> '') and FindTarget(CL.Target, T) and (T.OS = 'android') then
    Exit(RunOnAndroid(CL, T));
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
  List: TStringArray;

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
    else if Kind = 'apk' then
      Result := PackageApk(Project, ApkTargets(Project, CL.Target), CL.Verbose) <> ''
    else
      Result := PackageProject(Project, Target, CL.Verbose) <> '';
  end;

begin
  Kind := '';
  if Length(CL.Positional) > 0 then
    Kind := LowerCase(CL.Positional[0]);
  if (Kind <> '') and (Kind <> 'deb') and (Kind <> 'docker') and (Kind <> 'installer') and (Kind <> 'appimage') and
    (Kind <> 'apk') and (Kind <> 'aab') then
  begin
    Fail(Format('unknown package kind "%s"', [Kind]));
    Hint('use: pastel package, pastel package deb, docker, appimage, apk, aab, installer --target windows');
    Exit(ExitUsage);
  end;
  Project := OpenProject;
  if Project = nil then
    Exit(ExitError);
  try
    { one .apk for every Android CPU }
    if Kind = 'apk' then
    begin
      if PackageApk(Project, ApkTargets(Project, CL.Target), CL.Verbose) <> '' then
        Exit(ExitOk);
      Exit(ExitError);
    end;
    { Google Play's bundle, with every CPU }
    if Kind = 'aab' then
    begin
      if PackageAab(Project, ApkTargets(Project, CL.Target), CL.Verbose) <> '' then
        Exit(ExitOk);
      Exit(ExitError);
    end;
    if CL.All or (Pos(',', CL.Target) > 0) then
    begin
      List := TargetList(CL, Project);
      if Length(List) = 0 then
        Exit(ExitError);
      Failed := 0;
      for Name in List do
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
        Fail(Format('%d of %d platform(s) failed', [Failed, Length(List)]));
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
          Json := Json + Format('{"file":%s,"line":%s,"column":%s,"severity":"%s","message":%s,"explain":%s}',
            [JsonStr(F), M.Match[2], IntToStr(StrToIntDef(M.Match[3], 1)), Sev, JsonStr(Msg),
             JsonStr(ExplainCompilerMessage(Msg))]);
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
  Name, Err, Fpc, Prefix: string;
  I, Index: Integer;
  HaveBinutils, AllAndroid: Boolean;
  Names: TStringArray;
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
  { "android": every Android CPU this computer can set up (phones old and new, the emulator) }
  Names := nil;
  AllAndroid := False;
  for Name in CL.Positional do
    if SameText(Name, 'android') then
    begin
      AllAndroid := True;
      Names := Concat(Names, ['android-arm64', 'android-arm', 'android-x86_64', 'android-x86']);
    end
    else
      Names := Concat(Names, [Name]);
  for Name in Names do
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
    if T.OS = 'android' then
    begin
      Prefix := FindBinutilsPrefix(T, HaveBinutils);
      if not HaveBinutils then
      begin
        if AllAndroid and (T.Name <> 'android-arm64') then
        begin
          Status('Skipped', Format('%s (%s): needs %s', [T.Name, T.Description, BinutilsHint(T)]));
          Continue;
        end;
        Fail(Format('the binutils for %s are needed: %s', [T.Name, BinutilsHint(T)]));
        Result := ExitError;
        Continue;
      end;
      { the start of a library and the system libraries' names, made with the binutils }
      if not AndroidLibsReady(T) then
      begin
        Err := MakeAndroidLibs(T, Prefix);
        if Err <> '' then
        begin
          Fail(Err);
          Result := ExitError;
          Continue;
        end;
        Status('Made', 'the Android system library stand-ins in ' + AndroidLibDir(T));
      end;
    end;
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
    end;
    if (Fpc <> '') and (Index >= 0) then
      Status('Ready', Format('the compiler can build for %s (%s)', [T.Name, T.Description]));
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

{ pastel setup android: the compilers' parts (doctor --install android), then Android's tools }
function CmdSetup(const CL: TCommandLine): Integer;
var
  D: TCommandLine;
begin
  if (Length(CL.Positional) <> 1) or not SameText(CL.Positional[0], 'android') then
  begin
    Fail('set up what? pastel setup android');
    Exit(ExitUsage);
  end;
  D := CL;
  D.Install := True;
  Result := CmdDoctor(D);
  if not SetupAndroid(CL.Yes) then
    Result := ExitError;
end;

function CmdPreview(const CL: TCommandLine): Integer;
var
  Text, OutFile, Err: string;
begin
  if Length(CL.Positional) = 0 then
  begin
    Fail('usage: pastel preview <file.pform> [-o out.png] [--width W] [--height H] [--style S] [--dark]');
    Exit(ExitUsage);
  end;
  if not ReadText(CL.Positional[0], CL.Stdin, Text) then
    Exit(ExitError);
  OutFile := CL.Output;
  if OutFile = '' then
    OutFile := ChangeFileExt(ExtractFileName(CL.Positional[0]), '.png');
  Err := PreviewForm(CL.Positional[0], Text, OutFile, CL.Layout, CL.Width, CL.Height, CL.Style, CL.Dark);
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
    { a group's folder (like Delphi's project group) }
    if RunInGroup(CL, HostCode) then
      Halt(HostCode);
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
      'logcat':  ExitCode := CmdLogcat(CL);
      'keystore': ExitCode := CmdKeystore(CL);
      'update-manifest': ExitCode := CmdUpdateManifest(CL);
      'java':    ExitCode := RunJava(CL.Positional);
      'doctor':  ExitCode := CmdDoctor(CL);
      'setup':   ExitCode := CmdSetup(CL);
      'check':   ExitCode := CmdCheck(CL);
      'migrate': ExitCode := RunMigrate(CL.Positional, CL.Database);
      'lang':    ExitCode := RunLang(CL.Positional);
      'upgrade': ExitCode := RunUpgrade(CL.Check);
      'add':     ExitCode := RunAdd(CL.Positional, CL.Git, CL.SubPath, CL.Branch);
      'remove':  ExitCode := RunRemove(CL.Positional);
      'update':  ExitCode := RunUpdate(CL.Positional);
      'search':  ExitCode := RunSearch(CL.Positional);
      'deps':    ExitCode := RunDeps(CL.Json);
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
