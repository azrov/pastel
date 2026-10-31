# Pastel.Lang

Translations and the number and date formats of a language.

    assets/lang/tr.json:   { "Save": "Kaydet", "Delete %s?": "%s silinsin mi?" }

    Status.Text := _('Save');
    Ask(Format(_('Delete %s?'), [Name]));
    Total.Text := FormatNumber(1234.5, 2);      // 1.234,50 in Turkish

  The language is the computer's (LANG, or Windows' setting), or PASTEL_LANG,
  or UseLanguage('tr') before the forms are created. Texts in .pform files
  (Text, Caption, Title, Placeholder, Hint, Items) are translated when the
  form loads. A text without a translation stays as it is. "pastel lang"
  collects the texts of a project into the files.

`uses Pastel.Lang;` · source: [framework/src/pastel.lang.pas](../../framework/src/pastel.lang.pas)

**Contents:** [_](#-) · [Translate](#translate) · [UseLanguage](#uselanguage) · [Language](#language) · [LanguageChosen](#languagechosen) · [SystemLanguage](#systemlanguage) · [AvailableLanguages](#availablelanguages) · [FrameworkTexts](#frameworktexts) · [AddTranslation](#addtranslation) · [FormatNumber](#formatnumber) · [FormatDateShort](#formatdateshort) · [FormatDateTimeShort](#formatdatetimeshort) · [TryParseNumber](#tryparsenumber)

## Routines

### _

```pascal
function _(const S: string): string
```

The translation of S in the current language; S when there is none.

### Translate

```pascal
function Translate(const S: string): string
```

### UseLanguage

```pascal
function UseLanguage(const Code: string): Boolean
```

Switches to a language ('tr', 'de', 'pt-BR'): loads assets/lang/<code>.json
(also 'pt' for 'pt-BR') and sets the number and date formats. False when
there are no translations for it (the formats change anyway).

### Language

```pascal
function Language: string
```

The current language code; 'en' at the start.

### LanguageChosen

```pascal
function LanguageChosen: Boolean
```

UseLanguage was called (Pastel.App uses the computer's language otherwise).

### SystemLanguage

```pascal
function SystemLanguage: string
```

The language of the computer: PASTEL_LANG, LANG/LC_ALL, or Windows' setting.

### AvailableLanguages

```pascal
function AvailableLanguages: TStringArray
```

The languages that have a file in assets/lang/.

### FrameworkTexts

```pascal
function FrameworkTexts: TStringArray
```

Pastel's own texts (dialog buttons...); built in for some languages.

### AddTranslation

```pascal
procedure AddTranslation(const Source: string; const Translated: string)
```

Adds translations from code (Source=Translation pairs).

### FormatNumber

```pascal
function FormatNumber(Value: Double; Decimals: Integer = 0): string
```

1234.5 -> '1,234.50' (en), '1.234,50' (tr, de), '1 234,50' (fr).

### FormatDateShort

```pascal
function FormatDateShort(D: TDateTime): string
```

The date in the language's short form: 31.10.2026, 10/31/2026, 2026-10-31...

### FormatDateTimeShort

```pascal
function FormatDateTimeShort(D: TDateTime): string
```

### TryParseNumber

```pascal
function TryParseNumber(const S: string; out Value: Double): Boolean
```

Reads a number the way users of the language write it ('1.234,5' in tr).

