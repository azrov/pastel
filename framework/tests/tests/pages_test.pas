{ Tests for Pastel.Pages: HTML pages from templates. }
unit Pages_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Json, Pastel.Pages;

type
  TPagesTests = class(TTestSuite)
  private
    Dir: string;
    Pages: TPages;
    procedure Save(const Name, Text: string);
    function R(const Template: string; Data: TJSONObject = nil): string;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ValuesAreMadeSafe;
    procedure Conditions;
    procedure Loops;
    procedure Filters;
    procedure LayoutsSectionsIncludes;
    procedure CommentsAndLiterals;
    procedure MistakesSayWhere;
    procedure ChangedFilesAreReadAgain;
  end;

implementation

function Shout(const Value, Arg: string): string;
begin
  Result := UpperCase(Value) + Arg;
end;

procedure TPagesTests.SetUp;
begin
  Dir := GetTempDir + 'pastel-pages-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir + 'partials');
  Pages := TPages.Create(Dir);
end;

procedure TPagesTests.TearDown;
var
  SR: TSearchRec;
begin
  Pages.Free;
  for SR.Name in TStringArray.Create('layout.html', 'base.html', 'home.html', 'partials' + PathDelim + 'nav.html',
    'broken.html', 'changing.html') do
    DeleteFile(Dir + SR.Name);
  RemoveDir(Dir + 'partials');
  RemoveDir(Dir);
end;

procedure TPagesTests.Save(const Name, Text: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(Dir + StringReplace(Name, '.', PathDelim, [rfReplaceAll]) + '.html');
  finally
    L.Free;
  end;
end;

function TPagesTests.R(const Template: string; Data: TJSONObject): string;
begin
  try
    Result := Pages.RenderText(Template, Data);
  finally
    Data.Free;
  end;
end;

procedure TPagesTests.ValuesAreMadeSafe;
begin
  AssertEquals('<p>&lt;b&gt;Ali &amp; Ayşe&#39;s &quot;shop&quot;&lt;/b&gt;</p>',
    R('<p>{{ name }}</p>', JObject(['name', '<b>Ali & Ayşe''s "shop"</b>'])));
  AssertEquals('<b>bold</b>', R('{!! html !!}', JObject(['html', '<b>bold</b>'])), 'raw');
  AssertEquals('Ali, 30, 1.5, true, ', R('{{ user.name }}, {{ user.age }}, {{ x }}, {{ ok }}, {{ missing }}',
    JObject(['user', JObject(['name', 'Ali', 'age', 30]), 'x', 1.5, 'ok', True])));
  AssertEquals('b 2', R('{{ tags.1 }} {{ tags.count }}', JObject(['tags', JArrayOf(['a', 'b'])])), 'lists');
  AssertEquals('[1,2]', R('@json(list)', JObject(['list', JArrayOf([1, 2])])), '@json');
end;

procedure TPagesTests.Conditions;
var
  T: string;
begin
  T := '@if(n > 10) big @elseif(n > 2) middle @else small @endif';
  AssertEquals(' big ', R(T, JObject(['n', 11])));
  AssertEquals(' middle ', R(T, JObject(['n', 5])));
  AssertEquals(' small ', R(T, JObject(['n', 1])));
  AssertEquals('yes ', R('@if(user.admin and not user.blocked)yes @endif', JObject(['user', JObject(['admin', True])])));
  AssertEquals('', R('@if(role == ''admin'' || role == ''owner'')yes @endif', JObject(['role', 'guest'])));
  AssertEquals('no items ', R('@unless(items)no items @endunless', JObject(['items', TJSONArray.Create])));
  AssertEquals('Ali', R('@isset(name){{ name }}@endisset', JObject(['name', 'Ali'])));
  AssertEquals('on', R('{{ active ? ''on'' : ''off'' }}', JObject(['active', True])), 'cond ? a : b');
end;

procedure TPagesTests.Loops;
begin
  AssertEquals('1:a,2:b,3:c', R('@foreach(items as item){{ loop.iteration }}:{{ item }}{{ loop.last ? '''' : '','' }}@endforeach',
    JObject(['items', JArrayOf(['a', 'b', 'c'])])));
  AssertEquals('<li>Tea 2</li>' + LineEnding + '<li>Cake 5</li>' + LineEnding,
    R('@foreach(products as p)' + LineEnding + '<li>{{ p.name }} {{ p.price }}</li>' + LineEnding + '@endforeach' + LineEnding,
    JObject(['products', JArrayOf([JObject(['name', 'Tea', 'price', 2]), JObject(['name', 'Cake', 'price', 5])])])),
    'a directive on its own line takes the line break with it');
  AssertEquals(' Nothing yet. ', R('@forelse(items as i){{ i }}@empty Nothing yet. @endforelse', JObject(['items', TJSONArray.Create])));
  AssertEquals('a1a2 b1b2 ', R('@foreach(outer as o)@foreach(inner as i){{ o }}{{ i }}@endforeach @endforeach',
    JObject(['outer', JArrayOf(['a', 'b']), 'inner', JArrayOf([1, 2])])), 'nested loops');
  AssertEquals('x=1;y=2;', R('@foreach(point as k => v){{ k }}={{ v }};@endforeach', JObject(['point', JObject(['x', 1, 'y', 2])])),
    'key and value of an object');
end;

procedure TPagesTests.Filters;
begin
  AssertEquals('1,234.50', R('{{ price | number:2 }}', JObject(['price', 1234.5])));
  AssertEquals('ÇAĞ', R('{{ word | upper }}', JObject(['word', 'çağ'])), 'letters beyond A-Z');
  AssertEquals('İSTANBUL', R('{{ city | upper:''tr'' }}', JObject(['city', 'istanbul'])), 'the rules of a language');
  AssertEquals('—', R('{{ phone | default:''—'' }}', nil));
  AssertEquals('3', R('{{ name | length }}', JObject(['name', 'Ayş'])), 'letters, not bytes');
  RegisterPageFilter('shout', @Shout);
  AssertEquals('HI!', R('{{ word | shout:''!'' }}', JObject(['word', 'hi'])), 'a filter of your own');
end;

procedure TPagesTests.LayoutsSectionsIncludes;
var
  Out_: string;
  D: TJSONObject;
begin
  Save('base', '<html><title>@yield(''title'', ''Shop'')</title>@yield(''body'')</html>');
  Save('layout', '@extends(''base'')' + LineEnding + '@section(''body'')<nav>@include(''partials.nav'')</nav><main>@yield(''content'')</main>@endsection');
  Save('partials.nav', '<a href="/">{{ site }}</a>');
  Save('home', '@extends(''layout'')' + LineEnding + '@section(''title'', name)' + LineEnding + 'not shown' + LineEnding +
    '@section(''content'')<h1>Hi {{ name }}</h1>@endsection');
  D := JObject(['name', 'Ali', 'site', 'Pastel']);
  try
    Out_ := Pages.Render('home', D);
  finally
    D.Free;
  end;
  AssertEquals('<html><title>Ali</title><nav><a href="/">Pastel</a>' + LineEnding + '</nav><main><h1>Hi Ali</h1></main></html>' + LineEnding,
    Out_, 'a page in a layout in a layout, with a partial');
  D := JObject([]);
  try
    Save('home', '@extends(''layout'')');
    AssertTrue(Pos('<title>Shop</title>', Pages.Render('home', D)) > 0, 'the default of @yield');
  finally
    D.Free;
  end;
end;

procedure TPagesTests.CommentsAndLiterals;
begin
  AssertEquals('ab', R('a{{-- not shown --}}b'));
  AssertEquals('{{ vue }}', R('@{{ vue }}'), 'for JavaScript frameworks');
  AssertEquals('info@if.com', R('info@if.com'), 'an e-mail address is not a directive');
  AssertEquals('@media', R('@media'), 'unknown words stay');
end;

procedure TPagesTests.MistakesSayWhere;
var
  Msg: string;
begin
  Save('broken', 'line 1' + LineEnding + '@if(x)' + LineEnding + 'never closed');
  Msg := '';
  try
    Pages.Render('broken', nil);
  except
    on E: EPageError do
      Msg := E.Message;
  end;
  AssertTrue(Pos('broken(', Msg) = 1, Msg);
  AssertTrue(Pos('@endif is missing', Msg) > 0, Msg);
  Msg := '';
  try
    R('a' + LineEnding + '{{ price | nothing }}');
  except
    on E: EPageError do
      Msg := E.Message;
  end;
  AssertTrue((Pos('template(2)', Msg) = 1) and (Pos('no filter "nothing"', Msg) > 0), Msg);
  Msg := '';
  try
    Pages.Render('no-such-page', nil);
  except
    on E: EPageError do
      Msg := E.Message;
  end;
  AssertTrue(Pos('there is no page "no-such-page"', Msg) > 0, Msg);
end;

procedure TPagesTests.ChangedFilesAreReadAgain;
begin
  Save('changing', 'one');
  AssertEquals('one' + LineEnding, Pages.Render('changing', nil));
  Save('changing', 'two');
  FileSetDate(Dir + 'changing.html', DateTimeToFileDate(Now + 1));
  AssertEquals('two' + LineEnding, Pages.Render('changing', nil));
end;

initialization
  RegisterTests(TPagesTests);

end.
