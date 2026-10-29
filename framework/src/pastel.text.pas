{ Pastel - text helpers that understand UTF-8.

  Free Pascal's UpperCase and LowerCase only change the English letters A-Z;
  these work for every language:

    Upper('ayşe')            = 'AYŞE'
    Upper('istanbul', 'tr')  = 'İSTANBUL'   (Turkish and Azerbaijani i/İ, ı/I)
    CharCount('ağaç')        = 4            (Length gives 6: it counts bytes)
  Part of the Pastel project, MIT License. }
unit Pastel.Text;

{$mode objfpc}{$H+}

interface

{ Lang: '' for the general rules, 'tr' or 'az' for dotted and dotless i. }
function Upper(const S: string; const Lang: string = ''): string;
function Lower(const S: string; const Lang: string = ''): string;
{ First letter upper case, the rest unchanged. }
function Capitalize(const S: string; const Lang: string = ''): string;
{ Number of characters (Length counts bytes). }
function CharCount(const S: string): Integer;
{ Characters Start..Start+Count-1, counting characters from 1. }
function CharCopy(const S: string; Start, Count: Integer): string;
{ Shortens to at most MaxChars characters, ending with "…" when cut. }
function Shorten(const S: string; MaxChars: Integer): string;

implementation

uses
  SysUtils, unicodedata;

function IsTurkic(const Lang: string): Boolean;
begin
  Result := SameText(Lang, 'tr') or SameText(Lang, 'az');
end;

function Upper(const S: string; const Lang: string): string;
var
  U, R: UnicodeString;
begin
  if IsTurkic(Lang) then
    U := UTF8Decode(StringReplace(S, 'i', 'İ', [rfReplaceAll]))
  else
    U := UTF8Decode(S);
  if UnicodeToUpper(U, True, R) <> 0 then
    R := U;
  Result := UTF8Encode(R);
end;

function Lower(const S: string; const Lang: string): string;
var
  U, R: UnicodeString;
  T: string;
begin
  T := S;
  if IsTurkic(Lang) then
  begin
    T := StringReplace(T, 'I', 'ı', [rfReplaceAll]);
    T := StringReplace(T, 'İ', 'i', [rfReplaceAll]);
  end;
  U := UTF8Decode(T);
  if UnicodeToLower(U, True, R) <> 0 then
    R := U;
  Result := UTF8Encode(R);
end;

function CharLen(B: Byte): Integer; inline;
begin
  if B < $80 then Result := 1
  else if (B and $E0) = $C0 then Result := 2
  else if (B and $F0) = $E0 then Result := 3
  else if (B and $F8) = $F0 then Result := 4
  else Result := 1;
end;

function CharCount(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Inc(I, CharLen(Ord(S[I])));
    Inc(Result);
  end;
end;

function CharCopy(const S: string; Start, Count: Integer): string;
var
  I, N, From: Integer;
begin
  Result := '';
  if (Count <= 0) or (Start < 1) then
    Exit;
  I := 1;
  N := 1;
  while (I <= Length(S)) and (N < Start) do
  begin
    Inc(I, CharLen(Ord(S[I])));
    Inc(N);
  end;
  From := I;
  N := 0;
  while (I <= Length(S)) and (N < Count) do
  begin
    Inc(I, CharLen(Ord(S[I])));
    Inc(N);
  end;
  Result := Copy(S, From, I - From);
end;

function Capitalize(const S: string; const Lang: string): string;
begin
  Result := Upper(CharCopy(S, 1, 1), Lang) + CharCopy(S, 2, MaxInt);
end;

function Shorten(const S: string; MaxChars: Integer): string;
begin
  if CharCount(S) <= MaxChars then
    Result := S
  else if MaxChars <= 1 then
    Result := CharCopy('…', 1, MaxChars)
  else
    Result := CharCopy(S, 1, MaxChars - 1) + '…';
end;

end.
