{ Pastel - terminal output helpers (colors, status lines).
  Part of the Pastel project, MIT License. }
unit Pastel.Console;

{$mode objfpc}{$H+}

interface

var
  UseColor: Boolean = False;

procedure InitConsole;

function Bold(const S: string): string;
function Dim(const S: string): string;
function Green(const S: string): string;
function Red(const S: string): string;
function Yellow(const S: string): string;
function Cyan(const S: string): string;

function MarkOk: string;
function MarkFail: string;

{ Cargo-style status line: verb right-aligned in green, then the message. }
procedure Status(const Verb, Msg: string);
procedure Warn(const Msg: string);
procedure Fail(const Msg: string);
procedure Hint(const Msg: string);
{ Like Hint, but on stdout: for advice that is not about an error. }
procedure Tip(const Msg: string);

implementation

uses
  SysUtils
  {$IFDEF UNIX}, termio{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

function Wrap(const Code, S: string): string;
begin
  if UseColor then
    Result := #27'[' + Code + 'm' + S + #27'[0m'
  else
    Result := S;
end;

function Bold(const S: string): string;   begin Result := Wrap('1', S); end;
function Dim(const S: string): string;    begin Result := Wrap('2', S); end;
function Green(const S: string): string;  begin Result := Wrap('32', S); end;
function Red(const S: string): string;    begin Result := Wrap('31', S); end;
function Yellow(const S: string): string; begin Result := Wrap('33', S); end;
function Cyan(const S: string): string;   begin Result := Wrap('36', S); end;

function MarkOk: string;
begin
  {$IFDEF WINDOWS}
  Result := Green('[ok]');
  {$ELSE}
  Result := Green('✓');
  {$ENDIF}
end;

function MarkFail: string;
begin
  {$IFDEF WINDOWS}
  Result := Red('[--]');
  {$ELSE}
  Result := Red('✗');
  {$ENDIF}
end;

procedure Status(const Verb, Msg: string);
begin
  WriteLn(Wrap('1;32', Format('%12s', [Verb])), ' ', Msg);
end;

procedure Warn(const Msg: string);
begin
  WriteLn(Wrap('1;33', 'warning:'), ' ', Msg);
end;

{ Errors and their hints go to stderr. Flushing stdout first keeps the
  messages in the right order when both streams end up in the same place. }
procedure Fail(const Msg: string);
begin
  Flush(Output);
  WriteLn(StdErr, Wrap('1;31', 'error:'), ' ', Msg);
  Flush(StdErr);
end;

procedure Hint(const Msg: string);
begin
  Flush(Output);
  WriteLn(StdErr, Wrap('1;36', 'hint:'), ' ', Msg);
  Flush(StdErr);
end;

procedure Tip(const Msg: string);
begin
  WriteLn(Wrap('1;36', 'hint:'), ' ', Msg);
end;

procedure InitConsole;
{$IFDEF WINDOWS}
const
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = $0004;
var
  H: THandle;
  Mode: DWORD;
{$ENDIF}
begin
  UseColor := False;
  {$IFDEF WINDOWS}
  SetConsoleOutputCP(65001);
  {$ENDIF}
  if SysUtils.GetEnvironmentVariable('NO_COLOR') <> '' then
    Exit;
  {$IFDEF UNIX}
  UseColor := IsATTY(StdOutputHandle) = 1;
  {$ENDIF}
  {$IFDEF WINDOWS}
  { Windows 10+ understands ANSI colors once this flag is set.
    Older consoles (Windows 7) refuse it, so we stay in plain text there. }
  H := GetStdHandle(STD_OUTPUT_HANDLE);
  Mode := 0;
  if GetConsoleMode(H, Mode) then
    UseColor := SetConsoleMode(H, Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  {$ENDIF}
end;

end.
