{ The notes, kept in memory and saved to a JSON file after every change.
  Requests come in on several threads at once, so every method takes the
  lock first. }
unit Notes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson;

type
  ENoteError = class(Exception);

  TNoteStore = class
  private
    FLock: TCriticalSection;
    FNotes: TJSONArray;       // [{"id": 1, "title": "...", "text": "...", "created": "..."}]
    FNextId: Int64;
    FFileName: string;
    function IndexOf(Id: Int64): Integer;
    procedure Save;
    class procedure Check(const Title, Text: string);
  public
    { FileName: where the notes are kept; '' keeps them only in memory }
    constructor Create(const AFileName: string = '');
    destructor Destroy; override;
    { all notes, newest first; the caller frees the result }
    function List: TJSONArray;
    { a copy of the note, or nil }
    function Find(Id: Int64): TJSONObject;
    function Add(const Title, Text: string): TJSONObject;
    function Update(Id: Int64; const Title, Text: string): TJSONObject;
    function Remove(Id: Int64): Boolean;
    function Count: Integer;
  end;

implementation

uses
  DateUtils, Pastel.Json, Pastel.Files;

constructor TNoteStore.Create(const AFileName: string);
var
  Data: TJSONData;
  I: Integer;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFileName := AFileName;
  FNotes := TJSONArray.Create;
  FNextId := 1;
  if (FFileName <> '') and FileExists(FFileName) then
  begin
    Data := ParseJson(ReadText(FFileName));
    if Data is TJSONArray then
    begin
      FNotes.Free;
      FNotes := TJSONArray(Data);
    end
    else
      Data.Free;
    for I := 0 to FNotes.Count - 1 do
      if JInt(FNotes[I], 'id') >= FNextId then
        FNextId := JInt(FNotes[I], 'id') + 1;
  end;
end;

destructor TNoteStore.Destroy;
begin
  FNotes.Free;
  FLock.Free;
  inherited Destroy;
end;

class procedure TNoteStore.Check(const Title, Text: string);
begin
  if Trim(Title) = '' then
    raise ENoteError.Create('title is required');
  if Length(Title) > 200 then
    raise ENoteError.Create('title is too long (200 characters at most)');
  if Length(Text) > 100000 then
    raise ENoteError.Create('text is too long');
end;

function TNoteStore.IndexOf(Id: Int64): Integer;
begin
  for Result := 0 to FNotes.Count - 1 do
    if JInt(FNotes[Result], 'id') = Id then
      Exit;
  Result := -1;
end;

procedure TNoteStore.Save;
begin
  if FFileName <> '' then
    WriteText(FFileName, ToJson(FNotes, True));
end;

function TNoteStore.List: TJSONArray;
var
  I: Integer;
begin
  FLock.Acquire;
  try
    Result := TJSONArray.Create;
    for I := FNotes.Count - 1 downto 0 do
      Result.Add(FNotes[I].Clone);
  finally
    FLock.Release;
  end;
end;

function TNoteStore.Find(Id: Int64): TJSONObject;
var
  I: Integer;
begin
  FLock.Acquire;
  try
    I := IndexOf(Id);
    if I < 0 then
      Result := nil
    else
      Result := TJSONObject(FNotes[I].Clone);
  finally
    FLock.Release;
  end;
end;

function TNoteStore.Add(const Title, Text: string): TJSONObject;
var
  Note: TJSONObject;
begin
  Check(Title, Text);
  FLock.Acquire;
  try
    Note := JObject(['id', FNextId, 'title', Trim(Title), 'text', Text,
      'created', DateToISO8601(LocalTimeToUniversal(Now))]);
    Inc(FNextId);
    FNotes.Add(Note);
    Save;
    Result := TJSONObject(Note.Clone);
  finally
    FLock.Release;
  end;
end;

function TNoteStore.Update(Id: Int64; const Title, Text: string): TJSONObject;
var
  I: Integer;
  Note: TJSONObject;
begin
  Check(Title, Text);
  FLock.Acquire;
  try
    I := IndexOf(Id);
    if I < 0 then
      Exit(nil);
    Note := TJSONObject(FNotes[I]);
    Note.Strings['title'] := Trim(Title);
    Note.Strings['text'] := Text;
    Save;
    Result := TJSONObject(Note.Clone);
  finally
    FLock.Release;
  end;
end;

function TNoteStore.Remove(Id: Int64): Boolean;
var
  I: Integer;
begin
  FLock.Acquire;
  try
    I := IndexOf(Id);
    Result := I >= 0;
    if Result then
    begin
      FNotes.Delete(I);
      Save;
    end;
  finally
    FLock.Release;
  end;
end;

function TNoteStore.Count: Integer;
begin
  FLock.Acquire;
  try
    Result := FNotes.Count;
  finally
    FLock.Release;
  end;
end;

end.
