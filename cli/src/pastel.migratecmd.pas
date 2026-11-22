{ Pastel - "pastel migrate": database migrations from the command line.

    pastel migrate                  run the migrations that did not run yet
    pastel migrate status           which ones ran, which are pending
    pastel migrate new add_orders   a new file database/migrations/003_add_orders.sql

  The database comes from --database URL, the environment variable
  <NAME>_DATABASE_URL, or [database] url in the project's config.toml.
  Part of the Pastel project, MIT License. }
unit Pastel.MigrateCmd;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function RunMigrate(const Args: TStringArray; const DatabaseUrl: string): Integer;

implementation

uses
  Classes, Pastel.Console, Pastel.Project, Pastel.Config, Pastel.Db, Pastel.Log, Pastel.Files;

function MigrationsDir(Project: TPastelProject): string;
begin
  Result := JoinPath([Project.Root, 'database', 'migrations']);
end;

function NewMigration(Project: TPastelProject; const Name: string): Integer;
var
  Dir, FileName, Clean: string;
  Files: TStringArray;
  Next, N: Integer;
  F: string;
  C: Char;
begin
  Clean := '';
  for C in LowerCase(Name) do
    if C in ['a'..'z', '0'..'9', '_'] then
      Clean := Clean + C
    else if C in [' ', '-'] then
      Clean := Clean + '_';
  if Clean = '' then
  begin
    Fail('give the migration a name: pastel migrate new create_users');
    Exit(2);
  end;
  Dir := MigrationsDir(Project);
  EnsureDir(Dir);
  Next := 1;
  Files := ListFiles(Dir, '*.sql');
  for F in Files do
    if TryStrToInt(Copy(ExtractFileName(F), 1, Pos('_', ExtractFileName(F)) - 1), N) and (N >= Next) then
      Next := N + 1;
  FileName := JoinPath([Dir, Format('%.3d_%s.sql', [Next, Clean])]);
  WriteText(FileName,
    '-- ' + Clean + LineEnding +
    '-- Runs once, in a transaction, with "pastel migrate" or Db.Migrate.' + LineEnding +
    '-- Never change it after it ran somewhere: add a new migration instead.' + LineEnding +
    LineEnding);
  Status('Created', RelativePath(FileName, GetCurrentDir));
  Result := 0;
end;

function RunMigrate(const Args: TStringArray; const DatabaseUrl: string): Integer;
var
  Root, Url, Action, Line: string;
  Project: TPastelProject;
  Config: TConfig;
  Db: TDatabase;
  List: TStringList;
  Count, Pending: Integer;
begin
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if Root = '' then
  begin
    Fail('no ' + ProjectFileName + ' found here or in any parent folder');
    Exit(1);
  end;
  Project := TPastelProject.Load(Root);
  try
    Action := 'up';
    if Length(Args) > 0 then
      Action := LowerCase(Args[0]);
    if Action = 'new' then
    begin
      if Length(Args) < 2 then
      begin
        Fail('usage: pastel migrate new <name>');
        Exit(2);
      end;
      Exit(NewMigration(Project, Args[1]));
    end;
    if (Action <> 'up') and (Action <> 'status') then
    begin
      Fail(Format('unknown "%s"; use: pastel migrate, pastel migrate status, pastel migrate new <name>', [Action]));
      Exit(2);
    end;
    if not DirectoryExists(MigrationsDir(Project)) then
    begin
      Fail('this project has no database/migrations folder');
      Hint('create the first one with: pastel migrate new create_tables');
      Exit(1);
    end;

    { paths like sqlite:data/app.db mean the same as when the program runs in the project }
    SetCurrentDir(Root);
    Url := DatabaseUrl;
    if Url = '' then
    begin
      Config := TConfig.Create(Project.Name);
      try
        Config.LoadFileIfExists(Root + 'config.toml');
        Config.LoadEnv;
        Url := Config.Get('database.url');
        if Url = '' then
        begin
          Fail('which database? Set [database] url in config.toml, the variable ' +
            UpperCase(StringReplace(Project.Name, '-', '_', [rfReplaceAll])) +
            '_DATABASE_URL, or give --database URL');
          Exit(1);
        end;
      finally
        Config.Free;
      end;
    end;

    Log.Level := llWarn;     { the steps are reported here instead }
    try
      Db := TDatabase.Open(Url, 1);
    except
      on E: EDbError do
      begin
        Fail(E.Message);
        Exit(1);
      end;
    end;
    try
      if Action = 'status' then
      begin
        List := Db.MigrationStatus(MigrationsDir(Project));
        try
          Pending := 0;
          for Line in List do
            if Copy(Line, Pos('=', Line) + 1, 7) = 'pending' then
            begin
              Inc(Pending);
              WriteLn('  ', Yellow('pending'), '  ', Copy(Line, 1, Pos('=', Line) - 1));
            end
            else
              WriteLn('  ', Green('applied'), '  ', Copy(Line, 1, Pos('=', Line) - 1),
                Dim('  ' + Copy(Line, Pos('=', Line) + 9, MaxInt)));
          if List.Count = 0 then
            WriteLn('  no migrations yet');
          WriteLn;
          Status('Database', Db.SafeUrl);
          Status('Pending', IntToStr(Pending));
        finally
          List.Free;
        end;
        Exit(0);
      end;

      List := Db.MigrationStatus(MigrationsDir(Project));
      try
        Count := Db.Migrate(MigrationsDir(Project));
        for Line in List do
          if Copy(Line, Pos('=', Line) + 1, 7) = 'pending' then
            Status('Migrated', Copy(Line, 1, Pos('=', Line) - 1));
      except
        on E: EDbError do
        begin
          Fail(E.Message);
          Exit(1);
        end;
      end;
      List.Free;
      if Count = 0 then
        Status('Database', 'up to date (' + Db.SafeUrl + ')')
      else
        Status('Done', Format('%d migration(s) on %s', [Count, Db.SafeUrl]));
      Result := 0;
    finally
      Db.Free;
    end;
  finally
    Project.Free;
  end;
end;

end.
