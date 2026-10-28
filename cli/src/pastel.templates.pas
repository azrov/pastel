{ Pastel - project templates for "pastel new".
  Part of the Pastel project, MIT License. }
unit Pastel.Templates;

{$mode objfpc}{$H+}

interface

const
  ProjectKinds: array[0..2] of string = ('console', 'app', 'server');

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
    'program {{ident}};',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses',
    '  SysUtils, Greeting;',
    '',
    'var',
    '  Who: string;',
    'begin',
    '  if ParamCount > 0 then',
    '    Who := ParamStr(1)',
    '  else',
    '    Who := ''world'';',
    '  WriteLn(MakeGreeting(Who));',
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
procedure WriteVSCodeFiles(const Dir, Name, Ident: string);
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
    '      "label": "pastel: run",',
    '      "type": "shell",',
    '      "command": "pastel",',
    '      "args": ["run"],',
    '      "options": { "env": { "NO_COLOR": "1" } },',
    '      "problemMatcher": []',
    '    }',
    '  ]',
    '}'
  ], Name, Ident));

  WriteText(V + 'launch.json', Fill([
    '{',
    '  "version": "0.2.0",',
    '  "configurations": [',
    '    {',
    '      "name": "Debug {{name}}",',
    '      "type": "cppdbg",',
    '      "request": "launch",',
    '      "program": "${workspaceFolder}/build/linux/debug/{{name}}",',
    '      "windows": { "program": "${workspaceFolder}/build/windows/debug/{{name}}.exe" },',
    '      "cwd": "${workspaceFolder}",',
    '      "MIMode": "gdb",',
    '      "externalConsole": false,',
    '      "preLaunchTask": "pastel: build"',
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
    '  "files.watcherExclude": { "**/build/**": true }',
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

  if Kind = 'server' then
  begin
    Fail('"server" projects are not available yet');
    Hint('this is coming in a later Pastel version; available now: console, app');
    Exit;
  end;
  if (Kind <> 'console') and (Kind <> 'app') then
  begin
    Fail(Format('unknown project kind "%s"', [Kind]));
    Hint('available kinds: console, app');
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
  else
    WriteConsoleProject(Dir, Name, Ident);
  WriteVSCodeFiles(Dir, Name, Ident);

  Status('Created', Format('%s project "%s"', [Kind, Name]));
  WriteLn;
  WriteLn('  Next steps:');
  WriteLn('    cd ', Name);
  WriteLn('    pastel run');
  WriteLn;
  Result := True;
end;

end.
