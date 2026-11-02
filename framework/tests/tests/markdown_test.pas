{ Tests for Pastel.Markdown: Markdown to HTML the way GitHub shows it. }
unit Markdown_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Markdown;

type
  TMarkdownTests = class(TTestSuite)
  private
    function Md(const Lines: array of string): string;
    function Docs(const Href: string): string;
  published
    procedure HeadingsGetGitHubIds;
    procedure InlineText;
    procedure Lists;
    procedure CodeBlocks;
    procedure Tables;
    procedure QuotesRulesAndHtml;
    procedure LinksOfYourOwn;
  end;

implementation

function TMarkdownTests.Md(const Lines: array of string): string;
var
  S: string;
begin
  S := '';
  for Result in Lines do
    S := S + Result + #10;
  Result := Trim(MarkdownToHtml(S));
end;

function TMarkdownTests.Docs(const Href: string): string;
var
  H: Integer;
begin
  H := Pos('#', Href + '#');
  Result := Copy(Href, 1, H - 1);
  if Result.EndsWith('.md') then
    Result := ChangeFileExt(Result, '.html');
  Result := Result + Copy(Href, H, MaxInt);
end;

procedure TMarkdownTests.HeadingsGetGitHubIds;
begin
  AssertEquals('<h1 id="hello-world">Hello world</h1>', Md(['# Hello world']));
  AssertEquals('<h2 id="the-pastel-command">The <code>pastel</code> command</h2>', Md(['## The `pastel` command']));
  AssertEquals('getting-started', MarkdownSlug('Getting started!'));
  AssertEquals('çağ-ı-1-ok', MarkdownSlug('Çağ ı 1: ok?'), 'letters beyond A-Z stay');
  AssertEquals('<h2 id="a">A</h2>' + LineEnding + '<h2 id="a-1">A</h2>', Md(['## A', '', '## A']), 'the second gets -1');
  AssertEquals('Forms and controls', MarkdownTitle('Intro' + LineEnding + '# Forms and controls' + LineEnding));
end;

procedure TMarkdownTests.InlineText;
begin
  AssertEquals('<p><strong>bold</strong>, <em>em</em>, <em>em</em>, <del>gone</del>, <code>a &lt; b</code></p>',
    Md(['**bold**, *em*, _em_, ~~gone~~, `a < b`']));
  AssertEquals('<p><a href="https://example.com" title="Ex">site</a> and <img src="a.png" alt="pic"></p>',
    Md(['[site](https://example.com "Ex") and ![pic](a.png)']));
  AssertEquals('<p><a href="https://pastel.dev">https://pastel.dev</a></p>', Md(['<https://pastel.dev>']));
  AssertEquals('<p>see <a href="https://pastel.dev/docs">https://pastel.dev/docs</a>.</p>', Md(['see https://pastel.dev/docs.']),
    'a bare link without the full stop');
  AssertEquals('<p>*not em* &amp; 2 &lt; 3</p>', Md(['\*not em\* & 2 < 3']));
  AssertEquals('<p>line one<br>' + LineEnding + 'line two</p>', Md(['line one  ', 'line two']), 'a hard break');
  AssertEquals('<p>snake_case_name</p>', Md(['snake_case_name']), 'underscores inside words are not emphasis');
end;

procedure TMarkdownTests.Lists;
begin
  AssertEquals('<ul>' + LineEnding + '<li>one</li>' + LineEnding + '<li>two' + LineEnding + '<ul>' + LineEnding +
    '<li>inner</li>' + LineEnding + '</ul></li>' + LineEnding + '</ul>',
    Md(['- one', '- two', '  - inner']), 'tight and nested');
  AssertEquals('<ol start="3">' + LineEnding + '<li>c</li>' + LineEnding + '<li>d</li>' + LineEnding + '</ol>',
    Md(['3. c', '4. d']));
  AssertTrue(Pos('<li><p>first</p>', Md(['- first', '', '- second'])) > 0, 'a blank line between items: paragraphs');
  AssertTrue(Pos('<input type="checkbox" disabled checked> done', Md(['- [x] done', '- [ ] open'])) > 0, 'task boxes');
end;

procedure TMarkdownTests.CodeBlocks;
begin
  AssertEquals('<pre><code class="language-pascal">if A &lt; B then' + LineEnding + '  WriteLn(''&lt;b&gt;'');' + LineEnding +
    '</code></pre>', Md(['```pascal', 'if A < B then', '  WriteLn(''<b>'');', '```']));
  AssertEquals('<pre><code>indented' + LineEnding + '</code></pre>', Md(['    indented']));
  AssertEquals('<pre><code># not a heading' + LineEnding + '</code></pre>', Md(['~~~', '# not a heading', '~~~']));
end;

procedure TMarkdownTests.Tables;
var
  H: string;
begin
  H := Md(['| Name | Price |', '|:---|---:|', '| Tea | 2 |', '| `a|b` | 3 |']);
  AssertTrue(Pos('<th align="left">Name</th>', H) > 0, H);
  AssertTrue(Pos('<td align="right">2</td>', H) > 0, H);
  AssertTrue(Pos('<code>a|b</code>', H) > 0, 'a bar inside code is not a new cell: ' + H);
end;

procedure TMarkdownTests.QuotesRulesAndHtml;
begin
  AssertEquals('<blockquote>' + LineEnding + '<p>Note: <strong>this</strong></p>' + LineEnding + '</blockquote>',
    Md(['> Note: **this**']));
  AssertEquals('<hr>', Md(['---']));
  AssertEquals('<div align="center">' + LineEnding + '<b>as it is</b>' + LineEnding + '</div>',
    Md(['<div align="center">', '<b>as it is</b>', '</div>']), 'HTML stays as it is');
end;

procedure TMarkdownTests.LinksOfYourOwn;
var
  M: TMarkdown;
  H: string;
begin
  M := TMarkdown.Create;
  try
    M.OnLink := @Docs;
    M.HeadingAnchors := True;
    H := M.Render('# Start' + LineEnding + LineEnding + 'See [forms](forms.md#layout) and [web](https://x.org/a.md).' +
      LineEnding + LineEnding + '## Next step' + LineEnding);
    AssertTrue(Pos('<a href="forms.html#layout">', H) > 0, H);
    AssertTrue(Pos('<a href="https://x.org/a.html">', H) > 0, 'every address goes through OnLink: ' + H);
    AssertTrue(Pos('<h1 id="start"><a class="anchor" href="#start">#</a>Start</h1>', H) > 0, H);
    AssertEquals(2, M.HeadingIds.Count);
    AssertEquals('next-step', M.HeadingIds[1]);
  finally
    M.Free;
  end;
end;

initialization
  RegisterTests(TMarkdownTests);

end.
