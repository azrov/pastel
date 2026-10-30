{ Pastel - program start-up.

  Pastel adds this unit to every program automatically (fpc -Fa), as the
  very first unit. It
  - turns on thread support on Linux/macOS (cthreads), so TThread works
    without remembering to put cthreads first in the uses clause;
  - makes UTF-8 the code page of all strings, so text like "ayşe" or "Bakı"
    stays intact when libraries convert strings (fpjson, databases, ...);
  - on Windows switches the console to UTF-8 for WriteLn and ReadLn;
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

initialization
  DefaultSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  DefaultFileSystemCodePage := CP_UTF8;
  {$IFDEF WINDOWS}
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  SetTextCodePage(Input, CP_UTF8);
  {$ENDIF}
end.
