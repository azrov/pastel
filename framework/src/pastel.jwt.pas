(* Pastel - JSON Web Tokens (JWT) signed with HS256.

    Token := JwtSign(JObject(['sub', 'ayse', 'role', 'admin']), Secret, 3600);   // valid 1 hour
    Claims := JwtVerify(Token, Secret);      // EJwtError if forged, changed or expired
    try
      WriteLn(JStr(Claims, 'sub'));
    finally
      Claims.Free;
    end;

  Only HS256 (HMAC-SHA256 with a shared secret) is accepted; tokens that
  ask for another algorithm, or for none, are refused. The secret should
  be long and random: RandomToken(32) from Pastel.Crypto.
  Part of the Pastel project, MIT License. *)
unit Pastel.Jwt;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

type
  EJwtError = class(Exception);

{ Signs Claims (and frees them). ExpiresIn: seconds; 0 for no expiry.
  "iat" and "exp" are added. }
function JwtSign(Claims: TJSONObject; const Secret: string; ExpiresIn: Int64 = 3600): string;
{ The claims of a valid token (the caller frees them). Leeway: seconds of
  clock difference allowed between servers. }
function JwtVerify(const Token, Secret: string; Leeway: Integer = 30): TJSONObject;

implementation

uses
  DateUtils, Pastel.Crypto, Pastel.Json;

function NowUnix: Int64;
begin
  Result := DateTimeToUnix(LocalTimeToUniversal(Now));
end;

function JwtSign(Claims: TJSONObject; const Secret: string; ExpiresIn: Int64): string;
var
  Head, Body: string;
begin
  if Secret = '' then
    raise EJwtError.Create('a JWT needs a secret');
  try
    Claims.Delete('iat');
    Claims.Delete('exp');
    Claims.Add('iat', NowUnix);
    if ExpiresIn > 0 then
      Claims.Add('exp', NowUnix + ExpiresIn);
    Head := Base64UrlEncode('{"alg":"HS256","typ":"JWT"}');
    Body := Base64UrlEncode(ToJson(Claims));
  finally
    Claims.Free;
  end;
  Result := Head + '.' + Body + '.' + Base64UrlEncode(HmacSha256(Secret, Head + '.' + Body));
end;

function JwtVerify(const Token, Secret: string; Leeway: Integer): TJSONObject;
var
  Parts: TStringArray;
  Header: TJSONData;
  Data: TJSONData;
  Exp, Nbf: Int64;
begin
  if Secret = '' then
    raise EJwtError.Create('a JWT needs a secret');
  Parts := Token.Split(['.']);
  if Length(Parts) <> 3 then
    raise EJwtError.Create('not a JWT');
  try
    Header := ParseJson(Base64UrlDecode(Parts[0]));
  except
    raise EJwtError.Create('not a JWT');
  end;
  try
    if JStr(Header, 'alg') <> 'HS256' then
      raise EJwtError.CreateFmt('JWT algorithm "%s" is not accepted (only HS256)', [JStr(Header, 'alg')]);
  finally
    Header.Free;
  end;
  try
    if not SameSecret(Base64UrlDecode(Parts[2]), HmacSha256(Secret, Parts[0] + '.' + Parts[1])) then
      raise EJwtError.Create('the JWT signature is wrong');
  except
    on E: EConvertError do
      raise EJwtError.Create('the JWT signature is wrong');
  end;
  try
    Data := ParseJson(Base64UrlDecode(Parts[1]));
  except
    raise EJwtError.Create('the JWT claims are not JSON');
  end;
  if not (Data is TJSONObject) then
  begin
    Data.Free;
    raise EJwtError.Create('the JWT claims are not a JSON object');
  end;
  Result := TJSONObject(Data);
  Exp := JInt(Result, 'exp', 0);
  Nbf := JInt(Result, 'nbf', 0);
  if (Exp > 0) and (NowUnix > Exp + Leeway) then
  begin
    Result.Free;
    raise EJwtError.Create('the JWT has expired');
  end;
  if (Nbf > 0) and (NowUnix + Leeway < Nbf) then
  begin
    Result.Free;
    raise EJwtError.Create('the JWT is not valid yet');
  end;
end;

end.
