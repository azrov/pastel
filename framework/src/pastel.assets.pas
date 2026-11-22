{ Pastel - the files of a project's assets/ folder, inside the program.

    Logo.FileName := 'logo.png';            // TImage finds assets by name
    S := OpenAsset('data/cities.json');     // any file, as a stream
    try ... finally S.Free; end;

  "pastel build" compiles every file below assets/ into the program (in
  release builds; debug builds read them from the folder, so changes show
  without a rebuild). Names use / and are relative to assets/.
  Conventions: assets/icon.png is the window icon; assets/font.ttf and
  assets/font-bold.ttf replace the system font.
  Part of the Pastel project, MIT License. }
unit Pastel.Assets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  EAssetNotFound = class(Exception);

{ Called by the code "pastel build" generates. }
procedure RegisterAsset(const Name: string; Data: Pointer; Size: Integer);
procedure RegisterAssetFile(const Name, FileName: string);

function AssetExists(const Name: string): Boolean;
{ The asset as a stream; the caller frees it. EAssetNotFound when there is none. }
function OpenAsset(const Name: string): TStream;
{ The asset's bytes. }
function AssetBytes(const Name: string): TBytes;
function AssetText(const Name: string): string;
{ The names of all assets ('logo.png', 'data/cities.json'). }
function AssetNames: TStringArray;

implementation

type
  TAsset = class
    Data: Pointer;
    Size: Integer;
    FileName: string;
  end;

var
  Assets: TStringList = nil;

function Normalize(const Name: string): string;
begin
  Result := StringReplace(Name, '\', '/', [rfReplaceAll]);
  while Copy(Result, 1, 2) = './' do
    Delete(Result, 1, 2);
  if Copy(Result, 1, 7) = 'assets/' then
    Delete(Result, 1, 7);
end;

procedure Add(const Name: string; A: TAsset);
var
  I: Integer;
begin
  I := Assets.IndexOf(Normalize(Name));
  if I >= 0 then
    Assets.Delete(I);
  Assets.AddObject(Normalize(Name), A);
end;

procedure RegisterAsset(const Name: string; Data: Pointer; Size: Integer);
var
  A: TAsset;
begin
  A := TAsset.Create;
  A.Data := Data;
  A.Size := Size;
  Add(Name, A);
end;

procedure RegisterAssetFile(const Name, FileName: string);
var
  A: TAsset;
begin
  A := TAsset.Create;
  A.FileName := FileName;
  Add(Name, A);
end;

{ not registered: a file in assets/ next to the program or in the current folder }
function DiskFile(const Name: string): string;
var
  F: string;
begin
  for F in [ExtractFilePath(ParamStr(0)) + 'assets' + PathDelim + Name, 'assets' + PathDelim + Name] do
    if FileExists(F) then
      Exit(F);
  Result := '';
end;

function AssetExists(const Name: string): Boolean;
begin
  Result := (Assets.IndexOf(Normalize(Name)) >= 0) or (DiskFile(Normalize(Name)) <> '');
end;

function OpenAsset(const Name: string): TStream;
var
  I: Integer;
  A: TAsset;
  F: string;
  M: TMemoryStream;
begin
  I := Assets.IndexOf(Normalize(Name));
  if I >= 0 then
  begin
    A := TAsset(Assets.Objects[I]);
    if A.FileName <> '' then
      Exit(TFileStream.Create(A.FileName, fmOpenRead or fmShareDenyWrite));
    M := TMemoryStream.Create;
    M.WriteBuffer(A.Data^, A.Size);
    M.Position := 0;
    Exit(M);
  end;
  F := DiskFile(Normalize(Name));
  if F = '' then
    raise EAssetNotFound.CreateFmt('there is no asset "%s" (a file in assets/)', [Name]);
  Result := TFileStream.Create(F, fmOpenRead or fmShareDenyWrite);
end;

function AssetBytes(const Name: string): TBytes;
var
  S: TStream;
begin
  Result := nil;
  S := OpenAsset(Name);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[0], S.Size);
  finally
    S.Free;
  end;
end;

function AssetText(const Name: string): string;
var
  B: TBytes;
begin
  Result := '';
  B := AssetBytes(Name);
  if Length(B) > 0 then
    SetString(Result, PChar(@B[0]), Length(B));
end;

function AssetNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Assets.Count);
  for I := 0 to Assets.Count - 1 do
    Result[I] := Assets[I];
end;

initialization
  Assets := TStringList.Create;
  Assets.Sorted := True;
  Assets.CaseSensitive := True;
  Assets.OwnsObjects := True;

finalization
  FreeAndNil(Assets);

end.
