# Pastel.Syntax

Syntax highlighting for TMemo (and TEdit): SQL, Pascal, JSON.

    SqlMemo.OnHighlight := @Syntax.Sql;
    SqlMemo.Completions.AddStrings(SqlKeywords);

  The spans are worked out by a small scanner (keywords, strings, numbers,
  comments); HighlightCode does it for another language's words.

`uses Pastel.Syntax;` · source: [framework/src/pastel.syntax.pas](../../framework/src/pastel.syntax.pas)

**Contents:** [TCodeLanguage](#tcodelanguage) · [TSyntax](#tsyntax) · [HighlightCode](#highlightcode) · [HighlightSql](#highlightsql) · [HighlightPascal](#highlightpascal) · [HighlightJson](#highlightjson) · [SqlKeywords](#sqlkeywords)

## Types

### TCodeLanguage

```pascal
type TCodeLanguage = record
```

How a language is written, for HighlightCode.

| | |
|---|---|
| `Keywords: TStringList` | case-insensitive when CaseSensitive is False |
| `CaseSensitive: Boolean` |  |
| `LineComment: string` | '--', '//' |
| `LineComment2: string` | '--', '//' |
| `BlockOpen: string` | '/*' '*/' |
| `BlockClose: string` | '/*' '*/' |
| `BlockOpen2: string` | Pascal's braces and (* *) |
| `BlockClose2: string` | Pascal's braces and (* *) |
| `Quotes: string` | the characters strings begin with: '''"' |
| `NameQuotes: string` | names in quotes: SQL's "name" and `name` |
| `Doubled: Boolean` | a quote doubled is one in the string ('it''s') |
| `Backslash: Boolean` | \" escapes |

### TSyntax

```pascal
type TSyntax = class
```

The highlighters as events: Memo.OnHighlight := @Syntax.Sql.

| | |
|---|---|
| `procedure Sql(Sender: TObject; const AText: string; var Spans: TSyntaxSpans)` |  |
| `procedure Pascal(Sender: TObject; const AText: string; var Spans: TSyntaxSpans)` |  |
| `procedure Json(Sender: TObject; const AText: string; var Spans: TSyntaxSpans)` |  |

## Routines

### HighlightCode

```pascal
function HighlightCode(const Lang: TCodeLanguage; const S: string): TSyntaxSpans
```

### HighlightSql

```pascal
function HighlightSql(const S: string): TSyntaxSpans
```

### HighlightPascal

```pascal
function HighlightPascal(const S: string): TSyntaxSpans
```

### HighlightJson

```pascal
function HighlightJson(const S: string): TSyntaxSpans
```

### SqlKeywords

```pascal
function SqlKeywords: TStringArray
```

SQL's words (upper case), for Completions.

## Constants and variables

| | |
|---|---|
| `var Syntax: TSyntax` |  |
