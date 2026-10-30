{ Pastel - project templates for "pastel new".
  Part of the Pastel project, MIT License. }
unit Pastel.Templates;

{$mode objfpc}{$H+}

interface

const
  ProjectKinds: array[0..4] of string = ('console', 'app', 'lib', 'service', 'server');

function CreateProject(const Kind, Name, ParentDir: string): Boolean;

implementation

uses
  Classes, SysUtils, Pastel.Console, Pastel.Project;

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
    'and `uses {{unit}};` in the code.'
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
    'On your computer:',
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

  WriteText(Dir + 'src' + PathDelim + 'forms' + PathDelim + 'Home.pform', Fill([
    '// The layout of the Home form. While the app runs with "pastel run",',
    '// save this file and the window updates immediately (hot reload).',
    'object HomeForm: THomeForm',
    '  Title = ''{{name}}''',
    '  Width = 460',
    '  Height = 340',
    '  object Card: TCard',
    '    object Heading: TLabel',
    '      Text = ''Hello!''',
    '      FontSize = 22',
    '      Bold = True',
    '    end',
    '    object Hint: TLabel',
    '      Text = ''Type your name and press Send.''',
    '      Color = ''#6B7080''',
    '    end',
    '    object NameEdit: TEdit',
    '      Placeholder = ''Your name''',
    '      OnSubmit = SendClick',
    '    end',
    '    object Buttons: TRow',
    '      Gap = 8',
    '      Justify = End',
    '      object ClearButton: TButton',
    '        Text = ''Clear''',
    '        Style = Secondary',
    '        OnClick = ClearClick',
    '      end',
    '      object SendButton: TButton',
    '        Text = ''Send''',
    '        OnClick = SendClick',
    '      end',
    '    end',
    '  end',
    '  object Greeting: TLabel',
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
    '  SysUtils, Pastel.UI, Home.g;',
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
    '- `src/forms/Home.pas` is its code (event handlers)'
  ], Name, Ident));
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

  if (Kind = 'server') or (Kind = 'api') then
  begin
    Fail(Format('"%s" projects are not available yet', [Kind]));
    Hint('web APIs come in a later Pastel version; available now: console, app, lib, service');
    Exit;
  end;
  if (Kind <> 'console') and (Kind <> 'app') and (Kind <> 'lib') and (Kind <> 'service') then
  begin
    Fail(Format('unknown project kind "%s"', [Kind]));
    Hint('available kinds: console, app, lib, service');
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

end.
