{ Pastel - project templates for "pastel new".
  Part of the Pastel project, MIT License. }
unit Pastel.Templates;

{$mode objfpc}{$H+}

interface

const
  ProjectKinds: array[0..5] of string = ('console', 'app', 'lib', 'service', 'api', 'site');

function CreateProject(const Kind, Name, ParentDir: string): Boolean;
{ "pastel new form Settings": src/forms/Settings.pform and .pas, created in main.pas. }
function CreateFormFiles(const Root, Name: string): Boolean;
{ src/controls/<name>.pas: a control of the project, for .pform files and the designer. }
function CreateControlFile(const Root, Name: string): Boolean;

var
  { --phone: forms for small, upright screens (Android): stacked, full-width controls with big touch targets }
  PhoneTemplates: Boolean = False;

implementation

uses
  Classes, SysUtils, Pastel.Console, Pastel.Project, Pastel.WIcon;

function Fill(const Lines: array of string; const Name, Ident: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Low(Lines) to High(Lines) do
    Result := Result + Lines[I] + LineEnding;
  Result := StringReplace(Result, '{{name}}', Name, [rfReplaceAll]);
  Result := StringReplace(Result, '{{ident}}', Ident, [rfReplaceAll]);
  Result := StringReplace(Result, '{{pastel}}', PastelVersion, [rfReplaceAll]);
  Result := StringReplace(Result, '{{pastelminor}}', PastelMinor, [rfReplaceAll]);
  Result := StringReplace(Result, '{{title}}', TitleFromName(Name), [rfReplaceAll]);
end;

{ my-string-tools -> MyStringTools }
function UnitNameFor(const Name: string): string;
var
  Part: string;
begin
  Result := '';
  for Part in Name.Split(['-', '_']) do
    if Part <> '' then
      Result := Result + UpCase(Part[1]) + Copy(Part, 2, MaxInt);
end;

function ReadText(const FileName: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure WriteText(const FileName, Content: string);
var
  F: TFileStream;
begin
  ForceDirectories(ExtractFileDir(FileName));
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Content <> '' then
      F.WriteBuffer(Content[1], Length(Content));
  finally
    F.Free;
  end;
end;

function DirIsEmpty(const Dir: string): Boolean;
var
  SR: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
        Exit(False);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure WriteConsoleProject(const Dir, Name, Ident: string);
begin
  WriteText(Dir + 'pastel.toml', Fill([
    '# Pastel project file',
    '',
    '[project]',
    'name = "{{name}}"',
    'version = "0.1.0"',
    'pastel = "{{pastelminor}}"          # the Pastel version this project is made for',
    'type = "console"',
    '',
    '[build]',
    'main = "src/main.pas"',
    'mode = "objfpc"          # objfpc or delphi',
    'defines = []',
    '',
    '[targets]',
    '# Platforms built by "pastel build --all". See "pastel targets" for the list.',
    'platforms = ["linux", "windows", "rpi"]'
  ], Name, Ident));

  WriteText(Dir + 'src' + PathDelim + 'main.pas', Fill([
    '{ {{name}} - try: pastel run -- --help }',
    'program {{ident}};',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses',
    '  SysUtils, Pastel.Args, Pastel.Text, AppInfo, Greeting;',
    '',
    'var',
    '  Args: TArgs;',
    '  Who: string;',
    'begin',
    '  Args := TArgs.Create(AppName, ''Says hello. Change src/main.pas to make it yours.'');',
    '  try',
    '    Args.Version := AppVersion;     { from pastel.toml }',
    '    Args.Flag(''shout'', ''s'', ''Use capital letters'');',
    '    Args.Positional(''name'', ''Who to greet'').Default(''world'');',
    '    Args.Parse;                     { handles --help, --version and mistakes }',
    '',
    '    Who := Args.Get(''name'');',
    '    if Args.Has(''shout'') then',
    '      Who := Upper(Who);           { Unicode-aware, unlike UpperCase }',
    '    WriteLn(MakeGreeting(Who));',
    '  finally',
    '    Args.Free;',
    '  end;',
    'end.'
  ], Name, Ident));

  WriteText(Dir + 'src' + PathDelim + 'services' + PathDelim + 'greeting.pas', Fill([
    '{ Business logic lives in src/services. Pastel finds units in every',
    '  folder under src/, so no unit paths need to be configured. }',
    'unit Greeting;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'function MakeGreeting(const Name: string): string;',
    '',
    'implementation',
    '',
    'uses',
    '  SysUtils;',
    '',
    'function MakeGreeting(const Name: string): string;',
    'begin',
    '  Result := Format(''Hello, %s! This is {{name}}, built with Pastel.'', [Name]);',
    'end;',
    '',
    'end.'
  ], Name, Ident));

  WriteText(Dir + 'tests' + PathDelim + 'greeting_test.pas', Fill([
    '{ Tests for src/services/greeting.pas. Run them with: pastel test',
    '  Every published method of a TTestSuite class is one test. }',
    'unit Greeting_Test;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  Pastel.Testing, Greeting;',
    '',
    'type',
    '  TGreetingTests = class(TTestSuite)',
    '  published',
    '    procedure GreetsByName;',
    '    procedure MentionsTheProgram;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure TGreetingTests.GreetsByName;',
    'begin',
    '  AssertStartsWith(''Hello, Ali!'', MakeGreeting(''Ali''));',
    'end;',
    '',
    'procedure TGreetingTests.MentionsTheProgram;',
    'begin',
    '  AssertContains(''{{name}}'', MakeGreeting(''Ali''));',
    'end;',
    '',
    'initialization',
    '  RegisterTests(TGreetingTests);',
    'end.'
  ], Name, Ident));

  WriteText(Dir + '.gitignore', Fill([
    'build/',
    'dist/',
    '*.o',
    '*.ppu',
    '*.g.pas'
  ], Name, Ident));

  WriteText(Dir + 'README.md', Fill([
    '# {{name}}',
    '',
    'A console application made with Pastel.',
    '',
    '```',
    'pastel run                     # build and run on this computer',
    'pastel run -- Ali              # pass arguments to the program',
    'pastel test                    # run the tests in tests/',
    'pastel build --target windows  # build a Windows .exe',
    'pastel build --all --release   # build every platform in pastel.toml',
    '```'
  ], Name, Ident));
end;

procedure WriteLibProject(const Dir, Name, Ident: string);
var
  UnitName, FileBase, Content: string;
begin
  UnitName := UnitNameFor(Name);
  FileBase := LowerCase(UnitName);
  WriteText(Dir + 'pastel.toml', Fill([
    '# Pastel project file',
    '',
    '[project]',
    'name = "{{name}}"',
    'version = "0.1.0"',
    'pastel = "{{pastelminor}}"          # the Pastel version this project is made for',
    'type = "lib"             # units for other projects; no program of its own',
    '',
    '[build]',
    'mode = "objfpc"          # objfpc or delphi',
    'defines = []'
  ], Name, Ident));

  Content := Fill([
    '{ {{name}}: a Pastel library.',
    '',
    '  Another project uses it with two lines in its pastel.toml:',
    '    [dependencies]',
    '    {{name}} = { path = "../{{name}}" }',
    '  and then "uses {{unit}};" in its code. }',
    'unit {{unit}};',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    '{ S repeated Count times: Repeated(''ab'', 3) = ''ababab'' }',
    'function Repeated(const S: string; Count: Integer): string;',
    '',
    'implementation',
    '',
    'function Repeated(const S: string; Count: Integer): string;',
    'var',
    '  I: Integer;',
    'begin',
    '  Result := '''';',
    '  for I := 1 to Count do',
    '    Result := Result + S;',
    'end;',
    '',
    'end.'
  ], Name, Ident);
  WriteText(Dir + 'src' + PathDelim + FileBase + '.pas',
    StringReplace(Content, '{{unit}}', UnitName, [rfReplaceAll]));

  Content := Fill([
    '{ Tests for src/{{file}}.pas. Run them with: pastel test }',
    'unit {{unit}}_Test;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  Pastel.Testing, {{unit}};',
    '',
    'type',
    '  T{{unit}}Tests = class(TTestSuite)',
    '  published',
    '    procedure RepeatsText;',
    '    procedure ZeroTimesIsEmpty;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure T{{unit}}Tests.RepeatsText;',
    'begin',
    '  AssertEquals(''ababab'', Repeated(''ab'', 3));',
    'end;',
    '',
    'procedure T{{unit}}Tests.ZeroTimesIsEmpty;',
    'begin',
    '  AssertEquals('''', Repeated(''ab'', 0));',
    'end;',
    '',
    'initialization',
    '  RegisterTests(T{{unit}}Tests);',
    'end.'
  ], Name, Ident);
  Content := StringReplace(Content, '{{unit}}', UnitName, [rfReplaceAll]);
  WriteText(Dir + 'tests' + PathDelim + FileBase + '_test.pas',
    StringReplace(Content, '{{file}}', FileBase, [rfReplaceAll]));

  WriteText(Dir + '.gitignore', Fill([
    'build/',
    'dist/',
    '*.o',
    '*.ppu'
  ], Name, Ident));

  Content := Fill([
    '# {{name}}',
    '',
    'A Pascal library made with Pastel.',
    '',
    '```',
    'pastel build     # compile every unit in src/',
    'pastel test      # run the tests in tests/',
    'pastel fmt       # format the code',
    '```',
    '',
    'To use it in another Pastel project, add to its `pastel.toml`:',
    '',
    '```toml',
    '[dependencies]',
    '{{name}} = { path = "../{{name}}" }',
    '```',
    '',
    'and `uses {{unit}};` in the code.',
    '',
    'To share it as a package: put it in a git repository, tag a version (`git tag v0.1.0`),',
    'and others add it with `pastel add {{name}} --git <its URL>`. See docs/packages.md of Pastel.'
  ], Name, Ident);
  WriteText(Dir + 'README.md', StringReplace(Content, '{{unit}}', UnitName, [rfReplaceAll]));
end;

{ A service: keeps running, settings, jobs, systemd. Generated from
  template files; see docs/services.md. }
procedure WriteServiceProject(const Dir, Name, Ident: string);

  function Sub(const S: string): string;
  begin
    Result := StringReplace(S, '{{class}}', UnitNameFor(Name), [rfReplaceAll]);
    Result := StringReplace(Result, '{{ENV}}', UpperCase(StringReplace(Name, '-', '_', [rfReplaceAll])), [rfReplaceAll]);
  end;

begin
  WriteText(Dir + 'pastel.toml', Sub(Fill([
    '# Pastel project file',
    '',
    '[project]',
    'name = "{{name}}"',
    'version = "0.1.0"',
    'pastel = "{{pastelminor}}"          # the Pastel version this project is made for',
    'type = "service"          # a program that keeps running (see docs/services.md)',
    '',
    '[build]',
    'main = "src/main.pas"',
    'mode = "objfpc"           # objfpc or delphi',
    'defines = []',
    '',
    '[targets]',
    '# Platforms built by "pastel build --all" and "pastel package --all"',
    'platforms = ["linux", "linux-arm64"]',
    '',
    '[package]',
    'include = ["config.example.toml", "deploy"]'
  ], Name, Ident)));

  WriteText(Dir + 'config.toml', Sub(Fill([
    '# Settings while developing ("pastel run" reads ./config.toml).',
    '# On a server the service reads /etc/{{name}}/config.toml instead (see',
    '# config.example.toml), and every setting can come from an environment',
    '# variable too: check.interval -> {{ENV}}_CHECK_INTERVAL.',
    '',
    '[inbox]',
    'folder = "inbox"        # put files here and watch the log',
    '',
    '[check]',
    'interval = 2            # seconds',
    '',
    '[report]',
    'time = "23:55"          # the daily summary',
    '',
    '[log]',
    'level = "info"          # debug, info, warn, error'
  ], Name, Ident)));

  WriteText(Dir + 'config.example.toml', Sub(Fill([
    '# {{name}} settings. Copy to /etc/{{name}}/config.toml on the server;',
    '# "sudo systemctl reload {{name}}" applies changes without a restart.',
    '',
    '[inbox]',
    'folder = "inbox"        # relative to /var/lib/{{name}}',
    '',
    '[check]',
    'interval = 10           # seconds',
    '',
    '[report]',
    'time = "23:55"',
    '',
    '[log]',
    'level = "info"',
    '# format = "json"       # one JSON object per line, for log collectors'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'main.pas', Sub(Fill([
    '{ {{name}} - a service: it keeps running, watches the inbox folder and',
    '  logs every new file, with a summary once a day.',
    '  "pastel run" starts it; Ctrl+C stops it. On a server it runs under',
    '  systemd: see deploy/README.md. }',
    'program {{ident}};',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses',
    '  SysUtils, Pastel.Service, Pastel.Config, Pastel.Log, Pastel.Files, AppInfo, Inbox;',
    '',
    'type',
    '  T{{class}}Service = class(TService)',
    '  private',
    '    FInbox: TInbox;',
    '    FToday: Integer;',
    '  protected',
    '    procedure Configure(C: TConfig); override;',
    '    procedure Started; override;',
    '    procedure Stopping; override;',
    '    procedure Reloaded; override;',
    '  public',
    '    procedure CheckInbox;',
    '    procedure DailyReport;',
    '  end;',
    '',
    '{ defaults, used when config.toml does not say otherwise }',
    'procedure T{{class}}Service.Configure(C: TConfig);',
    'begin',
    '  C.SetDefault(''inbox.folder'', ''inbox'');',
    '  C.SetDefault(''check.interval'', ''10'');',
    '  C.SetDefault(''report.time'', ''23:55'');',
    'end;',
    '',
    'procedure T{{class}}Service.Started;',
    'begin',
    '  FInbox := TInbox.Create(ExpandFileName(Config.Get(''inbox.folder'')));',
    '  Log.Info(''watching %s'', [FInbox.Folder]);',
    'end;',
    '',
    'procedure T{{class}}Service.Stopping;',
    'begin',
    '  FreeAndNil(FInbox);',
    'end;',
    '',
    '{ "systemctl reload": the settings were read again }',
    'procedure T{{class}}Service.Reloaded;',
    'begin',
    '  if ExpandFileName(Config.Get(''inbox.folder'')) <> FInbox.Folder then',
    '  begin',
    '    FInbox.Free;',
    '    FInbox := TInbox.Create(ExpandFileName(Config.Get(''inbox.folder'')));',
    '    Log.Info(''now watching %s'', [FInbox.Folder]);',
    '  end;',
    'end;',
    '',
    'procedure T{{class}}Service.CheckInbox;',
    'var',
    '  F: string;',
    'begin',
    '  for F in FInbox.NewFiles do',
    '  begin',
    '    Log.Fields([''file'', ExtractFileName(F), ''size'', FormatSize(FileSize(F))]).Info(''new file'');',
    '    Inc(FToday);',
    '  end;',
    'end;',
    '',
    'procedure T{{class}}Service.DailyReport;',
    'begin',
    '  Log.Info(''%d new file(s) today'', [FToday]);',
    '  FToday := 0;',
    'end;',
    '',
    'var',
    '  Service: T{{class}}Service;',
    'begin',
    '  Service := T{{class}}Service.Create(AppName, AppVersion);',
    '  try',
    '    Service.Every(Service.Config.GetFloat(''check.interval''), @Service.CheckInbox, ''check inbox'', True);',
    '    Service.DailyAt(Service.Config.Get(''report.time''), @Service.DailyReport, ''daily report'');',
    '    ExitCode := Service.Run;',
    '  finally',
    '    Service.Free;',
    '  end;',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'services' + PathDelim + 'inbox.pas', Sub(Fill([
    '{ The work of the service, kept apart from the service itself so it can be',
    '  tested: which files in a folder are new since the last look. }',
    'unit Inbox;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  Classes, SysUtils;',
    '',
    'type',
    '  TInbox = class',
    '  private',
    '    FFolder: string;',
    '    FSeen: TStringList;',
    '  public',
    '    { Creates the folder when it does not exist. }',
    '    constructor Create(const AFolder: string);',
    '    destructor Destroy; override;',
    '    { Files that appeared since the last call (all of them the first time). }',
    '    function NewFiles: TStringArray;',
    '    property Folder: string read FFolder;',
    '  end;',
    '',
    'implementation',
    '',
    'uses',
    '  Pastel.Files;',
    '',
    'constructor TInbox.Create(const AFolder: string);',
    'begin',
    '  inherited Create;',
    '  FFolder := ExcludeTrailingPathDelimiter(AFolder);',
    '  EnsureDir(FFolder);',
    '  FSeen := TStringList.Create;',
    '  FSeen.Sorted := True;',
    'end;',
    '',
    'destructor TInbox.Destroy;',
    'begin',
    '  FSeen.Free;',
    '  inherited Destroy;',
    'end;',
    '',
    'function TInbox.NewFiles: TStringArray;',
    'var',
    '  Now: TStringArray;',
    '  F: string;',
    '  Current: TStringList;',
    'begin',
    '  Result := nil;',
    '  Now := ListFiles(FFolder);',
    '  Current := TStringList.Create;',
    '  try',
    '    Current.Sorted := True;',
    '    for F in Now do',
    '    begin',
    '      Current.Add(F);',
    '      if FSeen.IndexOf(F) < 0 then',
    '      begin',
    '        SetLength(Result, Length(Result) + 1);',
    '        Result[High(Result)] := F;',
    '      end;',
    '    end;',
    '    { forget deleted files: if one comes back, it is new again }',
    '    FSeen.Assign(Current);',
    '  finally',
    '    Current.Free;',
    '  end;',
    'end;',
    '',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'tests' + PathDelim + 'inbox_test.pas', Sub(Fill([
    '{ Tests for src/services/inbox.pas. Run them with: pastel test }',
    'unit Inbox_Test;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, Pastel.Testing, Pastel.Files, Inbox;',
    '',
    'type',
    '  TInboxTests = class(TTestSuite)',
    '  private',
    '    Dir: string;',
    '    Box: TInbox;',
    '  public',
    '    procedure SetUp; override;',
    '    procedure TearDown; override;',
    '  published',
    '    procedure CreatesTheFolder;',
    '    procedure FirstLookFindsEverything;',
    '    procedure OnlyNewFilesAfterThat;',
    '    procedure DeletedAndBackIsNew;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure TInboxTests.SetUp;',
    'begin',
    '  Dir := MakeTempDir(''inbox-test'');',
    '  Box := TInbox.Create(Dir + ''in'');',
    'end;',
    '',
    'procedure TInboxTests.TearDown;',
    'begin',
    '  Box.Free;',
    '  DeleteDir(Dir);',
    'end;',
    '',
    'procedure TInboxTests.CreatesTheFolder;',
    'begin',
    '  AssertTrue(DirectoryExists(Dir + ''in''));',
    'end;',
    '',
    'procedure TInboxTests.FirstLookFindsEverything;',
    'begin',
    '  WriteText(Dir + ''in/a.txt'', ''a'');',
    '  WriteText(Dir + ''in/b.txt'', ''b'');',
    '  AssertEquals(2, Length(Box.NewFiles));',
    'end;',
    '',
    'procedure TInboxTests.OnlyNewFilesAfterThat;',
    'var',
    '  New: TStringArray;',
    'begin',
    '  WriteText(Dir + ''in/a.txt'', ''a'');',
    '  Box.NewFiles;',
    '  AssertEquals(0, Length(Box.NewFiles));',
    '  WriteText(Dir + ''in/c.txt'', ''c'');',
    '  New := Box.NewFiles;',
    '  AssertEquals(1, Length(New));',
    '  AssertEquals(''c.txt'', ExtractFileName(New[0]));',
    'end;',
    '',
    'procedure TInboxTests.DeletedAndBackIsNew;',
    'begin',
    '  WriteText(Dir + ''in/a.txt'', ''a'');',
    '  Box.NewFiles;',
    '  DeleteFileIfExists(Dir + ''in/a.txt'');',
    '  AssertEquals(0, Length(Box.NewFiles));',
    '  WriteText(Dir + ''in/a.txt'', ''again'');',
    '  AssertEquals(1, Length(Box.NewFiles));',
    'end;',
    '',
    'initialization',
    '  RegisterTests(TInboxTests);',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'deploy' + PathDelim + Name + '.service', Sub(Fill([
    '# systemd unit for {{name}}. Install: see deploy/README.md',
    '[Unit]',
    'Description={{name}}',
    'After=network-online.target',
    'Wants=network-online.target',
    '',
    '[Service]',
    '# Pastel services tell systemd when they are ready',
    'Type=notify',
    'ExecStart=/opt/{{name}}/{{name}}',
    'ExecReload=/bin/kill -HUP $MAINPID',
    '# its own user, created by systemd; files go to /var/lib/{{name}}',
    'DynamicUser=yes',
    'StateDirectory={{name}}',
    'WorkingDirectory=/var/lib/{{name}}',
    'Restart=on-failure',
    'RestartSec=2',
    '# Settings can also be given here instead of /etc/{{name}}/config.toml:',
    '#Environment={{ENV}}_CHECK_INTERVAL=30',
    '# Restart it when it hangs (a job that takes longer than this counts as hanging):',
    '#WatchdogSec=60',
    'NoNewPrivileges=yes',
    'ProtectSystem=strict',
    'ProtectHome=yes',
    'PrivateTmp=yes',
    '',
    '[Install]',
    'WantedBy=multi-user.target'
  ], Name, Ident)));

  WriteText(Dir + 'deploy' + PathDelim + 'README.md', Sub(Fill([
    '# Running {{name}} on a Linux server',
    '',
    'The easiest on Debian, Ubuntu and Raspberry Pi OS is a package:',
    '',
    '```sh',
    'pastel package deb                      # dist/{{name}}_0.1.0_amd64.deb',
    'scp dist/{{name}}_0.1.0_amd64.deb you@server:',
    'ssh you@server',
    'sudo apt install ./{{name}}_0.1.0_amd64.deb',
    'sudo systemctl start {{name}}',
    '```',
    '',
    'Or a container image: `pastel package docker`. Both: docs/deploy.md of Pastel.',
    '',
    'By hand, on your computer:',
    '',
    '```sh',
    'pastel package                          # dist/{{name}}-0.1.0-linux.tar.gz',
    'pastel package --target linux-arm64     # for a Raspberry Pi or an ARM server',
    'scp dist/{{name}}-0.1.0-linux.tar.gz you@server:',
    '```',
    '',
    'On the server:',
    '',
    '```sh',
    'tar -xzf {{name}}-0.1.0-linux.tar.gz',
    'sudo mv {{name}}-0.1.0-linux /opt/{{name}}',
    'sudo mkdir -p /etc/{{name}}',
    'sudo cp /opt/{{name}}/config.example.toml /etc/{{name}}/config.toml',
    'sudo cp /opt/{{name}}/deploy/{{name}}.service /etc/systemd/system/',
    'sudo systemctl daemon-reload',
    'sudo systemctl enable --now {{name}}',
    '```',
    '',
    'Then:',
    '',
    '```sh',
    'systemctl status {{name}}               # is it running?',
    'journalctl -u {{name}} -f               # its log, live',
    'journalctl -u {{name}} -p err           # only errors',
    'sudo systemctl reload {{name}}          # after editing /etc/{{name}}/config.toml',
    'sudo systemctl restart {{name}}         # after installing a new version',
    '```',
    '',
    'The inbox folder is `/var/lib/{{name}}/inbox`.'
  ], Name, Ident)));

  WriteText(Dir + 'README.md', Sub(Fill([
    '# {{name}}',
    '',
    'A service made with Pastel: a program that keeps running. It watches a',
    'folder and logs every new file, with a summary once a day.',
    '',
    '```',
    'pastel run              # runs until Ctrl+C; put files into inbox/ and watch the log',
    'pastel run --watch      # restarts it whenever you save a file',
    'pastel test',
    'pastel package          # for the server; see deploy/README.md',
    '```',
    '',
    '- `src/main.pas`: the service: settings, jobs, start and stop',
    '- `src/services/inbox.pas`: its work, with tests in `tests/`',
    '- `config.toml`: settings while developing',
    '- `deploy/`: the systemd unit and how to install it on a server'
  ], Name, Ident)));

  WriteText(Dir + '.gitignore', Sub(Fill([
    'build/',
    'dist/',
    'data/',
    'inbox/',
    '*.o',
    '*.ppu'
  ], Name, Ident)));
end;

procedure WriteAppProject(const Dir, Name, Ident: string);
begin
  WriteText(Dir + 'pastel.toml', Fill([
    '# Pastel project file',
    '',
    '[project]',
    'name = "{{name}}"',
    'version = "0.1.0"',
    'pastel = "{{pastelminor}}"          # the Pastel version this project is made for',
    'title = "{{title}}"         # the name in window lists, menus and installers',
    'type = "app"',
    '',
    '[build]',
    'main = "src/main.pas"',
    'mode = "objfpc"          # objfpc or delphi',
    'defines = []',
    '',
    '[targets]',
    '# Platforms built by "pastel build --all". See "pastel targets" for the list.',
    'platforms = ["linux", "windows"]'
  ], Name, Ident));
  if PhoneTemplates then
    WriteText(Dir + 'pastel.toml', StringReplace(ReadText(Dir + 'pastel.toml'),
      'platforms = ["linux", "windows"]', 'platforms = ["android"]', []));

  WriteText(Dir + 'src' + PathDelim + 'main.pas', Fill([
    'program {{ident}};',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses',
    '  Pastel.App, Home;',
    '',
    'begin',
    '  Application.Initialize;',
    '  Application.CreateForm(THomeForm, HomeForm);',
    '  Application.Run;',
    'end.'
  ], Name, Ident));

  if PhoneTemplates then
    { a phone: the controls stacked and as wide as the screen, big enough for a finger }
    WriteText(Dir + 'src' + PathDelim + 'forms' + PathDelim + 'Home.pform', Fill([
      '// The layout of the Home form, made for phones: the controls are stacked',
      '// (Layout = Flow) and follow the screen''s width; 48 pixels suit a finger.',
      'object HomeForm: THomeForm',
      '  Title = ''{{name}}''',
      '  Width = 360',
      '  Height = 640',
      '  Padding = 16',
      '  Gap = 12',
      '  object Heading: TLabel',
      '    Text = ''Hello!''',
      '    FontSize = 26',
      '    Bold = True',
      '  end',
      '  object HintLabel: TLabel',
      '    Text = ''Type your name and tap Send.''',
      '    Color = ''#6B7080''',
      '    WordWrap = True',
      '  end',
      '  object NameEdit: TEdit',
      '    Height = 48',
      '    Placeholder = ''Your name''',
      '    OnSubmit = SendClick',
      '  end',
      '  object SendButton: TButton',
      '    Height = 48',
      '    Text = ''Send''',
      '    OnClick = SendClick',
      '  end',
      '  object ClearButton: TButton',
      '    Height = 48',
      '    Text = ''Clear''',
      '    Style = Secondary',
      '    OnClick = ClearClick',
      '  end',
      '  object Greeting: TLabel',
      '    TextAlign = Center',
      '    WordWrap = True',
      '  end',
      'end'
    ], Name, Ident))
  else
    WriteText(Dir + 'src' + PathDelim + 'forms' + PathDelim + 'Home.pform', Fill([
      '// The layout of the Home form. While the app runs with "pastel run",',
      '// save this file and the window updates immediately (hot reload).',
      'object HomeForm: THomeForm',
      '  Title = ''{{name}}''',
      '  Width = 460',
      '  Height = 340',
      '  Layout = Free',
      '  object Heading: TLabel',
      '    Left = 24',
      '    Top = 24',
      '    Text = ''Hello!''',
      '    FontSize = 22',
      '    Bold = True',
      '  end',
      '  object HintLabel: TLabel',
      '    Left = 24',
      '    Top = 64',
      '    Text = ''Type your name and press Send.''',
      '    Color = ''#6B7080''',
      '  end',
      '  object NameEdit: TEdit',
      '    Left = 24',
      '    Top = 96',
      '    Width = 412',
      '    Anchors = [Left, Top, Right]',
      '    Placeholder = ''Your name''',
      '    OnSubmit = SendClick',
      '  end',
      '  object ClearButton: TButton',
      '    Left = 264',
      '    Top = 144',
      '    Width = 80',
      '    Anchors = [Top, Right]',
      '    Text = ''Clear''',
      '    Style = Secondary',
      '    OnClick = ClearClick',
      '  end',
      '  object SendButton: TButton',
      '    Left = 356',
      '    Top = 144',
      '    Width = 80',
      '    Anchors = [Top, Right]',
      '    Text = ''Send''',
      '    OnClick = SendClick',
      '  end',
      '  object Greeting: TLabel',
      '    Left = 24',
      '    Top = 208',
      '    Width = 412',
      '    Anchors = [Left, Top, Right]',
      '    TextAlign = Center',
      '  end',
      'end'
    ], Name, Ident));

  WriteText(Dir + 'src' + PathDelim + 'forms' + PathDelim + 'Home.pas', Fill([
    '{ The code of the Home form. The controls declared in Home.pform are',
    '  available as fields (NameEdit, Greeting, ...) through THomeFormBase,',
    '  which Pastel generates from the .pform file. }',
    'unit Home;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, Pastel.UI, Pastel.Dialogs, Home.g;',
    '',
    'type',
    '  THomeForm = class(THomeFormBase)',
    '    procedure SendClick(Sender: TObject);',
    '    procedure ClearClick(Sender: TObject);',
    '  end;',
    '',
    'var',
    '  HomeForm: THomeForm;',
    '',
    'implementation',
    '',
    'procedure THomeForm.SendClick(Sender: TObject);',
    'begin',
    '  if Trim(NameEdit.Text) = '''' then',
    '    Greeting.Text := ''Please type your name first.''',
    '  else',
    '    Greeting.Text := ''Hello, '' + Trim(NameEdit.Text) + ''! Welcome to Pastel.'';',
    'end;',
    '',
    'procedure THomeForm.ClearClick(Sender: TObject);',
    'begin',
    '  NameEdit.Text := '''';',
    '  Greeting.Text := '''';',
    '  NameEdit.SetFocus;',
    'end;',
    '',
    'end.'
  ], Name, Ident));

  WriteText(Dir + '.gitignore', Fill([
    'build/',
    'dist/',
    '*.o',
    '*.ppu',
    '*.g.pas'
  ], Name, Ident));

  WriteText(Dir + 'README.md', Fill([
    '# {{name}}',
    '',
    'A desktop application made with Pastel.',
    '',
    '```',
    'pastel run                       # build and run; edit src/forms/Home.pform while it runs',
    'pastel build --release           # optimized build',
    'pastel build --target windows    # a Windows .exe',
    '```',
    '',
    '- `src/main.pas` starts the application',
    '- `src/forms/Home.pform` is the layout of the main window',
    '- `src/forms/Home.pas` is its code (event handlers)',
    '- `assets/icon.png` is the app''s icon: the window, the taskbar, the .exe, installers, the phone''s home screen.',
    '  Put your own square PNG there (512 x 512 is best).'
  ], Name, Ident));
  { the app's icon, ready to be replaced }
  WriteDefaultIcon(Dir + 'assets' + PathDelim + 'icon.png');
end;

{ A web API with a database: models, controllers, migrations, tests.
  Generated from template files; see docs/database.md. }
procedure WriteApiProject(const Dir, Name, Ident: string);

  function Sub(const S: string): string;
  begin
    Result := StringReplace(S, '{{class}}', UnitNameFor(Name), [rfReplaceAll]);
    Result := StringReplace(Result, '{{ENV}}', UpperCase(StringReplace(Name, '-', '_', [rfReplaceAll])), [rfReplaceAll]);
  end;

begin
  WriteText(Dir + 'pastel.toml', Sub(Fill([
    '# Pastel project file',
    '',
    '[project]',
    'name = "{{name}}"',
    'version = "0.1.0"',
    'pastel = "{{pastelminor}}"          # the Pastel version this project is made for',
    'description = "A web API with a database"',
    'type = "service"          # a web API is a service with a web server (docs/web.md)',
    '',
    '[build]',
    'main = "src/main.pas"',
    'mode = "objfpc"           # objfpc or delphi',
    'defines = []',
    '',
    '[targets]',
    'platforms = ["linux", "linux-arm64"]',
    '',
    '[package]',
    'include = ["config.example.toml", "database", "deploy"]',
    '# maintainer = "Your Name <you@example.com>"',
    '',
    '[package.deb]',
    '# what "pastel package deb" and "pastel package docker" install with it:',
    '# libpq5 for PostgreSQL, libmariadb3 for MySQL/MariaDB',
    'depends = ["libsqlite3-0"]'
  ], Name, Ident)));

  WriteText(Dir + 'config.toml', Sub(Fill([
    '# Settings while developing ("pastel run" reads ./config.toml). Every',
    '# setting can also come from an environment variable: database.url ->',
    '# {{ENV}}_DATABASE_URL, server.port -> {{ENV}}_SERVER_PORT.',
    '',
    '[server]',
    'port = 8080',
    'address = "127.0.0.1"        # only this computer while developing',
    '',
    '[database]',
    'url = "sqlite:data/app.db"   # or postgres://user:password@localhost/{{ident}}',
    '                             # or mysql://user:password@localhost/{{ident}}',
    '',
    '[api]',
    '# keys = ["make-one-with: openssl rand -base64 32"]   # then the API needs X-API-Key',
    '',
    '[log]',
    'level = "info"'
  ], Name, Ident)));

  WriteText(Dir + 'config.example.toml', Sub(Fill([
    '# {{name}} settings for a server: /etc/{{name}}/config.toml',
    '# "sudo systemctl reload {{name}}" reads them again; a new database needs a restart.',
    '',
    '[server]',
    'port = 8080',
    'address = "127.0.0.1"        # behind nginx/Caddy on the same machine',
    'trust_proxy = true',
    '# cors = ["https://app.example.com"]',
    '',
    '[database]',
    'url = "sqlite:/var/lib/{{name}}/app.db"',
    '# url = "postgres://{{ident}}:PASSWORD@localhost/{{ident}}"',
    '',
    '[api]',
    'keys = ["CHANGE-ME-openssl-rand-base64-32"]',
    '',
    '[log]',
    'level = "info"'
  ], Name, Ident)));

  WriteText(Dir + 'README.md', Sub(Fill([
    '# {{name}}',
    '',
    'A web API with a database, made with Pastel.',
    '',
    '```sh',
    'pastel run                 # http://localhost:8080',
    'pastel test',
    'pastel migrate status',
    'pastel package             # for a server: see deploy/README.md',
    '```',
    '',
    '```sh',
    'curl -s localhost:8080/api/tasks -H ''Content-Type: application/json'' -d ''{"title": "Süt al"}''',
    'curl -s localhost:8080/api/tasks',
    'curl -s -X PATCH localhost:8080/api/tasks/1 -d ''{"done": true}''',
    'curl -s -X DELETE localhost:8080/api/tasks/1',
    '```',
    '',
    '| | |',
    '|---|---|',
    '| `src/main.pas` | the service: settings, database, routes |',
    '| `src/models/` | the data: all SQL is here |',
    '| `src/controllers/` | the HTTP side: routes, checks, JSON |',
    '| `database/migrations/` | the tables; a new change: `pastel migrate new add_x` |',
    '| `tests/` | tests of the model and the API |',
    '| `config.toml` | settings while developing; `config.example.toml` for servers |',
    '',
    'The database is SQLite (`data/app.db`) until you set another one:',
    '`database.url = "postgres://user:password@localhost/{{ident}}"` or `mysql://...`.'
  ], Name, Ident)));

  WriteText(Dir + '.gitignore', Sub(Fill([
    'build/',
    'dist/',
    'data/',
    '*.o',
    '*.ppu'
  ], Name, Ident)));

  WriteText(Dir + 'database' + PathDelim + 'migrations' + PathDelim + '001_create_tasks.sql', Sub(Fill([
    '-- The tasks table. Runs once, with "pastel migrate" or when the API starts.',
    '-- the id placeholder becomes the auto-numbered key of SQLite, PostgreSQL or MySQL.',
    'create table tasks (',
    '  id {{id}},',
    '  title varchar(200) not null,',
    '  done boolean not null default false,',
    '  created_at varchar(30) not null',
    ');'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'main.pas', Sub(Fill([
    '{ {{name}} - a web API with a database.',
    '',
    '    pastel run               then: curl localhost:8080/api/tasks',
    '    pastel test',
    '    pastel migrate status    (migrations also run when the API starts)',
    '',
    '  src/models       the data: SQL and the database',
    '  src/controllers  the HTTP side: routes, checks, JSON answers',
    '  database/migrations  the tables, one change per file }',
    'program {{ident}}_api;     { not just {{ident}}: a project called "tasks" would clash with the unit Tasks }',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses',
    '  SysUtils, Pastel.Service, Pastel.Web, Pastel.Config, Pastel.Db, Pastel.Log, AppInfo,',
    '  Tasks, TasksController;',
    '',
    'type',
    '  T{{class}}Api = class(TWebService)',
    '  private',
    '    FDb: TDatabase;',
    '    FTasks: TTasks;',
    '    FTasksController: TTasksController;',
    '  protected',
    '    procedure Configure(C: TConfig); override;',
    '    procedure Started; override;',
    '    procedure Stopping; override;',
    '    procedure Routes(Web: TWebServer); override;',
    '  public',
    '    destructor Destroy; override;',
    '  end;',
    '',
    'procedure T{{class}}Api.Configure(C: TConfig);',
    'begin',
    '  inherited Configure(C);',
    '  C.SetDefault(''database.url'', ''sqlite:data/app.db'');',
    'end;',
    '',
    'procedure T{{class}}Api.Started;',
    'begin',
    '  FDb := TDatabase.Open(Config.Require(''database.url''));',
    '  Log.Info(''database %s'', [FDb.SafeUrl]);',
    '  FDb.Migrate;                        { database/migrations that did not run yet }',
    '  FTasks := TTasks.Create(FDb);',
    '  FTasksController := TTasksController.Create(FTasks);',
    '  inherited Started;                  { starts the web server; it calls Routes }',
    'end;',
    '',
    'procedure T{{class}}Api.Routes(Web: TWebServer);',
    'var',
    '  Keys: TStringArray;',
    'begin',
    '  Web.RateLimit(''/api'', 600, 60);',
    '  Keys := Config.GetList(''api.keys'');',
    '  if Length(Keys) > 0 then',
    '    Web.RequireApiKey(''/api'', Keys);',
    '  FTasksController.Routes(Web);',
    '  Web.Health(''/health'', AppVersion);',
    'end;',
    '',
    'procedure T{{class}}Api.Stopping;',
    'begin',
    '  inherited Stopping;                 { stops the web server first }',
    '  FreeAndNil(FDb);',
    'end;',
    '',
    'destructor T{{class}}Api.Destroy;',
    'begin',
    '  inherited Destroy;',
    '  FTasksController.Free;',
    '  FTasks.Free;',
    '  FDb.Free;',
    'end;',
    '',
    'var',
    '  Api: T{{class}}Api;',
    'begin',
    '  Api := T{{class}}Api.Create(AppName, AppVersion);',
    '  try',
    '    ExitCode := Api.Run;',
    '  finally',
    '    Api.Free;',
    '  end;',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'models' + PathDelim + 'tasks.pas', Sub(Fill([
    '{ Model: the tasks in the database. All SQL of tasks is here; the',
    '  controller only talks to this class. }',
    'unit Tasks;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, fpjson, Pastel.Db;',
    '',
    'type',
    '  TTasks = class',
    '  private',
    '    FDb: TDatabase;',
    '    function Clean(Row: TJSONObject): TJSONObject;',
    '  public',
    '    constructor Create(ADb: TDatabase);',
    '    { Done: -1 all, 0 open, 1 done; newest first }',
    '    function List(Done: Integer = -1): TJSONArray;',
    '    { nil when there is none }',
    '    function Find(Id: Int64): TJSONObject;',
    '    function Add(const Title: string; Done: Boolean = False): TJSONObject;',
    '    { Title '''' and Done -1 leave a value as it is; nil when there is none }',
    '    function Update(Id: Int64; const Title: string; Done: Integer): TJSONObject;',
    '    function Remove(Id: Int64): Boolean;',
    '  end;',
    '',
    'implementation',
    '',
    'uses',
    '  DateUtils;',
    '',
    'constructor TTasks.Create(ADb: TDatabase);',
    'begin',
    '  inherited Create;',
    '  FDb := ADb;',
    'end;',
    '',
    '{ the same JSON from every database: SQLite and MySQL give booleans as 0/1 }',
    'function TTasks.Clean(Row: TJSONObject): TJSONObject;',
    'var',
    '  D: TJSONData;',
    'begin',
    '  Result := Row;',
    '  if Result = nil then',
    '    Exit;',
    '  D := Result.Find(''done'');',
    '  if (D <> nil) and (D.JSONType <> jtBoolean) then',
    '    Result.Booleans[''done''] := (D.JSONType = jtNumber) and (D.AsInteger <> 0) or',
    '      (D.JSONType = jtString) and ((D.AsString = ''1'') or (LowerCase(D.AsString) = ''t'') or',
    '      (LowerCase(D.AsString) = ''true''));',
    'end;',
    '',
    'function TTasks.List(Done: Integer): TJSONArray;',
    'var',
    '  I: Integer;',
    'begin',
    '  if Done < 0 then',
    '    Result := FDb.Query(''select id, title, done, created_at from tasks order by id desc'', [])',
    '  else',
    '    Result := FDb.Query(''select id, title, done, created_at from tasks where done = ? order by id desc'',',
    '      [Done = 1]);',
    '  for I := 0 to Result.Count - 1 do',
    '    Clean(Result.Objects[I]);',
    'end;',
    '',
    'function TTasks.Find(Id: Int64): TJSONObject;',
    'begin',
    '  Result := Clean(FDb.QueryOne(''select id, title, done, created_at from tasks where id = ?'', [Id]));',
    'end;',
    '',
    'function TTasks.Add(const Title: string; Done: Boolean): TJSONObject;',
    'var',
    '  Id: Int64;',
    'begin',
    '  Id := FDb.Insert(''insert into tasks (title, done, created_at) values (?, ?, ?)'',',
    '    [Title, Done, DateToISO8601(LocalTimeToUniversal(Now))]);',
    '  Result := Find(Id);',
    'end;',
    '',
    'function TTasks.Update(Id: Int64; const Title: string; Done: Integer): TJSONObject;',
    'begin',
    '  if Title <> '''' then',
    '    FDb.Exec(''update tasks set title = ? where id = ?'', [Title, Id]);',
    '  if Done >= 0 then',
    '    FDb.Exec(''update tasks set done = ? where id = ?'', [Done = 1, Id]);',
    '  Result := Find(Id);',
    'end;',
    '',
    'function TTasks.Remove(Id: Int64): Boolean;',
    'begin',
    '  Result := FDb.Exec(''delete from tasks where id = ?'', [Id]) > 0;',
    'end;',
    '',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'controllers' + PathDelim + 'taskscontroller.pas', Sub(Fill([
    '{ Controller: the HTTP side of tasks. It reads and checks requests, asks',
    '  the model, and answers with JSON. }',
    'unit TasksController;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, fpjson, Pastel.Web, Tasks;',
    '',
    'type',
    '  TTasksController = class',
    '  private',
    '    FTasks: TTasks;',
    '  public',
    '    constructor Create(ATasks: TTasks);',
    '    procedure Routes(Web: TWebServer);',
    '    { GET /api/tasks?done=true }',
    '    procedure ListTasks(Req: TWebRequest; Res: TWebResponse);',
    '    { GET /api/tasks/:id }',
    '    procedure ShowTask(Req: TWebRequest; Res: TWebResponse);',
    '    { POST /api/tasks  with title (and done) }',
    '    procedure CreateTask(Req: TWebRequest; Res: TWebResponse);',
    '    { PATCH /api/tasks/:id  with title and/or done }',
    '    procedure UpdateTask(Req: TWebRequest; Res: TWebResponse);',
    '    { DELETE /api/tasks/:id }',
    '    procedure DeleteTask(Req: TWebRequest; Res: TWebResponse);',
    '  end;',
    '',
    'implementation',
    '',
    'constructor TTasksController.Create(ATasks: TTasks);',
    'begin',
    '  inherited Create;',
    '  FTasks := ATasks;',
    'end;',
    '',
    'procedure TTasksController.Routes(Web: TWebServer);',
    'begin',
    '  Web.Get(''/api/tasks'', @ListTasks);',
    '  Web.Get(''/api/tasks/:id'', @ShowTask);',
    '  Web.Post(''/api/tasks'', @CreateTask);',
    '  Web.Patch(''/api/tasks/:id'', @UpdateTask);',
    '  Web.Delete(''/api/tasks/:id'', @DeleteTask);',
    'end;',
    '',
    'procedure TTasksController.ListTasks(Req: TWebRequest; Res: TWebResponse);',
    'var',
    '  Done: Integer;',
    'begin',
    '  case LowerCase(Req.Query(''done'')) of',
    '    '''': Done := -1;',
    '    ''true'', ''1'': Done := 1;',
    '    ''false'', ''0'': Done := 0;',
    '  else',
    '    raise EWebError.Create(400, ''done must be true or false'');',
    '  end;',
    '  Res.Json(FTasks.List(Done));',
    'end;',
    '',
    'procedure TTasksController.ShowTask(Req: TWebRequest; Res: TWebResponse);',
    'var',
    '  Task: TJSONObject;',
    'begin',
    '  Task := FTasks.Find(Req.ParamInt(''id''));',
    '  if Task = nil then',
    '    raise EWebError.Create(404, ''no task with this id'');',
    '  Res.Json(Task);',
    'end;',
    '',
    'procedure TTasksController.CreateTask(Req: TWebRequest; Res: TWebResponse);',
    'var',
    '  V: TValidator;',
    '  Title: string;',
    '  Done: Boolean;',
    'begin',
    '  V := Req.Validate;',
    '  Title := V.Str(''title'', 1, 200);',
    '  Done := V.OptBool(''done'', False);',
    '  V.Check;',
    '  Res.Json(FTasks.Add(Title, Done), 201);',
    'end;',
    '',
    'procedure TTasksController.UpdateTask(Req: TWebRequest; Res: TWebResponse);',
    'var',
    '  V: TValidator;',
    '  Title: string;',
    '  Done: Integer;',
    '  Task: TJSONObject;',
    'begin',
    '  V := Req.Validate;',
    '  Title := V.OptStr(''title'', '''', 200);',
    '  Done := -1;',
    '  if Req.JsonObject.Find(''done'') <> nil then',
    '    Done := Ord(V.Bool(''done''));',
    '  V.Check;',
    '  Task := FTasks.Update(Req.ParamInt(''id''), Title, Done);',
    '  if Task = nil then',
    '    raise EWebError.Create(404, ''no task with this id'');',
    '  Res.Json(Task);',
    'end;',
    '',
    'procedure TTasksController.DeleteTask(Req: TWebRequest; Res: TWebResponse);',
    'begin',
    '  if not FTasks.Remove(Req.ParamInt(''id'')) then',
    '    raise EWebError.Create(404, ''no task with this id'');',
    '  Res.NoContent;',
    'end;',
    '',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'tests' + PathDelim + 'tasks_test.pas', Sub(Fill([
    '{ Tests for the tasks model and the API, on a fresh SQLite database.',
    '  Run them with: pastel test }',
    'unit Tasks_Test;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, fpjson, Pastel.Testing, Pastel.Db, Pastel.Json, Pastel.Files, Pastel.Web, Pastel.Http,',
    '  Pastel.Log, Tasks, TasksController;',
    '',
    'type',
    '  TTasksTests = class(TTestSuite)',
    '  private',
    '    Dir: string;',
    '    Db: TDatabase;',
    '    Model: TTasks;',
    '  public',
    '    procedure SetUp; override;',
    '    procedure TearDown; override;',
    '  published',
    '    procedure AddsAndFinds;',
    '    procedure ListsByState;',
    '    procedure UpdatesPartly;',
    '    procedure RemovesTasks;',
    '    procedure ApiCreatesAndChecks;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure TTasksTests.SetUp;',
    'begin',
    '  Log.Console := False;',
    '  Dir := MakeTempDir(''tasks-test'');',
    '  Db := TDatabase.Open(''sqlite:'' + Dir + ''test.db'');',
    '  Db.Migrate;                    { database/migrations of the project }',
    '  Model := TTasks.Create(Db);',
    'end;',
    '',
    'procedure TTasksTests.TearDown;',
    'begin',
    '  Model.Free;',
    '  Db.Free;',
    '  DeleteDir(Dir);',
    '  Log.Console := True;',
    'end;',
    '',
    'procedure TTasksTests.AddsAndFinds;',
    'var',
    '  T: TJSONObject;',
    'begin',
    '  Model.Add(''Süt al'').Free;',
    '  T := Model.Find(1);',
    '  try',
    '    AssertEquals(''Süt al'', JStr(T, ''title''));',
    '    AssertFalse(JBool(T, ''done''));',
    '  finally',
    '    T.Free;',
    '  end;',
    '  AssertNil(Model.Find(99));',
    'end;',
    '',
    'procedure TTasksTests.ListsByState;',
    'var',
    '  L: TJSONArray;',
    'begin',
    '  Model.Add(''one'').Free;',
    '  Model.Add(''two'', True).Free;',
    '  L := Model.List(1);',
    '  try',
    '    AssertEquals(1, L.Count);',
    '    AssertEquals(''two'', JStr(L, ''[0].title''));',
    '  finally',
    '    L.Free;',
    '  end;',
    '  L := Model.List;',
    '  try',
    '    AssertEquals(2, L.Count);',
    '  finally',
    '    L.Free;',
    '  end;',
    'end;',
    '',
    'procedure TTasksTests.UpdatesPartly;',
    'var',
    '  T: TJSONObject;',
    'begin',
    '  Model.Add(''old'').Free;',
    '  Model.Update(1, '''', 1).Free;',
    '  T := Model.Find(1);',
    '  try',
    '    AssertEquals(''old'', JStr(T, ''title''));',
    '    AssertTrue(JBool(T, ''done''));',
    '  finally',
    '    T.Free;',
    '  end;',
    '  AssertNil(Model.Update(42, ''x'', -1));',
    'end;',
    '',
    'procedure TTasksTests.RemovesTasks;',
    'begin',
    '  Model.Add(''x'').Free;',
    '  AssertTrue(Model.Remove(1));',
    '  AssertFalse(Model.Remove(1));',
    'end;',
    '',
    '{ the controller through real HTTP }',
    'procedure TTasksTests.ApiCreatesAndChecks;',
    'var',
    '  Web: TWebServer;',
    '  C: TTasksController;',
    '  Base: string;',
    '  R: THttpResponse;',
    '  Port: Integer;',
    'begin',
    '  Port := 23000 + Random(20000);',
    '  Base := Format(''http://127.0.0.1:%d'', [Port]);',
    '  C := TTasksController.Create(Model);',
    '  Web := TWebServer.Create(Port, ''127.0.0.1'');',
    '  try',
    '    Web.AccessLog := False;',
    '    C.Routes(Web);',
    '    Web.Start;',
    '    R := HttpPostJson(Base + ''/api/tasks'', ''{"title": "Ekmek al"}'');',
    '    AssertEquals(201, R.Status);',
    '    AssertContains(''"title":"Ekmek al"'', R.Body);',
    '    R := HttpPostJson(Base + ''/api/tasks'', ''{"title": ""}'');',
    '    AssertEquals(422, R.Status);',
    '    AssertEquals(404, HttpGet(Base + ''/api/tasks/99'').Status);',
    '    AssertEquals(400, HttpGet(Base + ''/api/tasks?done=maybe'').Status);',
    '  finally',
    '    Web.Free;',
    '    C.Free;',
    '  end;',
    'end;',
    '',
    'initialization',
    '  RegisterTests(TTasksTests);',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'deploy' + PathDelim + Name + '.service', Sub(Fill([
    '# systemd unit for {{name}}. Install: see deploy/README.md',
    '[Unit]',
    'Description={{name}}',
    'After=network-online.target',
    'Wants=network-online.target',
    '',
    '[Service]',
    '# Pastel services tell systemd when they are ready',
    'Type=notify',
    'ExecStart=/opt/{{name}}/{{name}}',
    'ExecReload=/bin/kill -HUP $MAINPID',
    '# its own user, created by systemd; files go to /var/lib/{{name}}',
    'DynamicUser=yes',
    'StateDirectory={{name}}',
    'WorkingDirectory=/var/lib/{{name}}',
    'Restart=on-failure',
    'RestartSec=2',
    '# Settings can also be given here instead of /etc/{{name}}/config.toml:',
    '#Environment={{ENV}}_DATABASE_URL=postgres://...',
    '# A database on this machine: start after it',
    '#After=postgresql.service',
    '# Restart it when it hangs (a job that takes longer than this counts as hanging):',
    '#WatchdogSec=60',
    'NoNewPrivileges=yes',
    'ProtectSystem=strict',
    'ProtectHome=yes',
    'PrivateTmp=yes',
    '',
    '[Install]',
    'WantedBy=multi-user.target'
  ], Name, Ident)));

  WriteText(Dir + 'deploy' + PathDelim + 'README.md', Sub(Fill([
    '# Running {{name}} on a Linux server',
    '',
    'The easiest on Debian, Ubuntu and Raspberry Pi OS is a package:',
    '',
    '```sh',
    'pastel package deb                      # dist/{{name}}_0.1.0_amd64.deb',
    'scp dist/{{name}}_0.1.0_amd64.deb you@server:',
    'ssh you@server',
    'sudo apt install ./{{name}}_0.1.0_amd64.deb',
    'sudo nano /etc/{{name}}/config.toml     # real API keys, the database',
    'sudo systemctl start {{name}}',
    '```',
    '',
    'Or a container image: `pastel package docker`. Both: docs/deploy.md of Pastel.',
    '',
    'By hand, on your computer:',
    '',
    '```sh',
    'pastel package                          # dist/{{name}}-0.1.0-linux.tar.gz',
    'pastel package --target linux-arm64     # for a Raspberry Pi or an ARM server',
    'scp dist/{{name}}-0.1.0-linux.tar.gz you@server:',
    '```',
    '',
    'On the server:',
    '',
    '```sh',
    'tar -xzf {{name}}-0.1.0-linux.tar.gz',
    'sudo mv {{name}}-0.1.0-linux /opt/{{name}}',
    'sudo mkdir -p /etc/{{name}}',
    'sudo cp /opt/{{name}}/config.example.toml /etc/{{name}}/config.toml',
    'sudo cp /opt/{{name}}/deploy/{{name}}.service /etc/systemd/system/',
    'sudo systemctl daemon-reload',
    'sudo systemctl enable --now {{name}}',
    '```',
    '',
    'Then:',
    '',
    '```sh',
    'systemctl status {{name}}               # is it running?',
    'journalctl -u {{name}} -f               # its log, live',
    'journalctl -u {{name}} -p err           # only errors',
    'sudo systemctl reload {{name}}          # after editing /etc/{{name}}/config.toml',
    'sudo systemctl restart {{name}}         # after installing a new version',
    '```',
    '',
    'The SQLite database (when used) is `/var/lib/{{name}}/app.db`; put nginx or Caddy in front for HTTPS (docs/web.md).'
  ], Name, Ident)));
end;

{ VS Code settings: Ctrl+Shift+B builds, F5 debugs, errors go to Problems.
  The tasks call the pastel program directly, so they work even without
  the Pastel extension. }
procedure WriteVSCodeFiles(const Dir, Name, Ident, Kind: string);
var
  V: string;
begin
  V := Dir + '.vscode' + PathDelim;
  WriteText(V + 'tasks.json', Fill([
    '{',
    '  "version": "2.0.0",',
    '  "tasks": [',
    '    {',
    '      "label": "pastel: build",',
    '      "type": "shell",',
    '      "command": "pastel",',
    '      "args": ["build"],',
    '      "options": { "env": { "NO_COLOR": "1" } },',
    '      "group": { "kind": "build", "isDefault": true },',
    '      "problemMatcher": {',
    '        "owner": "pastel",',
    '        "fileLocation": ["autoDetect", "${workspaceFolder}"],',
    '        "pattern": {',
    '          "regexp": "^(.+?)\\((\\d+)(?:,(\\d+))?\\)\\s+(Error|Fatal|Warning):\\s+(.*)$",',
    '          "file": 1, "line": 2, "column": 3, "severity": 4, "message": 5',
    '        }',
    '      }',
    '    },',
    '    {',
    '      "label": "pastel: test",',
    '      "type": "shell",',
    '      "command": "pastel",',
    '      "args": ["test"],',
    '      "options": { "env": { "NO_COLOR": "1" } },',
    '      "group": "test",',
    '      "problemMatcher": []',
    '    },',
    '    {',
    '      "label": "pastel: run",',
    '      "type": "shell",',
    '      "command": "pastel",',
    '      "args": ["run"],',
    '      "options": { "env": { "NO_COLOR": "1" } },',
    '      "problemMatcher": []',
    '    },',
    '    {',
    '      "label": "pastel: watch",',
    '      "detail": "build and run again on every save",',
    '      "type": "shell",',
    '      "command": "pastel",',
    '      "args": ["run", "--watch"],',
    '      "isBackground": true,',
    '      "problemMatcher": []',
    '    }',
    '  ]',
    '}'
  ], Name, Ident));

  if Kind <> 'lib' then
    WriteText(V + 'launch.json', Fill([
      '{',
      '  "version": "0.2.0",',
      '  "configurations": [',
      '    {',
      '      "name": "Debug {{name}}",',
      '      "type": "pastel",',
      '      "request": "launch",',
      '      "args": []',
      '    }',
      '  ]',
      '}'
    ], Name, Ident));

  WriteText(V + 'extensions.json', Fill([
    '{',
    '  "recommendations": ["ms-vscode.cpptools"]',
    '}'
  ], Name, Ident));

  WriteText(V + 'settings.json', Fill([
    '{',
    '  "search.exclude": { "build/**": true },',
    '  "files.watcherExclude": { "**/build/**": true },',
    '  "[pascal]": {',
    '    "editor.defaultFormatter": "pastel.pastel-vscode",',
    '    "editor.formatOnSave": true',
    '  }',
    '}'
  ], Name, Ident));
end;

{ "pastel new site": a web site with pages from templates (Pastel.Pages) and Bootstrap }
procedure WriteSiteProject(const Dir, Name, Ident: string);

  function Sub(const S: string): string;
  begin
    Result := StringReplace(S, '{{class}}', UnitNameFor(Name), [rfReplaceAll]);
    Result := StringReplace(Result, '{{ENV}}', UpperCase(StringReplace(Name, '-', '_', [rfReplaceAll])), [rfReplaceAll]);
  end;

begin
  WriteText(Dir + 'pastel.toml', Sub(Fill([
    '# Pastel project file',
    '',
    '[project]',
    'name = "{{name}}"',
    'version = "0.1.0"',
    'pastel = "{{pastelminor}}"          # the Pastel version this project is made for',
    'description = "A web site"',
    'type = "service"          # a web site is a service with a web server (docs/pages.md)',
    '',
    '[build]',
    'main = "src/main.pas"',
    'mode = "objfpc"           # objfpc or delphi',
    'defines = []',
    '',
    '[targets]',
    'platforms = ["linux", "linux-arm64"]',
    '',
    '[package]',
    'include = ["config.example.toml", "views", "public", "deploy"]',
    '# maintainer = "Your Name <you@example.com>"'
  ], Name, Ident)));

  WriteText(Dir + 'config.toml', Sub(Fill([
    '# Settings while developing ("pastel run" reads ./config.toml). Every setting',
    '# can also come from an environment variable: server.port -> {{ENV}}_SERVER_PORT.',
    '',
    '[server]',
    'port = 8080',
    'address = "127.0.0.1"        # only this computer while developing',
    '',
    '[site]',
    'title = "{{title}}"',
    '',
    '[log]',
    'level = "info"'
  ], Name, Ident)));

  WriteText(Dir + 'config.example.toml', Sub(Fill([
    '# {{name}} settings for a server: /etc/{{name}}/config.toml',
    '',
    '[server]',
    'port = 8080',
    'address = "127.0.0.1"        # behind nginx/Caddy on the same machine',
    'trust_proxy = true',
    '',
    '[site]',
    'title = "{{title}}"',
    '',
    '[log]',
    'level = "info"'
  ], Name, Ident)));

  WriteText(Dir + '.gitignore', Sub(Fill([
    'build/',
    'dist/',
    'data/',
    '*.o',
    '*.ppu'
  ], Name, Ident)));

  WriteText(Dir + 'README.md', Sub(Fill([
    '# {{name}}',
    '',
    'A web site made with Pastel: pages from templates in `views/`, Bootstrap for the looks.',
    '',
    '```sh',
    'pastel run          # http://localhost:8080',
    'pastel test',
    'pastel package deb  # for a server (deploy/{{name}}.service)',
    '```',
    '',
    '| | |',
    '|---|---|',
    '| `src/main.pas` | the service: settings and the web server |',
    '| `src/webpages.pas` | the pages: one handler for each address |',
    '| `views/` | the templates: `layouts/main.html` around every page, one file per page |',
    '| `public/` | files served as they are: `/static/css/site.css`, pictures |',
    '| `tests/` | the pages tested through real HTTP |',
    '',
    'Templates: `{{ value }}`, `@if`, `@foreach`, `@extends`, `@section`, `@include` — see docs/pages.md of Pastel.',
    'Saved templates show on the next reload of the page; Pascal changes need `pastel run` again (or `pastel run --watch`).'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'main.pas', Sub(Fill([
    '{ {{name}} - a web site.',
    '',
    '    pastel run       then open http://localhost:8080',
    '',
    '  src/webpages.pas  the pages: what each address shows',
    '  views/            the HTML templates',
    '  public/           CSS, pictures and other files served as they are }',
    'program {{ident}}_site;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses',
    '  SysUtils, Pastel.Service, Pastel.Web, Pastel.Config, Pastel.Log, Pastel.Pages, AppInfo, WebPages;',
    '',
    'type',
    '  T{{class}}Site = class(TWebService)',
    '  private',
    '    FPages: TWebPages;',
    '  protected',
    '    procedure Routes(Web: TWebServer); override;',
    '  public',
    '    destructor Destroy; override;',
    '  end;',
    '',
    'procedure T{{class}}Site.Routes(Web: TWebServer);',
    'begin',
    '  FPages := TWebPages.Create(Config.Get(''site.title'', ''{{title}}''));',
    '  Web.Static(''/static'', FindAppFolder(''public''));',
    '  FPages.Routes(Web);',
    '  Web.Health(''/health'', AppVersion);',
    'end;',
    '',
    'destructor T{{class}}Site.Destroy;',
    'begin',
    '  inherited Destroy;',
    '  FPages.Free;',
    'end;',
    '',
    'var',
    '  Site: T{{class}}Site;',
    'begin',
    '  Site := T{{class}}Site.Create(AppName, AppVersion);',
    '  try',
    '    ExitCode := Site.Run;',
    '  finally',
    '    Site.Free;',
    '  end;',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'src' + PathDelim + 'webpages.pas', Sub(Fill([
    '{ The pages of the site: each address gets its data and a template from views/.',
    '  View(''home'', Data) renders views/home.html with the data (a JSON object). }',
    'unit WebPages;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, fpjson, Pastel.Web, Pastel.Json, Pastel.Pages, Pastel.Log;',
    '',
    'type',
    '  TWebPages = class',
    '  private',
    '    FTitle: string;',
    '    { what every page has: the site''s name and the address it is on }',
    '    function Data(Req: TWebRequest; const Page: string): TJSONObject;',
    '    procedure Home(Req: TWebRequest; Res: TWebResponse);',
    '    procedure About(Req: TWebRequest; Res: TWebResponse);',
    '    procedure Contact(Req: TWebRequest; Res: TWebResponse);',
    '    procedure SendMessage(Req: TWebRequest; Res: TWebResponse);',
    '  public',
    '    constructor Create(const ATitle: string);',
    '    procedure Routes(Web: TWebServer);',
    '  end;',
    '',
    'implementation',
    '',
    'constructor TWebPages.Create(const ATitle: string);',
    'begin',
    '  inherited Create;',
    '  FTitle := ATitle;',
    'end;',
    '',
    'procedure TWebPages.Routes(Web: TWebServer);',
    'begin',
    '  Web.Get(''/'', @Home);',
    '  Web.Get(''/about'', @About);',
    '  Web.Get(''/contact'', @Contact);',
    '  Web.Post(''/contact'', @SendMessage);',
    'end;',
    '',
    'function TWebPages.Data(Req: TWebRequest; const Page: string): TJSONObject;',
    'begin',
    '  Result := JObject([''site'', FTitle, ''page'', Page, ''year'', FormatDateTime(''yyyy'', Now)]);',
    'end;',
    '',
    'procedure TWebPages.Home(Req: TWebRequest; Res: TWebResponse);',
    'var',
    '  D: TJSONObject;',
    'begin',
    '  D := Data(Req, ''home'');',
    '  D.Add(''features'', JArrayOf([',
    '    JObject([''title'', ''Fast'', ''text'', ''Compiled Object Pascal: pages in microseconds.'']),',
    '    JObject([''title'', ''Simple'', ''text'', ''Templates like Laravel''''s Blade, code in plain Pascal.'']),',
    '    JObject([''title'', ''Yours'', ''text'', ''One program and a folder of templates on your server.''])]));',
    '  Res.Html(View(''home'', D));',
    'end;',
    '',
    'procedure TWebPages.About(Req: TWebRequest; Res: TWebResponse);',
    'begin',
    '  Res.Html(View(''about'', Data(Req, ''about'')));',
    'end;',
    '',
    'procedure TWebPages.Contact(Req: TWebRequest; Res: TWebResponse);',
    'begin',
    '  Res.Html(View(''contact'', Data(Req, ''contact'')));',
    'end;',
    '',
    '{ the form sent: checked; the page again with the mistakes, or with thanks }',
    'procedure TWebPages.SendMessage(Req: TWebRequest; Res: TWebResponse);',
    'var',
    '  D, Errors: TJSONObject;',
    '  Name, Email, Message: string;',
    'begin',
    '  Name := Trim(Req.Form(''name''));',
    '  Email := Trim(Req.Form(''email''));',
    '  Message := Trim(Req.Form(''message''));',
    '  D := Data(Req, ''contact'');',
    '  Errors := TJSONObject.Create;',
    '  if Name = '''' then',
    '    Errors.Add(''name'', ''Please write your name.'');',
    '  if Pos(''@'', Email) < 2 then',
    '    Errors.Add(''email'', ''This does not look like an e-mail address.'');',
    '  if Length(Message) < 10 then',
    '    Errors.Add(''message'', ''Please write at least a sentence.'');',
    '  D.Add(''errors'', Errors);',
    '  D.Add(''old'', JObject([''name'', Name, ''email'', Email, ''message'', Message]));',
    '  if Errors.Count > 0 then',
    '  begin',
    '    Res.Html(View(''contact'', D), 422);',
    '    Exit;',
    '  end;',
    '  Log.Info(''message from %s <%s>: %s'', [Name, Email, Message]);',
    '  D.Add(''sent'', True);',
    '  Res.Html(View(''contact'', D));',
    'end;',
    '',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'views' + PathDelim + 'layouts' + PathDelim + 'main.html', Sub(Fill([
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '  <meta charset="utf-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    '  <title>@yield(''title'') · {{ site }}</title>',
    '  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">',
    '  <link href="/static/css/site.css" rel="stylesheet">',
    '</head>',
    '<body class="d-flex flex-column min-vh-100">',
    '  @include(''partials.nav'')',
    '  <main class="flex-grow-1">',
    '    @yield(''content'')',
    '  </main>',
    '  <footer class="border-top py-4 text-body-secondary small">',
    '    <div class="container">© {{ year }} {{ site }} · Made with Pastel</div>',
    '  </footer>',
    '  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>',
    '</body>',
    '</html>'
  ], Name, Ident)));

  WriteText(Dir + 'views' + PathDelim + 'partials' + PathDelim + 'nav.html', Sub(Fill([
    '<nav class="navbar navbar-expand-md bg-body-tertiary border-bottom">',
    '  <div class="container">',
    '    <a class="navbar-brand fw-semibold" href="/">{{ site }}</a>',
    '    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#menu" aria-label="Menu">',
    '      <span class="navbar-toggler-icon"></span>',
    '    </button>',
    '    <div class="collapse navbar-collapse" id="menu">',
    '      <ul class="navbar-nav ms-auto">',
    '        <li class="nav-item"><a class="nav-link {{ page == ''home'' ? ''active'' : '''' }}" href="/">Home</a></li>',
    '        <li class="nav-item"><a class="nav-link {{ page == ''about'' ? ''active'' : '''' }}" href="/about">About</a></li>',
    '        <li class="nav-item"><a class="nav-link {{ page == ''contact'' ? ''active'' : '''' }}" href="/contact">Contact</a></li>',
    '      </ul>',
    '    </div>',
    '  </div>',
    '</nav>'
  ], Name, Ident)));

  WriteText(Dir + 'views' + PathDelim + 'home.html', Sub(Fill([
    '@extends(''layouts.main'')',
    '',
    '@section(''title'', ''Home'')',
    '',
    '@section(''content'')',
    '<section class="hero py-5">',
    '  <div class="container py-4">',
    '    <h1 class="display-5 fw-bold">Welcome to {{ site }}</h1>',
    '    <p class="lead col-lg-8">A site made with Pastel: the pages come from templates in <code>views/</code>, the code is Object Pascal.</p>',
    '    <a class="btn btn-primary btn-lg" href="/contact">Get in touch</a>',
    '  </div>',
    '</section>',
    '<section class="container py-5">',
    '  <div class="row g-4">',
    '    @foreach(features as feature)',
    '    <div class="col-md-4">',
    '      <div class="card h-100 shadow-sm">',
    '        <div class="card-body">',
    '          <h2 class="h5">{{ loop.iteration }}. {{ feature.title }}</h2>',
    '          <p class="mb-0 text-body-secondary">{{ feature.text }}</p>',
    '        </div>',
    '      </div>',
    '    </div>',
    '    @endforeach',
    '  </div>',
    '</section>',
    '@endsection'
  ], Name, Ident)));

  WriteText(Dir + 'views' + PathDelim + 'about.html', Sub(Fill([
    '@extends(''layouts.main'')',
    '',
    '@section(''title'', ''About'')',
    '',
    '@section(''content'')',
    '<div class="container py-5 col-lg-8">',
    '  <h1 class="mb-3">About</h1>',
    '  <p>Write about yourself here: <code>views/about.html</code>. The page around it is <code>views/layouts/main.html</code>.</p>',
    '</div>',
    '@endsection'
  ], Name, Ident)));

  WriteText(Dir + 'views' + PathDelim + 'contact.html', Sub(Fill([
    '@extends(''layouts.main'')',
    '',
    '@section(''title'', ''Contact'')',
    '',
    '@section(''content'')',
    '<div class="container py-5 col-lg-6">',
    '  <h1 class="mb-4">Contact</h1>',
    '  @if(sent)',
    '  <div class="alert alert-success">Thank you, {{ old.name }}! Your message was sent.</div>',
    '  @else',
    '  <form method="post" action="/contact" novalidate>',
    '    <div class="mb-3">',
    '      <label class="form-label" for="name">Name</label>',
    '      <input class="form-control {{ errors.name ? ''is-invalid'' : '''' }}" id="name" name="name" value="{{ old.name }}">',
    '      <div class="invalid-feedback">{{ errors.name }}</div>',
    '    </div>',
    '    <div class="mb-3">',
    '      <label class="form-label" for="email">E-mail</label>',
    '      <input class="form-control {{ errors.email ? ''is-invalid'' : '''' }}" id="email" name="email" type="email" value="{{ old.email }}">',
    '      <div class="invalid-feedback">{{ errors.email }}</div>',
    '    </div>',
    '    <div class="mb-3">',
    '      <label class="form-label" for="message">Message</label>',
    '      <textarea class="form-control {{ errors.message ? ''is-invalid'' : '''' }}" id="message" name="message" rows="5">{{ old.message }}</textarea>',
    '      <div class="invalid-feedback">{{ errors.message }}</div>',
    '    </div>',
    '    <button class="btn btn-primary" type="submit">Send</button>',
    '  </form>',
    '  @endif',
    '</div>',
    '@endsection'
  ], Name, Ident)));

  WriteText(Dir + 'public' + PathDelim + 'css' + PathDelim + 'site.css', Sub(Fill([
    '/* The site''s own looks, on top of Bootstrap (https://getbootstrap.com/docs/5.3/) */',
    '.hero {',
    '  background: linear-gradient(135deg, #eef2ff, #f8fafc);',
    '}'
  ], Name, Ident)));

  WriteText(Dir + 'tests' + PathDelim + 'webpages_test.pas', Sub(Fill([
    '{ Tests of the pages through real HTTP. Run them with: pastel test }',
    'unit WebPages_Test;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  SysUtils, Pastel.Testing, Pastel.Web, Pastel.Http, Pastel.Pages, Pastel.Log, WebPages;',
    '',
    'type',
    '  TWebPagesTests = class(TTestSuite)',
    '  private',
    '    Web: TWebServer;',
    '    Pages: TWebPages;',
    '    Base: string;',
    '  public',
    '    procedure SetUp; override;',
    '    procedure TearDown; override;',
    '  published',
    '    procedure HomeShowsTheFeatures;',
    '    procedure ContactChecksTheForm;',
    '    procedure StaticFilesAreServed;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure TWebPagesTests.SetUp;',
    'var',
    '  Port: Integer;',
    'begin',
    '  Log.Console := False;',
    '  Port := 23000 + Random(20000);',
    '  Base := Format(''http://127.0.0.1:%d'', [Port]);',
    '  Pages := TWebPages.Create(''Test Site'');',
    '  Web := TWebServer.Create(Port, ''127.0.0.1'');',
    '  Web.AccessLog := False;',
    '  Web.Static(''/static'', FindAppFolder(''public''));',
    '  Pages.Routes(Web);',
    '  Web.Start;',
    'end;',
    '',
    'procedure TWebPagesTests.TearDown;',
    'begin',
    '  Web.Free;',
    '  Pages.Free;',
    '  Log.Console := True;',
    'end;',
    '',
    'procedure TWebPagesTests.HomeShowsTheFeatures;',
    'var',
    '  R: THttpResponse;',
    'begin',
    '  R := HttpGet(Base + ''/'');',
    '  AssertEquals(200, R.Status);',
    '  AssertContains(''<title>Home · Test Site</title>'', R.Body);',
    '  AssertContains(''2. Simple'', R.Body);',
    '  AssertContains(''Laravel&#39;s Blade'', R.Body, ''values are made safe for HTML'');',
    '  AssertContains(''nav-link active" href="/"'', R.Body, ''the menu shows where we are'');',
    'end;',
    '',
    'procedure TWebPagesTests.ContactChecksTheForm;',
    'var',
    '  R: THttpResponse;',
    'begin',
    '  R := HttpPost(Base + ''/contact'', ''name=&email=nope&message=hi'', ''application/x-www-form-urlencoded'');',
    '  AssertEquals(422, R.Status);',
    '  AssertContains(''Please write your name.'', R.Body);',
    '  AssertContains(''value="nope"'', R.Body, ''what was typed stays'');',
    '  R := HttpPost(Base + ''/contact'', ''name=Ay%C5%9Fe&email=ayse%40example.com&message=Merhaba%2C+nas%C4%B1ls%C4%B1n%C4%B1z%3F'',',
    '    ''application/x-www-form-urlencoded'');',
    '  AssertEquals(200, R.Status);',
    '  AssertContains(''Thank you, Ayşe!'', R.Body);',
    'end;',
    '',
    'procedure TWebPagesTests.StaticFilesAreServed;',
    'begin',
    '  AssertContains(''.hero'', HttpGet(Base + ''/static/css/site.css'').Body);',
    'end;',
    '',
    'initialization',
    '  RegisterTests(TWebPagesTests);',
    'end.'
  ], Name, Ident)));

  WriteText(Dir + 'deploy' + PathDelim + Name + '.service', Sub(Fill([
    '# systemd unit for {{name}}. Install: copy the package''s files to /opt/{{name}},',
    '# this file to /etc/systemd/system/, then: sudo systemctl enable --now {{name}}',
    '[Unit]',
    'Description={{name}}',
    'After=network-online.target',
    'Wants=network-online.target',
    '',
    '[Service]',
    'Type=notify',
    'ExecStart=/opt/{{name}}/{{name}}',
    'ExecReload=/bin/kill -HUP $MAINPID',
    'DynamicUser=yes',
    'StateDirectory={{name}}',
    'WorkingDirectory=/var/lib/{{name}}',
    'Restart=on-failure',
    'RestartSec=2',
    'NoNewPrivileges=yes',
    'ProtectSystem=strict',
    '',
    '[Install]',
    'WantedBy=multi-user.target'
  ], Name, Ident)));

end;

{ the name of a unit the template makes, when the program would have that name too }
function ClashingUnit(const Kind, Ident: string): string;
var
  L: string;
begin
  Result := '';
  L := LowerCase(Ident);
  if (Kind = 'lib') or (Kind = 'api') then
    Exit;                 { a library has no program; the API's program is <name>_api }
  if Kind = 'site' then
  begin
    { the site's program is <name>_site }
    if L = 'webpages' then
      Result := 'WebPages';
    Exit;
  end;
  if L = 'appinfo' then
    Result := 'AppInfo'
  else if (Kind = 'console') and (L = 'greeting') then
    Result := 'Greeting'
  else if (Kind = 'service') and (L = 'inbox') then
    Result := 'Inbox'
  else if (Kind = 'app') and (L = 'home') then
    Result := 'Home';
end;

function CreateProject(const Kind, Name, ParentDir: string): Boolean;
var
  Dir, Ident: string;
begin
  Result := False;
  if not IsValidProjectName(Name) then
  begin
    Fail(Format('"%s" is not a valid project name', [Name]));
    Hint('start with a letter and use only letters, digits, "-" and "_", e.g. my-app');
    Exit;
  end;

  if (Kind <> 'console') and (Kind <> 'app') and (Kind <> 'lib') and (Kind <> 'service') and (Kind <> 'api') and
    (Kind <> 'site') then
  begin
    Fail(Format('unknown project kind "%s"', [Kind]));
    Hint('available kinds: console, app, lib, service, api, site');
    Exit;
  end;

  if ClashingUnit(Kind, StringReplace(Name, '-', '_', [rfReplaceAll])) <> '' then
  begin
    Fail(Format('"%s" is also the name of a unit in the new project (%s), so Pascal cannot tell them apart',
      [Name, ClashingUnit(Kind, StringReplace(Name, '-', '_', [rfReplaceAll]))]));
    Hint(Format('choose another name, e.g. my-%s', [Name]));
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(ParentDir) + Name;
  if DirectoryExists(Dir) and not DirIsEmpty(Dir) then
  begin
    Fail(Format('folder "%s" already exists and is not empty', [Name]));
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(Dir);
  Ident := StringReplace(Name, '-', '_', [rfReplaceAll]);

  if Kind = 'app' then
    WriteAppProject(Dir, Name, Ident)
  else if Kind = 'lib' then
    WriteLibProject(Dir, Name, Ident)
  else if Kind = 'service' then
    WriteServiceProject(Dir, Name, Ident)
  else if Kind = 'api' then
    WriteApiProject(Dir, Name, Ident)
  else if Kind = 'site' then
    WriteSiteProject(Dir, Name, Ident)
  else
    WriteConsoleProject(Dir, Name, Ident);
  WriteVSCodeFiles(Dir, Name, Ident, Kind);

  if Kind = 'lib' then
    Status('Created', Format('library "%s" (unit %s)', [Name, UnitNameFor(Name)]))
  else
    Status('Created', Format('%s project "%s"', [Kind, Name]));
  WriteLn;
  WriteLn('  Next steps:');
  WriteLn('    cd ', Name);
  if Kind = 'lib' then
    WriteLn('    pastel test')
  else
    WriteLn('    pastel run');
  WriteLn;
  Result := True;
end;

function CreateFormFiles(const Root, Name: string): Boolean;
var
  Dir, Base, Cls, Main, Src: string;
  L: TStringList;
  I, LastCreate, UsesEnd: Integer;
begin
  Result := False;
  Base := Name;
  if LowerCase(Copy(Base, Length(Base) - 3, 4)) = 'form' then
    Base := Copy(Base, 1, Length(Base) - 4);
  if (Base = '') or not IsValidProjectName(Base) or (Pos('-', Base) > 0) then
  begin
    Fail(Format('"%s" is not a good form name', [Name]));
    Hint('use letters and digits, like Settings or OrderDetails');
    Exit;
  end;
  Base := UpCase(Base[1]) + Copy(Base, 2, MaxInt);
  Cls := 'T' + Base + 'Form';
  Dir := IncludeTrailingPathDelimiter(Root) + 'src' + PathDelim + 'forms' + PathDelim;
  if FileExists(Dir + Base + '.pform') or FileExists(Dir + Base + '.pas') then
  begin
    Fail(Format('src/forms/%s.pform exists already', [Base]));
    Exit;
  end;
  if PhoneTemplates then
    WriteText(Dir + Base + '.pform',
      'object ' + Base + 'Form: ' + Cls + LineEnding +
      '  Title = ''' + Base + '''' + LineEnding +
      '  Width = 360' + LineEnding +
      '  Height = 640' + LineEnding +
      '  Padding = 16' + LineEnding +
      '  Gap = 12' + LineEnding +
      '  object MessageLabel: TLabel' + LineEnding +
      '    Text = ''' + Base + '''' + LineEnding +
      '    FontSize = 20' + LineEnding +
      '    WordWrap = True' + LineEnding +
      '  end' + LineEnding +
      '  object Space: TSpacer' + LineEnding +
      '  end' + LineEnding +
      '  object OkButton: TButton' + LineEnding +
      '    Height = 48' + LineEnding +
      '    Text = ''OK''' + LineEnding +
      '    ModalResult = mrOk' + LineEnding +
      '    Default = True' + LineEnding +
      '  end' + LineEnding +
      '  object CancelButton: TButton' + LineEnding +
      '    Height = 48' + LineEnding +
      '    Text = ''Cancel''' + LineEnding +
      '    Style = Secondary' + LineEnding +
      '    ModalResult = mrCancel' + LineEnding +
      '    Cancel = True' + LineEnding +
      '  end' + LineEnding +
      'end' + LineEnding)
  else
    WriteText(Dir + Base + '.pform',
      'object ' + Base + 'Form: ' + Cls + LineEnding +
      '  Title = ''' + Base + '''' + LineEnding +
      '  Width = 420' + LineEnding +
      '  Height = 240' + LineEnding +
      '  Layout = Free' + LineEnding +
      '  object MessageLabel: TLabel' + LineEnding +
      '    Left = 24' + LineEnding +
      '    Top = 24' + LineEnding +
      '    Width = 372' + LineEnding +
      '    Anchors = [Left, Top, Right]' + LineEnding +
      '    Text = ''' + Base + '''' + LineEnding +
      '    WordWrap = True' + LineEnding +
      '  end' + LineEnding +
      '  object CancelButton: TButton' + LineEnding +
      '    Left = 216' + LineEnding +
      '    Top = 176' + LineEnding +
      '    Width = 88' + LineEnding +
      '    Anchors = [Right, Bottom]' + LineEnding +
      '    Text = ''Cancel''' + LineEnding +
      '    Style = Secondary' + LineEnding +
      '    ModalResult = mrCancel' + LineEnding +
      '    Cancel = True' + LineEnding +
      '  end' + LineEnding +
      '  object OkButton: TButton' + LineEnding +
      '    Left = 312' + LineEnding +
      '    Top = 176' + LineEnding +
      '    Width = 84' + LineEnding +
      '    Anchors = [Right, Bottom]' + LineEnding +
      '    Text = ''OK''' + LineEnding +
      '    ModalResult = mrOk' + LineEnding +
      '    Default = True' + LineEnding +
      '  end' + LineEnding +
      'end' + LineEnding);
  WriteText(Dir + Base + '.pas',
    '{ The code of the ' + Base + ' form. Show it as a dialog:' + LineEnding + LineEnding +
    '    if ' + Base + 'Form.ShowModal = mrOk then ...' + LineEnding + LineEnding +
    '  The buttons close it with their ModalResult. }' + LineEnding +
    'unit ' + Base + ';' + LineEnding + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding + LineEnding +
    'interface' + LineEnding + LineEnding +
    'uses' + LineEnding +
    '  SysUtils, Pastel.UI, Pastel.Dialogs, ' + Base + '.g;' + LineEnding + LineEnding +
    'type' + LineEnding +
    '  ' + Cls + ' = class(' + Cls + 'Base)' + LineEnding +
    '  end;' + LineEnding + LineEnding +
    'var' + LineEnding +
    '  ' + Base + 'Form: ' + Cls + ';' + LineEnding + LineEnding +
    'implementation' + LineEnding + LineEnding +
    'end.' + LineEnding);
  Status('Created', Format('src/forms/%s.pform and %s.pas', [Base, Base]));

  { create it at the start, after the other forms }
  Main := IncludeTrailingPathDelimiter(Root) + 'src' + PathDelim + 'main.pas';
  if not FileExists(Main) then
    Exit(True);
  L := TStringList.Create;
  try
    L.LoadFromFile(Main);
    LastCreate := -1;
    UsesEnd := -1;
    for I := 0 to L.Count - 1 do
    begin
      if Pos('application.createform(', LowerCase(L[I])) > 0 then
        LastCreate := I;
      if (UsesEnd < 0) and (I > 0) and (Pos(';', L[I]) > 0) and (Pos('uses', LowerCase(Trim(L[I - 1]))) = 1) then
        UsesEnd := I;
    end;
    if (LastCreate < 0) or (UsesEnd < 0) then
    begin
      Hint(Format('add to main.pas: uses %s; and Application.CreateForm(%s, %sForm);', [Base, Cls, Base]));
      Exit(True);
    end;
    L.Insert(LastCreate + 1, Format('  Application.CreateForm(%s, %sForm);', [Cls, Base]));
    Src := L[UsesEnd];
    L[UsesEnd] := StringReplace(Src, ';', ', ' + Base + ';', []);
    L.SaveToFile(Main);
    Status('Updated', 'src/main.pas creates it');
  finally
    L.Free;
  end;
  Result := True;
end;

function CreateControlFile(const Root, Name: string): Boolean;
var
  Base, Cls, FileName: string;
begin
  Result := False;
  Base := Name;
  if (Length(Base) > 1) and (Base[1] = 'T') and (Base[2] in ['A'..'Z']) then
    Delete(Base, 1, 1);
  if (Base = '') or not IsValidProjectName(Base) or (Pos('-', Base) > 0) then
  begin
    Fail(Format('"%s" is not a good control name', [Name]));
    Hint('use letters and digits, like StarRating or ColorPicker');
    Exit;
  end;
  Base := UpCase(Base[1]) + Copy(Base, 2, MaxInt);
  Cls := 'T' + Base;
  FileName := IncludeTrailingPathDelimiter(Root) + 'src' + PathDelim + 'controls' + PathDelim + LowerCase(Base) + '.pas';
  if FileExists(FileName) then
  begin
    Fail(Format('src/controls/%s.pas exists already', [LowerCase(Base)]));
    Exit;
  end;
  WriteText(FileName, Fill([
    '{ {{name}} - a control of this project. Use it in .pform files like the',
    '  built-in ones (object Rating: {{ident}}); the designer shows it in its toolbox. }',
    'unit {{name}};',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'interface',
    '',
    'uses',
    '  Classes, SysUtils, Pastel.Graphics, Pastel.UI;',
    '',
    'type',
    '  {{ident}} = class(TControl)',
    '  private',
    '    FText: string;',
    '    FOnClick: TNotifyEvent;',
    '    procedure SetText(const AValue: string);',
    '  protected',
    '    { the size the control wants }',
    '    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;',
    '    procedure Paint(C: TCanvas32); override;',
    '    procedure MouseDown(X, Y: Integer); override;',
    '  published',
    '    { published properties can be set in .pform files and the designer }',
    '    property Text: string read FText write SetText;',
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure {{ident}}.SetText(const AValue: string);',
    'begin',
    '  FText := AValue;',
    '  Changed;          { the size may change: layout and paint again }',
    'end;',
    '',
    'procedure {{ident}}.Measure(AvailWidth: Integer; out W, H: Integer);',
    'begin',
    '  W := 160;',
    '  H := 40;',
    'end;',
    '',
    'procedure {{ident}}.Paint(C: TCanvas32);',
    'var',
    '  F: TPastelFont;',
    'begin',
    '  F := GetFont(Theme.FontSize);',
    '  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);',
    '  C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Theme.Border);',
    '  C.DrawText(F, Bounds.X + (Bounds.W - F.TextWidth(FText)) div 2,',
    '    Bounds.Y + (Bounds.H - F.LineHeight) div 2, FText, Theme.Text);',
    'end;',
    '',
    'procedure {{ident}}.MouseDown(X, Y: Integer);',
    'begin',
    '  if Assigned(FOnClick) then',
    '    FOnClick(Self);',
    'end;',
    '',
    'initialization',
    '  RegisterControl({{ident}});',
    'end.'], Base, Cls));
  Status('Created', Format('src/controls/%s.pas: use it in a form as "object My%s: %s"', [LowerCase(Base), Base, Cls]));
  Result := True;
end;

end.
