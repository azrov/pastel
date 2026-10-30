(* Pastel - hashes, signatures, passwords and random tokens.

    Sha256Hex('abc')                          // 'ba7816bf...'
    Sig := HmacSha256(Secret, Message);       // raw bytes
    Token := RandomToken;                     // 43 characters, safe in URLs
    Hash := HashPassword('s3cret');           // store this, never the password
    if VerifyPassword(Typed, Hash) then ...
    if SameSecret(Given, Expected) then ...   // takes the same time either way

  All in Pascal, no OpenSSL needed. Strings here are bytes (RawByteString);
  text is used as its UTF-8 bytes.
  Part of the Pastel project, MIT License. *)
unit Pastel.Crypto;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ 32 bytes }
function Sha256(const Data: RawByteString): RawByteString;
{ 64 hex characters, lower case }
function Sha256Hex(const Data: RawByteString): string;
function Sha256File(const FileName: string): string;
function HmacSha256(const Key, Data: RawByteString): RawByteString;
{ PBKDF2 with HMAC-SHA256 (RFC 8018) }
function Pbkdf2Sha256(const Password, Salt: RawByteString; Iterations, Length: Integer): RawByteString;

{ 'pbkdf2-sha256$210000$<salt>$<hash>'; a new salt every time }
function HashPassword(const Password: string; Iterations: Integer = 210000): string;
{ also False for a hash in another format }
function VerifyPassword(const Password, Hash: string): Boolean;

{ bytes from the system's secure random source }
function RandomBytes(Count: Integer): RawByteString;
{ Count random bytes as base64url text: for API keys, session ids, ... }
function RandomToken(Count: Integer = 32): string;

{ compares without stopping at the first difference, so the time taken
  tells an attacker nothing }
function SameSecret(const A, B: RawByteString): Boolean;

function Base64UrlEncode(const Data: RawByteString): string;
{ EConvertError for text that is not base64url }
function Base64UrlDecode(const Text: string): RawByteString;
function ToHex(const Data: RawByteString): string;

implementation

uses
  base64 {$IFDEF WINDOWS}, Windows{$ENDIF};

{ ---------------- SHA-256 (FIPS 180-4) ---------------- }

const
  K256: array[0..63] of Cardinal = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);

type
  TSha256 = record
    H: array[0..7] of Cardinal;
    Block: array[0..63] of Byte;
    Used: Integer;
    Total: QWord;
  end;

{$push}{$R-}{$Q-}
function Ror(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

procedure Compress(var C: TSha256);
var
  W: array[0..63] of Cardinal;
  A, B, CC, D, E, F, G, H, T1, T2: Cardinal;
  I: Integer;
begin
  for I := 0 to 15 do
    W[I] := (Cardinal(C.Block[I * 4]) shl 24) or (Cardinal(C.Block[I * 4 + 1]) shl 16) or
      (Cardinal(C.Block[I * 4 + 2]) shl 8) or Cardinal(C.Block[I * 4 + 3]);
  for I := 16 to 63 do
    W[I] := (Ror(W[I - 2], 17) xor Ror(W[I - 2], 19) xor (W[I - 2] shr 10)) + W[I - 7] +
      (Ror(W[I - 15], 7) xor Ror(W[I - 15], 18) xor (W[I - 15] shr 3)) + W[I - 16];
  A := C.H[0]; B := C.H[1]; CC := C.H[2]; D := C.H[3];
  E := C.H[4]; F := C.H[5]; G := C.H[6]; H := C.H[7];
  for I := 0 to 63 do
  begin
    T1 := H + (Ror(E, 6) xor Ror(E, 11) xor Ror(E, 25)) + ((E and F) xor ((not E) and G)) + K256[I] + W[I];
    T2 := (Ror(A, 2) xor Ror(A, 13) xor Ror(A, 22)) + ((A and B) xor (A and CC) xor (B and CC));
    H := G; G := F; F := E; E := D + T1;
    D := CC; CC := B; B := A; A := T1 + T2;
  end;
  Inc(C.H[0], A); Inc(C.H[1], B); Inc(C.H[2], CC); Inc(C.H[3], D);
  Inc(C.H[4], E); Inc(C.H[5], F); Inc(C.H[6], G); Inc(C.H[7], H);
end;
{$pop}

procedure ShaInit(out C: TSha256);
begin
  C := Default(TSha256);
  C.H[0] := $6a09e667; C.H[1] := $bb67ae85; C.H[2] := $3c6ef372; C.H[3] := $a54ff53a;
  C.H[4] := $510e527f; C.H[5] := $9b05688c; C.H[6] := $1f83d9ab; C.H[7] := $5be0cd19;
end;

procedure ShaUpdate(var C: TSha256; P: PByte; N: Integer);
begin
  Inc(C.Total, N);
  while N > 0 do
  begin
    C.Block[C.Used] := P^;
    Inc(C.Used);
    Inc(P);
    Dec(N);
    if C.Used = 64 then
    begin
      Compress(C);
      C.Used := 0;
    end;
  end;
end;

function ShaDigest(var C: TSha256): RawByteString;
var
  Bits: QWord;
  Pad: Byte;
  I: Integer;
begin
  Bits := C.Total * 8;
  Pad := $80;
  ShaUpdate(C, @Pad, 1);
  Pad := 0;
  while C.Used <> 56 do
    ShaUpdate(C, @Pad, 1);
  for I := 7 downto 0 do
  begin
    Pad := Byte(Bits shr (I * 8));
    ShaUpdate(C, @Pad, 1);
  end;
  SetLength(Result, 32);
  for I := 0 to 7 do
  begin
    Result[I * 4 + 1] := Chr(C.H[I] shr 24);
    Result[I * 4 + 2] := Chr((C.H[I] shr 16) and $FF);
    Result[I * 4 + 3] := Chr((C.H[I] shr 8) and $FF);
    Result[I * 4 + 4] := Chr(C.H[I] and $FF);
  end;
end;

function Sha256(const Data: RawByteString): RawByteString;
var
  C: TSha256;
begin
  ShaInit(C);
  if Data <> '' then
    ShaUpdate(C, @Data[1], Length(Data));
  Result := ShaDigest(C);
end;

function ToHex(const Data: RawByteString): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(Data) do
    Result := Result + LowerCase(IntToHex(Ord(Data[I]), 2));
end;

function Sha256Hex(const Data: RawByteString): string;
begin
  Result := ToHex(Sha256(Data));
end;

function Sha256File(const FileName: string): string;
var
  F: TFileStream;
  C: TSha256;
  Buf: array[0..65535] of Byte;
  N: Integer;
begin
  ShaInit(C);
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Buf[0] := 0;
    repeat
      N := F.Read(Buf, SizeOf(Buf));
      if N > 0 then
        ShaUpdate(C, @Buf[0], N);
    until N <= 0;
  finally
    F.Free;
  end;
  Result := ToHex(ShaDigest(C));
end;

{ ---------------- HMAC, PBKDF2 ---------------- }

function HmacSha256(const Key, Data: RawByteString): RawByteString;
var
  K, IPad, OPad: RawByteString;
  I: Integer;
begin
  K := Key;
  if Length(K) > 64 then
    K := Sha256(K);
  SetLength(IPad, 64);
  SetLength(OPad, 64);
  for I := 1 to 64 do
  begin
    if I <= Length(K) then
    begin
      IPad[I] := Chr(Ord(K[I]) xor $36);
      OPad[I] := Chr(Ord(K[I]) xor $5C);
    end
    else
    begin
      IPad[I] := Chr($36);
      OPad[I] := Chr($5C);
    end;
  end;
  Result := Sha256(OPad + Sha256(IPad + Data));
end;

{ HMAC with the key's pads prepared once: PBKDF2 calls it many times }
type
  THmacKey = record
    Inner, Outer: TSha256;
  end;

procedure HmacPrepare(const Key: RawByteString; out H: THmacKey);
var
  K: RawByteString;
  Pad: array[0..63] of Byte;
  I: Integer;
begin
  K := Key;
  if Length(K) > 64 then
    K := Sha256(K);
  for I := 0 to 63 do
    if I < Length(K) then
      Pad[I] := Ord(K[I + 1]) xor $36
    else
      Pad[I] := $36;
  ShaInit(H.Inner);
  ShaUpdate(H.Inner, @Pad[0], 64);
  for I := 0 to 63 do
    Pad[I] := Pad[I] xor $36 xor $5C;
  ShaInit(H.Outer);
  ShaUpdate(H.Outer, @Pad[0], 64);
end;

function HmacWith(const H: THmacKey; const Data: RawByteString): RawByteString;
var
  C: TSha256;
  Inner: RawByteString;
begin
  C := H.Inner;
  if Data <> '' then
    ShaUpdate(C, @Data[1], Length(Data));
  Inner := ShaDigest(C);
  C := H.Outer;
  ShaUpdate(C, @Inner[1], 32);
  Result := ShaDigest(C);
end;

function Pbkdf2Sha256(const Password, Salt: RawByteString; Iterations, Length: Integer): RawByteString;
var
  H: THmacKey;
  Block, U, T: RawByteString;
  B, I, J: Integer;
begin
  if (Iterations < 1) or (Length < 1) then
    raise EArgumentException.Create('PBKDF2 needs at least one iteration and one byte');
  HmacPrepare(Password, H);
  Result := '';
  B := 1;
  while System.Length(Result) < Length do
  begin
    Block := Chr(B shr 24) + Chr((B shr 16) and $FF) + Chr((B shr 8) and $FF) + Chr(B and $FF);
    U := HmacWith(H, Salt + Block);
    T := U;
    for I := 2 to Iterations do
    begin
      U := HmacWith(H, U);
      for J := 1 to 32 do
        T[J] := Chr(Ord(T[J]) xor Ord(U[J]));
    end;
    Result := Result + T;
    Inc(B);
  end;
  SetLength(Result, Length);
end;

{ ---------------- random ---------------- }

{$IFDEF WINDOWS}
function RtlGenRandom(Buffer: Pointer; Length: ULONG): BOOLEAN; stdcall;
  external 'advapi32.dll' name 'SystemFunction036';
{$ENDIF}

function RandomBytes(Count: Integer): RawByteString;
{$IFNDEF WINDOWS}
var
  F: TFileStream;
{$ENDIF}
begin
  Result := '';
  if Count <= 0 then
    Exit;
  SetLength(Result, Count);
  {$IFDEF WINDOWS}
  if not RtlGenRandom(@Result[1], Count) then
    raise EOSError.Create('the system gave no random bytes');
  {$ELSE}
  F := TFileStream.Create('/dev/urandom', fmOpenRead or fmShareDenyNone);
  try
    F.ReadBuffer(Result[1], Count);
  finally
    F.Free;
  end;
  {$ENDIF}
end;

function RandomToken(Count: Integer): string;
begin
  Result := Base64UrlEncode(RandomBytes(Count));
end;

function SameSecret(const A, B: RawByteString): Boolean;
var
  I: Integer;
  Diff: Byte;
begin
  Diff := Ord(Length(A) <> Length(B));
  for I := 1 to Length(A) do
    if I <= Length(B) then
      Diff := Diff or (Ord(A[I]) xor Ord(B[I]))
    else
      Diff := Diff or 1;
  Result := Diff = 0;
end;

{ ---------------- base64url ---------------- }

function Base64UrlEncode(const Data: RawByteString): string;
begin
  Result := EncodeStringBase64(Data);
  Result := StringReplace(Result, '+', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '_', [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] = '=') do
    SetLength(Result, Length(Result) - 1);
end;

function Base64UrlDecode(const Text: string): RawByteString;
var
  S: string;
  C: Char;
begin
  for C in Text do
    if not (C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '=']) then
      raise EConvertError.Create('not base64url text');
  S := StringReplace(StringReplace(Text, '-', '+', [rfReplaceAll]), '_', '/', [rfReplaceAll]);
  while Length(S) mod 4 <> 0 do
    S := S + '=';
  Result := DecodeStringBase64(S);
end;

{ ---------------- passwords ---------------- }

function HashPassword(const Password: string; Iterations: Integer): string;
var
  Salt: RawByteString;
begin
  Salt := RandomBytes(16);
  Result := Format('pbkdf2-sha256$%d$%s$%s', [Iterations, Base64UrlEncode(Salt),
    Base64UrlEncode(Pbkdf2Sha256(RawByteString(Password), Salt, Iterations, 32))]);
end;

function VerifyPassword(const Password, Hash: string): Boolean;
var
  Parts: TStringArray;
  Iterations: Integer;
  Salt, Expected: RawByteString;
begin
  Result := False;
  Parts := Hash.Split(['$']);
  if (Length(Parts) <> 4) or (Parts[0] <> 'pbkdf2-sha256') or
     not TryStrToInt(Parts[1], Iterations) or (Iterations < 1) then
    Exit;
  try
    Salt := Base64UrlDecode(Parts[2]);
    Expected := Base64UrlDecode(Parts[3]);
  except
    on EConvertError do
      Exit;
  end;
  if Expected = '' then
    Exit;
  Result := SameSecret(Pbkdf2Sha256(RawByteString(Password), Salt, Iterations, Length(Expected)), Expected);
end;

end.
