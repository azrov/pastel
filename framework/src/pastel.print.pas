(* Pastel - printing and opening documents with the system.

    R.SaveToFile(TempFile);           // a PDF from Pastel.Report
    OpenDocument(TempFile);           // shown in the PDF viewer: a preview, with its Print button
    PrintFile(TempFile);              // or straight to the default printer
    PrintFile(TempFile, 'Kitchen');   // to another one; Printers lists them

  Linux prints with CUPS (lp), Windows with the program that opens PDF files.
  Part of the Pastel project, MIT License. *)
unit Pastel.Print;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  EPrintError = class(Exception);

{ The printers of this computer (their names). }
function Printers: TStringArray;
{ The default printer; '' when there is none. }
function DefaultPrinter: string;
{ Prints a PDF (or a picture, or a text file) on Printer, the default one when ''. }
procedure PrintFile(const FileName: string; const Printer: string = ''; Copies: Integer = 1);
{ Opens a file with the program the system uses for it (a PDF in the PDF
  viewer, a .xlsx in the spreadsheet program, a web address in the browser).
  Nothing happens while UI tests run (PASTEL_HEADLESS=1). }
procedure OpenDocument(const FileNameOrUrl: string);

implementation

uses
  {$IFDEF WINDOWS}Windows, ShellApi,{$ENDIF}
  Pastel.Process;

{$IFDEF WINDOWS}
type
  TPrinterInfo4 = record
    pPrinterName: PWideChar;
    pServerName: PWideChar;
    Attributes: DWORD;
  end;
  PPrinterInfo4 = ^TPrinterInfo4;

function EnumPrintersW(Flags: DWORD; Name: PWideChar; Level: DWORD; pPrinterEnum: Pointer; cbBuf: DWORD;
  var pcbNeeded, pcReturned: DWORD): BOOL; stdcall; external 'winspool.drv';
function GetDefaultPrinterW(pszBuffer: PWideChar; var pcchBuffer: DWORD): BOOL; stdcall; external 'winspool.drv';

const
  PRINTER_ENUM_LOCAL = 2;
  PRINTER_ENUM_CONNECTIONS = 4;
{$ENDIF}

function Printers: TStringArray;
{$IFDEF WINDOWS}
var
  Needed, Count, I: DWORD;
  Buf: array of Byte;
  P: PPrinterInfo4;
begin
  Result := nil;
  Needed := 0;
  Count := 0;
  EnumPrintersW(PRINTER_ENUM_LOCAL or PRINTER_ENUM_CONNECTIONS, nil, 4, nil, 0, Needed, Count);
  if Needed = 0 then
    Exit;
  SetLength(Buf, Needed);
  if not EnumPrintersW(PRINTER_ENUM_LOCAL or PRINTER_ENUM_CONNECTIONS, nil, 4, @Buf[0], Needed, Needed, Count) then
    Exit;
  SetLength(Result, Count);
  P := PPrinterInfo4(@Buf[0]);
  for I := 0 to Count - 1 do
  begin
    Result[I] := UTF8Encode(UnicodeString(P^.pPrinterName));
    Inc(P);
  end;
end;
{$ELSE}
var
  R: TRunResult;
  Line: string;
  L: TStringList;
begin
  Result := nil;
  if Which('lpstat') = '' then
    Exit;
  R := Run('lpstat', ['-e']);
  L := TStringList.Create;
  try
    for Line in R.Output.Split([#10]) do
      if Trim(Line) <> '' then
        L.Add(Trim(Line));
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;
{$ENDIF}

function DefaultPrinter: string;
{$IFDEF WINDOWS}
var
  Buf: array[0..511] of WideChar;
  N: DWORD;
begin
  N := Length(Buf);
  if GetDefaultPrinterW(@Buf[0], N) then
    Result := UTF8Encode(UnicodeString(PWideChar(@Buf[0])))
  else
    Result := '';
end;
{$ELSE}
var
  R: TRunResult;
  P: Integer;
begin
  Result := '';
  if Which('lpstat') = '' then
    Exit;
  R := Run('lpstat', ['-d']);
  { "system default destination: Office" }
  P := Pos(':', R.Output);
  if R.Ok and (P > 0) then
    Result := Trim(Copy(R.Output, P + 1, MaxInt));
end;
{$ENDIF}

procedure PrintFile(const FileName, Printer: string; Copies: Integer);
{$IFDEF WINDOWS}
var
  I: Integer;
  R: HINST;
begin
  if not FileExists(FileName) then
    raise EPrintError.CreateFmt('nothing to print: %s does not exist', [FileName]);
  for I := 1 to Copies do
  begin
    if Printer = '' then
      R := ShellExecuteW(0, 'print', PWideChar(UnicodeString(FileName)), nil, nil, SW_HIDE)
    else
      R := ShellExecuteW(0, 'printto', PWideChar(UnicodeString(FileName)),
        PWideChar(UnicodeString('"' + Printer + '"')), nil, SW_HIDE);
    if R <= 32 then
      raise EPrintError.CreateFmt('%s cannot be printed: no program for printing it is installed ' +
        '(for PDF files, e.g. SumatraPDF or Adobe Reader)', [FileName]);
  end;
end;
{$ELSE}
var
  Args: array of string;
  R: TRunResult;
begin
  if not FileExists(FileName) then
    raise EPrintError.CreateFmt('nothing to print: %s does not exist', [FileName]);
  if Which('lp') = '' then
    raise EPrintError.Create('printing needs CUPS (the "lp" command): sudo apt install cups-client');
  Args := nil;
  if Printer <> '' then
    Args := ['-d', Printer];
  if Copies > 1 then
    Args := Concat(Args, ['-n', IntToStr(Copies)]);
  Args := Concat(Args, ['--', FileName]);
  R := Run('lp', Args);
  if not R.Ok then
    raise EPrintError.CreateFmt('printing %s failed: %s', [FileName, Trim(R.Errors + R.Output)]);
end;
{$ENDIF}

procedure OpenDocument(const FileNameOrUrl: string);
{$IFDEF WINDOWS}
begin
  if GetEnvironmentVariable('PASTEL_HEADLESS') = '1' then
    Exit;
  if ShellExecuteW(0, 'open', PWideChar(UnicodeString(FileNameOrUrl)), nil, nil, SW_SHOWNORMAL) <= 32 then
    raise EPrintError.CreateFmt('%s cannot be opened: no program for it is installed', [FileNameOrUrl]);
end;
{$ELSE}
var
  Opener: string;
begin
  if GetEnvironmentVariable('PASTEL_HEADLESS') = '1' then
    Exit;      { UI tests: nothing is opened }
  {$IFDEF DARWIN}
  Opener := 'open';
  {$ELSE}
  Opener := 'xdg-open';
  {$ENDIF}
  if Which(Opener) = '' then
    raise EPrintError.CreateFmt('%s cannot be opened: "%s" is not installed', [FileNameOrUrl, Opener]);
  { in the background: the program does not wait for the viewer }
  Shell(Opener + ' ''' + StringReplace(FileNameOrUrl, '''', '''\''''', [rfReplaceAll]) + ''' >/dev/null 2>&1 &');
end;
{$ENDIF}

end.
