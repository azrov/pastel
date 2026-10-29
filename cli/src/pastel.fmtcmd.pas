{ Pastel - "pastel fmt": formats Pascal files.

    pastel fmt                  every .pas/.pp/.lpr/.dpr in src/ and tests/
    pastel fmt src/main.pas     these files or folders
    pastel fmt --check          only tell which files are not formatted (exit 1)
    pastel fmt --stdin [name]   read the code, write the result (for editors)

  Settings in pastel.toml:
    [format]
    indent = 2             # spaces per level
    keywords = "lower"     # or "keep"
  Part of the Pastel project, MIT License. }
unit Pastel.FmtCmd;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function RunFormat(const Paths: TStringArray; Check, FromStdin: Boolean): Integer;

implementation

uses
  Classes, Pastel.Console, Pastel.Project, Pastel.Format;

function ReadAll(const FileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

{ through a temporary file, so the original is never half written }
procedure WriteAll(const FileName, Text: string);
var
  F: TFileStream;
  Tmp: string;
begin
  Tmp := FileName + '.pastel-fmt';
  F := TFileStream.Create(Tmp, fmCreate);
  try
    if Text <> '' then
      F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
  {$IFDEF WINDOWS}
  SysUtils.DeleteFile(FileName);
  {$ENDIF}
  if not RenameFile(Tmp, FileName) then
  begin
    SysUtils.DeleteFile(Tmp);
    raise Exception.CreateFmt('cannot write "%s"', [FileName]);
  end;
end;

function ReadStdin: string;
var
  Buf: array[0..4095] of Char;
  N: LongInt;
  Chunk: string;
begin
  Result := '';
  Buf[0] := #0;
  repeat
    N := FileRead(GetFileHandle(Input), Buf, SizeOf(Buf));
    if N > 0 then
    begin
      SetString(Chunk, PChar(@Buf[0]), N);
      Result := Result + Chunk;
    end;
  until N <= 0;
end;

function IsPascalFile(const Name: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Name));
  Result := (Ext = '.pas') or (Ext = '.pp') or (Ext = '.lpr') or (Ext = '.dpr');
end;

procedure AddFiles(const Dir: string; List: TStrings);
var
  SR: TSearchRec;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Base + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        if SR.Name <> 'build' then
          AddFiles(Base + SR.Name, List);
      end
      else if IsPascalFile(SR.Name) and (Pos('.g.pas', LowerCase(SR.Name)) = 0) then
        List.Add(Base + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Settings of the project around Dir, or the defaults. }
function OptionsFor(const Dir: string): TFormatOptions;
var
  Root: string;
  P: TPastelProject;
begin
  Result := DefaultFormatOptions;
  Root := TPastelProject.FindRoot(Dir);
  if Root = '' then
    Exit;
  try
    P := TPastelProject.Load(Root);
    try
      Result.IndentSize := P.FormatIndent;
      Result.LowerKeywords := P.FormatKeywords <> 'keep';
      Result.NestedComments := P.Mode <> 'delphi';
    finally
      P.Free;
    end;
  except
    on EProjectError do ;   { a broken pastel.toml should not stop formatting }
  end;
end;

function Relative(const FileName: string): string;
begin
  Result := ExtractRelativePath(IncludeTrailingPathDelimiter(GetCurrentDir), FileName);
end;

function RunFormat(const Paths: TStringArray; Check, FromStdin: Boolean): Integer;
var
  Files: TStringList;
  Root, P, F, Src, Output, Error: string;
  Opts: TFormatOptions;
  Changed, Failed: Integer;
begin
  if FromStdin then
  begin
    if Length(Paths) > 0 then
      Opts := OptionsFor(ExtractFileDir(ExpandFileName(Paths[0])))
    else
      Opts := OptionsFor(GetCurrentDir);
    Src := ReadStdin;
    if FormatPascal(Src, Opts, Output, Error) then
    begin
      Write(Output);
      Exit(0);
    end;
    WriteLn(StdErr, Error);
    Exit(1);
  end;

  Files := TStringList.Create;
  try
    if Length(Paths) = 0 then
    begin
      Root := TPastelProject.FindRoot(GetCurrentDir);
      if Root = '' then
      begin
        Fail('no ' + ProjectFileName + ' found; give files or folders: pastel fmt src');
        Exit(2);
      end;
      if DirectoryExists(Root + 'src') then
        AddFiles(Root + 'src', Files);
      if DirectoryExists(Root + 'tests') then
        AddFiles(Root + 'tests', Files);
    end
    else
      for P in Paths do
        if DirectoryExists(P) then
          AddFiles(ExpandFileName(P), Files)
        else if FileExists(P) then
          Files.Add(ExpandFileName(P))
        else
        begin
          Fail(Format('"%s" not found', [P]));
          Exit(2);
        end;

    Changed := 0;
    Failed := 0;
    for F in Files do
    begin
      Opts := OptionsFor(ExtractFileDir(F));
      Src := ReadAll(F);
      if not FormatPascal(Src, Opts, Output, Error) then
      begin
        Inc(Failed);
        WriteLn(StdErr, Red(Relative(F) + ': ' + Error + ' (left as it is)'));
        Continue;
      end;
      if Output = Src then
        Continue;
      Inc(Changed);
      if Check then
        WriteLn(Relative(F))
      else
      begin
        WriteAll(F, Output);
        Status('Formatted', Relative(F));
      end;
    end;

    if Check then
    begin
      if Changed > 0 then
      begin
        Fail(Format('%d of %d file(s) are not formatted', [Changed, Files.Count]));
        Hint('run "pastel fmt" to format them');
        Result := 1;
      end
      else
      begin
        if Failed = 0 then
          Status('Checked', Format('%d file(s), all formatted', [Files.Count]));
        Result := 0;
      end;
    end
    else
    begin
      if Changed = 0 then
        Status('Checked', Format('%d file(s), nothing to change', [Files.Count - Failed]))
      else
        Status('Done', Format('%d of %d file(s) formatted', [Changed, Files.Count]));
      Result := 0;
    end;
    if Failed > 0 then
      Result := 1;
  finally
    Files.Free;
  end;
end;

end.
