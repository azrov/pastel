{ Pastel - UTF-8 everywhere.

  Pastel adds this unit to every program automatically (fpc -Fa). On Windows
  it makes strings, console output and input UTF-8, so text like "ayşe"
  survives WriteLn and ReadLn. On Linux and macOS UTF-8 is already the norm.
  Part of the Pastel project, MIT License. }
unit Pastel.Utf8;

{$mode objfpc}{$H+}

interface

implementation

{$IFDEF WINDOWS}
uses
  Windows;

initialization
  DefaultSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  SetTextCodePage(Input, CP_UTF8);
{$ENDIF}
end.
