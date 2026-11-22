unit Args_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.Args;

type
  TArgsTests = class(TTestSuite)
  private
    FArgs: TArgs;
    FError: string;
    function Parse(const Words: array of string): Boolean;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure FlagsAndOptions;
    procedure DefaultsWhenNotGiven;
    procedure ValueFormsLongAndShort;
    procedure CombinedShortFlags;
    procedure RepeatedOptions;
    procedure PositionalArguments;
    procedure DoubleDashEndsOptions;
    procedure MissingPositionalIsAnError;
    procedure UnknownOptionSuggestsName;
    procedure IntegerRangeIsChecked;
    procedure ChoicesAreChecked;
    procedure OptionNeedsValue;
    procedure FlagRejectsValue;
    procedure OptionGivenTwiceIsAnError;
    procedure EnvironmentVariableFallback;
    procedure HelpWinsOverMissingArguments;
    procedure HelpTextListsEverything;
    procedure SubCommands;
    procedure UnknownCommandSuggestsName;
    procedure GlobalOptionsWorkInCommands;
    procedure LevenshteinDistance;
  end;

implementation

procedure TArgsTests.SetUp;
begin
  FArgs := TArgs.Create('tool', 'A tool.');
  FArgs.Version := '1.0';
  FArgs.Flag('verbose', 'v', 'More output');
  FArgs.Flag('quiet', 'q', 'Less output');
  FArgs.Option('output', 'o', 'Where to write', 'out.txt');
  FArgs.Option('level', 'l', 'Level').IntRange(1, 9).Default('5');
  FArgs.Option('format', '', 'Format').Choices(['json', 'text']);
  FArgs.Option('tag', 't', 'Tags').Many;
  FArgs.Option('token', '', 'Token').Env('PASTEL_ARGS_TEST_TOKEN');
  FArgs.Positional('input', 'File to read');
  FArgs.Positional('more', 'More files').Many.Optional;
end;

procedure TArgsTests.TearDown;
begin
  FArgs.Free;
end;

function TArgsTests.Parse(const Words: array of string): Boolean;
begin
  FError := '';
  try
    FArgs.ParseFrom(Words);
    Result := True;
  except
    on E: EArgsError do
    begin
      FError := E.Message;
      Result := False;
    end;
  end;
end;

procedure TArgsTests.FlagsAndOptions;
begin
  AssertTrue(Parse(['-v', '--output', 'a.txt', 'in.txt']), FError);
  AssertTrue(FArgs.Has('verbose'));
  AssertFalse(FArgs.Has('quiet'));
  AssertEquals('a.txt', FArgs.Get('output'));
  AssertEquals('in.txt', FArgs.Get('input'));
end;

procedure TArgsTests.DefaultsWhenNotGiven;
begin
  AssertTrue(Parse(['in.txt']), FError);
  AssertEquals('out.txt', FArgs.Get('output'));
  AssertEquals(5, FArgs.GetInt('level'));
  AssertFalse(FArgs.Has('output'), 'a default does not count as given');
  AssertEquals('', FArgs.Get('format'));
end;

procedure TArgsTests.ValueFormsLongAndShort;
begin
  AssertTrue(Parse(['--output=a', '-l7', 'in']), FError);
  AssertEquals('a', FArgs.Get('output'));
  AssertEquals(7, FArgs.GetInt('level'));
  AssertTrue(Parse(['-o', 'b', '-l=2', 'in']), FError);
  AssertEquals('b', FArgs.Get('output'));
  AssertEquals(2, FArgs.GetInt('level'));
end;

procedure TArgsTests.CombinedShortFlags;
begin
  AssertTrue(Parse(['-vq', 'in']), FError);
  AssertTrue(FArgs.Has('verbose') and FArgs.Has('quiet'));
  AssertTrue(Parse(['-vvv', 'in']), FError);
  AssertEquals(3, FArgs.Count('verbose'));
end;

procedure TArgsTests.RepeatedOptions;
var
  Tags: TStringArray;
begin
  AssertTrue(Parse(['-t', 'a', '--tag=b', 'in']), FError);
  Tags := FArgs.GetAll('tag');
  AssertEquals(2, Length(Tags));
  AssertEquals('a', Tags[0]);
  AssertEquals('b', Tags[1]);
end;

procedure TArgsTests.PositionalArguments;
var
  More: TStringArray;
begin
  AssertTrue(Parse(['in', 'x', '-v', 'y']), FError);
  AssertEquals('in', FArgs.Get('input'));
  More := FArgs.GetAll('more');
  AssertEquals(2, Length(More));
  AssertEquals('y', More[1]);
end;

procedure TArgsTests.DoubleDashEndsOptions;
begin
  AssertTrue(Parse(['--', '-v']), FError);
  AssertEquals('-v', FArgs.Get('input'));
  AssertFalse(FArgs.Has('verbose'));
end;

procedure TArgsTests.MissingPositionalIsAnError;
begin
  AssertFalse(Parse(['-v']));
  AssertEquals('missing argument <input>: File to read', FError);
end;

procedure TArgsTests.UnknownOptionSuggestsName;
begin
  AssertFalse(Parse(['--outptu', 'x', 'in']));
  AssertEquals('unknown option "--outptu" (did you mean --output?)', FError);
  AssertFalse(Parse(['-z', 'in']));
  AssertEquals('unknown option "-z"', FError);
end;

procedure TArgsTests.IntegerRangeIsChecked;
begin
  AssertFalse(Parse(['-l', '12', 'in']));
  AssertEquals('--level must be between 1 and 9, got 12', FError);
  AssertFalse(Parse(['-l', 'x', 'in']));
  AssertContains('expects a whole number', FError);
end;

procedure TArgsTests.ChoicesAreChecked;
begin
  AssertTrue(Parse(['--format', 'json', 'in']), FError);
  AssertFalse(Parse(['--format', 'xml', 'in']));
  AssertEquals('--format must be one of: json, text (got "xml")', FError);
end;

procedure TArgsTests.OptionNeedsValue;
begin
  AssertFalse(Parse(['in', '--output']));
  AssertEquals('--output needs a value (OUTPUT)', FError);
end;

procedure TArgsTests.FlagRejectsValue;
begin
  AssertFalse(Parse(['--verbose=yes', 'in']));
  AssertEquals('--verbose does not take a value', FError);
end;

procedure TArgsTests.OptionGivenTwiceIsAnError;
begin
  AssertFalse(Parse(['-o', 'a', '-o', 'b', 'in']));
  AssertEquals('--output is given more than once', FError);
end;

procedure TArgsTests.EnvironmentVariableFallback;
begin
  { tests/run.sh sets PASTEL_ARGS_TEST_TOKEN=secret }
  if GetEnvironmentVariable('PASTEL_ARGS_TEST_TOKEN') = '' then
    Skip('run with PASTEL_ARGS_TEST_TOKEN=secret');
  AssertTrue(Parse(['in']), FError);
  AssertEquals('secret', FArgs.Get('token'));
  AssertTrue(Parse(['--token', 'given', 'in']), FError);
  AssertEquals('given', FArgs.Get('token'), 'the command line wins');
end;

procedure TArgsTests.HelpWinsOverMissingArguments;
begin
  AssertTrue(Parse(['--help']), FError);
  AssertTrue(FArgs.HelpWanted);
  AssertTrue(Parse(['--version']), FError);
  AssertTrue(FArgs.VersionWanted);
end;

procedure TArgsTests.HelpTextListsEverything;
var
  H: string;
begin
  H := FArgs.HelpText;
  AssertContains('Usage: tool [options] <input> [<more>...]', H);
  AssertContains('-o, --output OUTPUT', H);
  AssertContains('(default: out.txt)', H);
  AssertContains('[1-9]', H);
  AssertContains('[json|text]', H);
  AssertContains('(env: PASTEL_ARGS_TEST_TOKEN)', H);
  AssertContains('--version', H);
end;

procedure TArgsTests.SubCommands;
var
  A: TArgs;
begin
  A := TArgs.Create('todo', '');
  try
    with A.Command('add', 'Add') do
    begin
      Positional('title', 'Title');
      Option('priority', 'p', 'Priority', 'normal');
    end;
    A.Command('list', 'List').Flag('all', 'a', 'All');
    A.ParseFrom(['add', 'Buy milk', '-p', 'high']);
    AssertEquals('add', A.CommandName);
    AssertEquals('Buy milk', A.Get('title'));
    AssertEquals('high', A.Get('priority'));
    A.ParseFrom(['list', '-a']);
    AssertEquals('list', A.CommandName);
    AssertTrue(A.Has('all'));
  finally
    A.Free;
  end;
end;

procedure TArgsTests.UnknownCommandSuggestsName;
var
  A: TArgs;
begin
  A := TArgs.Create('todo', '');
  try
    A.Command('list', 'List');
    try
      A.ParseFrom(['lst']);
      Fail('expected an error');
    except
      on E: EArgsError do
        AssertEquals('unknown command "lst" (did you mean "list"?)', E.Message);
    end;
    try
      A.ParseFrom([]);
      Fail('expected an error');
    except
      on E: EArgsError do
        AssertEquals('a command is needed', E.Message);
    end;
  finally
    A.Free;
  end;
end;

procedure TArgsTests.GlobalOptionsWorkInCommands;
var
  A: TArgs;
begin
  A := TArgs.Create('todo', '');
  try
    A.Option('file', '', 'File', 'tasks.txt');
    A.Command('list', 'List');
    A.ParseFrom(['list', '--file', 'x.txt']);
    AssertEquals('x.txt', A.Get('file'));
    A.ParseFrom(['--file=y.txt', 'list']);
    AssertEquals('y.txt', A.Get('file'));
  finally
    A.Free;
  end;
end;

procedure TArgsTests.LevenshteinDistance;
begin
  AssertEquals(0, Levenshtein('output', 'OUTPUT'));
  AssertEquals(2, Levenshtein('outptu', 'output'));
  AssertEquals(3, Levenshtein('kitten', 'sitting'));
end;

initialization
  RegisterTests(TArgsTests);
end.
