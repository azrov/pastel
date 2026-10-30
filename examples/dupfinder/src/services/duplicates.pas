{ Finding files with the same content: first files of the same size (cheap,
  no reading), then, among those, the same MD5 checksum. }
unit Duplicates;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TDupGroup = record
    Size: Int64;
    Files: TStringArray;     { sorted }
  end;
  TDupGroups = array of TDupGroup;

  { called before a file is read, for a progress bar }
  TCheckProc = procedure(const FileName: string);

{ '500', '1k', '2.5M', '1G' (also with B: '10MB') -> bytes; EConvertError if not a size }
function ParseSize(const S: string): Int64;

{ The files that have the same size as at least one other file and are not
  smaller than MinSize: only these can be duplicates. }
function SameSizeFiles(const Files: array of string; MinSize: Int64): TStringArray;

{ Groups of files with equal content, the most wasted space first. }
function FindDuplicates(const Files: array of string; MinSize: Int64;
  OnCheck: TCheckProc = nil): TDupGroups;

{ Space that deleting all but one file of the group would free. }
function Wasted(const G: TDupGroup): Int64;

implementation

uses
  Classes, md5, Pastel.Files;

function ParseSize(const S: string): Int64;
var
  T: string;
  Factor: Int64;
  V: Double;
  FS: TFormatSettings;
begin
  T := UpperCase(Trim(S));
  if (T <> '') and (T[Length(T)] = 'B') then
    SetLength(T, Length(T) - 1);
  Factor := 1;
  if T <> '' then
    case T[Length(T)] of
      'K': Factor := 1024;
      'M': Factor := 1024 * 1024;
      'G': Factor := 1024 * 1024 * 1024;
      'T': Factor := Int64(1024) * 1024 * 1024 * 1024;
    end;
  if Factor > 1 then
    SetLength(T, Length(T) - 1);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(Trim(T), V, FS) or (V < 0) then
    raise EConvertError.CreateFmt('"%s" is not a size; use a number with k, M or G, like 10M', [S]);
  Result := Round(V * Factor);
end;

{ "000000000123|path": sorts by size }
function SizeKey(Size: Int64; const FileName: string): string;
begin
  Result := Format('%.20d|%s', [Size, FileName]);
end;

function KeyPart(const Key: string): string;
begin
  Result := Copy(Key, 1, Pos('|', Key) - 1);
end;

function FilePart(const Key: string): string;
begin
  Result := Copy(Key, Pos('|', Key) + 1, MaxInt);
end;

function SameSizeFiles(const Files: array of string; MinSize: Int64): TStringArray;
var
  L: TStringList;
  F: string;
  Size: Int64;
  I: Integer;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    for F in Files do
    begin
      Size := FileSize(F);
      if (Size > 0) and (Size >= MinSize) then
        L.Add(SizeKey(Size, F));
    end;
    for I := 0 to L.Count - 1 do
      if ((I > 0) and (KeyPart(L[I - 1]) = KeyPart(L[I]))) or
         ((I < L.Count - 1) and (KeyPart(L[I + 1]) = KeyPart(L[I]))) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := FilePart(L[I]);
      end;
  finally
    L.Free;
  end;
end;

function Wasted(const G: TDupGroup): Int64;
begin
  Result := G.Size * (Length(G.Files) - 1);
end;

procedure SortByWaste(var Groups: TDupGroups);
var
  I, J: Integer;
  G: TDupGroup;
begin
  for I := 1 to High(Groups) do
  begin
    G := Groups[I];
    J := I - 1;
    while (J >= 0) and (Wasted(Groups[J]) < Wasted(G)) do
    begin
      Groups[J + 1] := Groups[J];
      Dec(J);
    end;
    Groups[J + 1] := G;
  end;
end;

function FindDuplicates(const Files: array of string; MinSize: Int64;
  OnCheck: TCheckProc): TDupGroups;
var
  Candidates: TStringArray;
  L: TStringList;
  F: string;
  I, J, K: Integer;
  G: TDupGroup;
begin
  Result := nil;
  Candidates := SameSizeFiles(Files, MinSize);
  L := TStringList.Create;
  try
    L.Sorted := True;
    { "size-md5|path": equal keys mean equal content }
    for F in Candidates do
    begin
      if Assigned(OnCheck) then
        OnCheck(F);
      L.Add(Format('%.20d-%s|%s', [FileSize(F), MD5Print(MD5File(F)), F]));
    end;
    I := 0;
    while I < L.Count do
    begin
      J := I;
      while (J + 1 < L.Count) and (KeyPart(L[J + 1]) = KeyPart(L[I])) do
        Inc(J);
      if J > I then
      begin
        G.Size := StrToInt64(Copy(L[I], 1, 20));
        G.Files := nil;
        SetLength(G.Files, J - I + 1);
        for K := I to J do
          G.Files[K - I] := FilePart(L[K]);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := G;
      end;
      I := J + 1;
    end;
  finally
    L.Free;
  end;
  SortByWaste(Result);
end;

end.
