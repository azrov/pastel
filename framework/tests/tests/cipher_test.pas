{ Tests of Pastel.Cipher: NIST's AES-GCM vectors, sealing with a password. }
unit cipher_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Crypto, Pastel.Cipher;

type
  TCipherTests = class(TTestSuite)
  published
    procedure NistVectors;
    procedure RoundTripAndTampering;
    procedure TextWithAPassword;
  end;

implementation

function Hex(const S: string): RawByteString;
var
  I: Integer;
begin
  SetLength(Result, Length(S) div 2);
  for I := 1 to Length(S) div 2 do
    Result[I] := Chr(StrToInt('$' + Copy(S, I * 2 - 1, 2)));
end;

procedure TCipherTests.NistVectors;
var
  K: RawByteString;
begin
  { test case 14: zero key, zero nonce, a zero block }
  AssertEquals('cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919',
    ToHex(AesGcmSeal(StringOfChar(#0, 32), StringOfChar(#0, 12), StringOfChar(#0, 16), '')));
  { test case 16: with data checked too }
  K := Hex('feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308');
  AssertEquals('522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b',
    ToHex(AesGcmSeal(K, Hex('cafebabefacedbaddecaf888'),
    Hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39'),
    Hex('feedfacedeadbeeffeedfacedeadbeefabaddad2'))));
end;

procedure TCipherTests.RoundTripAndTampering;
var
  K, D, Bad: RawByteString;
begin
  K := RandomBytes(32);
  D := AesGcmEncrypt(K, 'hello, world');
  AssertEquals('hello, world', AesGcmDecrypt(K, D));
  AssertFalse(D = AesGcmEncrypt(K, 'hello, world'), 'a new nonce every time');
  Bad := D;
  Bad[20] := Chr(Ord(Bad[20]) xor 1);
  try
    AesGcmDecrypt(K, Bad);
    Fail('a changed byte');
  except
    on E: ECipherError do ;
  end;
  try
    AesGcmDecrypt(RandomBytes(32), D);
    Fail('another key');
  except
    on E: ECipherError do ;
  end;
end;

procedure TCipherTests.TextWithAPassword;
var
  S: string;
begin
  S := EncryptText('pa55', 'IBAN TR12 ğüşiöç', 1000);
  AssertTrue(Copy(S, 1, 8) = 'v1.1000.', S);
  AssertEquals('IBAN TR12 ğüşiöç', DecryptText('pa55', S));
  try
    DecryptText('wrong', S);
    Fail('a wrong password');
  except
    on E: ECipherError do ;
  end;
  try
    DecryptText('pa55', 'nonsense');
    Fail('not sealed text');
  except
    on E: ECipherError do ;
  end;
end;

initialization
  RegisterTests(TCipherTests);

end.
