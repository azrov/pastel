unit Crypto_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Testing, Pastel.Crypto, Pastel.Jwt, Pastel.Json;

type
  TCryptoTests = class(TTestSuite)
  private
    procedure VerifyNone;
    procedure VerifyExpired;
  published
    procedure Sha256Vectors;
    procedure HmacVector;
    procedure Pbkdf2Vectors;
    procedure Base64Url;
    procedure RandomTokensDiffer;
    procedure ComparesSecrets;
    procedure HashesPasswords;
    procedure SignsAndVerifiesJwt;
    procedure RejectsChangedJwt;
    procedure RejectsAlgorithmNone;
    procedure RejectsExpiredJwt;
  end;

implementation

const
  Secret = 'a-long-random-secret-for-tests';

procedure TCryptoTests.Sha256Vectors;
begin
  AssertEquals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', Sha256Hex('abc'));
  AssertEquals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', Sha256Hex(''));
  AssertEquals('cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    Sha256Hex(StringOfChar('a', 1000000)));
end;

procedure TCryptoTests.HmacVector;
begin
  { RFC 4231, test case 2 }
  AssertEquals('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    ToHex(HmacSha256('Jefe', 'what do ya want for nothing?')));
end;

procedure TCryptoTests.Pbkdf2Vectors;
begin
  AssertEquals('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    ToHex(Pbkdf2Sha256('password', 'salt', 1, 32)));
  AssertEquals('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    ToHex(Pbkdf2Sha256('password', 'salt', 4096, 32)));
end;

procedure TCryptoTests.Base64Url;
begin
  AssertEquals('-_8', Base64UrlEncode(#$FB#$FF));
  AssertEquals(#$FB#$FF, Base64UrlDecode('-_8'));
  AssertEquals('aGVsbG8', Base64UrlEncode('hello'));
end;

procedure TCryptoTests.RandomTokensDiffer;
begin
  AssertEquals(43, Length(RandomToken));
  AssertNotEquals(RandomToken, RandomToken);
  AssertEquals(16, Length(RandomBytes(16)));
end;

procedure TCryptoTests.ComparesSecrets;
begin
  AssertTrue(SameSecret('abc', 'abc'));
  AssertFalse(SameSecret('abc', 'abd'));
  AssertFalse(SameSecret('abc', 'abcd'));
  AssertFalse(SameSecret('', 'a'));
end;

procedure TCryptoTests.HashesPasswords;
var
  H: string;
begin
  H := HashPassword('gizli şifre', 1000);
  AssertStartsWith('pbkdf2-sha256$1000$', H);
  AssertTrue(VerifyPassword('gizli şifre', H));
  AssertFalse(VerifyPassword('gizli sifre', H));
  AssertNotEquals(H, HashPassword('gizli şifre', 1000), 'a new salt every time');
  AssertFalse(VerifyPassword('x', 'plain-text'));
  AssertFalse(VerifyPassword('x', 'pbkdf2-sha256$0$abc$abc'));
end;

procedure TCryptoTests.SignsAndVerifiesJwt;
var
  Token: string;
  C: TJSONObject;
begin
  Token := JwtSign(JObject(['sub', 'ayşe', 'role', 'admin']), Secret, 60);
  AssertEquals(3, Length(Token.Split(['.'])));
  C := JwtVerify(Token, Secret);
  try
    AssertEquals('ayşe', JStr(C, 'sub'));
    AssertEquals('admin', JStr(C, 'role'));
    AssertTrue(JInt(C, 'exp') > JInt(C, 'iat'));
  finally
    C.Free;
  end;
end;

procedure TCryptoTests.RejectsChangedJwt;
var
  Token: string;
  Parts: TStringArray;
begin
  Token := JwtSign(JObject(['role', 'user']), Secret, 60);
  Parts := Token.Split(['.']);
  try
    JwtVerify(Parts[0] + '.' + Base64UrlEncode('{"role":"admin"}') + '.' + Parts[2], Secret).Free;
    Fail('a changed token was accepted');
  except
    on E: EJwtError do
      AssertEquals('the JWT signature is wrong', E.Message);
  end;
  try
    JwtVerify(Token, 'another secret').Free;
    Fail('a token with another secret was accepted');
  except
    on E: EJwtError do ;
  end;
end;

procedure TCryptoTests.VerifyNone;
begin
  JwtVerify(Base64UrlEncode('{"alg":"none"}') + '.' + Base64UrlEncode('{"role":"admin"}') + '.', Secret);
end;

procedure TCryptoTests.RejectsAlgorithmNone;
begin
  AssertRaises(EJwtError, @VerifyNone);
end;

procedure TCryptoTests.VerifyExpired;
var
  Head, Body: string;
begin
  Head := Base64UrlEncode('{"alg":"HS256","typ":"JWT"}');
  Body := Base64UrlEncode('{"sub":"x","exp":1000000000}');
  JwtVerify(Head + '.' + Body + '.' + Base64UrlEncode(HmacSha256(Secret, Head + '.' + Body)), Secret);
end;

procedure TCryptoTests.RejectsExpiredJwt;
begin
  try
    VerifyExpired;
    Fail('an expired token was accepted');
  except
    on E: EJwtError do
      AssertEquals('the JWT has expired', E.Message);
  end;
end;

initialization
  RegisterTests(TCryptoTests);
end.
