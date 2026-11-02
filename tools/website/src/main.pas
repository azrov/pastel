{ Pastel's website: the home page, the download page and the documentation
  from the Markdown in the repository, made with Pastel.Markdown and
  Pastel.Pages (Bootstrap 5). Every link between pages and every #anchor is
  checked; a mistake stops the build.

    website                  -> site/ in the repository, the folder to publish
    website --check          only check the links
    website --out DIR        somewhere else
    website --root DIR       the repository (found by itself otherwise)

  SITE_REPO=owner/name: the GitHub repository of the download buttons and of
  links to source files (azrov/pastel when not set). }
program Website;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, StrUtils, fpjson, Pastel.Files, Pastel.Json, Pastel.Markdown, Pastel.Pages;

const
  DefaultRepo = 'azrov/pastel';

type
  TPage = class
    Src, Page, Title, Html: string;
  end;

  TSite = class
  private
    FCurSrc, FCurPage: string;
    function Rewrite(const Href: string): string;
    function PageOf(const Src: string): string;
    function NavTitle(const Src: string; P: TPage): string;
    function Nav(const Current: string): TJSONArray;
    function Common(const Base, Title, Section: string): TJSONObject;
    procedure Convert(const Src: string);
    procedure Write(const Page, Html: string);
  public
    Root, OutDir, Repo, Version: string;
    Groups: TStringList;      { group names; Objects: TStringList of sources }
    Pages: TStringList;       { source=page }
    Rendered: TStringList;    { page; Objects: TPage }
    Anchors: TStringList;     { page; Objects: TStringList of ids }
    Links: TStringList;       { from, page, anchor, text (4 lines each) }
    Problems: TStringList;
    Copies: TStringList;      { repository file=site path, copied into the site }
    Search: TJSONArray;
    Views: TPages;
    constructor Create(const ARoot: string);
    destructor Destroy; override;
    procedure Build;
    procedure CheckLinks;
    procedure WriteSite;
  end;

{ ---- paths ---- }

function NormPath(const P: string): string;
var
  Parts, Res: TStringArray;
  S: string;
begin
  Res := nil;
  Parts := P.Split(['/']);
  for S in Parts do
    if (S = '') or (S = '.') then
      Continue
    else if (S = '..') and (Length(Res) > 0) and (Res[High(Res)] <> '..') then
      SetLength(Res, Length(Res) - 1)
    else
    begin
      SetLength(Res, Length(Res) + 1);
      Res[High(Res)] := S;
    end;
  Result := string.Join('/', Res);
end;

function DirOf(const P: string): string;
var
  I: Integer;
begin
  I := LastDelimiter('/', P);
  Result := Copy(P, 1, I - 1);
end;

{ The way from one page of the site to another (both relative to the site). }
function Relative(const FromPage, ToPage: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(FromPage) do
    if FromPage[I] = '/' then
      Result := Result + '../';
  Result := Result + ToPage;
end;

function HasScheme(const Href: string): Boolean;
var
  I: Integer;
begin
  if Copy(Href, 1, 2) = '//' then
    Exit(True);
  I := 1;
  while (I <= Length(Href)) and (Href[I] in ['a'..'z', 'A'..'Z']) do
    Inc(I);
  Result := (I > 1) and (I <= Length(Href)) and (Href[I] = ':');
end;

function IsPicture(const P: string): Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(P));
  Result := (E = '.png') or (E = '.jpg') or (E = '.jpeg') or (E = '.gif') or (E = '.svg') or (E = '.webp');
end;

function Slash(const P: string): string;
begin
  Result := StringReplace(P, '\', '/', [rfReplaceAll]);
end;

{ ---- text ---- }

function StripTags(const S: string): string;
var
  I: Integer;
  InTag: Boolean;
begin
  Result := '';
  InTag := False;
  for I := 1 to Length(S) do
    if S[I] = '<' then
      InTag := True
    else if S[I] = '>' then
      InTag := False
    else if not InTag then
      Result := Result + S[I];
  Result := StringReplace(StringReplace(StringReplace(Result, '&lt;', '<', [rfReplaceAll]), '&gt;', '>', [rfReplaceAll]),
    '&amp;', '&', [rfReplaceAll]);
end;

{ The words of a page for the search: without code blocks and Markdown signs. }
function SearchText(const Md: string): string;
var
  L: TStringList;
  I: Integer;
  InCode: Boolean;
  B: TStringBuilder;
  C: Char;
  Space: Boolean;
begin
  L := TStringList.Create;
  B := TStringBuilder.Create;
  try
    L.Text := Md;
    InCode := False;
    Space := True;
    for I := 0 to L.Count - 1 do
    begin
      if (Copy(TrimLeft(L[I]), 1, 3) = '```') or (Copy(TrimLeft(L[I]), 1, 3) = '~~~') then
      begin
        InCode := not InCode;
        Continue;
      end;
      if InCode then
        Continue;
      for C in L[I] + ' ' do
        if C in ['#', '*', '`', '|', '>', '[', ']', '(', ')', '_', '-', ' ', #9] then
        begin
          if not Space then
            B.Append(' ');
          Space := True;
        end
        else
        begin
          B.Append(C);
          Space := False;
        end;
      if B.Length > 4000 then
        Break;
    end;
    Result := Trim(B.ToString);
    if Length(Result) > 4000 then
    begin
      SetLength(Result, 4000);
      while (Length(Result) > 0) and (Ord(Result[Length(Result)]) and $C0 = $80) do
        SetLength(Result, Length(Result) - 1);
      if (Length(Result) > 0) and (Ord(Result[Length(Result)]) >= $C0) then
        SetLength(Result, Length(Result) - 1);
    end;
  finally
    B.Free;
    L.Free;
  end;
end;

function Headings(const Md: string): TJSONArray;
var
  L: TStringList;
  I: Integer;
  InCode: Boolean;
  T: string;
begin
  Result := TJSONArray.Create;
  L := TStringList.Create;
  try
    L.Text := Md;
    InCode := False;
    for I := 0 to L.Count - 1 do
    begin
      T := L[I];
      if (Copy(TrimLeft(T), 1, 3) = '```') or (Copy(TrimLeft(T), 1, 3) = '~~~') then
        InCode := not InCode
      else if not InCode and ((Copy(T, 1, 3) = '## ') or (Copy(T, 1, 4) = '### ')) then
        Result.Add(StringReplace(Trim(Copy(T, Pos(' ', T) + 1, MaxInt)), '`', '', [rfReplaceAll]));
    end;
  finally
    L.Free;
  end;
end;

{ "On this page": the <h2> headings of the HTML. }
function Contents(const Html: string): TJSONArray;
var
  P, Q, E: Integer;
  Id, Text: string;
begin
  Result := TJSONArray.Create;
  P := Pos('<h2 id="', Html);
  while P > 0 do
  begin
    Q := PosEx('"', Html, P + 8);
    Id := Copy(Html, P + 8, Q - P - 8);
    E := PosEx('</h2>', Html, Q);
    Text := StripTags(Copy(Html, PosEx('>', Html, Q) + 1, E - PosEx('>', Html, Q) - 1));
    if Copy(Text, 1, 1) = '#' then
      Delete(Text, 1, 1);
    Result.Add(JObject(['id', Id, 'text', Text]));
    P := PosEx('<h2 id="', Html, E);
  end;
end;

{ ---- the site ---- }

constructor TSite.Create(const ARoot: string);

  procedure Group(const Name: string; const Sources: array of string);
  var
    L: TStringList;
    S: string;
  begin
    L := TStringList.Create;
    for S in Sources do
      L.Add(S);
    Groups.AddObject(Name, L);
  end;

var
  S: string;
  Ex: TStringList;
  Src: string;
  I, J: Integer;
  Api: TStringArray;
begin
  Root := IncludeTrailingPathDelimiter(ARoot);
  Groups := TStringList.Create;
  Groups.OwnsObjects := True;
  Pages := TStringList.Create;
  Rendered := TStringList.Create;
  Rendered.OwnsObjects := True;
  Anchors := TStringList.Create;
  Anchors.OwnsObjects := True;
  Anchors.Sorted := True;
  Links := TStringList.Create;
  Problems := TStringList.Create;
  Copies := TStringList.Create;
  Search := TJSONArray.Create;
  Repo := GetEnvironmentVariable('SITE_REPO');
  if Repo = '' then
    Repo := DefaultRepo;
  Version := '';
  for S in ReadLines(Root + 'cli/src/pastel.project.pas') do
    if Pos('PastelVersion = ''', S) > 0 then
      Version := Copy(S, Pos('''', S) + 1, LastDelimiter('''', S) - Pos('''', S) - 1);

  Group('Start', ['README.md', 'docs/README.md', 'docs/getting-started.md', 'docs/commands.md']);
  Group('Guides', ['docs/guide-cli.md', 'docs/guide-api.md', 'docs/guide-desktop.md', 'docs/guide-business.md']);
  Group('Desktop and phone apps', ['docs/forms.md', 'docs/controls.md', 'docs/components.md', 'docs/android.md']);
  Group('Programs and services', ['docs/console.md', 'docs/data.md', 'docs/documents.md', 'docs/system.md',
    'docs/services.md', 'docs/web.md', 'docs/pages.md', 'docs/markdown.md', 'docs/database.md', 'docs/sync.md',
    'docs/auth.md', 'docs/security.md', 'docs/deploy.md']);
  Group('Working with Pastel', ['docs/project.md', 'docs/workflow.md', 'docs/packages.md', 'docs/testing.md',
    'vscode/README.md']);
  Group('Reference', ['docs/api/README.md', 'docs/compatibility.md', 'docs/performance.md']);
  Ex := TStringList.Create;
  for S in ListDirs(Root + 'examples') do
    if FileExists(Root + 'examples' + PathDelim + ExtractFileName(ExcludeTrailingPathDelimiter(S)) + PathDelim + 'README.md') then
      Ex.Add('examples/' + ExtractFileName(ExcludeTrailingPathDelimiter(S)) + '/README.md');
  Ex.Sort;
  Groups.AddObject('Examples', Ex);
  Group('Project', ['ROADMAP.md', 'CHANGELOG.md', 'vscode/CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md',
    'CODE_OF_CONDUCT.md', 'docs/announcing-1.0.md']);

  for I := 0 to Groups.Count - 1 do
    for J := 0 to TStringList(Groups.Objects[I]).Count - 1 do
    begin
      Src := TStringList(Groups.Objects[I])[J];
      Pages.Add(Src + '=' + PageOf(Src));
    end;
  { the pages of the API reference: not in the menu, linked from its index }
  Api := ListFiles(Root + 'docs' + PathDelim + 'api', '*.md');
  Ex := TStringList.Create;
  try
    for S in Api do
      if ExtractFileName(S) <> 'README.md' then
        Ex.Add('docs/api/' + ExtractFileName(S));
    Ex.Sort;
    for I := 0 to Ex.Count - 1 do
      Pages.Add(Ex[I] + '=' + PageOf(Ex[I]));
  finally
    Ex.Free;
  end;
end;

destructor TSite.Destroy;
begin
  Groups.Free;
  Pages.Free;
  Rendered.Free;
  Anchors.Free;
  Links.Free;
  Problems.Free;
  Copies.Free;
  Search.Free;
  Views.Free;
  inherited Destroy;
end;

function TSite.PageOf(const Src: string): string;
begin
  if Src = 'README.md' then
    Exit('readme.html');
  if Src = 'docs/README.md' then
    Exit('docs.html');
  if Src = 'vscode/README.md' then
    Exit('vscode.html');
  if Src = 'vscode/CHANGELOG.md' then
    Exit('vscode-changelog.html');
  if Src = 'CHANGELOG.md' then
    Exit('changelog.html');
  if Src = 'CONTRIBUTING.md' then
    Exit('contributing.html');
  if Src = 'SECURITY.md' then
    Exit('security-policy.html');
  if Src = 'CODE_OF_CONDUCT.md' then
    Exit('code-of-conduct.html');
  if Src = 'ROADMAP.md' then
    Exit('roadmap.html');
  if Src = 'docs/api/README.md' then
    Exit('api/index.html');
  if (Copy(Src, 1, 9) = 'examples/') and (Copy(Src, Length(Src) - 9, 10) = '/README.md') then
    Exit('examples/' + Copy(Src, 10, Length(Src) - 19) + '.html');
  if Copy(Src, 1, 9) = 'docs/api/' then
    Exit('api/' + ChangeFileExt(Copy(Src, 10, MaxInt), '.html'));
  if Copy(Src, 1, 5) = 'docs/' then
    Exit(ChangeFileExt(Copy(Src, 6, MaxInt), '.html'));
  Result := '';
end;

{ A link of the page being converted: to another page (made .html, its #anchor
  checked), to a picture (copied into the site), to a source file (GitHub), or
  outside (as it is). }
function TSite.Rewrite(const Href: string): string;
var
  Target, Anchor, Resolved, Dest, Dir: string;
  H: Integer;
begin
  if HasScheme(Href) then
    Exit(Href);
  H := Pos('#', Href);
  if H > 0 then
  begin
    Target := Copy(Href, 1, H - 1);
    Anchor := Copy(Href, H + 1, MaxInt);
  end
  else
  begin
    Target := Href;
    Anchor := '';
  end;
  if Target = '' then
  begin
    Links.Add(FCurSrc);
    Links.Add(FCurPage);
    Links.Add(Anchor);
    Links.Add(Href);
    Exit(Href);
  end;
  Dir := DirOf(FCurSrc);
  if Dir <> '' then
    Resolved := NormPath(Dir + '/' + Target)
  else
    Resolved := NormPath(Target);
  Dest := Pages.Values[Resolved];
  if Dest = '' then
    Dest := Pages.Values[NormPath(Resolved + '/README.md')];
  if Dest <> '' then
  begin
    if Anchor <> '' then
    begin
      Links.Add(FCurSrc);
      Links.Add(Dest);
      Links.Add(Anchor);
      Links.Add(Href);
      Result := Relative(FCurPage, Dest) + '#' + Anchor;
    end
    else
      Result := Relative(FCurPage, Dest);
    Exit;
  end;
  if not FileExists(Root + Resolved) and not DirectoryExists(Root + Resolved) then
  begin
    Problems.Add(Format('%s: link to %s: %s does not exist', [FCurSrc, Href, Resolved]));
    Exit(Href);
  end;
  if LowerCase(ExtractFileExt(Resolved)) = '.md' then
    Problems.Add(Format('%s: link to %s: %s is not a page of the site (add it to the menu)', [FCurSrc, Href, Resolved]));
  if IsPicture(Resolved) and FileExists(Root + Resolved) then
  begin
    Copies.Values[Resolved] := 'files/' + Resolved;
    Exit(Relative(FCurPage, 'files/' + Resolved));
  end;
  if DirectoryExists(Root + Resolved) then
    Result := 'https://github.com/' + Repo + '/tree/main/' + Resolved
  else
    Result := 'https://github.com/' + Repo + '/blob/main/' + Resolved;
end;

procedure TSite.Convert(const Src: string);
var
  Md: string;
  M: TMarkdown;
  P: TPage;
  Ids: TStringList;
  Item: TJSONObject;
begin
  if not FileExists(Root + Src) then
  begin
    Problems.Add(Src + ': listed in the menu but missing');
    Exit;
  end;
  Md := ReadText(Root + Src);
  FCurSrc := Src;
  FCurPage := Pages.Values[Src];
  M := TMarkdown.Create;
  try
    M.HeadingAnchors := True;
    M.OnLink := @Rewrite;
    P := TPage.Create;
    P.Src := Src;
    P.Page := FCurPage;
    P.Title := StringReplace(MarkdownTitle(Md), '`', '', [rfReplaceAll]);
    P.Html := M.Render(Md);
    Rendered.AddObject(FCurPage, P);
    Ids := TStringList.Create;
    Ids.Sorted := True;
    Ids.Duplicates := dupIgnore;
    Ids.AddStrings(M.HeadingIds);
    Anchors.AddObject(FCurPage, Ids);
  finally
    M.Free;
  end;
  Item := JObject(['page', FCurPage, 'title', P.Title, 'text', SearchText(Md)]);
  Item.Add('headings', Headings(Md));
  Search.Add(Item);
end;

procedure TSite.Build;
var
  I: Integer;
begin
  for I := 0 to Pages.Count - 1 do
    Convert(Pages.Names[I]);
end;

procedure TSite.CheckLinks;
var
  I, A: Integer;
  Ids: TStringList;
begin
  I := 0;
  while I < Links.Count do
  begin
    A := Anchors.IndexOf(Links[I + 1]);
    Ids := nil;
    if A >= 0 then
      Ids := TStringList(Anchors.Objects[A]);
    if (Ids = nil) or (Ids.IndexOf(Links[I + 2]) < 0) then
      Problems.Add(Format('%s: link %s: no heading #%s in %s', [Links[I], Links[I + 3], Links[I + 2], Links[I + 1]]));
    Inc(I, 4);
  end;
end;

function TSite.NavTitle(const Src: string; P: TPage): string;
begin
  Result := P.Title;
  if Copy(Result, 1, 7) = 'Guide: ' then
    Result := UpperCase(Copy(Result, 8, 1)) + Copy(Result, 9, MaxInt);
  if Copy(Src, 1, 9) = 'examples/' then
    Result := Copy(Src, 10, Length(Src) - 19);
  if Src = 'README.md' then
    Result := 'Overview';
  if Src = 'docs/README.md' then
    Result := 'All topics';
  if Src = 'vscode/CHANGELOG.md' then
    Result := 'Changelog of the VS Code extension';
end;

function TSite.Nav(const Current: string): TJSONArray;
var
  I, J, R: Integer;
  Src, Page: string;
  G: TJSONObject;
  L: TJSONArray;
  Open: Boolean;
begin
  Result := TJSONArray.Create;
  for I := 0 to Groups.Count - 1 do
  begin
    L := TJSONArray.Create;
    Open := False;
    for J := 0 to TStringList(Groups.Objects[I]).Count - 1 do
    begin
      Src := TStringList(Groups.Objects[I])[J];
      Page := Pages.Values[Src];
      R := Rendered.IndexOf(Page);
      if R < 0 then
        Continue;
      L.Add(JObject(['title', NavTitle(Src, TPage(Rendered.Objects[R])), 'href', Relative(Current, Page),
        'current', Page = Current]));
      Open := Open or (Page = Current) or ((Groups[I] = 'Reference') and (Copy(Current, 1, 4) = 'api/'));
    end;
    G := JObject(['name', Groups[I], 'id', 'g' + IntToStr(I), 'open', Open]);
    G.Add('links', L);
    Result.Add(G);
  end;
end;

function TSite.Common(const Base, Title, Section: string): TJSONObject;
begin
  Result := JObject(['base', Base, 'title', Title, 'section', Section, 'version', Version, 'repo', Repo,
    'releases', 'https://github.com/' + Repo + '/releases/latest', 'github', 'https://github.com/' + Repo]);
end;

procedure TSite.Write(const Page, Html: string);
var
  F: string;
begin
  F := OutDir + StringReplace(Page, '/', PathDelim, [rfReplaceAll]);
  EnsureDir(ExtractFileDir(F));
  WriteText(F, Html);
end;

procedure TSite.WriteSite;
var
  I: Integer;
  P: TPage;
  D: TJSONObject;
  Base, Section, Edit: string;
  S: string;
begin
  if DirectoryExists(OutDir) then
    DeleteDir(OutDir);
  EnsureDir(OutDir);
  for I := 0 to Rendered.Count - 1 do
  begin
    P := TPage(Rendered.Objects[I]);
    Base := Relative(P.Page, '');
    Section := 'docs';
    if (P.Src = 'CHANGELOG.md') or (P.Src = 'vscode/CHANGELOG.md') then
      Section := 'changelog';
    D := Common(Base, P.Title, Section);
    try
      Edit := 'https://github.com/' + Repo + '/edit/main/' + P.Src;
      D.Add('html', P.Html);
      D.Add('edit', Edit);
      D.Add('nav', Nav(P.Page));
      D.Add('contents', Contents(P.Html));
      Write(P.Page, Views.Render('doc', D));
    finally
      D.Free;
    end;
  end;
  D := Common('', 'Pastel', 'home');
  try
    Write('index.html', Views.Render('home', D));
  finally
    D.Free;
  end;
  D := Common('', 'Download', 'download');
  try
    Write('download.html', Views.Render('download', D));
  finally
    D.Free;
  end;
  { pictures: those the pages show, and those of the home page }
  for S in ListFiles(Root + 'docs' + PathDelim + 'images') do
    Copies.Values['docs/images/' + ExtractFileName(S)] := 'files/docs/images/' + ExtractFileName(S);
  for I := 0 to Copies.Count - 1 do
  begin
    EnsureDir(ExtractFileDir(OutDir + Copies.ValueFromIndex[I]));
    CopyFile(Root + Copies.Names[I], OutDir + Copies.ValueFromIndex[I]);
  end;
  for S in ListFiles(FindAppFolder('public'), '*', True) do
  begin
    EnsureDir(ExtractFileDir(OutDir + 'assets' + PathDelim + RelativePath(S, FindAppFolder('public'))));
    CopyFile(S, OutDir + 'assets' + PathDelim + RelativePath(S, FindAppFolder('public')));
  end;
  WriteText(OutDir + 'search.json', Search.AsJSON);
  WriteText(OutDir + '.nojekyll', '');
end;

{ The repository: given, or the folder above this one that has docs/ and ROADMAP.md. }
function FindRoot(const Start: string): string;
var
  D: string;
begin
  D := ExpandFileName(Start);
  while True do
  begin
    if FileExists(IncludeTrailingPathDelimiter(D) + 'ROADMAP.md') and
      FileExists(IncludeTrailingPathDelimiter(D) + 'docs' + PathDelim + 'README.md') then
      Exit(IncludeTrailingPathDelimiter(D));
    if ExtractFileDir(ExcludeTrailingPathDelimiter(D)) = ExcludeTrailingPathDelimiter(D) then
      Exit('');
    D := ExtractFileDir(ExcludeTrailingPathDelimiter(D));
  end;
end;

var
  Site: TSite;
  Root, OutDir: string;
  Check: Boolean;
  I: Integer;
begin
  Root := '';
  OutDir := '';
  Check := False;
  I := 1;
  while I <= ParamCount do
  begin
    if ParamStr(I) = '--check' then
      Check := True
    else if (ParamStr(I) = '--out') and (I < ParamCount) then
    begin
      Inc(I);
      OutDir := ParamStr(I);
    end
    else if (ParamStr(I) = '--root') and (I < ParamCount) then
    begin
      Inc(I);
      Root := ParamStr(I);
    end
    else
    begin
      WriteLn(StdErr, 'usage: website [--check] [--out DIR] [--root DIR]');
      Halt(2);
    end;
    Inc(I);
  end;
  if Root = '' then
    Root := FindRoot(GetCurrentDir);
  if Root = '' then
    Root := FindRoot(ExtractFileDir(ParamStr(0)));
  if Root = '' then
  begin
    WriteLn(StdErr, 'error: run this in Pastel''s repository, or give it with --root');
    Halt(2);
  end;
  Site := TSite.Create(Root);
  try
    Site.Build;
    Site.CheckLinks;
    if Site.Problems.Count > 0 then
    begin
      WriteLn(StdErr, Site.Problems.Count, ' problem(s) in the documentation:');
      for I := 0 to Site.Problems.Count - 1 do
        WriteLn(StdErr, '  ', Slash(Site.Problems[I]));
      ExitCode := 1;
      Exit;
    end;
    if Check then
    begin
      WriteLn('site: ', Site.Rendered.Count, ' pages, every link and anchor exists');
      Exit;
    end;
    if OutDir = '' then
      OutDir := Site.Root + 'site';
    Site.OutDir := IncludeTrailingPathDelimiter(ExpandFileName(OutDir));
    Site.Views := TPages.Create(FindAppFolder('views'));
    Site.WriteSite;
    WriteLn('site: ', Site.Rendered.Count + 2, ' pages in ', Site.OutDir);
  finally
    Site.Free;
  end;
end.
