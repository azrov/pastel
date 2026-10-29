unit Config_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Config;

type
  TConfigTests = class(TTestSuite)
  private
    FDir: string;
    FConfig: TConfig;
    function WriteFile(const Name, Text: string): string;
    procedure LoadBroken;
    procedure LoadMissing;
    procedure RequireMissing;
    procedure GetBadInt;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ReadsToml;
    procedure ReadsJson;
    procedure LaterFilesWin;
    procedure DefaultsDoNotOverrideFiles;
    procedure SetValueWinsOverEverything;
    procedure EnvironmentOverridesFiles;
    procedure ListsFromFilesAndText;
    procedure BooleansInManyForms;
    procedure TellsWhereAValueCameFrom;
    procedure BrokenFileSaysFileAndLine;
    procedure MissingFileIsAnError;
    procedure RequireExplainsHowToSetIt;
    procedure WrongTypeNamesTheSource;
    procedure ListsKeys;
  end;

implementation

procedure TConfigTests.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'pastel-config-test' + PathDelim;
  ForceDirectories(FDir);
  FConfig := TConfig.Create('fwtest');
end;

procedure TConfigTests.TearDown;
var
  SR: TSearchRec;
begin
  FConfig.Free;
  if FindFirst(FDir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
        DeleteFile(FDir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(FDir);
end;

function TConfigTests.WriteFile(const Name, Text: string): string;
var
  L: TStringList;
begin
  Result := FDir + Name;
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

procedure TConfigTests.ReadsToml;
begin
  FConfig.LoadFile(WriteFile('a.toml',
    'name = "demo"' + LineEnding +
    '[server]' + LineEnding +
    'port = 8080' + LineEnding +
    'ratio = 0.75' + LineEnding +
    '[database]' + LineEnding +
    'host = "db.local"   # comment'));
  AssertEquals('demo', FConfig.Get('name'));
  AssertEquals(8080, FConfig.GetInt('server.port'));
  AssertEquals(0.75, FConfig.GetFloat('server.ratio'), 1E-9);
  AssertEquals('db.local', FConfig.Get('database.host'));
  AssertEquals('x', FConfig.Get('database.user', 'x'));
  AssertTrue(FConfig.Has('server.port'));
  AssertFalse(FConfig.Has('server.missing'));
end;

procedure TConfigTests.ReadsJson;
begin
  FConfig.LoadFile(WriteFile('a.json',
    '{"server": {"port": 9000, "tls": true}, "admins": ["ali", "ayşe"],' +
    ' "routes": [{"path": "/a"}, {"path": "/b"}]}'));
  AssertEquals(9000, FConfig.GetInt('server.port'));
  AssertTrue(FConfig.GetBool('server.tls'));
  AssertEquals(2, Length(FConfig.GetList('admins')));
  AssertEquals('ayşe', FConfig.GetList('admins')[1]);
  AssertEquals('/b', FConfig.Get('routes[1].path'));
end;

procedure TConfigTests.LaterFilesWin;
begin
  FConfig.LoadFile(WriteFile('a.toml', '[server]' + LineEnding + 'port = 1' + LineEnding + 'host = "a"'));
  FConfig.LoadFile(WriteFile('b.toml', '[server]' + LineEnding + 'port = 2'));
  AssertEquals(2, FConfig.GetInt('server.port'));
  AssertEquals('a', FConfig.Get('server.host'), 'values not in the later file stay');
  AssertEquals(2, FConfig.Files.Count);
end;

procedure TConfigTests.DefaultsDoNotOverrideFiles;
begin
  FConfig.SetDefault('server.port', '80');
  FConfig.SetDefault('server.host', 'localhost');
  FConfig.LoadFile(WriteFile('a.toml', '[server]' + LineEnding + 'port = 8080'));
  FConfig.SetDefault('server.port', '81');
  AssertEquals(8080, FConfig.GetInt('server.port'));
  AssertEquals('localhost', FConfig.Get('server.host'));
end;

procedure TConfigTests.SetValueWinsOverEverything;
begin
  FConfig.LoadFile(WriteFile('a.toml', '[server]' + LineEnding + 'port = 8080'));
  FConfig.SetValue('server.port', '1234');
  AssertEquals(1234, FConfig.GetInt('server.port'));
  AssertEquals('set in code', FConfig.Source('server.port'));
end;

procedure TConfigTests.EnvironmentOverridesFiles;
begin
  { tests/run.sh sets FWTEST_SERVER_PORT=9090 and FWTEST_FEATURES="a, b" }
  if GetEnvironmentVariable('FWTEST_SERVER_PORT') = '' then
    Skip('run with FWTEST_SERVER_PORT=9090');
  FConfig.LoadFile(WriteFile('a.toml', '[server]' + LineEnding + 'port = 8080'));
  AssertEquals(8080, FConfig.GetInt('server.port'), 'not before LoadEnv');
  FConfig.LoadEnv;
  AssertEquals(9090, FConfig.GetInt('server.port'));
  AssertEquals('environment FWTEST_SERVER_PORT', FConfig.Source('server.port'));
  AssertEquals(2, Length(FConfig.GetList('features')), 'comma-separated list');
  AssertEquals('b', FConfig.GetList('features')[1]);
end;

procedure TConfigTests.ListsFromFilesAndText;
begin
  FConfig.LoadFile(WriteFile('a.toml', 'hosts = ["a", "b", "c"]' + LineEnding + 'one = "x, y"'));
  AssertEquals(3, Length(FConfig.GetList('hosts')));
  AssertEquals('y', FConfig.GetList('one')[1]);
  AssertEquals(0, Length(FConfig.GetList('missing')));
end;

procedure TConfigTests.BooleansInManyForms;
begin
  FConfig.SetValue('a', 'yes');
  FConfig.SetValue('b', 'Off');
  FConfig.SetValue('c', '1');
  AssertTrue(FConfig.GetBool('a'));
  AssertFalse(FConfig.GetBool('b'));
  AssertTrue(FConfig.GetBool('c'));
  AssertTrue(FConfig.GetBool('missing', True));
end;

procedure TConfigTests.TellsWhereAValueCameFrom;
var
  F: string;
begin
  F := WriteFile('a.toml', 'x = 1');
  FConfig.SetDefault('y', '2');
  FConfig.LoadFile(F);
  AssertEquals(F, FConfig.Source('x'));
  AssertEquals('default', FConfig.Source('y'));
  AssertEquals('', FConfig.Source('z'));
end;

procedure TConfigTests.LoadBroken;
begin
  FConfig.LoadFile(WriteFile('bad.toml', '[server]' + LineEnding + 'port = 80' + LineEnding + 'host = localhost'));
end;

procedure TConfigTests.BrokenFileSaysFileAndLine;
begin
  try
    LoadBroken;
    Fail('expected an error');
  except
    on E: EConfigError do
    begin
      AssertContains('bad.toml, line 3', E.Message);
      AssertContains('strings need quotes', E.Message);
    end;
  end;
end;

procedure TConfigTests.LoadMissing;
begin
  FConfig.LoadFile(FDir + 'nope.toml');
end;

procedure TConfigTests.MissingFileIsAnError;
begin
  AssertRaises(EConfigError, @LoadMissing);
  AssertFalse(FConfig.LoadFileIfExists(FDir + 'nope.toml'));
end;

procedure TConfigTests.RequireMissing;
begin
  FConfig.Require('database.password');
end;

procedure TConfigTests.RequireExplainsHowToSetIt;
begin
  FConfig.LoadEnv;
  try
    RequireMissing;
    Fail('expected an error');
  except
    on E: EConfigError do
      AssertEquals('missing setting "database.password": add [database] password = ... ' +
        'to config.toml, or set FWTEST_DATABASE_PASSWORD', E.Message);
  end;
  FConfig.SetValue('database.password', 's3cret');
  AssertEquals('s3cret', FConfig.Require('database.password'));
end;

procedure TConfigTests.GetBadInt;
begin
  FConfig.GetInt('server.port');
end;

procedure TConfigTests.WrongTypeNamesTheSource;
begin
  FConfig.LoadFile(WriteFile('a.toml', '[server]' + LineEnding + 'port = "eighty"'));
  try
    GetBadInt;
    Fail('expected an error');
  except
    on E: EConfigError do
      AssertEquals(Format('setting "server.port" must be a whole number, got "eighty" (from %sa.toml)', [FDir]),
        E.Message);
  end;
end;

procedure TConfigTests.ListsKeys;
var
  K: TStringArray;
begin
  FConfig.SetDefault('b', '1');
  FConfig.SetValue('a', '2');
  K := FConfig.Keys;
  AssertEquals(2, Length(K));
  AssertEquals('a', K[0]);
end;

initialization
  RegisterTests(TConfigTests);
end.
