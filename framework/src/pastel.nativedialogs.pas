{ Pastel - the system's own open, save and folder dialogs.

  Windows: the common dialogs (comdlg32, shell32). Linux: zenity (GNOME and
  most desktops) or kdialog (KDE), when installed. Pastel.Dialogs uses them
  when they are there and falls back to its own dialogs otherwise; test
  scripts and headless runs always get Pastel's own.
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.
  Part of the Pastel project, MIT License. }
unit Pastel.NativeDialogs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils{$IFDEF UNIX}, Process{$ENDIF};

type
  TNativeDialogKind = (ndOpen, ndSave, ndFolder);

  { One dialog. Start shows it (False: no system dialog here); on Linux it
    runs beside the program, so the window keeps drawing: call Running until
    it is False. Then Ok and FileName hold the answer. }
  TNativeDialog = class
  private
    FKind: TNativeDialogKind;
    FTitle, FFilter, FFileName, FDefaultExt: string;
    FOk: Boolean;
    FOwner: Pointer;
    {$IFDEF UNIX}
    FProcess: TProcess;
    FOutput: TStringStream;
    FTool: string;
    procedure Collect;
    {$ENDIF}
  public
    constructor Create(AKind: TNativeDialogKind; const ATitle, AFilter, AFileName, ADefaultExt: string);
    destructor Destroy; override;
    function Start: Boolean;
    function Running: Boolean;
    property Ok: Boolean read FOk;
    property FileName: string read FFileName;
    { The window that owns the dialog (Windows: HWND). }
    property Owner: Pointer read FOwner write FOwner;
  end;

{ Filter 'Text files|*.txt;*.md|All files|*' as pairs: names and patterns. }
procedure SplitFilter(const Filter: string; out Names, Patterns: TStringArray);

implementation

{$IFDEF WINDOWS}
uses
  Windows;

type
  TOpenFileNameW = record
    lStructSize: DWORD;
    hwndOwner: HWND;
    hInstance: HINST;
    lpstrFilter: PWideChar;
    lpstrCustomFilter: PWideChar;
    nMaxCustFilter: DWORD;
    nFilterIndex: DWORD;
    lpstrFile: PWideChar;
    nMaxFile: DWORD;
    lpstrFileTitle: PWideChar;
    nMaxFileTitle: DWORD;
    lpstrInitialDir: PWideChar;
    lpstrTitle: PWideChar;
    Flags: DWORD;
    nFileOffset: Word;
    nFileExtension: Word;
    lpstrDefExt: PWideChar;
    lCustData: LPARAM;
    lpfnHook: Pointer;
    lpTemplateName: PWideChar;
    pvReserved: Pointer;
    dwReserved: DWORD;
    FlagsEx: DWORD;
  end;

  TBrowseInfoW = record
    hwndOwner: HWND;
    pidlRoot: Pointer;
    pszDisplayName: PWideChar;
    lpszTitle: PWideChar;
    ulFlags: UINT;
    lpfn: Pointer;
    lParam: LPARAM;
    iImage: Integer;
  end;

const
  OFN_OVERWRITEPROMPT = $2;
  OFN_HIDEREADONLY = $4;
  OFN_NOCHANGEDIR = $8;
  OFN_PATHMUSTEXIST = $800;
  OFN_FILEMUSTEXIST = $1000;
  OFN_EXPLORER = $80000;
  BIF_RETURNONLYFSDIRS = $1;
  BIF_NEWDIALOGSTYLE = $40;

function GetOpenFileNameW(var OFN: TOpenFileNameW): BOOL; stdcall; external 'comdlg32.dll';
function GetSaveFileNameW(var OFN: TOpenFileNameW): BOOL; stdcall; external 'comdlg32.dll';
function SHBrowseForFolderW(var BI: TBrowseInfoW): Pointer; stdcall; external 'shell32.dll';
function SHGetPathFromIDListW(pidl: Pointer; pszPath: PWideChar): BOOL; stdcall; external 'shell32.dll';
procedure CoTaskMemFree(pv: Pointer); stdcall; external 'ole32.dll';
{$ENDIF}

procedure SplitFilter(const Filter: string; out Names, Patterns: TStringArray);
var
  Parts: TStringArray;
  I: Integer;
begin
  Names := nil;
  Patterns := nil;
  if Trim(Filter) = '' then
    Exit;
  Parts := Filter.Split(['|']);
  SetLength(Names, (Length(Parts) + 1) div 2);
  SetLength(Patterns, Length(Names));
  for I := 0 to High(Names) do
  begin
    Names[I] := Trim(Parts[I * 2]);
    if I * 2 + 1 <= High(Parts) then
      Patterns[I] := Trim(Parts[I * 2 + 1])
    else
      Patterns[I] := '*';
  end;
end;

constructor TNativeDialog.Create(AKind: TNativeDialogKind; const ATitle, AFilter, AFileName, ADefaultExt: string);
begin
  inherited Create;
  FKind := AKind;
  FTitle := ATitle;
  FFilter := AFilter;
  FFileName := AFileName;
  FDefaultExt := ADefaultExt;
end;

destructor TNativeDialog.Destroy;
begin
  {$IFDEF UNIX}
  if (FProcess <> nil) and FProcess.Running then
    FProcess.Terminate(1);
  FProcess.Free;
  FOutput.Free;
  {$ENDIF}
  inherited Destroy;
end;

{$IFDEF WINDOWS}
function TNativeDialog.Start: Boolean;
var
  OFN: TOpenFileNameW;
  BI: TBrowseInfoW;
  Names, Patterns: TStringArray;
  WFilter, WTitle, WDir, WExt: UnicodeString;
  Buf: array[0..32767] of WideChar;
  I: Integer;
  Pidl: Pointer;
  StartAt: string;
begin
  Result := True;
  FOk := False;
  WTitle := UTF8Decode(FTitle);
  if FKind = ndFolder then
  begin
    FillChar(BI, SizeOf(BI), 0);
    BI.hwndOwner := HWND(FOwner);
    BI.lpszTitle := PWideChar(WTitle);
    BI.ulFlags := BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE;
    Buf[0] := #0;
    BI.pszDisplayName := @Buf[0];
    Pidl := SHBrowseForFolderW(BI);
    if Pidl <> nil then
    begin
      FOk := SHGetPathFromIDListW(Pidl, @Buf[0]);
      if FOk then
        FFileName := UTF8Encode(UnicodeString(PWideChar(@Buf[0])));
      CoTaskMemFree(Pidl);
    end;
    Exit;
  end;
  SplitFilter(FFilter, Names, Patterns);
  WFilter := '';
  for I := 0 to High(Names) do
    WFilter := WFilter + UTF8Decode(Names[I]) + #0 + UTF8Decode(Patterns[I]) + #0;
  WFilter := WFilter + #0;
  FillChar(OFN, SizeOf(OFN), 0);
  OFN.lStructSize := SizeOf(OFN);
  OFN.hwndOwner := HWND(FOwner);
  if Length(Names) > 0 then
  begin
    OFN.lpstrFilter := PWideChar(WFilter);
    OFN.nFilterIndex := 1;
  end;
  StartAt := FFileName;
  FillChar(Buf, SizeOf(Buf), 0);
  if DirectoryExists(StartAt) then
    WDir := UTF8Decode(StartAt)
  else
  begin
    WDir := UTF8Decode(ExtractFileDir(StartAt));
    StrPLCopy(PWideChar(@Buf[0]), UTF8Decode(ExtractFileName(StartAt)), High(Buf));
  end;
  if WDir <> '' then
    OFN.lpstrInitialDir := PWideChar(WDir);
  OFN.lpstrFile := @Buf[0];
  OFN.nMaxFile := Length(Buf);
  OFN.lpstrTitle := PWideChar(WTitle);
  WExt := UTF8Decode(Copy(FDefaultExt, 2 - Ord(Copy(FDefaultExt, 1, 1) <> '.'), MaxInt));
  if WExt <> '' then
    OFN.lpstrDefExt := PWideChar(WExt);
  OFN.Flags := OFN_EXPLORER or OFN_HIDEREADONLY or OFN_NOCHANGEDIR or OFN_PATHMUSTEXIST;
  if FKind = ndOpen then
  begin
    OFN.Flags := OFN.Flags or OFN_FILEMUSTEXIST;
    FOk := GetOpenFileNameW(OFN);
  end
  else
  begin
    OFN.Flags := OFN.Flags or OFN_OVERWRITEPROMPT;
    FOk := GetSaveFileNameW(OFN);
  end;
  if FOk then
    FFileName := UTF8Encode(UnicodeString(PWideChar(@Buf[0])));
end;

function TNativeDialog.Running: Boolean;
begin
  Result := False;
end;
{$ENDIF}

{$IFDEF UNIX}
function FindTool(const Name: string): string;
begin
  Result := ExeSearch(Name, GetEnvironmentVariable('PATH'));
end;

function TNativeDialog.Start: Boolean;
var
  Names, Patterns: TStringArray;
  I: Integer;
  Desktop, StartAt, Pats: string;
begin
  Result := False;
  FOk := False;
  if (GetEnvironmentVariable('DISPLAY') = '') and (GetEnvironmentVariable('WAYLAND_DISPLAY') = '') then
    Exit;
  Desktop := UpperCase(GetEnvironmentVariable('XDG_CURRENT_DESKTOP'));
  FTool := '';
  if (Pos('KDE', Desktop) > 0) then
    FTool := FindTool('kdialog');
  if FTool = '' then
    FTool := FindTool('zenity');
  if FTool = '' then
    FTool := FindTool('kdialog');
  if FTool = '' then
    Exit;
  StartAt := FFileName;
  if StartAt = '' then
    StartAt := GetCurrentDir + '/'
  else if DirectoryExists(StartAt) then
    StartAt := IncludeTrailingPathDelimiter(ExpandFileName(StartAt))
  else
    StartAt := ExpandFileName(StartAt);
  SplitFilter(FFilter, Names, Patterns);
  FProcess := TProcess.Create(nil);
  FProcess.Executable := FTool;
  FProcess.Options := [poUsePipes, poStderrToOutPut];
  if ExtractFileName(FTool) = 'zenity' then
  begin
    FProcess.Parameters.Add('--file-selection');
    FProcess.Parameters.Add('--title=' + FTitle);
    case FKind of
      ndSave:
        begin
          FProcess.Parameters.Add('--save');
          FProcess.Parameters.Add('--confirm-overwrite');
        end;
      ndFolder:
        FProcess.Parameters.Add('--directory');
    end;
    FProcess.Parameters.Add('--filename=' + StartAt);
    if FKind <> ndFolder then
      for I := 0 to High(Names) do
        FProcess.Parameters.Add('--file-filter=' + Names[I] + ' | ' +
          StringReplace(Patterns[I], ';', ' ', [rfReplaceAll]));
  end
  else
  begin
    case FKind of
      ndOpen: FProcess.Parameters.Add('--getopenfilename');
      ndSave: FProcess.Parameters.Add('--getsavefilename');
      ndFolder: FProcess.Parameters.Add('--getexistingdirectory');
    end;
    FProcess.Parameters.Add(StartAt);
    if FKind <> ndFolder then
    begin
      Pats := '';
      for I := 0 to High(Names) do
      begin
        if Pats <> '' then
          Pats := Pats + #10;
        Pats := Pats + StringReplace(Patterns[I], ';', ' ', [rfReplaceAll]) + '|' + Names[I];
      end;
      if Pats <> '' then
        FProcess.Parameters.Add(Pats);
    end;
    FProcess.Parameters.Add('--title');
    FProcess.Parameters.Add(FTitle);
  end;
  FOutput := TStringStream.Create('');
  try
    FProcess.Execute;
  except
    FreeAndNil(FProcess);
    Exit;
  end;
  Result := True;
end;

procedure TNativeDialog.Collect;
var
  Buf: array[0..4095] of Byte;
  N: Integer;
begin
  while FProcess.Output.NumBytesAvailable > 0 do
  begin
    N := FProcess.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then
      Break;
    FOutput.WriteBuffer(Buf, N);
  end;
end;

function TNativeDialog.Running: Boolean;
var
  Lines: TStringArray;
  S, Ext: string;
  I: Integer;
begin
  if FProcess = nil then
    Exit(False);
  Collect;
  if FProcess.Running then
    Exit(True);
  Collect;
  Result := False;
  FOk := FProcess.ExitStatus = 0;
  if FOk then
  begin
    { the last line: tools may print warnings before it }
    Lines := FOutput.DataString.Split([#10]);
    S := '';
    for I := High(Lines) downto 0 do
      if Trim(Lines[I]) <> '' then
      begin
        S := Trim(Lines[I]);
        Break;
      end;
    FOk := S <> '';
    if FOk then
    begin
      Ext := FDefaultExt;
      if (Ext <> '') and (Ext[1] <> '.') then
        Ext := '.' + Ext;
      if (FKind = ndSave) and (Ext <> '') and (ExtractFileExt(S) = '') then
        S := S + Ext;
      FFileName := S;
    end;
  end;
  FreeAndNil(FProcess);
end;
{$ENDIF}

end.
