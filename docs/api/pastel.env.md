# Pastel.Env

Environment variables.

    Home := GetEnv('HOME');
    Port := GetEnv('PORT', '8080');
    if HasEnv('CI') then ...
    SetEnv('APP_MODE', 'test');          // for this program and programs it starts

  The values are UTF-8 on every system. (Free Pascal's own
  GetEnvironmentVariable gives Windows "ANSI" text there, where 'şeker'
  becomes 'seker'.)

`uses Pastel.Env;` · source: [framework/src/pastel.env.pas](../../framework/src/pastel.env.pas)

## Routines

### GetEnv

```pascal
function GetEnv(const Name: string; const Default: string = ''): string
```

### HasEnv

```pascal
function HasEnv(const Name: string): Boolean
```

### SetEnv

```pascal
procedure SetEnv(const Name: string; const Value: string)
```

### UnsetEnv

```pascal
procedure UnsetEnv(const Name: string)
```

### EnvList

```pascal
function EnvList: TStringArray
```

All variables as 'NAME=value'

### InvariantFormat

```pascal
function InvariantFormat: TFormatSettings
```

Numbers as machines write them (1234.5): files, protocols, other programs.
DefaultFormatSettings is the user's language's (Pastel.Lang sets it: 1234,5
in Turkish), not for these.

