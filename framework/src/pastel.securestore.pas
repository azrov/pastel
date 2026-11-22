{ Pastel - secrets kept by the system: tokens, passwords, keys.

    SecureSet('api-token', Token);
    Token := SecureGet('api-token');          // '' when there is none
    SecureDelete('api-token');

  Android: encrypted with a key of the phone's Keystore (it never leaves the
  phone's secure hardware). Windows: the user's data protection (DPAPI), only
  that Windows user can read them. Linux: the desktop's keyring (GNOME Keyring,
  KWallet) through secret-tool; without one, a file only the user may read.
  Part of the Pastel project, MIT License. }
unit Pastel.SecureStore;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  ESecureStoreError = class(Exception);

procedure SecureSet(const Name, Value: string);
function SecureGet(const Name: string; const Default: string = ''): string;
function SecureHas(const Name: string): Boolean;
procedure SecureDelete(const Name: string);
{ Where they are kept: 'android-keystore', 'windows-dpapi', 'linux-keyring' or 'file'. }
function SecureStoreKind: string;

var
  { the app's name the secrets are kept under (default: the program's name) }
  SecureStoreApp: string = '';

implementation

uses
  base64, Pastel.Files, Pastel.Env
  {$IFDEF ANDROID}, Pastel.Android{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF}
  {$IFDEF UNIX}{$IFNDEF ANDROID}, BaseUnix, Pastel.Process{$ENDIF}{$ENDIF};

function AppName: string;
begin
  Result := SecureStoreApp;
  if Result = '' then
    Result := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  if Result = '' then
    Result := 'pastel-app';
end;

{ ---- the file (and the folder of the other kinds' files) ---- }

function StoreFile: string;
var
  Dir: string;
begin
  Dir := GetEnv('PASTEL_SECURE_DIR');
  if Dir = '' then
  begin
    {$IFDEF WINDOWS}
    Dir := JoinPath([GetEnv('APPDATA'), AppName]);
    {$ELSE}
    Dir := GetEnv('XDG_CONFIG_HOME');
    if Dir = '' then
      Dir := JoinPath([HomeDir, '.config']);
    Dir := JoinPath([Dir, AppName]);
    {$ENDIF}
  end;
  Result := JoinPath([Dir, 'secrets']);
end;

function LoadFile: TStringList;
begin
  Result := TStringList.Create;
  if FileExists(StoreFile) then
    Result.LoadFromFile(StoreFile);
end;

procedure SaveFile(L: TStringList);
var
  F: string;
begin
  F := StoreFile;
  ForceDirectories(ExtractFileDir(F));
  L.SaveToFile(F);
  {$IFDEF UNIX}{$IFNDEF ANDROID}
  fpChmod(F, &600);
  fpChmod(ExtractFileDir(F), &700);
  {$ENDIF}{$ENDIF}
end;

function FileGet(const Name: string; out Value: string): Boolean;
var
  L: TStringList;
  I: Integer;
begin
  L := LoadFile;
  try
    I := L.IndexOfName(Name);
    Result := I >= 0;
    if Result then
      Value := DecodeStringBase64(L.ValueFromIndex[I])
    else
      Value := '';
  finally
    L.Free;
  end;
end;

procedure FileSet(const Name, Raw: string);
var
  L: TStringList;
begin
  L := LoadFile;
  try
    L.Values[Name] := EncodeStringBase64(Raw);
    SaveFile(L);
  finally
    L.Free;
  end;
end;

procedure FileDelete(const Name: string);
var
  L: TStringList;
  I: Integer;
begin
  L := LoadFile;
  try
    I := L.IndexOfName(Name);
    if I >= 0 then
    begin
      L.Delete(I);
      SaveFile(L);
    end;
  finally
    L.Free;
  end;
end;

procedure CheckName(const Name: string);
var
  C: Char;
begin
  if Name = '' then
    raise ESecureStoreError.Create('a secret needs a name');
  for C in Name do
    if C in [#0..#31, '='] then
      raise ESecureStoreError.CreateFmt('"%s": a secret''s name has no "=" or control characters', [Name]);
end;

{ ---- Windows: DPAPI ---- }

{$IFDEF WINDOWS}
type
  TDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDataBlob = ^TDataBlob;

function CryptProtectData(DataIn: PDataBlob; Descr: PWideChar; Entropy: PDataBlob; Reserved, Prompt: Pointer;
  Flags: DWORD; DataOut: PDataBlob): BOOL; stdcall; external 'crypt32.dll';
function CryptUnprotectData(DataIn: PDataBlob; Descr: PPWideChar; Entropy: PDataBlob; Reserved, Prompt: Pointer;
  Flags: DWORD; DataOut: PDataBlob): BOOL; stdcall; external 'crypt32.dll';

function Protect(const S: RawByteString; Encrypt: Boolean): RawByteString;
var
  InB, OutB: TDataBlob;
  Ok: BOOL;
begin
  InB.cbData := Length(S);
  InB.pbData := PByte(PAnsiChar(S));
  OutB := Default(TDataBlob);
  if Encrypt then
    Ok := CryptProtectData(@InB, nil, nil, nil, nil, 1 { UI_FORBIDDEN }, @OutB)
  else
    Ok := CryptUnprotectData(@InB, nil, nil, nil, nil, 1, @OutB);
  if not Ok then
    raise ESecureStoreError.Create('Windows could not protect the secret: ' + SysErrorMessage(GetLastError));
  SetLength(Result, OutB.cbData);
  if OutB.cbData > 0 then
    Move(OutB.pbData^, Result[1], OutB.cbData);
  LocalFree(HLOCAL(OutB.pbData));
end;
{$ENDIF}

{ ---- Linux: the keyring through secret-tool ---- }

{$IFDEF UNIX}{$IFNDEF ANDROID}
function SecretTool: string;
begin
  if GetEnv('PASTEL_SECURE_DIR') <> '' then
    Exit('');        { tests: the file }
  if (GetEnv('DBUS_SESSION_BUS_ADDRESS') = '') and (GetEnv('XDG_RUNTIME_DIR') = '') then
    Exit('');        { no desktop session (a server, ssh): no keyring }
  Result := Which('secret-tool');
end;
{$ENDIF}{$ENDIF}

function SecureStoreKind: string;
begin
  {$IFDEF ANDROID}
  Result := 'android-keystore';
  {$ELSE}
  {$IFDEF WINDOWS}
  Result := 'windows-dpapi';
  {$ELSE}
  if SecretTool <> '' then
    Result := 'linux-keyring'
  else
    Result := 'file';
  {$ENDIF}
  {$ENDIF}
end;

procedure SecureSet(const Name, Value: string);
{$IFDEF ANDROID}
var
  Err: string;
{$ENDIF}
{$IFDEF UNIX}{$IFNDEF ANDROID}
var
  R: TRunResult;
  O: TRunOptions;
{$ENDIF}{$ENDIF}
begin
  CheckName(Name);
  {$IFDEF ANDROID}
  Err := AndroidCallString('secureSet', '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;', [Name, Value]);
  if Err <> '' then
    raise ESecureStoreError.Create('the secret could not be kept: ' + Err);
  {$ELSE}
  {$IFDEF WINDOWS}
  FileSet(Name, Protect(Value, True));
  {$ELSE}
  if SecretTool <> '' then
  begin
    O := Default(TRunOptions);
    O.Input := Value;
    O.Timeout := 60000;
    R := Run(SecretTool, ['store', '--label=' + AppName + ': ' + Name, 'application', AppName, 'name', Name], O);
    if not R.Ok then
      raise ESecureStoreError.Create('the keyring did not keep the secret: ' + Trim(R.Errors + R.Output));
    { a value kept in the file before: gone }
    FileDelete(Name);
  end
  else
    FileSet(Name, Value);
  {$ENDIF}
  {$ENDIF}
end;

function TryGet(const Name: string; out Value: string): Boolean;
{$IFDEF UNIX}{$IFNDEF ANDROID}
var
  R: TRunResult;
{$ENDIF}{$ENDIF}
begin
  CheckName(Name);
  {$IFDEF ANDROID}
  Value := AndroidCallString('secureGet', '(Ljava/lang/String;)Ljava/lang/String;', [Name]);
  Result := Value <> #1;
  if not Result then
    Value := '';
  {$ELSE}
  {$IFDEF WINDOWS}
  Result := FileGet(Name, Value);
  if Result then
  try
    Value := Protect(Value, False);
    SetCodePage(RawByteString(Value), CP_UTF8, False);
  except
    Result := False;
    Value := '';
  end;
  {$ELSE}
  if SecretTool <> '' then
  begin
    R := Run(SecretTool, ['lookup', 'application', AppName, 'name', Name]);
    Result := R.Ok;
    if Result then
    begin
      Value := R.Output;
      { secret-tool ends it with a newline on a terminal }
      if (Value <> '') and (Value[Length(Value)] = #10) then
        SetLength(Value, Length(Value) - 1);
      SetCodePage(RawByteString(Value), CP_UTF8, False);
      Exit;
    end;
  end;
  Result := FileGet(Name, Value);
  SetCodePage(RawByteString(Value), CP_UTF8, False);
  {$ENDIF}
  {$ENDIF}
end;

function SecureGet(const Name: string; const Default: string): string;
begin
  if not TryGet(Name, Result) then
    Result := Default;
end;

function SecureHas(const Name: string): Boolean;
var
  V: string;
begin
  Result := TryGet(Name, V);
end;

procedure SecureDelete(const Name: string);
begin
  CheckName(Name);
  {$IFDEF ANDROID}
  AndroidCall('secureDelete', '(Ljava/lang/String;)V', [Name]);
  {$ELSE}
  {$IFDEF UNIX}
  if SecretTool <> '' then
    Run(SecretTool, ['clear', 'application', AppName, 'name', Name]);
  {$ENDIF}
  FileDelete(Name);
  {$ENDIF}
end;

end.
