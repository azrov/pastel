{ dupfinder - finds files with the same content.
  An example of a Pastel console tool: arguments, files, a progress bar,
  a table, JSON output. Try: pastel run -- --help }
program dupfinder;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpjson, Pastel.Args, Pastel.Files, Pastel.Term, Pastel.Json,
  AppInfo, Duplicates;

var
  Progress: TProgress = nil;

procedure Checked(const FileName: string);
begin
  if Progress <> nil then
    Progress.Step;
end;

{ every file under the folders that matches one of the patterns }
function CollectFiles(const Folders, Patterns: TStringArray): TStringArray;
var
  All: TStringList;
  Folder, Pattern, F: string;
  I: Integer;
begin
  All := TStringList.Create;
  try
    All.Sorted := True;
    All.Duplicates := dupIgnore;
    for Folder in Folders do
      for Pattern in Patterns do
        for F in ListFiles(Folder, Pattern, True) do
          All.Add(F);
    SetLength(Result, All.Count);
    for I := 0 to All.Count - 1 do
      Result[I] := All[I];
  finally
    All.Free;
  end;
end;

procedure PrintGroups(const Groups: TDupGroups; FileCount: Integer);
var
  G: TDupGroup;
  F: string;
  Total: Int64;
begin
  Total := 0;
  for G in Groups do
  begin
    WriteLn(Bold(Format('%d files of %s', [Length(G.Files), FormatSize(G.Size)])));
    for F in G.Files do
      WriteLn('  ', F);
    WriteLn;
    Inc(Total, Wasted(G));
  end;
  if Length(Groups) = 0 then
    Success(Format('No duplicates among %d file(s)', [FileCount]))
  else
    Success(Format('%d group(s) of duplicates; deleting the copies would free %s',
      [Length(Groups), FormatSize(Total)]));
end;

procedure PrintJson(const Groups: TDupGroups);
var
  List, Files: TJSONArray;
  G: TDupGroup;
  F: string;
begin
  List := TJSONArray.Create;
  try
    for G in Groups do
    begin
      Files := TJSONArray.Create;
      for F in G.Files do
        Files.Add(F);
      List.Add(JObject(['size', G.Size, 'wasted', Wasted(G), 'files', Files]));
    end;
    WriteLn(ToJson(List, True));
  finally
    List.Free;
  end;
end;

var
  Args: TArgs;
  Folder: string;
  Patterns, Files: TStringArray;
  MinSize: Int64;
  Groups: TDupGroups;
begin
  Args := TArgs.Create(AppName, 'Finds files with the same content, so the copies can go.');
  try
    Args.Version := AppVersion;
    Args.Positional('folders', 'Folders to search (with their sub-folders)').Many;
    Args.Option('pattern', 'p', 'Only files whose name matches').Many.MetaVar('PATTERN');
    Args.Option('min-size', 'm', 'Ignore files smaller than this, e.g. 100k or 5M', '1').MetaVar('SIZE');
    Args.Flag('json', '', 'Print the groups as JSON');
    Args.Example('dupfinder ~/Pictures ~/Downloads');
    Args.Example('dupfinder -p "*.jpg" -p "*.png" --min-size 100k photos');
    Args.Parse;

    try
      MinSize := ParseSize(Args.Get('min-size'));
    except
      on E: EConvertError do
      begin
        Error(E.Message);
        Halt(2);
      end;
    end;
    for Folder in Args.GetAll('folders') do
      if not DirectoryExists(Folder) then
      begin
        Error(Format('folder "%s" does not exist', [Folder]));
        Halt(2);
      end;
    Patterns := Args.GetAll('pattern');
    if Length(Patterns) = 0 then
      Patterns := ['*'];

    Files := CollectFiles(Args.GetAll('folders'), Patterns);
    { a progress bar only for people, not when the output goes to a file }
    if not Args.Has('json') and IsTerminal then
      Progress := TProgress.Create(Length(SameSizeFiles(Files, MinSize)), 'comparing');
    try
      Groups := FindDuplicates(Files, MinSize, @Checked);
    finally
      FreeAndNil(Progress);
    end;

    if Args.Has('json') then
      PrintJson(Groups)
    else
      PrintGroups(Groups, Length(Files));
  finally
    Args.Free;
  end;
end.
