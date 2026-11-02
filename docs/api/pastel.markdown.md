# Pastel.Markdown

Markdown to HTML, the way GitHub shows it.

  CommonMark with tables, ~~strikethrough~~ and bare links:

    Html := MarkdownToHtml(Text);

  Headings get GitHub's ids (## Getting started -> id="getting-started"), so
  links to #getting-started work. TMarkdown gives a say over links and
  headings (a documentation site rewrites links to .md files):

    M := TMarkdown.Create;
    M.OnLink := @RewriteLink;          // function(const Href: string): string of object
    Html := M.Render(Text);
    for Id in M.HeadingIds do ...

  Supported: headings (#), paragraphs, **strong**, *em*, _em_, ~~del~~,
  `code`, fenced code (``` and ~~~ with a language), indented code, links,
  images, <autolinks> and bare https:// links, lists (ordered, nested, - [ ]
  task boxes), block quotes, tables with alignment, --- rules, hard breaks,
  \ escapes, HTML blocks and inline HTML as they are.

`uses Pastel.Markdown;` · source: [framework/src/pastel.markdown.pas](../../framework/src/pastel.markdown.pas)

## Types

### TMarkdown

```pascal
type TMarkdown = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `function Render(const Text: string): string` |  |
| `property HeadingIds: TStringList` | The ids given to the headings by the last Render. |
| `property OnLink: TMarkdownLinkEvent` | Changes every link and image address (a documentation site makes .md links .html). |
| `property HeadingAnchors: Boolean` | A # link before each heading's text (<a class="anchor" href="#id">#</a>). |

## Other types

| | |
|---|---|
| `type TMarkdownLinkEvent = function(Href: string): string` |  |

## Routines

### MarkdownToHtml

```pascal
function MarkdownToHtml(const Text: string): string
```

Markdown text as HTML.

### MarkdownSlug

```pascal
function MarkdownSlug(const Heading: string): string
```

GitHub's id of a heading: lower case, without punctuation, spaces as '-'.

### MarkdownTitle

```pascal
function MarkdownTitle(const Text: string): string
```

The text of the first "# Title" heading, '' when there is none.

