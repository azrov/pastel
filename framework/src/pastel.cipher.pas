(* Pastel - encryption: AES-256-GCM, and text sealed with a password.

    Sealed := EncryptText(Password, 'IBAN TR12 0006 ...');   // 'v1.' + base64url
    Plain := DecryptText(Password, Sealed);                   // ECipherError: wrong password or changed
    Data := AesGcmEncrypt(Key, Bytes);                        // Key: 32 bytes (RandomBytes(32))
    Bytes := AesGcmDecrypt(Key, Data);

  AES-256 in GCM mode (NIST SP 800-38D): a new random nonce every time, a
  tag that finds any change. EncryptText makes the key from the password
  with PBKDF2-SHA256 and a random salt. All in Pascal, no OpenSSL.
  Part of the Pastel project, MIT License. *)
unit Pastel.Cipher;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  ECipherError = class(Exception);

{ Key: 32 bytes. The answer: a 12-byte nonce, the cipher text, a 16-byte tag.
  Aad: data that is checked (not encrypted) with it. }
function AesGcmEncrypt(const Key, Plain: RawByteString; const Aad: RawByteString = ''): RawByteString;
{ ECipherError when the key is wrong or the data was changed }
function AesGcmDecrypt(const Key, Data: RawByteString; const Aad: RawByteString = ''): RawByteString;
{ The same with the nonce given (tests, protocols that set it): no nonce in the answer. }
function AesGcmSeal(const Key, Nonce, Plain, Aad: RawByteString): RawByteString;
function AesGcmOpen(const Key, Nonce, Sealed, Aad: RawByteString): RawByteString;

{ Text sealed with a password: 'v1.' and base64url (salt, nonce, text, tag). }
function EncryptText(const Password, Text: string; Iterations: Integer = 100000): string;
function DecryptText(const Password, Sealed: string): string;

implementation

uses
  Pastel.Crypto;

{ ---------------- AES (FIPS 197) ---------------- }

const
  SBox: array[0..255] of Byte = (
    $63, $7c, $77, $7b, $f2, $6b, $6f, $c5, $30, $01, $67, $2b, $fe, $d7, $ab, $76,
    $ca, $82, $c9, $7d, $fa, $59, $47, $f0, $ad, $d4, $a2, $af, $9c, $a4, $72, $c0,
    $b7, $fd, $93, $26, $36, $3f, $f7, $cc, $34, $a5, $e5, $f1, $71, $d8, $31, $15,
    $04, $c7, $23, $c3, $18, $96, $05, $9a, $07, $12, $80, $e2, $eb, $27, $b2, $75,
    $09, $83, $2c, $1a, $1b, $6e, $5a, $a0, $52, $3b, $d6, $b3, $29, $e3, $2f, $84,
    $53, $d1, $00, $ed, $20, $fc, $b1, $5b, $6a, $cb, $be, $39, $4a, $4c, $58, $cf,
    $d0, $ef, $aa, $fb, $43, $4d, $33, $85, $45, $f9, $02, $7f, $50, $3c, $9f, $a8,
    $51, $a3, $40, $8f, $92, $9d, $38, $f5, $bc, $b6, $da, $21, $10, $ff, $f3, $d2,
    $cd, $0c, $13, $ec, $5f, $97, $44, $17, $c4, $a7, $7e, $3d, $64, $5d, $19, $73,
    $60, $81, $4f, $dc, $22, $2a, $90, $88, $46, $ee, $b8, $14, $de, $5e, $0b, $db,
    $e0, $32, $3a, $0a, $49, $06, $24, $5c, $c2, $d3, $ac, $62, $91, $95, $e4, $79,
    $e7, $c8, $37, $6d, $8d, $d5, $4e, $a9, $6c, $56, $f4, $ea, $65, $7a, $ae, $08,
    $ba, $78, $25, $2e, $1c, $a6, $b4, $c6, $e8, $dd, $74, $1f, $4b, $bd, $8b, $8a,
    $70, $3e, $b5, $66, $48, $03, $f6, $0e, $61, $35, $57, $b9, $86, $c1, $1d, $9e,
    $e1, $f8, $98, $11, $69, $d9, $8e, $94, $9b, $1e, $87, $e9, $ce, $55, $28, $df,
    $8c, $a1, $89, $0d, $bf, $e6, $42, $68, $41, $99, $2d, $0f, $b0, $54, $bb, $16);

type
  TBlock = array[0..15] of Byte;
  TRoundKeys = array[0..239] of Byte;      { 15 round keys of AES-256 }

function XTime(B: Byte): Byte; inline;
begin
  Result := Byte((B shl 1) xor (((B shr 7) and 1) * $1b));
end;

procedure ExpandKey(const Key: RawByteString; out RK: TRoundKeys);
const
  Rcon: array[1..7] of Byte = ($01, $02, $04, $08, $10, $20, $40);
var
  I: Integer;
  T: array[0..3] of Byte;
  B: Byte;
begin
  RK := Default(TRoundKeys);
  Move(Key[1], RK[0], 32);
  I := 8;
  while I < 60 do
  begin
    T[0] := RK[(I - 1) * 4]; T[1] := RK[(I - 1) * 4 + 1]; T[2] := RK[(I - 1) * 4 + 2]; T[3] := RK[(I - 1) * 4 + 3];
    if I mod 8 = 0 then
    begin
      B := T[0];
      T[0] := SBox[T[1]] xor Rcon[I div 8];
      T[1] := SBox[T[2]];
      T[2] := SBox[T[3]];
      T[3] := SBox[B];
    end
    else if I mod 8 = 4 then
    begin
      T[0] := SBox[T[0]]; T[1] := SBox[T[1]]; T[2] := SBox[T[2]]; T[3] := SBox[T[3]];
    end;
    RK[I * 4] := RK[(I - 8) * 4] xor T[0];
    RK[I * 4 + 1] := RK[(I - 8) * 4 + 1] xor T[1];
    RK[I * 4 + 2] := RK[(I - 8) * 4 + 2] xor T[2];
    RK[I * 4 + 3] := RK[(I - 8) * 4 + 3] xor T[3];
    Inc(I);
  end;
end;

procedure EncryptBlock(const RK: TRoundKeys; var S: TBlock);
var
  R, C, I: Integer;
  T: TBlock;
  A0, A1, A2, A3, X: Byte;
begin
  for I := 0 to 15 do
    S[I] := S[I] xor RK[I];
  for R := 1 to 14 do
  begin
    { SubBytes and ShiftRows }
    for C := 0 to 3 do
      for I := 0 to 3 do
        T[C * 4 + I] := SBox[S[((C + I) mod 4) * 4 + I]];
    { MixColumns (not in the last round) }
    if R < 14 then
      for C := 0 to 3 do
      begin
        A0 := T[C * 4]; A1 := T[C * 4 + 1]; A2 := T[C * 4 + 2]; A3 := T[C * 4 + 3];
        X := A0 xor A1 xor A2 xor A3;
        T[C * 4] := A0 xor X xor XTime(A0 xor A1);
        T[C * 4 + 1] := A1 xor X xor XTime(A1 xor A2);
        T[C * 4 + 2] := A2 xor X xor XTime(A2 xor A3);
        T[C * 4 + 3] := A3 xor X xor XTime(A3 xor A0);
      end;
    for I := 0 to 15 do
      S[I] := T[I] xor RK[R * 16 + I];
  end;
end;

{ ---------------- GCM ---------------- }

{ X := X * Y in GF(2^128), GCM's bit order }
procedure GMul(var X: TBlock; const Y: TBlock);
var
  Z, V: TBlock;
  I, J: Integer;
  Lsb: Boolean;
begin
  Z := Default(TBlock);
  V := Y;
  for I := 0 to 127 do
  begin
    if (X[I shr 3] shr (7 - (I and 7))) and 1 = 1 then
      for J := 0 to 15 do
        Z[J] := Z[J] xor V[J];
    Lsb := (V[15] and 1) = 1;
    for J := 15 downto 1 do
      V[J] := (V[J] shr 1) or ((V[J - 1] and 1) shl 7);
    V[0] := V[0] shr 1;
    if Lsb then
      V[0] := V[0] xor $e1;
  end;
  X := Z;
end;

procedure GHashData(var Y: TBlock; const H: TBlock; const Data: RawByteString);
var
  I, J, N: Integer;
begin
  I := 1;
  while I <= Length(Data) do
  begin
    N := Length(Data) - I + 1;
    if N > 16 then
      N := 16;
    for J := 0 to N - 1 do
      Y[J] := Y[J] xor Byte(Data[I + J]);
    GMul(Y, H);
    Inc(I, 16);
  end;
end;

procedure Inc32(var B: TBlock);
var
  I: Integer;
begin
  for I := 15 downto 12 do
  begin
    B[I] := Byte(B[I] + 1);
    if B[I] <> 0 then
      Break;
  end;
end;

{ CTR from the counter block J0 + 1 }
function Ctr(const RK: TRoundKeys; const J0: TBlock; const Data: RawByteString): RawByteString;
var
  Cb, K: TBlock;
  I, J: Integer;
begin
  SetLength(Result, Length(Data));
  Cb := J0;
  I := 1;
  while I <= Length(Data) do
  begin
    Inc32(Cb);
    K := Cb;
    EncryptBlock(RK, K);
    for J := 0 to 15 do
      if I + J <= Length(Data) then
        Result[I + J] := Chr(Byte(Data[I + J]) xor K[J]);
    Inc(I, 16);
  end;
end;

function Tag(const RK: TRoundKeys; const H, J0: TBlock; const Aad, Cipher: RawByteString): RawByteString;
var
  Y, L, E: TBlock;
  Bits: QWord;
  I: Integer;
begin
  Y := Default(TBlock);
  GHashData(Y, H, Aad);
  GHashData(Y, H, Cipher);
  Bits := QWord(Length(Aad)) * 8;
  for I := 0 to 7 do
    L[7 - I] := Byte(Bits shr (8 * I));
  Bits := QWord(Length(Cipher)) * 8;
  for I := 0 to 7 do
    L[15 - I] := Byte(Bits shr (8 * I));
  for I := 0 to 15 do
    Y[I] := Y[I] xor L[I];
  GMul(Y, H);
  E := J0;
  EncryptBlock(RK, E);
  SetLength(Result, 16);
  for I := 0 to 15 do
    Result[I + 1] := Chr(Y[I] xor E[I]);
end;

procedure Setup(const Key, Nonce: RawByteString; out RK: TRoundKeys; out H, J0: TBlock);
begin
  if Length(Key) <> 32 then
    raise ECipherError.Create('AES-256 needs a key of 32 bytes');
  if Length(Nonce) <> 12 then
    raise ECipherError.Create('GCM needs a nonce of 12 bytes');
  ExpandKey(Key, RK);
  H := Default(TBlock);
  EncryptBlock(RK, H);
  J0 := Default(TBlock);
  Move(Nonce[1], J0[0], 12);
  J0[15] := 1;
end;

function AesGcmSeal(const Key, Nonce, Plain, Aad: RawByteString): RawByteString;
var
  RK: TRoundKeys;
  H, J0: TBlock;
  C: RawByteString;
begin
  Setup(Key, Nonce, RK, H, J0);
  C := Ctr(RK, J0, Plain);
  Result := C + Tag(RK, H, J0, Aad, C);
end;

function AesGcmOpen(const Key, Nonce, Sealed, Aad: RawByteString): RawByteString;
var
  RK: TRoundKeys;
  H, J0: TBlock;
  C: RawByteString;
begin
  if Length(Sealed) < 16 then
    raise ECipherError.Create('the data is too short to be encrypted data');
  Setup(Key, Nonce, RK, H, J0);
  C := Copy(Sealed, 1, Length(Sealed) - 16);
  if not SameSecret(Tag(RK, H, J0, Aad, C), Copy(Sealed, Length(Sealed) - 15, 16)) then
    raise ECipherError.Create('the data cannot be decrypted: a wrong key, or it was changed');
  Result := Ctr(RK, J0, C);
end;

function AesGcmEncrypt(const Key, Plain: RawByteString; const Aad: RawByteString): RawByteString;
var
  Nonce: RawByteString;
begin
  Nonce := RandomBytes(12);
  Result := Nonce + AesGcmSeal(Key, Nonce, Plain, Aad);
end;

function AesGcmDecrypt(const Key, Data: RawByteString; const Aad: RawByteString): RawByteString;
begin
  if Length(Data) < 28 then
    raise ECipherError.Create('the data is too short to be encrypted data');
  Result := AesGcmOpen(Key, Copy(Data, 1, 12), Copy(Data, 13, MaxInt), Aad);
end;

{ ---------------- with a password ---------------- }

function EncryptText(const Password, Text: string; Iterations: Integer): string;
var
  Salt, Key: RawByteString;
begin
  Salt := RandomBytes(16);
  Key := Pbkdf2Sha256(Password, Salt, Iterations, 32);
  Result := 'v1.' + IntToStr(Iterations) + '.' + Base64UrlEncode(Salt + AesGcmEncrypt(Key, Text, 'pastel-v1'));
end;

function DecryptText(const Password, Sealed: string): string;
var
  Parts: TStringArray;
  Raw, Key: RawByteString;
  Iterations: Integer;
begin
  Parts := Sealed.Split(['.']);
  if (Length(Parts) <> 3) or (Parts[0] <> 'v1') or not TryStrToInt(Parts[1], Iterations) or (Iterations < 1) then
    raise ECipherError.Create('this is not text of EncryptText');
  try
    Raw := Base64UrlDecode(Parts[2]);
  except
    raise ECipherError.Create('this is not text of EncryptText');
  end;
  if Length(Raw) < 16 + 28 then
    raise ECipherError.Create('this is not text of EncryptText');
  Key := Pbkdf2Sha256(Password, Copy(Raw, 1, 16), Iterations, 32);
  Result := AesGcmDecrypt(Key, Copy(Raw, 17, MaxInt), 'pastel-v1');
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

end.
