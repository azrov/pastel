# Pastel.Crypto

Hashes, signatures, passwords and random tokens.

    Sha256Hex('abc')                          // 'ba7816bf...'
    Sig := HmacSha256(Secret, Message);       // raw bytes
    Token := RandomToken;                     // 43 characters, safe in URLs
    Hash := HashPassword('s3cret');           // store this, never the password
    if VerifyPassword(Typed, Hash) then ...
    if SameSecret(Given, Expected) then ...   // takes the same time either way

  All in Pascal, no OpenSSL needed. Strings here are bytes (RawByteString);
  text is used as its UTF-8 bytes.

`uses Pastel.Crypto;` · source: [framework/src/pastel.crypto.pas](../../framework/src/pastel.crypto.pas)

**Contents:** [Sha256](#sha256) · [Sha256Hex](#sha256hex) · [Sha256File](#sha256file) · [HmacSha256](#hmacsha256) · [Pbkdf2Sha256](#pbkdf2sha256) · [HashPassword](#hashpassword) · [VerifyPassword](#verifypassword) · [RandomBytes](#randombytes) · [RandomToken](#randomtoken) · [SameSecret](#samesecret) · [Base64UrlEncode](#base64urlencode) · [Base64UrlDecode](#base64urldecode) · [ToHex](#tohex)

## Routines

### Sha256

```pascal
function Sha256(const Data: RawByteString): RawByteString
```

32 bytes

### Sha256Hex

```pascal
function Sha256Hex(const Data: RawByteString): string
```

64 hex characters, lower case

### Sha256File

```pascal
function Sha256File(const FileName: string): string
```

### HmacSha256

```pascal
function HmacSha256(const Key: RawByteString; const Data: RawByteString): RawByteString
```

### Pbkdf2Sha256

```pascal
function Pbkdf2Sha256(const Password: RawByteString; const Salt: RawByteString; Iterations: Integer; Length: Integer): RawByteString
```

PBKDF2 with HMAC-SHA256 (RFC 8018)

### HashPassword

```pascal
function HashPassword(const Password: string; Iterations: Integer = 210000): string
```

'pbkdf2-sha256$210000$<salt>$<hash>'; a new salt every time

### VerifyPassword

```pascal
function VerifyPassword(const Password: string; const Hash: string): Boolean
```

also False for a hash in another format

### RandomBytes

```pascal
function RandomBytes(Count: Integer): RawByteString
```

bytes from the system's secure random source

### RandomToken

```pascal
function RandomToken(Count: Integer = 32): string
```

Count random bytes as base64url text: for API keys, session ids, ...

### SameSecret

```pascal
function SameSecret(const A: RawByteString; const B: RawByteString): Boolean
```

compares without stopping at the first difference, so the time taken
tells an attacker nothing

### Base64UrlEncode

```pascal
function Base64UrlEncode(const Data: RawByteString): string
```

### Base64UrlDecode

```pascal
function Base64UrlDecode(const Text: string): RawByteString
```

EConvertError for text that is not base64url

### ToHex

```pascal
function ToHex(const Data: RawByteString): string
```

