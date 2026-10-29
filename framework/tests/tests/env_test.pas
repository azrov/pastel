unit Env_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.Env, Pastel.Process;

type
  TEnvTests = class(TTestSuite)
  published
    procedure SetsAndReadsUtf8;
    procedure DefaultWhenMissing;
    procedure UnsetRemoves;
    procedure ListsVariables;
    procedure ChildProgramsSeeChanges;
  end;

implementation

procedure TEnvTests.SetsAndReadsUtf8;
begin
  SetEnv('PASTEL_ENV_TEST', 'çiçek ağacı');
  AssertEquals('çiçek ağacı', GetEnv('PASTEL_ENV_TEST'));
  AssertTrue(HasEnv('PASTEL_ENV_TEST'));
end;

procedure TEnvTests.DefaultWhenMissing;
begin
  AssertEquals('8080', GetEnv('PASTEL_ENV_NOT_SET', '8080'));
  AssertEquals('', GetEnv('PASTEL_ENV_NOT_SET'));
  AssertFalse(HasEnv('PASTEL_ENV_NOT_SET'));
end;

procedure TEnvTests.UnsetRemoves;
begin
  SetEnv('PASTEL_ENV_GONE', 'x');
  UnsetEnv('PASTEL_ENV_GONE');
  AssertFalse(HasEnv('PASTEL_ENV_GONE'));
end;

procedure TEnvTests.ListsVariables;
var
  S: string;
  Found: Boolean;
begin
  SetEnv('PASTEL_ENV_LISTED', 'şeker');
  Found := False;
  for S in EnvList do
    if S = 'PASTEL_ENV_LISTED=şeker' then
      Found := True;
  AssertTrue(Found);
end;

procedure TEnvTests.ChildProgramsSeeChanges;
var
  Opts: TRunOptions;
begin
  SetEnv('PASTEL_ENV_CHILD', 'gül');
  Opts := Default(TRunOptions);
  Opts.Env := ['PASTEL_PROCESS_HELPER=env'];
  AssertEquals('gül', Run(ParamStr(0), ['PASTEL_ENV_CHILD'], Opts).Text);
end;

initialization
  RegisterTests(TEnvTests);
end.
