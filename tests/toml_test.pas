{ Unit tests for Pastel.Toml. Run with: sh tests/run.sh }
program toml_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Pastel.Toml;

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const Name: string);
begin
  if Cond then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name);
  end;
end;

function Parse(const Src: string): TTomlDocument;
begin
  Result := TTomlDocument.Create;
  Result.LoadFromString(Src);
end;

{ True if parsing Src raises ETomlError whose message contains Part. }
function FailsWith(const Src, Part: string): Boolean;
var
  D: TTomlDocument;
begin
  D := TTomlDocument.Create;
  try
    try
      D.LoadFromString(Src);
      Result := False;
    except
      on E: ETomlError do
        Result := Pos(Part, E.Message) > 0;
    end;
  finally
    D.Free;
  end;
end;

procedure TestBasics;
var
  D: TTomlDocument;
  A: TStringArray;
begin
  D := Parse(
    '# comment' + LineEnding +
    'top = "level"' + LineEnding +
    '' + LineEnding +
    '[project]' + LineEnding +
    'name = "hello"   # trailing comment' + LineEnding +
    'version = ''0.1.0''' + LineEnding +
    'count = 1_000' + LineEnding +
    'ratio = 0.5' + LineEnding +
    'debug = true' + LineEnding +
    'site.url = "https://x.org/#top"' + LineEnding +
    '[targets]' + LineEnding +
    'platforms = [' + LineEnding +
    '  "linux",   # first' + LineEnding +
    '  "windows",' + LineEnding +
    ']' + LineEnding +
    'empty = []');
  try
    Check(D.GetString('top') = 'level', 'top-level key');
    Check(D.GetString('project.name') = 'hello', 'basic string');
    Check(D.GetString('project.version') = '0.1.0', 'literal string');
    Check(D.GetInt('project.count') = 1000, 'integer with underscores');
    Check(D.Find('project.ratio').Kind = tkFloat, 'float');
    Check(D.GetBool('project.debug'), 'boolean');
    Check(D.GetString('project.site.url') = 'https://x.org/#top', 'dotted key, # inside string');
    A := D.GetArray('targets.platforms');
    Check((Length(A) = 2) and (A[0] = 'linux') and (A[1] = 'windows'), 'multi-line array, trailing comma');
    Check(Length(D.GetArray('targets.empty')) = 0, 'empty array');
    Check(D.Has('targets'), 'table exists');
    Check(D.GetString('missing', 'dflt') = 'dflt', 'default value');
    Check(D.GetArray('missing') = nil, 'missing array is nil');
  finally
    D.Free;
  end;
end;

procedure TestEscapes;
var
  D: TTomlDocument;
begin
  D := Parse('a = "tab\there \"q\" \\ \u00e7\u011f"' + LineEnding +
             'b = ''C:\no\escapes''');
  try
    Check(D.GetString('a') = 'tab'#9'here "q" \ çğ', 'escapes and unicode');
    Check(D.GetString('b') = 'C:\no\escapes', 'literal string keeps backslashes');
  finally
    D.Free;
  end;
end;

procedure TestWindowsLineEndings;
var
  D: TTomlDocument;
begin
  D := Parse('[project]'#13#10'name = "win"'#13#10'list = ["a",'#13#10' "b"]'#13#10);
  try
    Check(D.GetString('project.name') = 'win', 'CRLF line endings');
    Check(Length(D.GetArray('project.list')) = 2, 'CRLF inside array');
  finally
    D.Free;
  end;
end;

procedure TestErrors;
begin
  Check(FailsWith('name = hello', 'line 1: invalid value'), 'unquoted string');
  Check(FailsWith('a = 1'#10'a = 2', 'line 2: key "a" is defined twice'), 'duplicate key');
  Check(FailsWith('[x]'#10'[x]', 'defined twice'), 'duplicate table');
  Check(FailsWith('a = "open', 'unterminated string'), 'unterminated string');
  Check(FailsWith('a = 1 2', 'unexpected text'), 'text after value');
  Check(FailsWith('a = [1, 2', 'unterminated array'), 'unterminated array');
  Check(FailsWith('[[items]]', 'not supported'), 'arrays of tables');
  Check(FailsWith('= 5', 'expected a key'), 'missing key');
end;

procedure TestTypeErrors;
var
  D: TTomlDocument;
  Raised: Boolean;
begin
  D := Parse('n = "text"'#10'l = ["a"]');
  try
    Raised := False;
    try
      D.GetInt('n');
    except
      on ETomlError do Raised := True;
    end;
    Check(Raised, 'GetInt on a string raises');
    Raised := False;
    try
      D.GetString('l');
    except
      on ETomlError do Raised := True;
    end;
    Check(Raised, 'GetString on a list raises');
  finally
    D.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestBasics;
  TestEscapes;
  TestWindowsLineEndings;
  TestErrors;
  TestTypeErrors;
  WriteLn(Format('toml: %d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
