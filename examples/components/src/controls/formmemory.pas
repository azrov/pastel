{ TFormMemory - remembers what the user entered in a form, between runs.

    object Memory: TFormMemory
      Fields = ('NameEdit', 'CityCombo', 'DarkSwitch')
      FileName = 'order-form.json'
    end

    procedure THomeForm.FormCreate(Sender: TObject);
    begin
      Memory.Restore;        // the values of the last run
    end;

    procedure THomeForm.FormClose(Sender: TObject);
    begin
      Memory.Store;
    end;

  The values go to a JSON file in the user's settings folder
  (~/.config/<program>/ on Linux, AppData\Local\<program>\ on Windows).
  An example of a component without a place on the form (like TTimer): it is
  a TDataBinding (which knows how to read and set the controls) that also
  writes a file. }
unit FormMemory;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI, Pastel.Binding;

type
  TFormMemory = class(TDataBinding)
  private
    FFileName: string;
  public
    { The full path of the file. }
    function FilePath: string;
    { Sets the controls to the stored values; False when nothing was stored yet. }
    function Restore: Boolean;
    { Writes the controls' values to the file. }
    procedure Store;
    { Deletes the file: the next start begins empty. }
    procedure Forget;
  published
    { The file name in the settings folder; 'form.json' when empty. }
    property FileName: string read FFileName write FFileName;
  end;

implementation

uses
  fpjson, jsonparser, Pastel.Files;

function TFormMemory.FilePath: string;
var
  N: string;
begin
  N := FFileName;
  if N = '' then
    N := 'form.json';
  if (ExtractFilePath(N) <> '') and (N[1] in ['/', '\', '.']) then
    Exit(N);     { a path of its own }
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + N;
end;

function TFormMemory.Restore: Boolean;
var
  D: TJSONData;
begin
  Result := False;
  if not FileExists(FilePath) then
    Exit;
  try
    D := GetJSON(ReadText(FilePath));
  except
    Exit;      { a broken file: start empty }
  end;
  try
    if D is TJSONObject then
    begin
      Load(TJSONObject(D));
      Result := True;
    end;
  finally
    D.Free;
  end;
end;

procedure TFormMemory.Store;
var
  O: TJSONObject;
begin
  O := ToJson;
  try
    ForceDirectories(ExtractFileDir(FilePath));
    WriteText(FilePath, O.FormatJSON);
  finally
    O.Free;
  end;
end;

procedure TFormMemory.Forget;
begin
  DeleteFileIfExists(FilePath);
end;

initialization
  RegisterNonVisual(TFormMemory);
end.
