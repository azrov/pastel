# Pastel.Jwt

JSON Web Tokens (JWT) signed with HS256.

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

`uses Pastel.Jwt;` · source: [framework/src/pastel.jwt.pas](../../framework/src/pastel.jwt.pas)

## Types

### EJwtError

```pascal
type EJwtError = class(Exception)
```

## Routines

### JwtSign

```pascal
function JwtSign(Claims: TJSONObject; const Secret: string; ExpiresIn: Int64 = 3600): string
```

Signs Claims (and frees them). ExpiresIn: seconds; 0 for no expiry.
"iat" and "exp" are added.

### JwtVerify

```pascal
function JwtVerify(const Token: string; const Secret: string; Leeway: Integer = 30): TJSONObject
```

The claims of a valid token (the caller frees them). Leeway: seconds of
clock difference allowed between servers.

