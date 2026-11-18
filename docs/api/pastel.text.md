# Pastel.Text

Text helpers that understand UTF-8.

  Free Pascal's UpperCase and LowerCase only change the English letters A-Z;
  these work for every language:

    Upper('ayşe')            = 'AYŞE'
    Upper('istanbul', 'tr')  = 'İSTANBUL'   (Turkish and Azerbaijani i/İ, ı/I)
    CharCount('ağaç')        = 4            (Length gives 6: it counts bytes)

`uses Pastel.Text;` · source: [framework/src/pastel.text.pas](../../framework/src/pastel.text.pas)

## Routines

### Upper

```pascal
function Upper(const S: string; const Lang: string = ''): string
```

Lang: '' for the general rules, 'tr' or 'az' for dotted and dotless i.

### Lower

```pascal
function Lower(const S: string; const Lang: string = ''): string
```

### Capitalize

```pascal
function Capitalize(const S: string; const Lang: string = ''): string
```

First letter upper case, the rest unchanged.

### CharCount

```pascal
function CharCount(const S: string): Integer
```

Number of characters (Length counts bytes).

### CharCopy

```pascal
function CharCopy(const S: string; Start: Integer; Count: Integer): string
```

Characters Start..Start+Count-1, counting characters from 1.

### Shorten

```pascal
function Shorten(const S: string; MaxChars: Integer): string
```

Shortens to at most MaxChars characters, ending with "…" when cut.

