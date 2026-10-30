# Passwords, tokens and signatures: `Pastel.Crypto`, `Pastel.Jwt`

What a web API or a service needs to keep secrets safe. Written in Pascal,
tested against the official test vectors; no OpenSSL needed.

## Passwords

Never store passwords, only a hash made for passwords:

```pascal
uses Pastel.Crypto;

Hash := HashPassword(Password);          { store this }
...
if VerifyPassword(Typed, Hash) then      { at login }
```

The hash looks like `pbkdf2-sha256$210000$<salt>$<hash>`: PBKDF2 with
HMAC-SHA256, 210 000 rounds and a new random salt for every password, so
equal passwords give different hashes and guessing is slow (about 0.4 s per
try on a PC). The rounds are stored in the hash, so a later Pastel can use
more without breaking old hashes. `VerifyPassword` compares in constant time
and returns `False` for anything that is not such a hash.

## Random tokens

```pascal
Key := RandomToken;          { 32 random bytes as 43 URL-safe characters }
Bytes := RandomBytes(16);
```

From the system's secure source (`/dev/urandom`, `RtlGenRandom` on
Windows): for API keys, session ids, password reset links, secrets. Never
use `Random` for these.

## Comparing secrets

```pascal
if SameSecret(Given, Expected) then ...
```

takes the same time whether the first or the last character differs, so an
attacker cannot find a key character by character by timing the answers.

## JSON Web Tokens

```pascal
uses Pastel.Jwt;

Token := JwtSign(JObject(['sub', 'ayse', 'role', 'admin']), Secret, 3600);
Claims := JwtVerify(Token, Secret);      { EJwtError if forged, changed or expired }
try
  Name := JStr(Claims, 'sub');
finally
  Claims.Free;
end;
```

- HS256 only; tokens that name another algorithm (or `none`) are refused.
- `iat` and `exp` are added; `exp` and `nbf` are checked, with 30 seconds of leeway for clocks.
- The secret should be long and random (`RandomToken`), the same on every server, and kept in the settings or an environment variable.
- A JWT is signed, not encrypted: anyone can read its claims. Put nothing secret in it.
- In a web server, `Web.RequireJwt('/api', Secret)` checks the tokens ([web.md](web.md)).

## Hashes and signatures

| | |
|---|---|
| `Sha256(Data)`, `Sha256Hex(Data)` | SHA-256 of bytes or text |
| `Sha256File(FileName)` | of a file, as hex |
| `HmacSha256(Key, Data)` | to sign messages, e.g. webhooks |
| `Pbkdf2Sha256(Password, Salt, Rounds, Length)` | to derive keys |
| `Base64UrlEncode`, `Base64UrlDecode`, `ToHex` | |

Checking a webhook signature, for example:

```pascal
if not SameSecret(ToHex(HmacSha256(WebhookSecret, Req.Body)), Req.Header('X-Signature')) then
  raise EWebError.Create(401, 'bad signature');
```
