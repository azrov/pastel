# Pastel.Cipher

Encryption: AES-256-GCM, and text sealed with a password.

    Sealed := EncryptText(Password, 'IBAN TR12 0006 ...');   // 'v1.' + base64url
    Plain := DecryptText(Password, Sealed);                   // ECipherError: wrong password or changed
    Data := AesGcmEncrypt(Key, Bytes);                        // Key: 32 bytes (RandomBytes(32))
    Bytes := AesGcmDecrypt(Key, Data);

  AES-256 in GCM mode (NIST SP 800-38D): a new random nonce every time, a
  tag that finds any change. EncryptText makes the key from the password
  with PBKDF2-SHA256 and a random salt. All in Pascal, no OpenSSL.

`uses Pastel.Cipher;` · source: [framework/src/pastel.cipher.pas](../../framework/src/pastel.cipher.pas)

**Contents:** [ECipherError](#eciphererror) · [AesGcmEncrypt](#aesgcmencrypt) · [AesGcmDecrypt](#aesgcmdecrypt) · [AesGcmSeal](#aesgcmseal) · [AesGcmOpen](#aesgcmopen) · [EncryptText](#encrypttext) · [DecryptText](#decrypttext)

## Types

### ECipherError

```pascal
type ECipherError = class(Exception)
```

## Routines

### AesGcmEncrypt

```pascal
function AesGcmEncrypt(const Key: RawByteString; const Plain: RawByteString; const Aad: RawByteString = ''): RawByteString
```

Key: 32 bytes. The answer: a 12-byte nonce, the cipher text, a 16-byte tag.
Aad: data that is checked (not encrypted) with it.

### AesGcmDecrypt

```pascal
function AesGcmDecrypt(const Key: RawByteString; const Data: RawByteString; const Aad: RawByteString = ''): RawByteString
```

ECipherError when the key is wrong or the data was changed

### AesGcmSeal

```pascal
function AesGcmSeal(const Key: RawByteString; const Nonce: RawByteString; const Plain: RawByteString; const Aad: RawByteString): RawByteString
```

The same with the nonce given (tests, protocols that set it): no nonce in the answer.

### AesGcmOpen

```pascal
function AesGcmOpen(const Key: RawByteString; const Nonce: RawByteString; const Sealed: RawByteString; const Aad: RawByteString): RawByteString
```

### EncryptText

```pascal
function EncryptText(const Password: string; const Text: string; Iterations: Integer = 100000): string
```

Text sealed with a password: 'v1.' and base64url (salt, nonce, text, tag).

### DecryptText

```pascal
function DecryptText(const Password: string; const Sealed: string): string
```

