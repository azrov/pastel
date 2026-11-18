# Pastel.Pages

HTML pages from templates, in the style of Laravel's Blade.

  A template is an .html file in views/ (views/home.html is 'home',
  views/shop/list.html is 'shop.list'):

    @extends('layout')

    @section('title', 'Products')

    @section('content')
      <h1>{{ title }}</h1>
      @if(user.admin)
        <a href="/new">New product</a>
      @endif
      <ul>
      @forelse(products as product)
        <li class="{{ loop.first ? 'first' : '' }}">{{ product.name }} — {{ product.price | number:2 }}</li>
      @empty
        <li>No products yet.</li>
      @endforelse
      </ul>
    @endsection

  And the code:

    Res.Html(View('products', JObject(['title', 'Products', 'user', User, 'products', List])));

  {{ x }} writes x with < > & " ' made safe for HTML; {!! x !!} writes it as it is.
  Values come from the data (a JSON object), names inside it with dots
  (user.name, items.0.title). See docs/pages.md for everything.

`uses Pastel.Pages;` · source: [framework/src/pastel.pages.pas](../../framework/src/pastel.pages.pas)

**Contents:** [EPageError](#epageerror) · [TPages](#tpages) · [View](#view) · [SetViewsFolder](#setviewsfolder) · [FindAppFolder](#findappfolder) · [RenderPage](#renderpage) · [RegisterPageFilter](#registerpagefilter) · [HtmlEscape](#htmlescape)

## Types

### EPageError

```pascal
type EPageError = class(Exception)
```

### TPages

```pascal
type TPages = class
```

The templates of one folder, read once and again when a file changes.

| | |
|---|---|
| `constructor Create(const AFolder: string)` |  |
| `destructor Destroy` |  |
| `function Render(const Name: string; Data: TJSONObject): string` | The page Name ('home', 'shop.list') with the data (not freed). |
| `function RenderText(const Template: string; Data: TJSONObject): string` | A template given as text (no @extends or @include of files needed). |
| `property Folder: string` |  |

## Other types

| | |
|---|---|
| `type TPageFilter = function(Value: string; Arg: string): string` | A filter: {{ name | upper }}, {{ price | number:2 }}. Value is what is left of the bar, Arg what follows the colon ('' when there is none). |

## Routines

### View

```pascal
function View(const Name: string; Data: TJSONObject = nil): string
```

The page Name from the app's views/ folder (next to the program, or in the
folder it runs in). The data is freed.

### SetViewsFolder

```pascal
procedure SetViewsFolder(const Folder: string)
```

The folder View uses: set it when the views are somewhere else.

### FindAppFolder

```pascal
function FindAppFolder(const Name: string): string
```

A folder of the app (views, public): next to the program (on a server), in the
folder it runs in (pastel run), or in the project when the program is in
build/<platform>/<mode>/.

### RenderPage

```pascal
function RenderPage(const Template: string; Data: TJSONObject = nil): string
```

A template as text, with the data (freed).

### RegisterPageFilter

```pascal
procedure RegisterPageFilter(const Name: string; Filter: TPageFilter)
```

Adds a filter for {{ value | name }} and {{ value | name:arg }}.

### HtmlEscape

```pascal
function HtmlEscape(const S: string): string
```

< > & " ' as HTML entities.

