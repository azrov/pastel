{ Pastel - Markdown to HTML, the way GitHub shows it.

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

  Part of the Pastel project, MIT License. }
unit Pastel.Markdown;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TMarkdownLinkEvent = function(const Href: string): string of object;

  TMarkdown = class
  private
    FIds: TStringList;
    FOnLink: TMarkdownLinkEvent;
    FHeadingAnchors: Boolean;
    function Link(const Href: string): string;
    function Inline_(const S: string): string;
    procedure Blocks(Lines: TStrings; Out_: TStringBuilder; Tight: Boolean);
    function HeadingId(const Raw: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    function Render(const Text: string): string;
    { The ids given to the headings by the last Render. }
    property HeadingIds: TStringList read FIds;
    { Changes every link and image address (a documentation site makes .md links .html). }
    property OnLink: TMarkdownLinkEvent read FOnLink write FOnLink;
    { A # link before each heading's text (<a class="anchor" href="#id">#</a>). }
    property HeadingAnchors: Boolean read FHeadingAnchors write FHeadingAnchors;
  end;

{ Markdown text as HTML. }
function MarkdownToHtml(const Text: string): string;
{ GitHub's id of a heading: lower case, without punctuation, spaces as '-'. }
function MarkdownSlug(const Heading: string): string;
{ The text of the first "# Title" heading, '' when there is none. }
function MarkdownTitle(const Text: string): string;

implementation

uses
  StrUtils, Character;

function Esc(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '&': Result := Result + '&amp;';
      '"': Result := Result + '&quot;';
    else
      Result := Result + S[I];
    end;
end;

{ & that starts an entity (&amp; &#39; &copy;) stays }
function EscText(const S: string): string;
var
  I, J: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    case S[I] of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '&':
        begin
          J := I + 1;
          while (J <= Length(S)) and (J - I < 10) and (S[J] in ['A'..'Z', 'a'..'z', '0'..'9', '#']) do
            Inc(J);
          if (J <= Length(S)) and (S[J] = ';') and (J > I + 1) then
            Result := Result + Copy(S, I, J - I + 1)
          else
            Result := Result + '&amp;';
          if (J <= Length(S)) and (S[J] = ';') and (J > I + 1) then
            I := J;
        end;
    else
      Result := Result + S[I];
    end;
    Inc(I);
  end;
end;

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
end;

function MarkdownSlug(const Heading: string): string;
var
  U, R: UnicodeString;
  I: Integer;
  C: WideChar;
begin
  U := UTF8Decode(Trim(StripTags(Heading)));
  U := TCharacter.ToLower(U);
  R := '';
  for I := 1 to Length(U) do
  begin
    C := U[I];
    { letters, digits, spaces, _ and -: GitHub keeps them }
    if TCharacter.IsLetterOrDigit(C) or (C = ' ') or (C = '_') or (C = '-') or
       (Ord(C) >= $D800) and (Ord(C) <= $DFFF) then
      R := R + C
    else if TCharacter.IsWhiteSpace(C) then
      R := R + ' ';
  end;
  { not trimmed again: "Values go in as `?`" is #values-go-in-as- on GitHub }
  Result := StringReplace(UTF8Encode(R), ' ', '-', [rfReplaceAll]);
end;

function MarkdownTitle(const Text: string): string;
var
  L: TStringList;
  I: Integer;
  InCode: Boolean;
  T: string;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := Text;
    InCode := False;
    for I := 0 to L.Count - 1 do
    begin
      T := TrimLeft(L[I]);
      if (Copy(T, 1, 3) = '```') or (Copy(T, 1, 3) = '~~~') then
        InCode := not InCode;
      if not InCode and (Copy(L[I], 1, 2) = '# ') then
        Exit(StringReplace(Trim(Copy(L[I], 3, MaxInt)), '`', '', [rfReplaceAll]));
    end;
  finally
    L.Free;
  end;
end;

function MarkdownToHtml(const Text: string): string;
var
  M: TMarkdown;
begin
  M := TMarkdown.Create;
  try
    Result := M.Render(Text);
  finally
    M.Free;
  end;
end;

{ ---- block helpers ---- }

function Indent(const S: string): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (S[Result + 1] in [' ', #9]) do
    if S[Result + 1] = #9 then Inc(Result, 4) else Inc(Result);
end;

function IsBlank(const S: string): Boolean;
begin
  Result := Trim(S) = '';
end;

{ the indent removed (tabs as 4 spaces) }
function Dedent(const S: string; N: Integer): string;
var
  I, Col: Integer;
begin
  I := 1;
  Col := 0;
  while (I <= Length(S)) and (Col < N) and (S[I] in [' ', #9]) do
  begin
    if S[I] = #9 then Inc(Col, 4) else Inc(Col);
    Inc(I);
  end;
  Result := Copy(S, I, MaxInt);
end;

function IsFence(const S: string; out Fence: string; out Info: string): Boolean;
var
  T: string;
  C: Char;
  N: Integer;
begin
  Result := False;
  if Indent(S) > 3 then
    Exit;
  T := TrimLeft(S);
  if (Length(T) < 3) or not (T[1] in ['`', '~']) then
    Exit;
  C := T[1];
  N := 0;
  while (N < Length(T)) and (T[N + 1] = C) do
    Inc(N);
  if N < 3 then
    Exit;
  Fence := StringOfChar(C, N);
  Info := Trim(Copy(T, N + 1, MaxInt));
  Result := not ((C = '`') and (Pos('`', Info) > 0));
end;

function IsRule(const S: string): Boolean;
var
  T: string;
  C: Char;
  I, N: Integer;
begin
  Result := False;
  if Indent(S) > 3 then
    Exit;
  T := StringReplace(Trim(S), ' ', '', [rfReplaceAll]);
  if (Length(T) < 3) or not (T[1] in ['-', '*', '_']) then
    Exit;
  C := T[1];
  N := 0;
  for I := 1 to Length(T) do
    if T[I] = C then Inc(N) else Exit(False);
  Result := N >= 3;
end;

function HeadingLevel(const S: string; out Text: string): Integer;
var
  T: string;
begin
  Result := 0;
  if Indent(S) > 3 then
    Exit;
  T := TrimLeft(S);
  while (Result < Length(T)) and (T[Result + 1] = '#') do
    Inc(Result);
  if (Result = 0) or (Result > 6) or ((Result < Length(T)) and (T[Result + 1] <> ' ')) then
    Exit(0);
  Text := Trim(Copy(T, Result + 1, MaxInt));
  { closing #s }
  while (Text <> '') and (Text[Length(Text)] = '#') do
    Delete(Text, Length(Text), 1);
  Text := Trim(Text);
end;

{ "- ", "* ", "+ ", "1. ", "1) ": the marker's kind, the start number and where the text begins }
function ListItem(const S: string; out Ordered: Boolean; out Start, ContentAt: Integer): Boolean;
var
  I, Ind: Integer;
  T: string;
begin
  Result := False;
  Ind := Indent(S);
  if Ind > 3 + 0 then
    if Ind > 3 then Exit;
  T := Copy(S, Length(S) - Length(TrimLeft(S)) + 1, MaxInt);
  if T = '' then
    Exit;
  if T[1] in ['-', '*', '+'] then
  begin
    if (Length(T) > 1) and (T[2] <> ' ') then
      Exit;
    Ordered := False;
    Start := 0;
    ContentAt := Ind + 2;
    Exit(True);
  end;
  I := 1;
  while (I <= Length(T)) and (T[I] in ['0'..'9']) and (I <= 9) do
    Inc(I);
  if (I = 1) or (I > Length(T)) or not (T[I] in ['.', ')']) then
    Exit;
  if (I < Length(T)) and (T[I + 1] <> ' ') then
    Exit;
  Ordered := True;
  Start := StrToIntDef(Copy(T, 1, I - 1), 1);
  ContentAt := Ind + I + 1;
  Result := True;
end;

function IsTableSeparator(const S: string): Boolean;
var
  T: string;
  I: Integer;
begin
  T := Trim(S);
  Result := (Pos('-', T) > 0) and (Pos('|', T) > 0) or ((Pos('-', T) > 0) and (Pos(':', T) > 0));
  if not Result then
    Exit;
  for I := 1 to Length(T) do
    if not (T[I] in ['|', '-', ':', ' ', #9]) then
      Exit(False);
end;

{ the cells of a table row: split at | that are not escaped or in `code` }
function Cells(const S: string): TStringArray;
var
  T, Cur: string;
  I: Integer;
  InCode: Boolean;
begin
  Result := nil;
  T := Trim(S);
  if (T <> '') and (T[1] = '|') then
    Delete(T, 1, 1);
  if (T <> '') and (T[Length(T)] = '|') and ((Length(T) < 2) or (T[Length(T) - 1] <> '\')) then
    Delete(T, Length(T), 1);
  Cur := '';
  InCode := False;
  I := 1;
  while I <= Length(T) do
  begin
    if T[I] = '`' then
      InCode := not InCode;
    if (T[I] = '\') and (I < Length(T)) and (T[I + 1] = '|') then
    begin
      Cur := Cur + '|';
      Inc(I, 2);
      Continue;
    end;
    if (T[I] = '|') and not InCode then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(Cur);
      Cur := '';
    end
    else
      Cur := Cur + T[I];
    Inc(I);
  end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := Trim(Cur);
end;

{ an HTML block starts with a tag of its own on the line }
{ A line that starts with a tag (<div ...>, </p>, <!-- ): not <https://...>. }
function IsHtmlBlock(const S: string): Boolean;
var
  T: string;
  I: Integer;
begin
  T := TrimLeft(S);
  Result := False;
  if (Indent(S) > 3) or (Length(T) < 3) or (T[1] <> '<') then
    Exit;
  if T[2] = '!' then
    Exit(True);
  I := 2;
  if T[2] = '/' then
    I := 3;
  if (I > Length(T)) or not (T[I] in ['A'..'Z', 'a'..'z']) then
    Exit;
  while (I <= Length(T)) and (T[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-']) do
    Inc(I);
  Result := (I > Length(T)) or (T[I] in [' ', #9, '>', '/']);
end;

{ ---- TMarkdown ---- }

constructor TMarkdown.Create;
begin
  inherited Create;
  FIds := TStringList.Create;
end;

destructor TMarkdown.Destroy;
begin
  FIds.Free;
  inherited Destroy;
end;

function TMarkdown.Link(const Href: string): string;
begin
  if Assigned(FOnLink) then
    Result := FOnLink(Href)
  else
    Result := Href;
end;

function TMarkdown.HeadingId(const Raw: string): string;
var
  Base: string;
  N: Integer;
begin
  Base := MarkdownSlug(Raw);
  Result := Base;
  N := 1;
  while FIds.IndexOf(Result) >= 0 do
  begin
    Result := Base + '-' + IntToStr(N);
    Inc(N);
  end;
  FIds.Add(Result);
end;

{ ---- inline ---- }

{ [text](href "title"): the parts; P at '[' (or '!'); False when it is not a link }
function ParseLink(const S: string; At: Integer; out Text, Href, Title: string; out Next: Integer): Boolean;
var
  I, Depth, J: Integer;
  Dest: string;
begin
  Result := False;
  I := At;
  if S[I] = '!' then
    Inc(I);
  if (I > Length(S)) or (S[I] <> '[') then
    Exit;
  Depth := 0;
  J := I;
  repeat
    if J > Length(S) then
      Exit;
    case S[J] of
      '\': Inc(J);
      '[': Inc(Depth);
      ']': Dec(Depth);
      '`':
        begin
          { a ] in code does not close the text }
          Inc(J);
          while (J <= Length(S)) and (S[J] <> '`') do
            Inc(J);
        end;
    end;
    Inc(J);
  until Depth = 0;
  Text := Copy(S, I + 1, J - I - 2);
  if (J > Length(S)) or (S[J] <> '(') then
    Exit;
  Inc(J);
  Depth := 1;
  Dest := '';
  while (J <= Length(S)) and (Depth > 0) do
  begin
    if S[J] = '(' then Inc(Depth);
    if S[J] = ')' then Dec(Depth);
    if Depth > 0 then
      Dest := Dest + S[J];
    Inc(J);
  end;
  if Depth > 0 then
    Exit;
  Dest := Trim(Dest);
  Title := '';
  I := Pos(' "', Dest);
  if (I > 0) and (Dest[Length(Dest)] = '"') then
  begin
    Title := Copy(Dest, I + 2, Length(Dest) - I - 2);
    Dest := Trim(Copy(Dest, 1, I - 1));
  end;
  if (Dest <> '') and (Dest[1] = '<') and (Dest[Length(Dest)] = '>') then
    Dest := Copy(Dest, 2, Length(Dest) - 2);
  Href := Dest;
  Next := J;
  Result := True;
end;

function TMarkdown.Inline_(const S: string): string;
var
  I, J, N, Next: Integer;
  Text, Href, Title, Code, Tag: string;
  C: Char;

  function CanOpen(At, Len: Integer): Boolean;
  begin
    { not before a space; _ only at the start of a word }
    Result := (At + Len <= Length(S)) and not (S[At + Len] in [' ', #9]);
    if Result and (S[At] = '_') and (At > 1) and (S[At - 1] in ['A'..'Z', 'a'..'z', '0'..'9']) then
      Result := False;
  end;

  { the closing run of the same marker, not after a space }
  function FindClose(From: Integer; const Marker: string): Integer;
  var
    K: Integer;
  begin
    K := From;
    while K <= Length(S) - Length(Marker) + 1 do
    begin
      if S[K] = '`' then
      begin
        Inc(K);
        while (K <= Length(S)) and (S[K] <> '`') do
          Inc(K);
      end
      else if S[K] = '\' then
        Inc(K)
      else if (Copy(S, K, Length(Marker)) = Marker) and (K > From) and not (S[K - 1] in [' ', #9]) and
        ((Marker[1] <> '_') or (K + Length(Marker) > Length(S)) or not (S[K + Length(Marker)] in ['A'..'Z', 'a'..'z', '0'..'9'])) and
        ((Length(Marker) > 1) or (K + 1 > Length(S)) or (S[K + 1] <> Marker[1]) or (Copy(S, K, 2) <> Marker + Marker) or True) then
        Exit(K);
      Inc(K);
    end;
    Result := 0;
  end;

begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    C := S[I];
    { \* and friends }
    if (C = '\') and (I < Length(S)) and (S[I + 1] in ['\', '`', '*', '_', '{', '}', '[', ']', '(', ')', '#', '+', '-', '.', '!', '|', '<', '>', '~', '"', '''']) then
    begin
      Result := Result + Esc(S[I + 1]);
      Inc(I, 2);
      Continue;
    end;
    { a hard break: two spaces or \ at the end of a line }
    if (C = #10) then
    begin
      if (Length(Result) >= 2) and (Copy(Result, Length(Result) - 1, 2) = '  ') then
        Result := TrimRight(Result) + '<br>' + LineEnding
      else
        Result := TrimRight(Result) + LineEnding;
      Inc(I);
      Continue;
    end;
    if C = '`' then
    begin
      N := 0;
      while (I + N <= Length(S)) and (S[I + N] = '`') do
        Inc(N);
      J := PosEx(StringOfChar('`', N), S, I + N);
      while (J > 0) and (J + N <= Length(S)) and (S[J + N] = '`') do
        J := PosEx(StringOfChar('`', N), S, J + N + 1);
      if J > 0 then
      begin
        Code := StringReplace(Copy(S, I + N, J - I - N), #10, ' ', [rfReplaceAll]);
        if (Length(Code) >= 2) and (Code[1] = ' ') and (Code[Length(Code)] = ' ') and (Trim(Code) <> '') then
          Code := Copy(Code, 2, Length(Code) - 2);
        Result := Result + '<code>' + Esc(Code) + '</code>';
        I := J + N;
        Continue;
      end;
      Result := Result + StringOfChar('`', N);
      Inc(I, N);
      Continue;
    end;
    if (C = '!') and (I < Length(S)) and (S[I + 1] = '[') and ParseLink(S, I, Text, Href, Title, Next) then
    begin
      Result := Result + '<img src="' + Esc(Link(Href)) + '" alt="' + Esc(StripTags(Inline_(Text))) + '"' +
        IfThen(Title <> '', ' title="' + Esc(Title) + '"', '') + '>';
      I := Next;
      Continue;
    end;
    if (C = '[') and ParseLink(S, I, Text, Href, Title, Next) then
    begin
      Result := Result + '<a href="' + Esc(Link(Href)) + '"' + IfThen(Title <> '', ' title="' + Esc(Title) + '"', '') + '>' +
        Inline_(Text) + '</a>';
      I := Next;
      Continue;
    end;
    { <https://...> and inline HTML }
    if C = '<' then
    begin
      J := PosEx('>', S, I);
      if J > 0 then
      begin
        Tag := Copy(S, I + 1, J - I - 1);
        if (Pos('://', Tag) > 0) and (Pos(' ', Tag) = 0) then
        begin
          Result := Result + '<a href="' + Esc(Link(Tag)) + '">' + Esc(Tag) + '</a>';
          I := J + 1;
          Continue;
        end;
        if (Pos('@', Tag) > 1) and (Pos(' ', Tag) = 0) and (Pos('.', Tag) > 0) then
        begin
          Result := Result + '<a href="mailto:' + Esc(Tag) + '">' + Esc(Tag) + '</a>';
          I := J + 1;
          Continue;
        end;
        if (Tag <> '') and ((Tag[1] in ['A'..'Z', 'a'..'z', '!']) or ((Tag[1] = '/') and (Length(Tag) > 1) and (Tag[2] in ['A'..'Z', 'a'..'z']))) then
        begin
          Result := Result + '<' + Tag + '>';
          I := J + 1;
          Continue;
        end;
      end;
    end;
    { a bare https:// link (GitHub's) }
    if ((Copy(S, I, 8) = 'https://') or (Copy(S, I, 7) = 'http://')) and ((I = 1) or not (S[I - 1] in ['"', '''', '=', '(', '/'])) then
    begin
      J := I;
      while (J <= Length(S)) and not (S[J] in [' ', #9, #10, '<', '>', '"']) do
        Inc(J);
      { a full stop or a bracket at the end is the sentence's }
      while (J > I) and (S[J - 1] in ['.', ',', ':', ';', ')', '!', '?']) do
        Dec(J);
      Href := Copy(S, I, J - I);
      Result := Result + '<a href="' + Esc(Link(Href)) + '">' + Esc(Href) + '</a>';
      I := J;
      Continue;
    end;
    { **strong**, __strong__, *em*, _em_, ~~del~~ }
    if (C in ['*', '_', '~']) then
    begin
      N := 0;
      while (I + N <= Length(S)) and (S[I + N] = C) do
        Inc(N);
      if (C = '~') and (N = 2) and CanOpen(I, 2) then
      begin
        J := FindClose(I + 2, '~~');
        if J > 0 then
        begin
          Result := Result + '<del>' + Inline_(Copy(S, I + 2, J - I - 2)) + '</del>';
          I := J + 2;
          Continue;
        end;
      end;
      if (C <> '~') and (N >= 2) and CanOpen(I, 2) then
      begin
        if N >= 3 then
        begin
          J := FindClose(I + 3, StringOfChar(C, 3));
          if J > 0 then
          begin
            Result := Result + '<em><strong>' + Inline_(Copy(S, I + 3, J - I - 3)) + '</strong></em>';
            I := J + 3;
            Continue;
          end;
        end;
        J := FindClose(I + 2, StringOfChar(C, 2));
        if J > 0 then
        begin
          Result := Result + '<strong>' + Inline_(Copy(S, I + 2, J - I - 2)) + '</strong>';
          I := J + 2;
          Continue;
        end;
      end;
      if (C <> '~') and (N = 1) and CanOpen(I, 1) then
      begin
        J := I + 1;
        repeat
          J := FindClose(J, C);
          { ** inside *em* is strong, not the end }
          if (J > 0) and (J < Length(S)) and (S[J + 1] = C) then
          begin
            J := FindClose(J + 2, C + C);
            if J > 0 then
              J := J + 2;
            Continue;
          end;
          Break;
        until J = 0;
        if J > 0 then
        begin
          Result := Result + '<em>' + Inline_(Copy(S, I + 1, J - I - 1)) + '</em>';
          I := J + 1;
          Continue;
        end;
      end;
      Result := Result + StringOfChar(C, N);
      Inc(I, N);
      Continue;
    end;
    case C of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '&':
        begin
          J := I + 1;
          while (J <= Length(S)) and (J - I < 10) and (S[J] in ['A'..'Z', 'a'..'z', '0'..'9', '#']) do
            Inc(J);
          if (J <= Length(S)) and (S[J] = ';') and (J > I + 1) then
          begin
            Result := Result + Copy(S, I, J - I + 1);
            I := J + 1;
            Continue;
          end;
          Result := Result + '&amp;';
        end;
    else
      Result := Result + C;
    end;
    Inc(I);
  end;
end;

{ ---- blocks ---- }

procedure TMarkdown.Blocks(Lines: TStrings; Out_: TStringBuilder; Tight: Boolean);
var
  I, J, K, Level, Start, ContentAt, ItemStart, ItemAt, Cols: Integer;
  Fence, Info, Text, Id, Para, Tag: string;
  Ordered, Ord2, Loose, Task: Boolean;
  Sub, Item: TStringList;
  Head, Row: TStringArray;
  Aligns: TStringArray;
  ItemOut: TStringBuilder;

  function Line(N: Integer): string;
  begin
    if N < Lines.Count then Result := Lines[N] else Result := '';
  end;

  { a line that ends a paragraph }
  function Interrupts(const S: string): Boolean;
  var
    F, Inf, T: string;
    O: Boolean;
    St, CA: Integer;
  begin
    Result := IsBlank(S) or IsFence(S, F, Inf) or (HeadingLevel(S, T) > 0) or IsRule(S) or
      (TrimLeft(S) <> '') and (TrimLeft(S)[1] = '>') and (Indent(S) <= 3) or
      (ListItem(S, O, St, CA) and (not O or (St = 1)) and not IsBlank(Copy(S, CA + 1, MaxInt))) or
      IsHtmlBlock(S) and (Pos('<!--', TrimLeft(S)) = 1);
  end;

begin
  I := 0;
  while I < Lines.Count do
  begin
    if IsBlank(Lines[I]) then
    begin
      Inc(I);
      Continue;
    end;
    { ``` code ``` }
    if IsFence(Lines[I], Fence, Info) then
    begin
      Level := Indent(Lines[I]);
      Info := ExtractDelimited(1, Info, [' ']);
      if Info <> '' then
        Out_.Append('<pre><code class="language-' + Esc(Info) + '">')
      else
        Out_.Append('<pre><code>');
      Inc(I);
      while (I < Lines.Count) and not ((Indent(Lines[I]) <= 3) and (Copy(Trim(Lines[I]), 1, Length(Fence)) = Fence) and
        (Trim(StringReplace(Trim(Lines[I]), Fence[1], '', [rfReplaceAll])) = '')) do
      begin
        Out_.Append(Esc(Dedent(Lines[I], Level)) + #10);
        Inc(I);
      end;
      Out_.Append('</code></pre>' + LineEnding);
      Inc(I);
      Continue;
    end;
    Level := HeadingLevel(Lines[I], Text);
    if Level > 0 then
    begin
      Id := HeadingId(Text);
      Out_.Append(Format('<h%d id="%s">', [Level, Id]));
      if FHeadingAnchors then
        Out_.Append('<a class="anchor" href="#' + Id + '">#</a>');
      Out_.Append(Inline_(Text) + Format('</h%d>', [Level]) + LineEnding);
      Inc(I);
      Continue;
    end;
    if IsRule(Lines[I]) then
    begin
      Out_.Append('<hr>' + LineEnding);
      Inc(I);
      Continue;
    end;
    { > quote }
    if (Indent(Lines[I]) <= 3) and (TrimLeft(Lines[I])[1] = '>') then
    begin
      Sub := TStringList.Create;
      try
        while (I < Lines.Count) and not IsBlank(Lines[I]) do
        begin
          Text := TrimLeft(Lines[I]);
          if (Text <> '') and (Text[1] = '>') then
          begin
            Delete(Text, 1, 1);
            if (Text <> '') and (Text[1] = ' ') then
              Delete(Text, 1, 1);
          end;
          Sub.Add(Text);
          Inc(I);
        end;
        Out_.Append('<blockquote>' + LineEnding);
        Blocks(Sub, Out_, False);
        Out_.Append('</blockquote>' + LineEnding);
      finally
        Sub.Free;
      end;
      Continue;
    end;
    { lists }
    if ListItem(Lines[I], Ordered, Start, ContentAt) then
    begin
      ItemAt := Indent(Lines[I]);
      Loose := False;
      if Ordered then
      begin
        if Start <> 1 then
          Out_.Append('<ol start="' + IntToStr(Start) + '">' + LineEnding)
        else
          Out_.Append('<ol>' + LineEnding);
      end
      else
        Out_.Append('<ul>' + LineEnding);
      Item := TStringList.Create;
      Sub := TStringList.Create;
      try
        { first the items' lines, to know whether the list is loose }
        J := I;
        while J < Lines.Count do
        begin
          if IsBlank(Lines[J]) then
          begin
            K := J + 1;
            while (K < Lines.Count) and IsBlank(Lines[K]) do
              Inc(K);
            if (K < Lines.Count) and ((Indent(Lines[K]) >= ContentAt) or
              ListItem(Lines[K], Ord2, Start, ItemStart) and (Ord2 = Ordered) and (Indent(Lines[K]) = ItemAt)) then
            begin
              Loose := True;      { a blank line between items, or between the blocks of one }
              J := K;
              Continue;
            end;
            Break;
          end;
          if (Indent(Lines[J]) < ContentAt) and not ListItem(Lines[J], Ord2, Start, ItemStart) and
             Interrupts(Lines[J]) then
            Break;
          if ListItem(Lines[J], Ord2, Start, ItemStart) and (Indent(Lines[J]) < ItemAt) then
            Break;
          if ListItem(Lines[J], Ord2, Start, ItemStart) and (Indent(Lines[J]) = ItemAt) and (Ord2 <> Ordered) then
            Break;
          Inc(J);
        end;
        { then each item, its lines parsed as blocks }
        while I < J do
        begin
          ListItem(Lines[I], Ord2, Start, ContentAt);
          Item.Clear;
          Item.Add(Copy(Lines[I], ContentAt + 1, MaxInt));
          Inc(I);
          while (I < J) and not ((Indent(Lines[I]) = ItemAt) and ListItem(Lines[I], Ord2, Start, ItemStart)) do
          begin
            if IsBlank(Lines[I]) then
              Item.Add('')
            else if Indent(Lines[I]) >= ContentAt then
              Item.Add(Dedent(Lines[I], ContentAt))
            else
              Item.Add(TrimLeft(Lines[I]));     { a lazy line of the paragraph }
            Inc(I);
          end;
          while (Item.Count > 0) and IsBlank(Item[Item.Count - 1]) do
            Item.Delete(Item.Count - 1);
          { - [ ] and - [x]: a task }
          Task := False;
          Text := Item[0];
          if (Copy(Text, 1, 4) = '[ ] ') or (LowerCase(Copy(Text, 1, 4)) = '[x] ') then
          begin
            Task := True;
            Item[0] := Copy(Text, 5, MaxInt);
          end;
          Out_.Append('<li>');
          if Task then
            Out_.Append('<input type="checkbox" disabled' + IfThen(LowerCase(Text[2]) = 'x', ' checked', '') + '> ');
          Sub.Clear;
          ItemOut := TStringBuilder.Create;
          try
            Blocks(Item, ItemOut, not Loose);
            Out_.Append(TrimRight(ItemOut.ToString));
          finally
            ItemOut.Free;
          end;
          Out_.Append('</li>' + LineEnding);
        end;
      finally
        Item.Free;
        Sub.Free;
      end;
      if Ordered then
        Out_.Append('</ol>' + LineEnding)
      else
        Out_.Append('</ul>' + LineEnding);
      I := J;
      Continue;
    end;
    { a table: a header, a line of --- and the rows }
    if (Pos('|', Lines[I]) > 0) and IsTableSeparator(Line(I + 1)) and (Length(Cells(Lines[I])) = Length(Cells(Line(I + 1)))) then
    begin
      Head := Cells(Lines[I]);
      Aligns := Cells(Line(I + 1));
      Cols := Length(Head);
      for K := 0 to Cols - 1 do
      begin
        Text := Trim(Aligns[K]);
        if (Text <> '') and (Text[1] = ':') and (Text[Length(Text)] = ':') then Aligns[K] := 'center'
        else if (Text <> '') and (Text[Length(Text)] = ':') then Aligns[K] := 'right'
        else if (Text <> '') and (Text[1] = ':') then Aligns[K] := 'left'
        else Aligns[K] := '';
      end;
      Out_.Append('<table>' + LineEnding + '<thead>' + LineEnding + '<tr>' + LineEnding);
      for K := 0 to Cols - 1 do
        Out_.Append('<th' + IfThen(Aligns[K] <> '', ' align="' + Aligns[K] + '"', '') + '>' + Inline_(Head[K]) + '</th>' + LineEnding);
      Out_.Append('</tr>' + LineEnding + '</thead>' + LineEnding);
      Inc(I, 2);
      if (I < Lines.Count) and not IsBlank(Lines[I]) and (Pos('|', Lines[I]) > 0) then
        Out_.Append('<tbody>');
      Tag := '';
      while (I < Lines.Count) and not IsBlank(Lines[I]) and (Pos('|', Lines[I]) > 0) do
      begin
        Tag := '</tbody>';
        Row := Cells(Lines[I]);
        Out_.Append('<tr>' + LineEnding);
        for K := 0 to Cols - 1 do
        begin
          if K < Length(Row) then Text := Row[K] else Text := '';
          Out_.Append('<td' + IfThen(Aligns[K] <> '', ' align="' + Aligns[K] + '"', '') + '>' + Inline_(Text) + '</td>' + LineEnding);
        end;
        Out_.Append('</tr>' + LineEnding);
        Inc(I);
      end;
      Out_.Append(Tag + '</table>' + LineEnding);
      Continue;
    end;
    { a comment: up to the line with its end (a fence may follow at once) }
    if IsHtmlBlock(Lines[I]) and (Pos('<!--', TrimLeft(Lines[I])) = 1) then
    begin
      repeat
        Out_.Append(Lines[I] + LineEnding);
        Inc(I);
      until (I >= Lines.Count) or (Pos('-->', Lines[I - 1]) > 0);
      Continue;
    end;
    { HTML as it is, up to a blank line }
    if IsHtmlBlock(Lines[I]) then
    begin
      while (I < Lines.Count) and not IsBlank(Lines[I]) do
      begin
        Out_.Append(Lines[I] + LineEnding);
        Inc(I);
      end;
      Continue;
    end;
    { code indented by 4 spaces }
    if Indent(Lines[I]) >= 4 then
    begin
      Out_.Append('<pre><code>');
      while (I < Lines.Count) and ((Indent(Lines[I]) >= 4) or IsBlank(Lines[I]) and (I + 1 < Lines.Count) and
        (Indent(Lines[I + 1]) >= 4)) do
      begin
        Out_.Append(Esc(Dedent(Lines[I], 4)) + #10);
        Inc(I);
      end;
      Out_.Append('</code></pre>' + LineEnding);
      Continue;
    end;
    { a paragraph }
    Para := TrimLeft(Lines[I]);
    Inc(I);
    while (I < Lines.Count) and not Interrupts(Lines[I]) and
      not ((Pos('|', Lines[I]) > 0) and IsTableSeparator(Line(I + 1))) do
    begin
      Para := Para + #10 + TrimLeft(Lines[I]);
      Inc(I);
    end;
    if Tight then
      Out_.Append(Inline_(TrimRight(Para)) + LineEnding)
    else
      Out_.Append('<p>' + Inline_(TrimRight(Para)) + '</p>' + LineEnding);
  end;
end;

function TMarkdown.Render(const Text: string): string;
var
  L: TStringList;
  Out_: TStringBuilder;
begin
  FIds.Clear;
  L := TStringList.Create;
  Out_ := TStringBuilder.Create;
  try
    L.Text := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
    Blocks(L, Out_, False);
    Result := Out_.ToString;
  finally
    Out_.Free;
    L.Free;
  end;
end;

end.
