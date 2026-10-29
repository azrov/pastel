{ Unit tests for Pastel.Format. Run with: sh tests/run.sh }
program format_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Pastel.Format;

var
  Passed, Failed: Integer;

function J(const Lines: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Lines) do
    Result := Result + Lines[I] + #10;
end;

procedure Expect(const Name: string; const Input, Expected: string);
var
  Output, Again, Error: string;
begin
  if not FormatPascal(Input, DefaultFormatOptions, Output, Error) then
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name, ': ', Error);
    Exit;
  end;
  if Output <> Expected then
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name);
    WriteLn('--- expected'#10, Expected, '--- got'#10, Output, '---');
    Exit;
  end;
  { formatting twice changes nothing }
  FormatPascal(Output, DefaultFormatOptions, Again, Error);
  if Again <> Output then
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name, ' (not stable)'#10, Again);
    Exit;
  end;
  Inc(Passed);
end;

procedure ExpectError(const Name, Input, Part: string);
var
  Output, Error: string;
begin
  if FormatPascal(Input, DefaultFormatOptions, Output, Error) or (Pos(Part, Error) = 0) or
     (Output <> Input) then
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name, ': got "', Error, '"');
  end
  else
    Inc(Passed);
end;

begin
  Passed := 0;
  Failed := 0;

  Expect('statements', J([
    'program t;',
    'begin',
    'if A then',
    'Foo',
    'else',
    'begin',
    'Bar;',
    'end;',
    'while X do',
    'Inc(X);',
    'for I := 1 to 3 do begin',
    'WriteLn(I);',
    'end;',
    'end.']), J([
    'program t;',
    'begin',
    '  if A then',
    '    Foo',
    '  else',
    '  begin',
    '    Bar;',
    '  end;',
    '  while X do',
    '    Inc(X);',
    '  for I := 1 to 3 do begin',
    '    WriteLn(I);',
    '  end;',
    'end.']));

  Expect('else if chains and nested if', J([
    'begin',
    '      if A then',
    'X',
    '        else if B then',
    '   Y',
    'else',
    '  if C then',
    'Z',
    '  else',
    'W;',
    'Done;',
    'end.']), J([
    'begin',
    '  if A then',
    '    X',
    '  else if B then',
    '    Y',
    '  else',
    '    if C then',
    '      Z',
    '    else',
    '      W;',
    '  Done;',
    'end.']));

  Expect('end else begin', J([
    'begin',
    'if A then begin',
    'X;',
    'end else begin',
    'Y;',
    'end;',
    'end.']), J([
    'begin',
    '  if A then begin',
    '    X;',
    '  end else begin',
    '    Y;',
    '  end;',
    'end.']));

  Expect('case', J([
    'begin',
    'case Mode of',
    '1: A;',
    '2, 3:',
    'B;',
    '4:',
    'begin',
    'C;',
    'end;',
    'else',
    'D;',
    'E;',
    'end;',
    'end.']), J([
    'begin',
    '  case Mode of',
    '    1: A;',
    '    2, 3:',
    '      B;',
    '    4:',
    '      begin',
    '        C;',
    '      end;',
    '  else',
    '    D;',
    '    E;',
    '  end;',
    'end.']));

  Expect('try, repeat, on', J([
    'begin',
    'try',
    'repeat',
    'Step;',
    'until Done;',
    'except',
    'on E: Exception do',
    'Show(E);',
    'end;',
    'if Found then',
    'try',
    'Use;',
    'finally',
    'Close;',
    'end;',
    'end.']), J([
    'begin',
    '  try',
    '    repeat',
    '      Step;',
    '    until Done;',
    '  except',
    '    on E: Exception do',
    '      Show(E);',
    '  end;',
    '  if Found then',
    '  try',
    '    Use;',
    '  finally',
    '    Close;',
    '  end;',
    'end.']));

  Expect('unit with class, record and routines', J([
    'unit u;',
    'interface',
    'uses',
    'Classes;',
    'type',
    'TFoo = class(TObject)',
    'private',
    'FX: Integer;',
    'public',
    'procedure Run; virtual;',
    'property X: Integer read FX;',
    'end;',
    'TBar = class;',
    'TErr = class(Exception);',
    'TRec = record',
    'case Integer of',
    '0: (A: Integer);',
    '1: (B: Byte);',
    'end;',
    'TProc = procedure(X: Integer) of object;',
    'const',
    'Max = 10;',
    'function Twice(X: Integer): Integer;',
    'implementation',
    'function Twice(X: Integer): Integer;',
    'var',
    'Y: Integer;',
    'procedure Inner;',
    'begin',
    'Y := X;',
    'end;',
    'begin',
    'Inner;',
    'Result := Y * 2;',
    'end;',
    'procedure TFoo.Run;',
    'begin',
    'end;',
    'initialization',
    'Init;',
    'finalization',
    'Done;',
    'end.']), J([
    'unit u;',
    'interface',
    'uses',
    '  Classes;',
    'type',
    '  TFoo = class(TObject)',
    '  private',
    '    FX: Integer;',
    '  public',
    '    procedure Run; virtual;',
    '    property X: Integer read FX;',
    '  end;',
    '  TBar = class;',
    '  TErr = class(Exception);',
    '  TRec = record',
    '    case Integer of',
    '      0: (A: Integer);',
    '      1: (B: Byte);',
    '  end;',
    '  TProc = procedure(X: Integer) of object;',
    'const',
    '  Max = 10;',
    'function Twice(X: Integer): Integer;',
    'implementation',
    'function Twice(X: Integer): Integer;',
    'var',
    '  Y: Integer;',
    '  procedure Inner;',
    '  begin',
    '    Y := X;',
    '  end;',
    'begin',
    '  Inner;',
    '  Result := Y * 2;',
    'end;',
    'procedure TFoo.Run;',
    'begin',
    'end;',
    'initialization',
    '  Init;',
    'finalization',
    '  Done;',
    'end.']));

  Expect('external and forward have no body', J([
    'unit u;',
    'interface',
    'implementation',
    'function getenv(Name: PChar): PChar;',
    'cdecl; external ''c'';',
    'procedure Later; forward;',
    'procedure Now;',
    'begin',
    'Later;',
    'end;',
    'procedure Later;',
    'begin',
    'end;',
    'end.']), J([
    'unit u;',
    'interface',
    'implementation',
    'function getenv(Name: PChar): PChar;',
    '  cdecl; external ''c'';',
    'procedure Later; forward;',
    'procedure Now;',
    'begin',
    '  Later;',
    'end;',
    'procedure Later;',
    'begin',
    'end;',
    'end.']));

  Expect('continuation lines keep their shape', J([
    'begin',
    '      X := Foo(A,',
    '               B) +',
    '        C;',
    '      if A and',
    '         B then',
    '        Go;',
    'end.']), J([
    'begin',
    '  X := Foo(A,',
    '           B) +',
    '    C;',
    '  if A and',
    '     B then',
    '    Go;',
    'end.']));

  Expect('keywords and spacing', J([
    'BEGIN',
    '  X:=1 ;',
    '  F(A,B ,C);',
    '  Y   := 2;    // lined up',
    '  if A then ; ',
    'End.']), J([
    'begin',
    '  X := 1;',
    '  F(A, B, C);',
    '  Y   := 2;    // lined up',
    '  if A then ;',
    'end.']));

  Expect('strings and comments are not touched', J([
    'begin',
    'S := ''a,b ;c:=d'';  { x:=1 , y }',
    'end.']), J([
    'begin',
    '  S := ''a,b ;c:=d'';  { x:=1 , y }',
    'end.']));

  Expect('comments over several lines move with the code', J([
    'begin',
    '{ first',
    '  second }',
    'X;',
    'end.']), J([
    'begin',
    '  { first',
    '    second }',
    '  X;',
    'end.']));

  Expect('nested comments', J([
    'begin',
    '{ a { b } c }',
    'X;',
    'end.']), J([
    'begin',
    '  { a { b } c }',
    '  X;',
    'end.']));

  Expect('blank lines', J([
    '',
    'program t;',
    '',
    '',
    '',
    'begin   ',
    #9'X;',
    'end.',
    '',
    '']), J([
    'program t;',
    '',
    'begin',
    '  X;',
    'end.']));

  Expect('fmt off', J([
    'begin',
    '// fmt: off',
    '  M := [1, 0,',
    '        0, 1];',
    '// fmt: on',
    'X;',
    'end.']), J([
    'begin',
    '  // fmt: off',
    '  M := [1, 0,',
    '        0, 1];',
    '// fmt: on',
    '  X;',
    'end.']));

  Expect('asm is kept', J([
    'procedure P; assembler;',
    'asm',
    '      mov eax, 1',
    '  nop',
    'end;',
    'begin',
    'end.']), J([
    'procedure P; assembler;',
    'asm',
    '      mov eax, 1',
    '  nop',
    'end;',
    'begin',
    'end.']));

  Expect('conditional compilation', J([
    'begin',
    '{$IFDEF WINDOWS}',
    'for E in Exts do',
    '{$ELSE}',
    'E := '''';',
    '{$ENDIF}',
    'if Ok(E) then',
    'Exit;',
    'end.']), J([
    'begin',
    '  {$IFDEF WINDOWS}',
    '  for E in Exts do',
    '  {$ELSE}',
    '  E := '''';',
    '  {$ENDIF}',
    '    if Ok(E) then',
    '      Exit;',
    'end.']));

  Expect('comment above a routine lines up with it', J([
    'unit u;',
    'interface',
    'var',
    '  A: Integer;',
    '{ about B }',
    'procedure B;',
    'implementation',
    'procedure B;',
    'begin',
    'end;',
    'end.']), J([
    'unit u;',
    'interface',
    'var',
    '  A: Integer;',
    '{ about B }',
    'procedure B;',
    'implementation',
    'procedure B;',
    'begin',
    'end;',
    'end.']));

  Expect('windows line endings stay', 'begin'#13#10'X;'#13#10'end.'#13#10,
    'begin'#13#10'  X;'#13#10'end.'#13#10);

  ExpectError('missing end', J(['begin', 'if A then begin', 'X;', 'end.']), 'no matching "end"');
  ExpectError('extra end', J(['begin', 'X;', 'end;', 'end;', 'end.']), 'without a matching');
  ExpectError('open string', J(['begin', 'S := ''abc;', 'end.']), 'string is not closed');
  ExpectError('open comment', J(['begin', '{ abc', 'end.']), 'comment is not closed');

  WriteLn(Format('format: %d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
