(* Pastel - settings from files, environment variables and code.

    Config := TConfig.Create('myapp');
    Config.SetDefault('server.port', '8080');
    Config.LoadStandard;                 // see below
    Port := Config.GetInt('server.port');
    Host := Config.Get('database.host', 'localhost');
    Pass := Config.Require('database.password');   // clear error if missing

  A setting can come from several places; the later one wins:
    1. SetDefault in code
    2. /etc/myapp/config.toml          (Linux; on Windows %ProgramData%\myapp)
    3. ~/.config/myapp/config.toml     (the user's own settings)
    4. ./config.toml                   (next to where the program runs)
    5. environment: MYAPP_SERVER_PORT for server.port
    6. Config.SetValue in code, e.g. from a command-line option
  LoadStandard loads 2-5; LoadFile and LoadEnv do it step by step.
  Files can be TOML or JSON. Config.Source('server.port') tells where a
  value came from, which helps when something is not what you expect.
  Part of the Pastel project, MIT License. *)
unit Pastel.Config;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Env;

type
  EConfigError = class(Exception);

  TConfig = class
  private
    FAppName: string;
    FEnvPrefix: string;
    FValues: TStringList;      { files and defaults }
    FOverrides: TStringList;   { SetValue }
    FFiles: TStringList;
    procedure Store(List: TStringList; const Key, Value: string; const Items: TStringArray;
      IsList: Boolean; const Source: string);
    function Lookup(const Key: string; out Value: string; out Items: TStringArray;
      out IsList: Boolean; out Source: string): Boolean;
    function EnvName(const Key: string): string;
    procedure LoadToml(const FileName, Text: string);
    procedure LoadJson(const FileName, Text: string);
  public
    constructor Create(const AAppName: string = '');
    destructor Destroy; override;

    procedure SetDefault(const Key, Value: string);
    { Highest priority: for values from the command line. }
    procedure SetValue(const Key, Value: string);

    { Loads a .toml or .json file. Raises EConfigError (with file and line)
      for mistakes, and when the file does not exist. }
    procedure LoadFile(const FileName: string);
    { Same, but a missing file is fine. Returns True if it was loaded. }
    function LoadFileIfExists(const FileName: string): Boolean;
    { Settings from environment variables PREFIX_SECTION_KEY. Default prefix:
      the app name in capitals, with - turned into _. }
    procedure LoadEnv(const Prefix: string = '');
    { System file, user file, ./config.toml (or .json), then the environment. }
    procedure LoadStandard;

    function Has(const Key: string): Boolean;
    function Get(const Key: string; const Default: string = ''): string;
    function GetInt(const Key: string; Default: Int64 = 0): Int64;
    function GetFloat(const Key: string; Default: Double = 0): Double;
    function GetBool(const Key: string; Default: Boolean = False): Boolean;
    { A list: a TOML/JSON array, or comma-separated text (handy in environment variables). }
    function GetList(const Key: string): TStringArray;
    { The value, or an EConfigError explaining how to set it. }
    function Require(const Key: string): string;
    { Where the value came from: a file name, 'environment NAME', 'default' or 'set in code'. }
    function Source(const Key: string): string;
    { All known keys (from files and defaults), sorted. }
    function Keys: TStringArray;
    { Files that were loaded, in order. }
    property Files: TStringList read FFiles;
    property AppName: string read FAppName;
  end;

{ Standard folders for an app's settings on this system. }
function SystemConfigDir(const AppName: string): string;
function UserConfigDir(const AppName: string): string;

implementation

uses
  Pastel.Toml, fpjson, Pastel.Json;

type
  TEntry = class
    Value: string;
    Items: TStringArray;
    IsList: Boolean;
    Source: string;
  end;

function SystemConfigDir(const AppName: string): string;
begin
  {$IFDEF WINDOWS}
  Result := IncludeTrailingPathDelimiter(GetEnv('ProgramData')) + AppName;
  {$ELSE}
  Result := '/etc/' + AppName;
  {$ENDIF}
end;

function UserConfigDir(const AppName: string): string;
var
  Base: string;
begin
  {$IFDEF WINDOWS}
  Base := GetEnv('APPDATA');
  {$ELSE}
  Base := GetEnv('XDG_CONFIG_HOME');
  if Base = '' then
    Base := IncludeTrailingPathDelimiter(GetEnv('HOME')) + '.config';
  {$ENDIF}
  Result := IncludeTrailingPathDelimiter(Base) + AppName;
end;

constructor TConfig.Create(const AAppName: string);
begin
  inherited Create;
  FAppName := AAppName;
  if FAppName = '' then
    FAppName := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  FValues := TStringList.Create;
  FValues.Sorted := True;
  FValues.CaseSensitive := False;
  FValues.OwnsObjects := True;
  FOverrides := TStringList.Create;
  FOverrides.Sorted := True;
  FOverrides.CaseSensitive := False;
  FOverrides.OwnsObjects := True;
  FFiles := TStringList.Create;
end;

destructor TConfig.Destroy;
begin
  FValues.Free;
  FOverrides.Free;
  FFiles.Free;
  inherited Destroy;
end;

procedure TConfig.Store(List: TStringList; const Key, Value: string; const Items: TStringArray;
  IsList: Boolean; const Source: string);
var
  I: Integer;
  E: TEntry;
begin
  I := List.IndexOf(Key);
  if I >= 0 then
    E := TEntry(List.Objects[I])
  else
  begin
    E := TEntry.Create;
    List.AddObject(Key, E);
  end;
  E.Value := Value;
  E.Items := Copy(Items);
  E.IsList := IsList;
  E.Source := Source;
end;

procedure TConfig.SetDefault(const Key, Value: string);
begin
  { a default never replaces a value that is already there }
  if FValues.IndexOf(Key) < 0 then
    Store(FValues, Key, Value, nil, False, 'default');
end;

procedure TConfig.SetValue(const Key, Value: string);
begin
  Store(FOverrides, Key, Value, nil, False, 'set in code');
end;

procedure TConfig.LoadToml(const FileName, Text: string);
var
  Doc: TTomlDocument;
  I: Integer;
  V: TTomlValue;
begin
  Doc := TTomlDocument.Create;
  try
    try
      Doc.LoadFromString(Text);
    except
      on E: ETomlError do
        raise EConfigError.Create(FileName + ', ' + E.Message);
    end;
    for I := 0 to Doc.Values.Count - 1 do
    begin
      V := TTomlValue(Doc.Values.Objects[I]);
      if V.Kind = tkArray then
        Store(FValues, Doc.Values[I], string.Join(',', V.Items), V.Items, True, FileName)
      else
        Store(FValues, Doc.Values[I], V.Text, nil, False, FileName);
    end;
  finally
    Doc.Free;
  end;
end;

procedure TConfig.LoadJson(const FileName, Text: string);

  procedure Walk(D: TJSONData; const Prefix: string);
  var
    I: Integer;
    Items: TStringArray;
    AllScalar: Boolean;
    Key: string;
  begin
    case D.JSONType of
      jtObject:
        for I := 0 to D.Count - 1 do
        begin
          if Prefix = '' then
            Key := TJSONObject(D).Names[I]
          else
            Key := Prefix + '.' + TJSONObject(D).Names[I];
          Walk(D.Items[I], Key);
        end;
      jtArray:
        begin
          AllScalar := True;
          for I := 0 to D.Count - 1 do
            if D.Items[I].JSONType in [jtArray, jtObject] then
              AllScalar := False;
          if AllScalar then
          begin
            SetLength(Items, D.Count);
            for I := 0 to D.Count - 1 do
              Items[I] := D.Items[I].AsString;
            Store(FValues, Prefix, string.Join(',', Items), Items, True, FileName);
          end
          else
            for I := 0 to D.Count - 1 do
              Walk(D.Items[I], Format('%s[%d]', [Prefix, I]));
        end;
      jtNull: ;
    else
      Store(FValues, Prefix, D.AsString, nil, False, FileName);
    end;
  end;

var
  Data: TJSONData;
begin
  try
    Data := ParseJson(Text);
  except
    on E: EJsonError do
      raise EConfigError.Create(FileName + ', ' + E.Message);
  end;
  try
    if not (Data is TJSONObject) then
      raise EConfigError.Create(FileName + ': the settings must be a JSON object { ... }');
    Walk(Data, '');
  finally
    Data.Free;
  end;
end;

procedure TConfig.LoadFile(const FileName: string);
var
  L: TStringList;
begin
  if not FileExists(FileName) then
    raise EConfigError.CreateFmt('settings file "%s" was not found', [FileName]);
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
    except
      on E: Exception do
        raise EConfigError.CreateFmt('cannot read settings file "%s": %s', [FileName, E.Message]);
    end;
    if LowerCase(ExtractFileExt(FileName)) = '.json' then
      LoadJson(FileName, L.Text)
    else
      LoadToml(FileName, L.Text);
    FFiles.Add(FileName);
  finally
    L.Free;
  end;
end;

function TConfig.LoadFileIfExists(const FileName: string): Boolean;
begin
  Result := FileExists(FileName);
  if Result then
    LoadFile(FileName);
end;

procedure TConfig.LoadEnv(const Prefix: string);
begin
  if Prefix <> '' then
    FEnvPrefix := Prefix
  else
    FEnvPrefix := StringReplace(UpperCase(FAppName), '-', '_', [rfReplaceAll]);
  if (FEnvPrefix <> '') and (FEnvPrefix[Length(FEnvPrefix)] <> '_') then
    FEnvPrefix := FEnvPrefix + '_';
end;

procedure TConfig.LoadStandard;
var
  Dir: string;
begin
  LoadFileIfExists(IncludeTrailingPathDelimiter(SystemConfigDir(FAppName)) + 'config.toml');
  Dir := IncludeTrailingPathDelimiter(UserConfigDir(FAppName));
  if not LoadFileIfExists(Dir + 'config.toml') then
    LoadFileIfExists(Dir + 'config.json');
  if not LoadFileIfExists('config.toml') then
    LoadFileIfExists('config.json');
  LoadEnv;
end;

function TConfig.EnvName(const Key: string): string;
var
  I: Integer;
begin
  Result := '';
  if FEnvPrefix = '' then
    Exit;
  Result := FEnvPrefix + UpperCase(Key);
  for I := Length(FEnvPrefix) + 1 to Length(Result) do
    if not (Result[I] in ['A'..'Z', '0'..'9', '_']) then
      Result[I] := '_';
end;

function SplitList(const S: string): TStringArray;
var
  I: Integer;
begin
  Result := S.Split([',']);
  for I := 0 to High(Result) do
    Result[I] := Trim(Result[I]);
end;

function TConfig.Lookup(const Key: string; out Value: string; out Items: TStringArray;
  out IsList: Boolean; out Source: string): Boolean;
var
  I: Integer;
  E: TEntry;
  Env: string;
begin
  Items := nil;
  IsList := False;
  I := FOverrides.IndexOf(Key);
  if I >= 0 then
  begin
    E := TEntry(FOverrides.Objects[I]);
    Value := E.Value;
    Source := E.Source;
    Exit(True);
  end;
  Env := EnvName(Key);
  if (Env <> '') and (GetEnv(Env) <> '') then
  begin
    Value := GetEnv(Env);
    Source := 'environment ' + Env;
    Exit(True);
  end;
  I := FValues.IndexOf(Key);
  if I >= 0 then
  begin
    E := TEntry(FValues.Objects[I]);
    Value := E.Value;
    Items := Copy(E.Items);
    IsList := E.IsList;
    Source := E.Source;
    Exit(True);
  end;
  Value := '';
  Source := '';
  Result := False;
end;

function TConfig.Has(const Key: string): Boolean;
var
  V, S: string;
  Items: TStringArray;
  L: Boolean;
begin
  Result := Lookup(Key, V, Items, L, S);
end;

function TConfig.Get(const Key: string; const Default: string): string;
var
  S: string;
  Items: TStringArray;
  L: Boolean;
begin
  if not Lookup(Key, Result, Items, L, S) then
    Result := Default;
end;

function TConfig.GetInt(const Key: string; Default: Int64): Int64;
var
  V, S: string;
  Items: TStringArray;
  L: Boolean;
begin
  if not Lookup(Key, V, Items, L, S) then
    Exit(Default);
  if not TryStrToInt64(Trim(V), Result) then
    raise EConfigError.CreateFmt('setting "%s" must be a whole number, got "%s" (from %s)', [Key, V, S]);
end;

function TConfig.GetFloat(const Key: string; Default: Double): Double;
var
  V, S: string;
  Items: TStringArray;
  L: Boolean;
  FS: TFormatSettings;
begin
  if not Lookup(Key, V, Items, L, S) then
    Exit(Default);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(Trim(V), Result, FS) then
    raise EConfigError.CreateFmt('setting "%s" must be a number, got "%s" (from %s)', [Key, V, S]);
end;

function TConfig.GetBool(const Key: string; Default: Boolean): Boolean;
var
  V, S: string;
  Items: TStringArray;
  L: Boolean;
begin
  if not Lookup(Key, V, Items, L, S) then
    Exit(Default);
  V := LowerCase(Trim(V));
  if (V = 'true') or (V = 'yes') or (V = 'on') or (V = '1') then
    Exit(True);
  if (V = 'false') or (V = 'no') or (V = 'off') or (V = '0') then
    Exit(False);
  raise EConfigError.CreateFmt('setting "%s" must be true or false, got "%s" (from %s)', [Key, V, S]);
end;

function TConfig.GetList(const Key: string): TStringArray;
var
  V, S: string;
  L: Boolean;
begin
  Result := nil;
  if not Lookup(Key, V, Result, L, S) then
    Exit(nil);
  if not L then
  begin
    if Trim(V) = '' then
      Result := nil
    else
      Result := SplitList(V);
  end;
end;

function TConfig.Require(const Key: string): string;
var
  Section, Name, Hint: string;
  P: Integer;
begin
  if Has(Key) and (Get(Key) <> '') then
    Exit(Get(Key));
  P := LastDelimiter('.', Key);
  if P > 0 then
  begin
    Section := Copy(Key, 1, P - 1);
    Name := Copy(Key, P + 1, MaxInt);
    Hint := Format('[%s] %s = ...', [Section, Name]);
  end
  else
    Hint := Key + ' = ...';
  if FEnvPrefix <> '' then
    raise EConfigError.CreateFmt('missing setting "%s": add %s to config.toml, or set %s',
      [Key, Hint, EnvName(Key)])
  else
    raise EConfigError.CreateFmt('missing setting "%s": add %s to config.toml', [Key, Hint]);
end;

function TConfig.Source(const Key: string): string;
var
  V: string;
  Items: TStringArray;
  L: Boolean;
begin
  if not Lookup(Key, V, Items, L, Result) then
    Result := '';
end;

function TConfig.Keys: TStringArray;
var
  All: TStringList;
  I: Integer;
begin
  Result := nil;
  All := TStringList.Create;
  try
    All.Sorted := True;
    All.Duplicates := dupIgnore;
    All.AddStrings(FValues);
    All.AddStrings(FOverrides);
    SetLength(Result, All.Count);
    for I := 0 to All.Count - 1 do
      Result[I] := All[I];
  finally
    All.Free;
  end;
end;

end.
