# Markdown

`Pastel.Markdown` turns Markdown into HTML the way GitHub shows it: CommonMark with tables, ~~strikethrough~~, task lists and bare links. Use it for help pages, blog posts, README files shown in an app, or a whole documentation site — [Pastel's website](https://github.com/azrov/pastel/tree/main/tools/website) is made with it and [Pastel.Pages](pages.md).

## Markdown to HTML

```pascal
uses
  Pastel.Markdown;

Html := MarkdownToHtml('# Hello' + LineEnding + LineEnding + 'Some **bold** text.');
// <h1 id="hello">Hello</h1>
// <p>Some <strong>bold</strong> text.</p>
```

In a web page, put it in with `{!! !!}` so it is not escaped a second time:

```pascal
Res.Html(View('post', JObject(['title', Post.Title, 'body', MarkdownToHtml(Post.Text)])));
```

```html
<article>{!! body !!}</article>
```

HTML in the Markdown stays as it is (as on GitHub), so Markdown written by visitors of a site needs cleaning first; Markdown you wrote yourself does not.

## What it understands

| Markdown | HTML |
|---|---|
| `# Title` … `###### Small` | `<h1 id="title">` … with GitHub's ids |
| `**strong**`, `*em*`, `_em_`, `~~del~~` | `<strong>`, `<em>`, `<del>` |
| `` `code` `` and fenced code with a language (```` ```pascal ````) | `<code>`, `<pre><code class="language-pascal">` |
| `[text](address "title")`, `![alt](picture.png)` | links and pictures |
| `<https://example.com>`, `https://example.com` | links |
| `- item`, `1. item`, nested lists, `- [x] done` | lists, task boxes |
| `> quote` | `<blockquote>` |
| tables with `:---:` alignment | `<table>` |
| `---` | `<hr>` |
| two spaces or `\` at the end of a line | `<br>` |
| `\*` | a `*` that is not emphasis |

## Headings and their ids

Every heading gets the id GitHub gives it, so links like `page.html#getting-started` work as they do on GitHub: lower case, punctuation left out, spaces as `-`, a second heading with the same text gets `-1`.

```pascal
MarkdownSlug('Getting started!');   // 'getting-started'
MarkdownTitle(Text);                // the text of the first "# " heading
```

## Links of your own

`TMarkdown` gives a say over every link and picture address, and tells which ids the headings got. A documentation site makes links to `.md` files links to `.html` pages:

```pascal
type
  TDocs = class
    function Link(const Href: string): string;
  end;

function TDocs.Link(const Href: string): string;
begin
  if Href.EndsWith('.md') then
    Result := ChangeFileExt(Href, '.html')
  else
    Result := Href;
end;

var
  M: TMarkdown;
  Id: string;
begin
  M := TMarkdown.Create;
  try
    M.OnLink := @Docs.Link;
    M.HeadingAnchors := True;          // a # link before each heading
    Html := M.Render(ReadText('docs/start.md'));
    for Id in M.HeadingIds do          // to check links to #anchors
      WriteLn(Id);
  finally
    M.Free;
  end;
end;
```

## Pastel's website

`tools/website` in the repository is a Pastel console program that makes the website: the home page, the download page and every page of the documentation, with a menu, a search and *On this page*. It checks every link between pages and every `#anchor`, so a broken link stops the tests.

```sh
cd tools/website
pastel run                 # ../../site, the folder to publish
pastel run -- --check      # only check the links
```
