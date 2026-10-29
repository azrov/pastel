(* Pastel - environment variables.

    Home := GetEnv('HOME');
    Port := GetEnv('PORT', '8080');
    if HasEnv('CI') then ...
    SetEnv('APP_MODE', 'test');          // for this program and programs it starts

  The values are UTF-8 on every system. (Free Pascal's own
  GetEnvironmentVariable gives Windows "ANSI" text there, where 'şeker'
  becomes 'seker'.)
  Part of the Pastel project, MIT License. *)
unit Pastel.Env;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function GetEnv(const Name: string; const Default: string = ''): string;
function HasEnv(const Name: string): Boolean;
procedure SetEnv(const Name, Value: string);
procedure UnsetEnv(const Name: string);
{ All variables as 'NAME=value' }
function EnvList: TStringArray;

implementation

{$IFDEF WINDOWS}
uses
  Windows;

function GetEnv(const Name, Default: string): string;
var
  W: UnicodeString;
  N: DWORD;
begin
  W := '';
  SetLength(W, 256);
  N := GetEnvironmentVariableW(PWideChar(UnicodeString(Name)), PWideChar(W), Length(W));
  if N > DWORD(Length(W)) then
  begin
    SetLength(W, N);
    N := GetEnvironmentVariableW(PWideChar(UnicodeString(Name)), PWideChar(W), Length(W));
  end;
  if N = 0 then
    Exit(Default);
  SetLength(W, N);
  Result := UTF8Encode(W);
end;

function HasEnv(const Name: string): Boolean;
var
  C: WideChar;
begin
  C := #0;
  Result := (GetEnvironmentVariableW(PWideChar(UnicodeString(Name)), @C, 1) > 0) or
    (GetLastError <> ERROR_ENVVAR_NOT_FOUND);
end;

procedure SetEnv(const Name, Value: string);
begin
  SetEnvironmentVariableW(PWideChar(UnicodeString(Name)), PWideChar(UnicodeString(Value)));
end;

procedure UnsetEnv(const Name: string);
begin
  SetEnvironmentVariableW(PWideChar(UnicodeString(Name)), nil);
end;

function EnvList: TStringArray;
var
  Block, P: PWideChar;
  S: UnicodeString;
begin
  Result := nil;
  Block := GetEnvironmentStringsW;
  if Block = nil then
    Exit;
  try
    P := Block;
    while P^ <> #0 do
    begin
      S := P;
      Inc(P, Length(S) + 1);
      if (S <> '') and (S[1] <> '=') then       // '=C:=C:\' entries are cmd.exe's
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := UTF8Encode(S);
      end;
    end;
  finally
    FreeEnvironmentStringsW(Block);
  end;
end;

{$ELSE}

function libc_setenv(name, value: PChar; overwrite: LongInt): LongInt; cdecl; external 'c' name 'setenv';
function libc_unsetenv(name: PChar): LongInt; cdecl; external 'c' name 'unsetenv';

function libc_getenv(name: PChar): PChar; cdecl; external 'c' name 'getenv';

{ libc's getenv, not the RTL's copy, so SetEnv is seen too }
function GetEnv(const Name, Default: string): string;
var
  P: PChar;
begin
  P := libc_getenv(PChar(Name));
  if P = nil then
    Exit(Default);
  Result := P;
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

function HasEnv(const Name: string): Boolean;
begin
  Result := libc_getenv(PChar(Name)) <> nil;
end;

procedure SetEnv(const Name, Value: string);
begin
  libc_setenv(PChar(Name), PChar(Value), 1);
end;

procedure UnsetEnv(const Name: string);
begin
  libc_unsetenv(PChar(Name));
end;

var
  environ: PPChar; cvar; external;

function EnvList: TStringArray;
var
  P: PPChar;
begin
  Result := nil;
  P := environ;
  if P = nil then
    Exit;
  while P^ <> nil do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := P^;
    SetCodePage(RawByteString(Result[High(Result)]), CP_UTF8, False);
    Inc(P);
  end;
end;

{$ENDIF}

end.
