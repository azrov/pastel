{ Counting what is in a text, for the status bar. }
unit TextStats;

{$mode objfpc}{$H+}

interface

{ The number of words in S (separated by spaces, tabs or line breaks). }
function WordCount(const S: string): Integer;
{ The number of lines in S; an empty text has one. }
function LineCount(const S: string): Integer;

implementation

function WordCount(const S: string): Integer;
var
  I: Integer;
  InWord: Boolean;
begin
  Result := 0;
  InWord := False;
  for I := 1 to Length(S) do
    if S[I] in [' ', #9, #10, #13] then
      InWord := False
    else if not InWord then
    begin
      InWord := True;
      Inc(Result);
    end;
end;

function LineCount(const S: string): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Length(S) do
    if S[I] = #10 then
      Inc(Result);
end;

end.
