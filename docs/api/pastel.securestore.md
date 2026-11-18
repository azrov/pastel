# Pastel.SecureStore

Secrets kept by the system: tokens, passwords, keys.

    SecureSet('api-token', Token);
    Token := SecureGet('api-token');          // '' when there is none
    SecureDelete('api-token');

  Android: encrypted with a key of the phone's Keystore (it never leaves the
  phone's secure hardware). Windows: the user's data protection (DPAPI), only
  that Windows user can read them. Linux: the desktop's keyring (GNOME Keyring,
  KWallet) through secret-tool; without one, a file only the user may read.

`uses Pastel.SecureStore;` · source: [framework/src/pastel.securestore.pas](../../framework/src/pastel.securestore.pas)

## Types

### ESecureStoreError

```pascal
type ESecureStoreError = class(Exception)
```

## Routines

### SecureSet

```pascal
procedure SecureSet(const Name: string; const Value: string)
```

### SecureGet

```pascal
function SecureGet(const Name: string; const Default: string = ''): string
```

### SecureHas

```pascal
function SecureHas(const Name: string): Boolean
```

### SecureDelete

```pascal
procedure SecureDelete(const Name: string)
```

### SecureStoreKind

```pascal
function SecureStoreKind: string
```

Where they are kept: 'android-keystore', 'windows-dpapi', 'linux-keyring' or 'file'.

## Constants and variables

| | |
|---|---|
| `var SecureStoreApp: string` | the app's name the secrets are kept under (default: the program's name) |
