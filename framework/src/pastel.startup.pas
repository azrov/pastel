{ Pastel - program start-up.

  Pastel adds this unit to every program automatically (fpc -Fa), as the
  very first unit. It
  - turns on thread support on Linux/macOS (cthreads), so TThread works
    without remembering to put cthreads first in the uses clause;
  - makes UTF-8 the code page of all strings, so text like "ayşe" or "Bakı"
    stays intact when libraries convert strings (fpjson, databases, ...);
  - on Windows switches the console to UTF-8 for WriteLn and ReadLn;
  - on Windows lets programs without a console window (apps) still WriteLn:
    to the console they were started from (cmd, "pastel run", VS Code's
    terminal), to where their output was sent, else nowhere - not into
    Free Pascal's message boxes;
  - on Linux/macOS loads the system's text conversions (cwstring), so
    converting between string and UnicodeString keeps letters like "ş"
    (Free Pascal would otherwise treat every byte as one Latin-1 letter;
    databases are one place where this shows).
  Part of the Pastel project, MIT License. }
unit Pastel.Startup;

{$mode objfpc}{$H+}

interface

implementation

uses
  {$IFDEF UNIX}cthreads, cwstring{$ENDIF}
  {$IFDEF WINDOWS}Windows{$ENDIF};

{$IFDEF WINDOWS}
const
  ATTACH_PARENT_PROCESS = DWORD(-1);

function AttachConsole(ProcessId: DWORD): BOOL; stdcall; external 'kernel32' name 'AttachConsole';

function Usable(H: THandle): Boolean;
begin
  Result := (H <> 0) and (H <> INVALID_HANDLE_VALUE) and (GetFileType(H) <> FILE_TYPE_UNKNOWN);
end;

procedure OpenOutput(var F: Text; H: THandle);
begin
  if Usable(H) then
  begin
    Assign(F, '');
    Rewrite(F);
    TextRec(F).Handle := H;
  end
  else
  begin
    Assign(F, 'nul');
    Rewrite(F);
  end;
end;

{ a program without a console (-WG): Output and StdErr like a console program's }
procedure OpenGuiOutput;
begin
  if not Usable(StdOutputHandle) and not Usable(StdErrorHandle) and AttachConsole(ATTACH_PARENT_PROCESS) then
  begin
    StdOutputHandle := THandle(GetStdHandle(STD_OUTPUT_HANDLE));
    StdErrorHandle := THandle(GetStdHandle(STD_ERROR_HANDLE));
  end;
  {$I-}
  OpenOutput(Output, StdOutputHandle);
  OpenOutput(StdOut, StdOutputHandle);
  OpenOutput(ErrOutput, StdErrorHandle);
  OpenOutput(StdErr, StdErrorHandle);
  {$I+}
  InOutRes := 0;
end;
{$ENDIF}

initialization
  DefaultSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  DefaultFileSystemCodePage := CP_UTF8;
  {$IFDEF WINDOWS}
  if not IsConsole then
    OpenGuiOutput;
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  SetTextCodePage(Input, CP_UTF8);
  {$ENDIF}
end.
