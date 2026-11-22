{ Pastel - terminal output and input for console programs.

    WriteLn(Green('done'), ' in ', Bold('2.1s'));
    T := TTable.Create(['Name', 'Size']);
    T.AddRow(['report.pdf', '1.2 MB']);
    T.Print;
    if Confirm('Delete 3 files?') then ...
    Name := Ask('Your name', 'Ali');

  Colors are switched off automatically when the output is not a terminal
  (a pipe or a file), when NO_COLOR is set, or on old Windows consoles.
  Prompts read from standard input, so they also work in scripts and tests.
  Part of the Pastel project, MIT License. }
unit Pastel.Term;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Env;

type
  TTextAlign = (alLeft, alRight, alCenter);

  { A table printed with aligned columns and a line under the header. }
  TTable = class
  private
    FHeader: TStringArray;
    FRows: array of TStringArray;
    FAlign: array of TTextAlign;
  public
    constructor Create(const AHeader: array of string);
    procedure AddRow(const Cells: array of string);
    procedure SetAlign(Column: Integer; Align: TTextAlign);
    function RowCount: Integer;
    function ToText: string;
    procedure Print;
  end;

  { A progress bar on one line: "[########------]  45%  45/100  copying". }
  TProgress = class
  private
    FTotal, FDone: Int64;
    FLabel: string;
    FWidth: Integer;
    FLastDraw: QWord;
    FLastText: string;
    procedure Draw(Force: Boolean);
  public
    constructor Create(ATotal: Int64; const ALabel: string = '');
    destructor Destroy; override;
    procedure Step(Amount: Int64 = 1);
    procedure SetPosition(AValue: Int64);
    procedure SetLabel(const AValue: string);
    { Ends the line; called by Free too. }
    procedure Finish;
    property Position: Int64 read FDone;
    property Total: Int64 read FTotal;
  end;

{ ---- colors and styles: return the text wrapped in escape codes ---- }
function Bold(const S: string): string;
function Dim(const S: string): string;
function Italic(const S: string): string;
function Underline(const S: string): string;
function Red(const S: string): string;
function Green(const S: string): string;
function Yellow(const S: string): string;
function Blue(const S: string): string;
function Magenta(const S: string): string;
function Cyan(const S: string): string;
function Gray(const S: string): string;
{ 24-bit color from '#RRGGBB'; falls back to plain text. }
function Rgb(const Hex, S: string): string;
{ Removes escape codes. }
function StripStyles(const S: string): string;

{ True if colors are used. Can be changed, e.g. for a --no-color option. }
function ColorsEnabled: Boolean;
procedure SetColors(AEnabled: Boolean);
{ True if standard output is a terminal (not a file or a pipe). }
function IsTerminal: Boolean;
function TerminalWidth: Integer;

{ Number of columns a text takes on screen (UTF-8 aware, styles ignored). }
function DisplayWidth(const S: string): Integer;
function PadRight(const S: string; Width: Integer): string;
function PadLeft(const S: string; Width: Integer): string;

{ ---- messages with a symbol, written to the right stream ---- }
procedure Success(const Msg: string);
procedure Info(const Msg: string);
procedure Warning(const Msg: string);
procedure Error(const Msg: string);

{ ---- questions ---- }
{ Asks for a line of text; Default is used when the answer is empty. }
function Ask(const Question: string; const Default: string = ''): string;
{ Yes/no question; Enter gives Default. }
function Confirm(const Question: string; Default: Boolean = False): Boolean;
{ Shows numbered choices; returns the index of the chosen one. }
function Choose(const Question: string; const Choices: array of string; Default: Integer = 0): Integer;
{ Like Ask, but the typed text is not shown (when standard input is a terminal). }
function AskPassword(const Question: string): string;

{ True when standard input is a terminal (someone can answer questions). }
function IsInteractive: Boolean;

implementation

uses
  {$IFDEF UNIX}BaseUnix, termio{$ENDIF}
  {$IFDEF WINDOWS}Windows{$ENDIF};

var
  UseColors: Boolean = False;
  ColorsDecided: Boolean = False;

{ ---- terminal detection ---- }

function IsTerminal: Boolean;
{$IFDEF WINDOWS}
var
  Mode: DWORD;
{$ENDIF}
begin
  {$IFDEF UNIX}
  Result := IsATTY(StdOutputHandle) = 1;
  {$ELSE}
  {$IFDEF WINDOWS}
  Result := GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), Mode);
  {$ELSE}
  Result := False;
  {$ENDIF}
  {$ENDIF}
end;

function IsInteractive: Boolean;
{$IFDEF WINDOWS}
var
  Mode: DWORD;
{$ENDIF}
begin
  {$IFDEF UNIX}
  Result := IsATTY(StdInputHandle) = 1;
  {$ELSE}
  {$IFDEF WINDOWS}
  Result := GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), Mode);
  {$ELSE}
  Result := False;
  {$ENDIF}
  {$ENDIF}
end;

procedure DecideColors;
{$IFDEF WINDOWS}
const
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = $0004;
var
  H: THandle;
  Mode: DWORD;
{$ENDIF}
begin
  ColorsDecided := True;
  UseColors := False;
  if GetEnv('NO_COLOR') <> '' then
    Exit;
  if GetEnv('FORCE_COLOR') <> '' then
  begin
    UseColors := True;
    Exit;
  end;
  if GetEnv('TERM') = 'dumb' then
    Exit;
  {$IFDEF WINDOWS}
  SetConsoleOutputCP(65001);
  H := GetStdHandle(STD_OUTPUT_HANDLE);
  Mode := 0;
  if GetConsoleMode(H, Mode) then
    UseColors := SetConsoleMode(H, Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  {$ELSE}
  UseColors := IsTerminal;
  {$ENDIF}
end;

function ColorsEnabled: Boolean;
begin
  if not ColorsDecided then
    DecideColors;
  Result := UseColors;
end;

procedure SetColors(AEnabled: Boolean);
begin
  ColorsDecided := True;
  UseColors := AEnabled;
end;

function TerminalWidth: Integer;
{$IFDEF UNIX}
var
  WS: TWinSize;
{$ENDIF}
{$IFDEF WINDOWS}
var
  Info: TConsoleScreenBufferInfo;
{$ENDIF}
begin
  Result := StrToIntDef(GetEnv('COLUMNS'), 0);
  if Result > 0 then
    Exit;
  Result := 80;
  {$IFDEF UNIX}
  if (FpIOCtl(StdOutputHandle, TIOCGWINSZ, @WS) = 0) and (WS.ws_col > 0) then
    Result := WS.ws_col;
  {$ENDIF}
  {$IFDEF WINDOWS}
  if GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), Info) then
    Result := Info.srWindow.Right - Info.srWindow.Left + 1;
  {$ENDIF}
end;

{ ---- styles ---- }

function Wrap(const Code, S: string): string;
begin
  if ColorsEnabled then
    Result := #27'[' + Code + 'm' + S + #27'[0m'
  else
    Result := S;
end;

function Bold(const S: string): string;      begin Result := Wrap('1', S); end;
function Dim(const S: string): string;       begin Result := Wrap('2', S); end;
function Italic(const S: string): string;    begin Result := Wrap('3', S); end;
function Underline(const S: string): string; begin Result := Wrap('4', S); end;
function Red(const S: string): string;       begin Result := Wrap('31', S); end;
function Green(const S: string): string;     begin Result := Wrap('32', S); end;
function Yellow(const S: string): string;    begin Result := Wrap('33', S); end;
function Blue(const S: string): string;      begin Result := Wrap('34', S); end;
function Magenta(const S: string): string;   begin Result := Wrap('35', S); end;
function Cyan(const S: string): string;      begin Result := Wrap('36', S); end;
function Gray(const S: string): string;      begin Result := Wrap('90', S); end;

function Rgb(const Hex, S: string): string;
var
  V: LongInt;
begin
  if (Length(Hex) <> 7) or (Hex[1] <> '#') or not TryStrToInt('$' + Copy(Hex, 2, 6), V) then
    Exit(S);
  Result := Wrap(Format('38;2;%d;%d;%d', [(V shr 16) and $FF, (V shr 8) and $FF, V and $FF]), S);
end;

function StripStyles(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = #27) and (I < Length(S)) and (S[I + 1] = '[') then
    begin
      Inc(I, 2);
      while (I <= Length(S)) and not (S[I] in ['@'..'~']) do
        Inc(I);
      Inc(I);
      Continue;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
end;

{ East Asian wide characters and most emoji take two columns. }
function CharWidth(CP: Cardinal): Integer;
begin
  if (CP = 0) or ((CP >= $300) and (CP <= $36F)) or (CP = $200D) or
     ((CP >= $FE00) and (CP <= $FE0F)) then
    Exit(0);   { combining marks, joiners, variation selectors }
  if ((CP >= $1100) and (CP <= $115F)) or ((CP >= $2E80) and (CP <= $A4CF)) or
     ((CP >= $AC00) and (CP <= $D7A3)) or ((CP >= $F900) and (CP <= $FAFF)) or
     ((CP >= $FE30) and (CP <= $FE4F)) or ((CP >= $FF00) and (CP <= $FF60)) or
     ((CP >= $FFE0) and (CP <= $FFE6)) or ((CP >= $1F300) and (CP <= $1FAFF)) or
     ((CP >= $20000) and (CP <= $3FFFD)) then
    Exit(2);
  Result := 1;
end;

function DisplayWidth(const S: string): Integer;
var
  T: string;
  I, N, K: Integer;
  B: Byte;
  CP: Cardinal;
begin
  T := StripStyles(S);
  Result := 0;
  I := 1;
  while I <= Length(T) do
  begin
    B := Ord(T[I]);
    if B < $80 then begin CP := B; N := 0; end
    else if (B and $E0) = $C0 then begin CP := B and $1F; N := 1; end
    else if (B and $F0) = $E0 then begin CP := B and $0F; N := 2; end
    else if (B and $F8) = $F0 then begin CP := B and $07; N := 3; end
    else begin CP := $FFFD; N := 0; end;
    Inc(I);
    for K := 1 to N do
      if (I <= Length(T)) and ((Ord(T[I]) and $C0) = $80) then
      begin
        CP := (CP shl 6) or (Ord(T[I]) and $3F);
        Inc(I);
      end;
    Inc(Result, CharWidth(CP));
  end;
end;

function PadRight(const S: string; Width: Integer): string;
var
  W: Integer;
begin
  W := DisplayWidth(S);
  if W >= Width then
    Result := S
  else
    Result := S + StringOfChar(' ', Width - W);
end;

function PadLeft(const S: string; Width: Integer): string;
var
  W: Integer;
begin
  W := DisplayWidth(S);
  if W >= Width then
    Result := S
  else
    Result := StringOfChar(' ', Width - W) + S;
end;

{ ---- messages ---- }

function Mark(const Unicode, Ascii: string): string;
begin
  {$IFDEF WINDOWS}
  if not ColorsEnabled then
    Exit(Ascii);
  {$ENDIF}
  Result := Unicode;
end;

procedure Success(const Msg: string);
begin
  WriteLn(Green(Mark('✓', '[ok]')), ' ', Msg);
end;

procedure Info(const Msg: string);
begin
  WriteLn(Cyan(Mark('i', '[i]')), ' ', Msg);
end;

procedure Warning(const Msg: string);
begin
  Flush(Output);
  WriteLn(StdErr, Yellow(Mark('!', '[!]')), ' ', Msg);
  Flush(StdErr);
end;

procedure Error(const Msg: string);
begin
  Flush(Output);
  WriteLn(StdErr, Red(Mark('✗', '[x]')), ' ', Msg);
  Flush(StdErr);
end;

{ ---- table ---- }

constructor TTable.Create(const AHeader: array of string);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FHeader, Length(AHeader));
  SetLength(FAlign, Length(AHeader));
  for I := 0 to High(AHeader) do
  begin
    FHeader[I] := AHeader[I];
    FAlign[I] := alLeft;
  end;
end;

procedure TTable.AddRow(const Cells: array of string);
var
  Row: TStringArray;
  I: Integer;
begin
  SetLength(Row, Length(FHeader));
  for I := 0 to High(Row) do
    if I <= High(Cells) then
      Row[I] := Cells[I]
    else
      Row[I] := '';
  SetLength(FRows, Length(FRows) + 1);
  FRows[High(FRows)] := Row;
end;

procedure TTable.SetAlign(Column: Integer; Align: TTextAlign);
begin
  if (Column >= 0) and (Column <= High(FAlign)) then
    FAlign[Column] := Align;
end;

function TTable.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TTable.ToText: string;
var
  Widths: array of Integer;
  I, R, Total: Integer;
  Line: string;

  function Cell(const S: string; Col: Integer): string;
  var
    Space: Integer;
  begin
    case FAlign[Col] of
      alRight: Result := PadLeft(S, Widths[Col]);
      alCenter:
        begin
          Space := Widths[Col] - DisplayWidth(S);
          Result := StringOfChar(' ', Space div 2) + S + StringOfChar(' ', Space - Space div 2);
        end;
    else
      Result := PadRight(S, Widths[Col]);
    end;
  end;

  function Join(const Cells: TStringArray; Header: Boolean): string;
  var
    C: Integer;
  begin
    Result := '';
    for C := 0 to High(Cells) do
    begin
      if C > 0 then
        Result := Result + '  ';
      if Header then
        Result := Result + Bold(Cell(Cells[C], C))
      else
        Result := Result + Cell(Cells[C], C);
    end;
    Result := TrimRight(Result);
  end;

begin
  SetLength(Widths, Length(FHeader));
  for I := 0 to High(FHeader) do
  begin
    Widths[I] := DisplayWidth(FHeader[I]);
    for R := 0 to High(FRows) do
      if DisplayWidth(FRows[R][I]) > Widths[I] then
        Widths[I] := DisplayWidth(FRows[R][I]);
  end;
  Total := 0;
  for I := 0 to High(Widths) do
    Inc(Total, Widths[I] + 2);
  if Total > 0 then
    Dec(Total, 2);
  Result := Join(FHeader, True) + LineEnding;
  Line := '';
  for I := 0 to High(Widths) do
  begin
    if I > 0 then
      Line := Line + '  ';
    Line := Line + StringOfChar('-', Widths[I]);
  end;
  Result := Result + Dim(Line) + LineEnding;
  for R := 0 to High(FRows) do
    Result := Result + Join(FRows[R], False) + LineEnding;
end;

procedure TTable.Print;
begin
  Write(ToText);
end;

{ ---- progress ---- }

constructor TProgress.Create(ATotal: Int64; const ALabel: string);
begin
  inherited Create;
  FTotal := ATotal;
  FLabel := ALabel;
  FWidth := 30;
  Draw(True);
end;

destructor TProgress.Destroy;
begin
  Finish;
  inherited Destroy;
end;

procedure TProgress.Draw(Force: Boolean);
var
  Filled, Percent: Integer;
  Text: string;
begin
  if FTotal > 0 then
    Percent := Integer(FDone * 100 div FTotal)
  else
    Percent := 0;
  if Percent > 100 then
    Percent := 100;
  if not IsTerminal then
  begin
    { in a log file, one line per 10% is enough }
    Text := Format('%3d%%', [Percent div 10 * 10]);
    if Force or (Text <> FLastText) then
    begin
      WriteLn(Format('%3d%%  %d/%d  %s', [Percent, FDone, FTotal, FLabel]));
      FLastText := Text;
    end;
    Exit;
  end;
  if not Force and (GetTickCount64 - FLastDraw < 50) then
    Exit;
  FLastDraw := GetTickCount64;
  Filled := Percent * FWidth div 100;
  Text := Format('[%s%s] %3d%%  %d/%d  %s', [StringOfChar('#', Filled),
    StringOfChar('-', FWidth - Filled), Percent, FDone, FTotal, FLabel]);
  if DisplayWidth(Text) > TerminalWidth - 1 then
    Text := Copy(Text, 1, TerminalWidth - 1);
  Write(#13, Text, #27'[K');
  Flush(Output);
end;

procedure TProgress.Step(Amount: Int64);
begin
  SetPosition(FDone + Amount);
end;

procedure TProgress.SetPosition(AValue: Int64);
begin
  FDone := AValue;
  Draw(FDone >= FTotal);
end;

procedure TProgress.SetLabel(const AValue: string);
begin
  FLabel := AValue;
  Draw(False);
end;

procedure TProgress.Finish;
begin
  if FWidth = 0 then
    Exit;
  if IsTerminal then
  begin
    Draw(True);
    WriteLn;
  end;
  FWidth := 0;
end;

{ ---- questions ---- }

function ReadAnswer(out Line: string): Boolean;
begin
  Line := '';
  if EOF(Input) then
    Exit(False);
  ReadLn(Line);
  Line := Trim(Line);
  Result := True;
end;

function Ask(const Question: string; const Default: string): string;
begin
  if Default <> '' then
    Write(Bold(Question), ' ', Dim('[' + Default + ']'), ': ')
  else
    Write(Bold(Question), ': ');
  Flush(Output);
  if not ReadAnswer(Result) or (Result = '') then
    Result := Default;
  if not IsInteractive then
    WriteLn(Result);   { keep the transcript readable when answers are piped in }
end;

function Confirm(const Question: string; Default: Boolean): Boolean;
var
  Answer, Hint: string;
begin
  if Default then Hint := 'Y/n' else Hint := 'y/N';
  repeat
    Write(Bold(Question), ' ', Dim('[' + Hint + ']'), ' ');
    Flush(Output);
    if not ReadAnswer(Answer) then
    begin
      if not IsInteractive then WriteLn;
      Exit(Default);
    end;
    if not IsInteractive then
      WriteLn(Answer);
    Answer := LowerCase(Answer);
    if Answer = '' then Exit(Default);
    if (Answer = 'y') or (Answer = 'yes') or (Answer = 'e') or (Answer = 'evet') then Exit(True);
    if (Answer = 'n') or (Answer = 'no') or (Answer = 'h') or (Answer = 'hayir') or (Answer = 'hayır') then
      Exit(False);
    WriteLn(Yellow('Please answer y or n.'));
  until False;
end;

function Choose(const Question: string; const Choices: array of string; Default: Integer): Integer;
var
  I, N: Integer;
  Answer: string;
begin
  if Length(Choices) = 0 then
    Exit(-1);
  if (Default < 0) or (Default > High(Choices)) then
    Default := 0;
  WriteLn(Bold(Question));
  for I := 0 to High(Choices) do
    if I = Default then
      WriteLn('  ', Cyan(IntToStr(I + 1) + ')'), ' ', Choices[I], ' ', Dim('(default)'))
    else
      WriteLn('  ', Cyan(IntToStr(I + 1) + ')'), ' ', Choices[I]);
  repeat
    Write(Dim(Format('Choose 1-%d', [Length(Choices)])), ' ', Dim('[' + IntToStr(Default + 1) + ']'), ': ');
    Flush(Output);
    if not ReadAnswer(Answer) then
    begin
      if not IsInteractive then WriteLn;
      Exit(Default);
    end;
    if not IsInteractive then
      WriteLn(Answer);
    if Answer = '' then
      Exit(Default);
    N := StrToIntDef(Answer, 0);
    if (N >= 1) and (N <= Length(Choices)) then
      Exit(N - 1);
    { the text of a choice works too }
    for I := 0 to High(Choices) do
      if SameText(Answer, Choices[I]) then
        Exit(I);
    WriteLn(Yellow(Format('Please type a number from 1 to %d.', [Length(Choices)])));
  until False;
end;

function AskPassword(const Question: string): string;
{$IFDEF UNIX}
var
  Old, Raw: Termios;
  Hidden: Boolean;
{$ENDIF}
{$IFDEF WINDOWS}
var
  H: THandle;
  Mode: DWORD;
  Hidden: Boolean;
{$ENDIF}
begin
  Write(Bold(Question), ': ');
  Flush(Output);
  {$IFDEF UNIX}
  Hidden := IsInteractive and (TCGetAttr(StdInputHandle, Old) = 0);
  if Hidden then
  begin
    Raw := Old;
    Raw.c_lflag := Raw.c_lflag and not ECHO;
    TCSetAttr(StdInputHandle, TCSANOW, Raw);
  end;
  try
    ReadAnswer(Result);
  finally
    if Hidden then
    begin
      TCSetAttr(StdInputHandle, TCSANOW, Old);
      WriteLn;
    end;
  end;
  {$ELSE}
  {$IFDEF WINDOWS}
  H := GetStdHandle(STD_INPUT_HANDLE);
  Hidden := GetConsoleMode(H, Mode);
  if Hidden then
    SetConsoleMode(H, Mode and not ENABLE_ECHO_INPUT);
  try
    ReadAnswer(Result);
  finally
    if Hidden then
    begin
      SetConsoleMode(H, Mode);
      WriteLn;
    end;
  end;
  {$ELSE}
  ReadAnswer(Result);
  {$ENDIF}
  {$ENDIF}
  if not IsInteractive then
    WriteLn;
end;

end.
