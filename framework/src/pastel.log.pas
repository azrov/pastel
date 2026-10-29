(* Pastel - logging.

    Log.Info('Server started on port %d', [Port]);
    Log.Warn('Disk is %d%% full', [Used]);
    Log.Error(E, 'could not save the order');          // an exception
    Log.Fields(['user', Name, 'ip', IP]).Info('login'); // structured fields
    Log.Debug('only shown with Log.Level := llDebug');

  Output goes to standard error, one line per message:
    2026-10-29 15:04:05.123 INFO  login user=ali ip=10.0.0.5
  Under systemd it switches to the form journald understands (priority
  prefix, no time stamp), so "journalctl -p err" works. Log.Format := lfJson
  writes one JSON object per line for log collectors. Log.ToFile adds a file
  that is rotated by size. Logging is safe from several threads.
  Part of the Pastel project, MIT License. *)
unit Pastel.Log;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

type
  TLogLevel = (llDebug, llInfo, llWarn, llError, llOff);
  TLogFormat = (lfAuto, lfText, lfJson, lfJournal);
  TLogLineEvent = procedure(Level: TLogLevel; const Line: string) of object;

  TLogger = class;

  { Fields to attach to one message: Log.Fields(['user', 'ali']).Info('login') }
  TLogFields = record
    Logger: TLogger;
    Items: TStringArray;
    procedure Debug(const Msg: string);
    procedure Info(const Msg: string);
    procedure Warn(const Msg: string);
    procedure Error(const Msg: string);
  end;

  TLogger = class
  private
    FLevel: TLogLevel;
    FFormat: TLogFormat;
    FConsole: Boolean;
    FFileName: string;
    FMaxBytes: Int64;
    FKeep: Integer;
    FLock: TRTLCriticalSection;
    FOnLine: TLogLineEvent;
    FColors: Boolean;
    function EffectiveFormat: TLogFormat;
    function FormatLine(Level: TLogLevel; Fmt: TLogFormat; const Msg: string;
      const Fields: TStringArray; Colored: Boolean): string;
    procedure WriteToFile(const Line: string);
    procedure Rotate;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Write(Level: TLogLevel; const Msg: string; const Fields: TStringArray);
    function Enabled(Level: TLogLevel): Boolean;

    procedure Debug(const Msg: string); overload;
    procedure Debug(const Fmt: string; const Args: array of const); overload;
    procedure Info(const Msg: string); overload;
    procedure Info(const Fmt: string; const Args: array of const); overload;
    procedure Warn(const Msg: string); overload;
    procedure Warn(const Fmt: string; const Args: array of const); overload;
    procedure Error(const Msg: string); overload;
    procedure Error(const Fmt: string; const Args: array of const); overload;
    { Logs an exception with its class and message, after What (if given). }
    procedure Error(E: Exception; const What: string = ''); overload;

    { Names and values alternate: ['user', 'ali', 'items', 3]. }
    function Fields(const NamesAndValues: array of const): TLogFields;

    { Also write to a file. When it grows past MaxMB it becomes name.1
      (older ones name.2 ... name.Keep), and a new file is started. }
    procedure ToFile(const FileName: string; MaxMB: Integer = 10; Keep: Integer = 5);
    { 'debug', 'info', 'warn'/'warning', 'error', 'off'; raises for others. }
    procedure SetLevel(const Name: string);

    property Level: TLogLevel read FLevel write FLevel;
    property Format: TLogFormat read FFormat write FFormat;
    { Write to standard error (default True). }
    property Console: Boolean read FConsole write FConsole;
    { Size at which the log file is rotated (ToFile sets it from MaxMB). }
    property MaxBytes: Int64 read FMaxBytes write FMaxBytes;
    { Called for every line written (for tests or custom outputs). }
    property OnLine: TLogLineEvent read FOnLine write FOnLine;
  end;

var
  { The program's logger. }
  Log: TLogger;

function LevelName(Level: TLogLevel): string;

implementation

uses
  {$IFDEF UNIX}termio,{$ENDIF} DateUtils;

function LevelName(Level: TLogLevel): string;
const
  Names: array[TLogLevel] of string = ('debug', 'info', 'warn', 'error', 'off');
begin
  Result := Names[Level];
end;

function VarToText(const V: TVarRec): string;
begin
  case V.VType of
    vtInteger: Result := IntToStr(V.VInteger);
    vtInt64: Result := IntToStr(V.VInt64^);
    vtQWord: Result := IntToStr(V.VQWord^);
    vtBoolean: Result := BoolToStr(V.VBoolean, 'true', 'false');
    vtExtended: Result := FloatToStr(V.VExtended^);
    vtCurrency: Result := CurrToStr(V.VCurrency^);
    vtString: Result := V.VString^;
    vtAnsiString: Result := AnsiString(V.VAnsiString);
    vtUnicodeString: Result := UTF8Encode(UnicodeString(V.VUnicodeString));
    vtWideString: Result := UTF8Encode(WideString(V.VWideString));
    vtChar: Result := V.VChar;
    vtPChar: Result := StrPas(V.VPChar);
    vtObject:
      if V.VObject = nil then Result := 'nil' else Result := V.VObject.ClassName;
    vtPointer:
      if V.VPointer = nil then Result := 'nil' else Result := '$' + HexStr(V.VPointer);
  else
    Result := '?';
  end;
end;

function JsonEscape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
    else
      if S[I] < ' ' then
        Result := Result + '\u' + IntToHex(Ord(S[I]), 4)
      else
        Result := Result + S[I];
    end;
end;

{ value as it appears after name= in text logs: quoted when it has spaces }
function TextValue(const S: string): string;
begin
  if (S = '') or (Pos(' ', S) > 0) or (Pos('"', S) > 0) or (Pos('=', S) > 0) then
    Result := '"' + StringReplace(S, '"', '\"', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

{ ---- TLogFields ---- }

procedure TLogFields.Debug(const Msg: string);
begin
  Logger.Write(llDebug, Msg, Items);
end;

procedure TLogFields.Info(const Msg: string);
begin
  Logger.Write(llInfo, Msg, Items);
end;

procedure TLogFields.Warn(const Msg: string);
begin
  Logger.Write(llWarn, Msg, Items);
end;

procedure TLogFields.Error(const Msg: string);
begin
  Logger.Write(llError, Msg, Items);
end;

{ ---- TLogger ---- }

constructor TLogger.Create;
var
  L: string;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FLevel := llInfo;
  FFormat := lfAuto;
  FConsole := True;
  {$IFDEF UNIX}
  FColors := (IsATTY(StdErrorHandle) = 1) and (GetEnvironmentVariable('NO_COLOR') = '');
  {$ENDIF}
  { LOG_LEVEL=debug works for every Pastel program }
  L := GetEnvironmentVariable('LOG_LEVEL');
  if L <> '' then
    try
      SetLevel(L);
    except
      on EConvertError do ;
    end;
end;

destructor TLogger.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TLogger.SetLevel(const Name: string);
begin
  case LowerCase(Trim(Name)) of
    'debug', 'trace', 'all': FLevel := llDebug;
    'info', 'information': FLevel := llInfo;
    'warn', 'warning': FLevel := llWarn;
    'error': FLevel := llError;
    'off', 'none', 'quiet': FLevel := llOff;
  else
    raise EConvertError.CreateFmt('unknown log level "%s" (debug, info, warn, error or off)', [Name]);
  end;
end;

function TLogger.Enabled(Level: TLogLevel): Boolean;
begin
  Result := (Level >= FLevel) and (FLevel <> llOff);
end;

function TLogger.EffectiveFormat: TLogFormat;
begin
  Result := FFormat;
  if Result = lfAuto then
  begin
    { systemd sets JOURNAL_STREAM when stderr goes to the journal }
    if GetEnvironmentVariable('JOURNAL_STREAM') <> '' then
      Result := lfJournal
    else
      Result := lfText;
  end;
end;

function TLogger.FormatLine(Level: TLogLevel; Fmt: TLogFormat; const Msg: string;
  const Fields: TStringArray; Colored: Boolean): string;
const
  Upper: array[TLogLevel] of string = ('DEBUG', 'INFO ', 'WARN ', 'ERROR', 'OFF  ');
  Colors: array[TLogLevel] of string = ('90', '36', '33', '31', '0');
  { syslog priorities: debug=7, info=6, warning=4, err=3 }
  Priority: array[TLogLevel] of string = ('<7>', '<6>', '<4>', '<3>', '<6>');
var
  I: Integer;
  Now_: TDateTime;
  Tail, LevelText: string;
begin
  Tail := '';
  I := 0;
  if Fmt = lfJson then
  begin
    Now_ := LocalTimeToUniversal(Now);
    Result := '{"time":"' + FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz"Z"', Now_) +
      '","level":"' + LevelName(Level) + '","msg":"' + JsonEscape(Msg) + '"';
    while I < High(Fields) do
    begin
      Result := Result + ',"' + JsonEscape(Fields[I]) + '":"' + JsonEscape(Fields[I + 1]) + '"';
      Inc(I, 2);
    end;
    Result := Result + '}';
    Exit;
  end;
  while I < High(Fields) do
  begin
    Tail := Tail + ' ' + Fields[I] + '=' + TextValue(Fields[I + 1]);
    Inc(I, 2);
  end;
  if Fmt = lfJournal then
    Exit(Priority[Level] + Msg + Tail);
  LevelText := Upper[Level];
  if Colored then
    LevelText := #27'[' + Colors[Level] + 'm' + LevelText + #27'[0m';
  Result := FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss"."zzz', Now) + ' ' + LevelText + ' ' + Msg + Tail;
end;

procedure TLogger.Rotate;
var
  I: Integer;
begin
  if FKeep <= 0 then
  begin
    DeleteFile(FFileName);
    Exit;
  end;
  DeleteFile(FFileName + '.' + IntToStr(FKeep));
  for I := FKeep - 1 downto 1 do
    if FileExists(FFileName + '.' + IntToStr(I)) then
      RenameFile(FFileName + '.' + IntToStr(I), FFileName + '.' + IntToStr(I + 1));
  RenameFile(FFileName, FFileName + '.1');
end;

procedure TLogger.WriteToFile(const Line: string);
var
  F: TFileStream;
  S: string;
begin
  S := Line + LineEnding;
  try
    if FileExists(FFileName) then
    begin
      F := TFileStream.Create(FFileName, fmOpenReadWrite or fmShareDenyNone);
      if (FMaxBytes > 0) and (F.Size + Length(S) > FMaxBytes) and (F.Size > 0) then
      begin
        F.Free;
        Rotate;
        F := TFileStream.Create(FFileName, fmCreate);
      end;
    end
    else
      F := TFileStream.Create(FFileName, fmCreate);
    try
      F.Seek(0, soEnd);
      F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
  except
    on E: Exception do
      if FConsole then
        WriteLn(StdErr, 'log: cannot write to ', FFileName, ': ', E.Message);
  end;
end;

procedure TLogger.Write(Level: TLogLevel; const Msg: string; const Fields: TStringArray);
var
  Fmt: TLogFormat;
  Line: string;
begin
  if not Enabled(Level) then
    Exit;
  Fmt := EffectiveFormat;
  EnterCriticalSection(FLock);
  try
    if FConsole then
    begin
      Line := FormatLine(Level, Fmt, Msg, Fields, FColors);
      Flush(Output);
      WriteLn(StdErr, Line);
      Flush(StdErr);
    end;
    if FFileName <> '' then
    begin
      { files get text or JSON, never colors or journal prefixes }
      if Fmt = lfJson then
        WriteToFile(FormatLine(Level, lfJson, Msg, Fields, False))
      else
        WriteToFile(FormatLine(Level, lfText, Msg, Fields, False));
    end;
    if Assigned(FOnLine) then
      FOnLine(Level, FormatLine(Level, Fmt, Msg, Fields, False));
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogger.Debug(const Msg: string);
begin
  Write(llDebug, Msg, nil);
end;

procedure TLogger.Debug(const Fmt: string; const Args: array of const);
begin
  if Enabled(llDebug) then
    Write(llDebug, SysUtils.Format(Fmt, Args), nil);
end;

procedure TLogger.Info(const Msg: string);
begin
  Write(llInfo, Msg, nil);
end;

procedure TLogger.Info(const Fmt: string; const Args: array of const);
begin
  if Enabled(llInfo) then
    Write(llInfo, SysUtils.Format(Fmt, Args), nil);
end;

procedure TLogger.Warn(const Msg: string);
begin
  Write(llWarn, Msg, nil);
end;

procedure TLogger.Warn(const Fmt: string; const Args: array of const);
begin
  if Enabled(llWarn) then
    Write(llWarn, SysUtils.Format(Fmt, Args), nil);
end;

procedure TLogger.Error(const Msg: string);
begin
  Write(llError, Msg, nil);
end;

procedure TLogger.Error(const Fmt: string; const Args: array of const);
begin
  if Enabled(llError) then
    Write(llError, SysUtils.Format(Fmt, Args), nil);
end;

procedure TLogger.Error(E: Exception; const What: string);
var
  F: TStringArray;
begin
  SetLength(F, 2);
  F[0] := 'error';
  F[1] := E.ClassName;
  if What <> '' then
    Write(llError, What + ': ' + E.Message, F)
  else
    Write(llError, E.Message, F);
end;

function TLogger.Fields(const NamesAndValues: array of const): TLogFields;
var
  I: Integer;
begin
  Result.Logger := Self;
  SetLength(Result.Items, Length(NamesAndValues) and not 1);
  for I := 0 to High(Result.Items) do
    Result.Items[I] := VarToText(NamesAndValues[I]);
end;

procedure TLogger.ToFile(const FileName: string; MaxMB: Integer; Keep: Integer);
begin
  FFileName := ExpandFileName(FileName);
  FMaxBytes := Int64(MaxMB) * 1024 * 1024;
  FKeep := Keep;
  ForceDirectories(ExtractFileDir(FFileName));
end;

initialization
  Log := TLogger.Create;

finalization
  FreeAndNil(Log);

end.
