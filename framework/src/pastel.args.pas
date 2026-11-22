{ Pastel - command-line arguments.

    Args := TArgs.Create('backup', 'Copies folders into an archive.');
    Args.Version := '1.2.0';
    Args.Flag('verbose', 'v', 'Show every file');
    Args.Option('output', 'o', 'Archive to write', 'backup.tar');
    Args.Option('level', 'l', 'Compression level').IntRange(1, 9).Default('6');
    Args.Positional('folders', 'Folders to back up').Many;
    Args.Parse;          // prints help or errors and exits when needed

    if Args.Has('verbose') then ...
    Level := Args.GetInt('level');
    for F in Args.GetAll('folders') do ...

  Sub-commands ("todo add", "todo list") have their own options:

    with Args.Command('add', 'Add a task') do
      Positional('title', 'What to do');
    Args.Parse;
    case Args.CommandName of
      'add': AddTask(Args.Get('title'));

  --help, --version and --no-color are added automatically.
  Part of the Pastel project, MIT License. }
unit Pastel.Args;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Env;

type
  EArgsError = class(Exception);

  TArgKind = (akFlag, akOption, akPositional);

  TArgCommand = class;

  { One flag, option or positional argument. Its setup methods return the
    argument itself, so they can be chained. }
  TArgDef = class
  private
    FKind: TArgKind;
    FName, FShort, FHelp, FDefault, FEnv, FMetaVar: string;
    FRequired, FMany, FIsInt: Boolean;
    FMin, FMax: Int64;
    FChoices: TStringArray;
    FValues: TStringList;
    FCount: Integer;
    function Display: string;
    function Validate(const V: string): string;
  public
    constructor Create(AKind: TArgKind; const AName, AShort, AHelp: string);
    destructor Destroy; override;
    function Default(const AValue: string): TArgDef;
    function Required: TArgDef;
    function Optional: TArgDef;
    { May be given more than once (options) or take all remaining words (positional). }
    function Many: TArgDef;
    function IsInteger: TArgDef;
    function IntRange(AMin, AMax: Int64): TArgDef;
    function Choices(const AValues: array of string): TArgDef;
    { Value taken from this environment variable when not given on the command line. }
    function Env(const AVariable: string): TArgDef;
    { Placeholder in the help, e.g. FILE in "--output FILE". }
    function MetaVar(const AValue: string): TArgDef;
    property Name: string read FName;
    property Kind: TArgKind read FKind;
  end;

  TArgCommand = class
  private
    FName, FDescription: string;
    FDefs: TFPList;
    FCommands: TFPList;
    FParent: TArgCommand;
    FExamples: TStringList;
    function FindLong(const N: string): TArgDef;
    function FindShort(C: Char): TArgDef;
    function FindCommand(const N: string): TArgCommand;
    function Add(D: TArgDef): TArgDef;
    function FullName: string;
    function Positionals: TFPList;
    function PositionalCount: Integer;
    procedure Reset;
  public
    constructor Create(const AName, ADescription: string);
    destructor Destroy; override;
    function Flag(const AName, AShort, AHelp: string): TArgDef;
    function Option(const AName, AShort, AHelp: string; const ADefault: string = ''): TArgDef;
    { Required unless Optional or a Default is set. }
    function Positional(const AName, AHelp: string): TArgDef;
    function Command(const AName, ADescription: string): TArgCommand;
    procedure Example(const Line: string);
    function HelpText: string;
    property Name: string read FName;
    property Description: string read FDescription;
  end;

  TArgs = class(TArgCommand)
  private
    FVersion: string;
    FSelected: TArgCommand;
    FHelpWanted, FVersionWanted: Boolean;
    FHelpFor: TArgCommand;
    function Lookup(const AName: string): TArgDef;
  public
    constructor Create(const AProgram, ADescription: string);
    { Parses the given words. Raises EArgsError with a message for the user. }
    procedure ParseFrom(const Words: array of string);
    { Parses the program's command line. Prints help, the version or an error
      and ends the program when that is what the command line asks for. }
    procedure Parse;

    function Has(const AName: string): Boolean;
    function Count(const AName: string): Integer;
    function Get(const AName: string): string;
    function GetInt(const AName: string): Int64;
    function GetAll(const AName: string): TStringArray;
    { The chosen sub-command ('' when the program has none, or none was given);
      "remote add" for nested commands. }
    function CommandName: string;
    property Version: string read FVersion write FVersion;
    property HelpWanted: Boolean read FHelpWanted;
    property VersionWanted: Boolean read FVersionWanted;
  end;

{ Edit distance: how many letters differ ("did you mean ...?" suggestions). }
function Levenshtein(const A, B: string): Integer;

{ The program's arguments as UTF-8 (on Windows ParamStr uses the old ANSI
  code page, which cannot hold every character). }
function CommandLineWords: TStringArray;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} Pastel.Term;

{$IFDEF WINDOWS}
function CommandLineToArgvW(lpCmdLine: PWideChar; out pNumArgs: Integer): PPWideChar;
  stdcall; external 'shell32.dll';
{$ENDIF}

function CommandLineWords: TStringArray;
var
  I: Integer;
  {$IFDEF WINDOWS}
  Argv: PPWideChar;
  N: Integer;
  {$ENDIF}
begin
  Result := nil;
  {$IFDEF WINDOWS}
  Argv := CommandLineToArgvW(GetCommandLineW, N);
  if Argv <> nil then
  begin
    SetLength(Result, N - 1);
    for I := 1 to N - 1 do
      Result[I - 1] := UTF8Encode(UnicodeString(Argv[I]));
    LocalFree(HLOCAL(Argv));
    Exit;
  end;
  {$ENDIF}
  SetLength(Result, ParamCount);
  for I := 1 to ParamCount do
    Result[I - 1] := ParamStr(I);
end;

function Levenshtein(const A, B: string): Integer;
var
  D: array of array of Integer;
  I, J, Cost: Integer;
begin
  SetLength(D, Length(A) + 1, Length(B) + 1);
  for I := 0 to Length(A) do D[I][0] := I;
  for J := 0 to Length(B) do D[0][J] := J;
  for I := 1 to Length(A) do
    for J := 1 to Length(B) do
    begin
      if LowerCase(A[I]) = LowerCase(B[J]) then Cost := 0 else Cost := 1;
      D[I][J] := D[I - 1][J] + 1;
      if D[I][J - 1] + 1 < D[I][J] then D[I][J] := D[I][J - 1] + 1;
      if D[I - 1][J - 1] + Cost < D[I][J] then D[I][J] := D[I - 1][J - 1] + Cost;
    end;
  Result := D[Length(A)][Length(B)];
end;

{ ---- TArgDef ---- }

constructor TArgDef.Create(AKind: TArgKind; const AName, AShort, AHelp: string);
begin
  inherited Create;
  FKind := AKind;
  FName := AName;
  FShort := AShort;
  FHelp := AHelp;
  FValues := TStringList.Create;
  FRequired := AKind = akPositional;
  FMetaVar := UpperCase(AName);
end;

destructor TArgDef.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

function TArgDef.Default(const AValue: string): TArgDef;
begin
  FDefault := AValue;
  FRequired := False;
  Result := Self;
end;

function TArgDef.Required: TArgDef;
begin
  FRequired := True;
  Result := Self;
end;

function TArgDef.Optional: TArgDef;
begin
  FRequired := False;
  Result := Self;
end;

function TArgDef.Many: TArgDef;
begin
  FMany := True;
  Result := Self;
end;

function TArgDef.IsInteger: TArgDef;
begin
  FIsInt := True;
  FMin := Low(Int64);
  FMax := High(Int64);
  if FMetaVar = UpperCase(FName) then
    FMetaVar := 'N';
  Result := Self;
end;

function TArgDef.IntRange(AMin, AMax: Int64): TArgDef;
begin
  IsInteger;
  FMin := AMin;
  FMax := AMax;
  Result := Self;
end;

function TArgDef.Choices(const AValues: array of string): TArgDef;
var
  I: Integer;
begin
  SetLength(FChoices, Length(AValues));
  for I := 0 to High(AValues) do
    FChoices[I] := AValues[I];
  Result := Self;
end;

function TArgDef.Env(const AVariable: string): TArgDef;
begin
  FEnv := AVariable;
  Result := Self;
end;

function TArgDef.MetaVar(const AValue: string): TArgDef;
begin
  FMetaVar := AValue;
  Result := Self;
end;

function TArgDef.Display: string;
begin
  case FKind of
    akPositional: Result := '<' + FName + '>';
  else
    Result := '--' + FName;
  end;
end;

{ '' if V is fine, otherwise the reason. }
function TArgDef.Validate(const V: string): string;
var
  N: Int64;
  C: string;
begin
  Result := '';
  if FIsInt then
  begin
    if not TryStrToInt64(V, N) then
      Exit(Format('%s expects a whole number, got "%s"', [Display, V]));
    if (N < FMin) or (N > FMax) then
      Exit(Format('%s must be between %d and %d, got %d', [Display, FMin, FMax, N]));
  end;
  if Length(FChoices) > 0 then
  begin
    for C in FChoices do
      if C = V then
        Exit('');
    Result := Format('%s must be one of: %s (got "%s")',
      [Display, string.Join(', ', FChoices), V]);
  end;
end;

{ ---- TArgCommand ---- }

constructor TArgCommand.Create(const AName, ADescription: string);
begin
  inherited Create;
  FName := AName;
  FDescription := ADescription;
  FDefs := TFPList.Create;
  FCommands := TFPList.Create;
  FExamples := TStringList.Create;
end;

destructor TArgCommand.Destroy;
var
  I: Integer;
begin
  for I := 0 to FDefs.Count - 1 do
    TArgDef(FDefs[I]).Free;
  for I := 0 to FCommands.Count - 1 do
    TArgCommand(FCommands[I]).Free;
  FDefs.Free;
  FCommands.Free;
  FExamples.Free;
  inherited Destroy;
end;

function TArgCommand.Add(D: TArgDef): TArgDef;
begin
  if FindLong(D.FName) <> nil then
    raise EArgsError.CreateFmt('argument "%s" is defined twice', [D.FName]);
  FDefs.Add(D);
  Result := D;
end;

function TArgCommand.Flag(const AName, AShort, AHelp: string): TArgDef;
begin
  Result := Add(TArgDef.Create(akFlag, AName, AShort, AHelp));
end;

function TArgCommand.Option(const AName, AShort, AHelp: string; const ADefault: string): TArgDef;
begin
  Result := Add(TArgDef.Create(akOption, AName, AShort, AHelp));
  if ADefault <> '' then
    Result.Default(ADefault);
end;

function TArgCommand.Positional(const AName, AHelp: string): TArgDef;
begin
  Result := Add(TArgDef.Create(akPositional, AName, '', AHelp));
end;

function TArgCommand.Command(const AName, ADescription: string): TArgCommand;
begin
  Result := TArgCommand.Create(AName, ADescription);
  Result.FParent := Self;
  FCommands.Add(Result);
end;

procedure TArgCommand.Example(const Line: string);
begin
  FExamples.Add(Line);
end;

function TArgCommand.FindLong(const N: string): TArgDef;
var
  I: Integer;
begin
  for I := 0 to FDefs.Count - 1 do
    if (TArgDef(FDefs[I]).FKind <> akPositional) and SameText(TArgDef(FDefs[I]).FName, N) then
      Exit(TArgDef(FDefs[I]));
  for I := 0 to FDefs.Count - 1 do
    if SameText(TArgDef(FDefs[I]).FName, N) then
      Exit(TArgDef(FDefs[I]));
  Result := nil;
end;

function TArgCommand.FindShort(C: Char): TArgDef;
var
  I: Integer;
begin
  for I := 0 to FDefs.Count - 1 do
    if TArgDef(FDefs[I]).FShort = C then
      Exit(TArgDef(FDefs[I]));
  Result := nil;
end;

function TArgCommand.FindCommand(const N: string): TArgCommand;
var
  I: Integer;
begin
  for I := 0 to FCommands.Count - 1 do
    if SameText(TArgCommand(FCommands[I]).FName, N) then
      Exit(TArgCommand(FCommands[I]));
  Result := nil;
end;

function TArgCommand.FullName: string;
begin
  if FParent <> nil then
    Result := FParent.FullName + ' ' + FName
  else
    Result := FName;
end;

function TArgCommand.Positionals: TFPList;
var
  I: Integer;
begin
  Result := TFPList.Create;
  for I := 0 to FDefs.Count - 1 do
    if TArgDef(FDefs[I]).FKind = akPositional then
      Result.Add(FDefs[I]);
end;

function TArgCommand.PositionalCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FDefs.Count - 1 do
    if TArgDef(FDefs[I]).FKind = akPositional then
      Inc(Result);
end;

procedure TArgCommand.Reset;
var
  I: Integer;
begin
  for I := 0 to FDefs.Count - 1 do
  begin
    TArgDef(FDefs[I]).FValues.Clear;
    TArgDef(FDefs[I]).FCount := 0;
  end;
  for I := 0 to FCommands.Count - 1 do
    TArgCommand(FCommands[I]).Reset;
end;

function TArgCommand.HelpText: string;
var
  Lines: TStringList;
  I, W: Integer;
  D: TArgDef;
  C: TArgCommand;
  Usage, Left, Right: string;
  Pos: TFPList;
  Rows: array of array[0..1] of string;

  procedure Row(const L, R: string);
  begin
    SetLength(Rows, Length(Rows) + 1);
    Rows[High(Rows)][0] := L;
    Rows[High(Rows)][1] := R;
  end;

  procedure FlushRows;
  var
    K: Integer;
  begin
    W := 0;
    for K := 0 to High(Rows) do
      if DisplayWidth(Rows[K][0]) > W then
        W := DisplayWidth(Rows[K][0]);
    for K := 0 to High(Rows) do
      Lines.Add('  ' + PadRight(Rows[K][0], W) + '  ' + Rows[K][1]);
    Rows := nil;
  end;

  function Extras(Def: TArgDef): string;
  begin
    Result := '';
    if Length(Def.FChoices) > 0 then
      Result := Result + ' [' + string.Join('|', Def.FChoices) + ']';
    if Def.FIsInt and (Def.FMin <> Low(Int64)) then
      Result := Result + Format(' [%d-%d]', [Def.FMin, Def.FMax]);
    if Def.FDefault <> '' then
      Result := Result + ' ' + Dim('(default: ' + Def.FDefault + ')');
    if Def.FEnv <> '' then
      Result := Result + ' ' + Dim('(env: ' + Def.FEnv + ')');
    if Def.FRequired and (Def.FKind = akOption) then
      Result := Result + ' ' + Dim('(required)');
  end;

begin
  Lines := TStringList.Create;
  Pos := Positionals;
  try
    if FDescription <> '' then
    begin
      Lines.Add(FDescription);
      Lines.Add('');
    end;
    Usage := FullName;
    if FDefs.Count > Pos.Count then
      Usage := Usage + ' [options]';
    if FCommands.Count > 0 then
      Usage := Usage + ' <command>';
    for I := 0 to Pos.Count - 1 do
    begin
      D := TArgDef(Pos[I]);
      Left := '<' + D.FName + '>';
      if D.FMany then
        Left := Left + '...';
      if not D.FRequired then
        Left := '[' + Left + ']';
      Usage := Usage + ' ' + Left;
    end;
    Lines.Add(Bold('Usage:') + ' ' + Usage);

    if FCommands.Count > 0 then
    begin
      Lines.Add('');
      Lines.Add(Bold('Commands:'));
      for I := 0 to FCommands.Count - 1 do
      begin
        C := TArgCommand(FCommands[I]);
        Row(C.FName, C.FDescription);
      end;
      FlushRows;
    end;

    if Pos.Count > 0 then
    begin
      Lines.Add('');
      Lines.Add(Bold('Arguments:'));
      for I := 0 to Pos.Count - 1 do
      begin
        D := TArgDef(Pos[I]);
        Row('<' + D.FName + '>', D.FHelp + Extras(D));
      end;
      FlushRows;
    end;

    Lines.Add('');
    Lines.Add(Bold('Options:'));
    for I := 0 to FDefs.Count - 1 do
    begin
      D := TArgDef(FDefs[I]);
      if D.FKind = akPositional then
        Continue;
      if D.FShort <> '' then
        Left := '-' + D.FShort + ', --' + D.FName
      else
        Left := '    --' + D.FName;
      if D.FKind = akOption then
        Left := Left + ' ' + D.FMetaVar;
      Right := D.FHelp + Extras(D);
      Row(Left, Right);
    end;
    Row('-h, --help', 'Show this help');
    if (FParent = nil) and (Self is TArgs) and (TArgs(Self).FVersion <> '') then
      Row('    --version', 'Show the version');
    if FParent = nil then
      Row('    --no-color', 'Plain output without colors');
    FlushRows;

    if FCommands.Count > 0 then
    begin
      Lines.Add('');
      Lines.Add(Format('Run "%s <command> --help" for the options of a command.', [FullName]));
    end;

    if FExamples.Count > 0 then
    begin
      Lines.Add('');
      Lines.Add(Bold('Examples:'));
      for I := 0 to FExamples.Count - 1 do
        Lines.Add('  ' + FExamples[I]);
    end;
    Result := Lines.Text;
  finally
    Pos.Free;
    Lines.Free;
  end;
end;

{ ---- TArgs ---- }

constructor TArgs.Create(const AProgram, ADescription: string);
var
  N: string;
begin
  N := AProgram;
  if N = '' then
    N := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  inherited Create(N, ADescription);
end;

function Suggest(const Word: string; const Candidates: TStringList): string;
var
  I, Best, D: Integer;
begin
  Result := '';
  Best := 3;
  for I := 0 to Candidates.Count - 1 do
  begin
    D := Levenshtein(Word, Candidates[I]);
    if (D < Best) or ((D <= 2) and (Pos(LowerCase(Word), LowerCase(Candidates[I])) = 1) and (Result = '')) then
    begin
      Best := D;
      Result := Candidates[I];
    end;
  end;
end;

procedure TArgs.ParseFrom(const Words: array of string);
var
  I, PosIndex, K: Integer;
  W, NameP, Value: string;
  HasValue, OnlyPositional: Boolean;
  Cmd, Sub: TArgCommand;
  D: TArgDef;
  Pos, Names: TStringList;
  PosDefs: TFPList;

  procedure Fail(const Msg: string);
  begin
    FHelpFor := Cmd;
    raise EArgsError.Create(Msg);
  end;

  { an option is looked up on the current command, then on its parents }
  function FindOpt(const N: string; Short: Boolean): TArgDef;
  var
    C: TArgCommand;
  begin
    C := Cmd;
    while C <> nil do
    begin
      if Short then
        Result := C.FindShort(N[1])
      else
        Result := C.FindLong(N);
      if (Result <> nil) and (Result.FKind <> akPositional) then
        Exit;
      C := C.FParent;
    end;
    Result := nil;
  end;

  procedure UnknownOption(const Shown, Bare: string);
  var
    C: TArgCommand;
    J: Integer;
    S: string;
  begin
    Names := TStringList.Create;
    try
      C := Cmd;
      while C <> nil do
      begin
        for J := 0 to C.FDefs.Count - 1 do
          if TArgDef(C.FDefs[J]).FKind <> akPositional then
            Names.Add(TArgDef(C.FDefs[J]).FName);
        C := C.FParent;
      end;
      Names.Add('help');
      S := Suggest(Bare, Names);
      if S <> '' then
        Fail(Format('unknown option "%s" (did you mean --%s?)', [Shown, S]))
      else
        Fail(Format('unknown option "%s"', [Shown]));
    finally
      FreeAndNil(Names);
    end;
  end;

  procedure SetValue(Def: TArgDef; const V: string);
  var
    Err: string;
  begin
    Err := Def.Validate(V);
    if Err <> '' then
      Fail(Err);
    if (Def.FValues.Count > 0) and not Def.FMany and (Def.FKind = akOption) then
      Fail(Format('%s is given more than once', [Def.Display]));
    Def.FValues.Add(V);
  end;

begin
  Reset;
  FSelected := Self;
  FHelpWanted := False;
  FVersionWanted := False;
  FHelpFor := Self;
  Cmd := Self;
  Pos := TStringList.Create;
  try
    OnlyPositional := False;
    I := 0;
    while I <= High(Words) do
    begin
      W := Words[I];
      Inc(I);
      if OnlyPositional or (W = '-') or (W = '') or (W[1] <> '-') then
      begin
        { the first word may choose a sub-command }
        if not OnlyPositional and (Pos.Count = 0) and (Cmd.FCommands.Count > 0) then
        begin
          Sub := Cmd.FindCommand(W);
          if Sub <> nil then
          begin
            Cmd := Sub;
            FSelected := Sub;
            Continue;
          end;
          Names := TStringList.Create;
          try
            for K := 0 to Cmd.FCommands.Count - 1 do
              Names.Add(TArgCommand(Cmd.FCommands[K]).FName);
            NameP := Suggest(W, Names);
          finally
            FreeAndNil(Names);
          end;
          if Cmd.PositionalCount = 0 then
          begin
            if NameP <> '' then
              Fail(Format('unknown command "%s" (did you mean "%s"?)', [W, NameP]))
            else
              Fail(Format('unknown command "%s"', [W]));
          end;
        end;
        Pos.Add(W);
        Continue;
      end;
      if W = '--' then
      begin
        OnlyPositional := True;
        Continue;
      end;
      if (W = '-h') or (W = '--help') then
      begin
        FHelpWanted := True;
        FHelpFor := Cmd;
        Continue;
      end;
      if (W = '--version') and (FVersion <> '') then
      begin
        FVersionWanted := True;
        Continue;
      end;
      if W = '--no-color' then
      begin
        SetColors(False);
        Continue;
      end;

      HasValue := False;
      Value := '';
      if Copy(W, 1, 2) = '--' then
      begin
        NameP := Copy(W, 3, MaxInt);
        K := System.Pos('=', NameP);
        if K > 0 then
        begin
          Value := Copy(NameP, K + 1, MaxInt);
          NameP := Copy(NameP, 1, K - 1);
          HasValue := True;
        end;
        D := FindOpt(NameP, False);
        if D = nil then
          UnknownOption(W, NameP);
      end
      else
      begin
        { -v, -o value, -o=value, -ovalue, -vq (several flags) }
        NameP := W[2];
        D := FindOpt(NameP, True);
        if D = nil then
          UnknownOption('-' + NameP, NameP);
        if Length(W) > 2 then
        begin
          if D.FKind = akFlag then
          begin
            for K := 3 to Length(W) do
            begin
              Inc(D.FCount);
              D := FindOpt(W[K], True);
              if (D = nil) or (D.FKind <> akFlag) then
                Fail(Format('"%s": -%s is not a flag that can be combined', [W, W[K]]));
            end;
          end
          else
          begin
            Value := Copy(W, 3, MaxInt);
            if (Value <> '') and (Value[1] = '=') then
              Delete(Value, 1, 1);
            HasValue := True;
          end;
        end;
      end;

      if D.FKind = akFlag then
      begin
        if HasValue then
          Fail(Format('%s does not take a value', [D.Display]));
        Inc(D.FCount);
        Continue;
      end;
      if not HasValue then
      begin
        if I > High(Words) then
          Fail(Format('%s needs a value (%s)', [D.Display, D.FMetaVar]));
        Value := Words[I];
        Inc(I);
      end;
      SetValue(D, Value);
    end;

    { help and version win over missing arguments }
    if FHelpWanted or FVersionWanted then
      Exit;

    if (Cmd.FCommands.Count > 0) and (Cmd.PositionalCount = 0) and (Pos.Count = 0) then
      Fail('a command is needed');

    { positional words }
    PosDefs := Cmd.Positionals;
    try
      PosIndex := 0;
      for K := 0 to PosDefs.Count - 1 do
      begin
        D := TArgDef(PosDefs[K]);
        if D.FMany then
        begin
          while PosIndex < Pos.Count do
          begin
            SetValue(D, Pos[PosIndex]);
            Inc(PosIndex);
          end;
        end
        else if PosIndex < Pos.Count then
        begin
          SetValue(D, Pos[PosIndex]);
          Inc(PosIndex);
        end;
      end;
      if PosIndex < Pos.Count then
        Fail(Format('unexpected argument "%s"', [Pos[PosIndex]]));
    finally
      PosDefs.Free;
    end;

    { environment variables, then required checks }
    Sub := Cmd;
    while Sub <> nil do
    begin
      for K := 0 to Sub.FDefs.Count - 1 do
      begin
        D := TArgDef(Sub.FDefs[K]);
        if (D.FValues.Count = 0) and (D.FEnv <> '') and (GetEnv(D.FEnv) <> '') then
          SetValue(D, GetEnv(D.FEnv));
        if D.FRequired and (D.FValues.Count = 0) then
          if D.FKind = akPositional then
            Fail(Format('missing argument <%s>: %s', [D.FName, D.FHelp]))
          else
            Fail(Format('missing option --%s: %s', [D.FName, D.FHelp]));
      end;
      Sub := Sub.FParent;
    end;
  finally
    Pos.Free;
  end;
end;

procedure TArgs.Parse;
begin
  try
    ParseFrom(CommandLineWords);
  except
    on E: EArgsError do
    begin
      Flush(Output);
      WriteLn(StdErr, Red('error:'), ' ', E.Message);
      WriteLn(StdErr, Format('Run "%s --help" for usage.', [FHelpFor.FullName]));
      Halt(2);
    end;
  end;
  if FHelpWanted then
  begin
    Write(FHelpFor.HelpText);
    Halt(0);
  end;
  if FVersionWanted then
  begin
    WriteLn(FName, ' ', FVersion);
    Halt(0);
  end;
end;

function TArgs.Lookup(const AName: string): TArgDef;
var
  C: TArgCommand;
begin
  C := FSelected;
  if C = nil then
    C := Self;
  while C <> nil do
  begin
    Result := C.FindLong(AName);
    if Result <> nil then
      Exit;
    C := C.FParent;
  end;
  raise EArgsError.CreateFmt('the program asks for argument "%s", but it was never defined', [AName]);
end;

function TArgs.Has(const AName: string): Boolean;
var
  D: TArgDef;
begin
  D := Lookup(AName);
  Result := (D.FCount > 0) or (D.FValues.Count > 0);
end;

function TArgs.Count(const AName: string): Integer;
var
  D: TArgDef;
begin
  D := Lookup(AName);
  Result := D.FCount + D.FValues.Count;
end;

function TArgs.Get(const AName: string): string;
var
  D: TArgDef;
begin
  D := Lookup(AName);
  if D.FValues.Count > 0 then
    Result := D.FValues[D.FValues.Count - 1]
  else
    Result := D.FDefault;
end;

function TArgs.GetInt(const AName: string): Int64;
var
  S: string;
begin
  S := Get(AName);
  if S = '' then
    Exit(0);
  if not TryStrToInt64(S, Result) then
    raise EArgsError.CreateFmt('--%s expects a whole number, got "%s"', [AName, S]);
end;

function TArgs.GetAll(const AName: string): TStringArray;
var
  D: TArgDef;
  I: Integer;
begin
  Result := nil;
  D := Lookup(AName);
  if (D.FValues.Count = 0) and (D.FDefault <> '') then
  begin
    SetLength(Result, 1);
    Result[0] := D.FDefault;
    Exit;
  end;
  SetLength(Result, D.FValues.Count);
  for I := 0 to D.FValues.Count - 1 do
    Result[I] := D.FValues[I];
end;

function TArgs.CommandName: string;
var
  C: TArgCommand;
begin
  Result := '';
  C := FSelected;
  while (C <> nil) and (C <> Self) do
  begin
    if Result = '' then
      Result := C.FName
    else
      Result := C.FName + ' ' + Result;
    C := C.FParent;
  end;
end;

end.
