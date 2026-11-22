{ Tests of Pastel.SecureStore with its file (PASTEL_SECURE_DIR). }
unit securestore_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.SecureStore;

type
  TSecureStoreTests = class(TTestSuite)
  published
    procedure KeptAndGone;
  end;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF} Pastel.Env, Pastel.Files;

procedure TSecureStoreTests.KeptAndGone;
var
  Dir: string;
  {$IFDEF UNIX}
  St: Stat;
  {$ENDIF}
begin
  Dir := MakeTempDir('pastel-secure');
  SetEnv('PASTEL_SECURE_DIR', Dir);
  try
    AssertEquals('file', SecureStoreKind);
    AssertFalse(SecureHas('token'));
    AssertEquals('none', SecureGet('token', 'none'));
    SecureSet('token', 'abc=def'#10'ğüş');
    AssertTrue(SecureHas('token'));
    AssertEquals('abc=def'#10'ğüş', SecureGet('token'));
    SecureSet('token', 'new');
    AssertEquals('new', SecureGet('token'));
    {$IFDEF UNIX}
    AssertEquals(0, fpStat(JoinPath([Dir, 'secrets']), St));
    AssertEquals(&600, St.st_mode and &777, 'only the user reads it');
    {$ENDIF}
    SecureDelete('token');
    AssertFalse(SecureHas('token'));
    try
      SecureSet('a=b', 'x');
      Fail('a name with =');
    except
      on E: ESecureStoreError do ;
    end;
  finally
    UnsetEnv('PASTEL_SECURE_DIR');
    DeleteDir(Dir);
  end;
end;

initialization
  RegisterTests(TSecureStoreTests);

end.
