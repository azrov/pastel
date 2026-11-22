{ What the compiler's messages mean, in plain words, and what to do: the
  most common errors and warnings of Free Pascal, for people who are
  learning. pastel build prints the explanation under the message (once per
  kind), pastel check --json gives it as "explain" (VS Code shows it under
  the error).

    Explain('Fatal: Syntax error, ";" expected but "ELSE" found')
      -> 'There is a ; before else. The statement before else ends without one: ...' }
unit Pastel.Explain;

{$mode objfpc}{$H+}

interface

{ The explanation of one compiler message (the whole line, or the text after
  "Error: "); '' when there is none. }
function ExplainCompilerMessage(const Line: string): string;

implementation

uses
  SysUtils, StrUtils;

{ the text between the N-th pair of quotes ("got", "expected"); '' when there is none }
function Quoted(const S: string; N: Integer): string;
var
  I, Q, Start: Integer;
begin
  Result := '';
  Q := 0;
  Start := 0;
  for I := 1 to Length(S) do
    if S[I] = '"' then
    begin
      Inc(Q);
      if Odd(Q) then
        Start := I + 1
      else if Q div 2 = N then
        Exit(Copy(S, Start, I - Start));
    end;
end;

function IsTextType(const T: string): Boolean;
var
  L: string;
begin
  L := LowerCase(T);
  Result := (Pos('string', L) > 0) or (L = 'char') or (L = 'widechar') or (L = 'pchar');
end;

function IsNumberType(const T: string): Boolean;
var
  L: string;
begin
  L := LowerCase(T);
  Result := (L = 'longint') or (L = 'shortint') or (L = 'smallint') or (L = 'byte') or (L = 'word') or
    (L = 'int64') or (L = 'qword') or (L = 'longword') or (L = 'cardinal') or (L = 'integer') or
    (L = 'double') or (L = 'single') or (L = 'extended') or (L = 'currency') or (L = 'real') or
    (L = 'smallint') or (L = 'nativeint');
end;

function TypesAdvice(const Got, Expected: string): string;
begin
  if IsTextType(Got) and IsNumberType(Expected) then
    Result := 'A text cannot go where a number is needed: convert it, with StrToInt, StrToFloat or ' +
      'TryStrToInt (which says when the text is not a number).'
  else if IsNumberType(Got) and IsTextType(Expected) then
    Result := 'A number cannot go where a text is needed: convert it, with IntToStr, FloatToStr or Format ' +
      '(''%d items'').'
  else if (LowerCase(Got) = 'boolean') and IsTextType(Expected) then
    Result := 'True or False cannot go where a text is needed: BoolToStr(B, ''yes'', ''no'') makes one.'
  else if (Pos('procedure', LowerCase(Got)) > 0) or (Pos('function', LowerCase(Got)) > 0) then
    Result := 'A routine is given where a value of another kind is needed. To give a method to an event, ' +
      'write @ before it: Button.OnClick := @SaveClick; its parameters must be the ones the event has.'
  else
    Result := Format('The value is a %s, but a %s is needed here. Convert it, or use a variable of the right ' +
      'type.', [Got, Expected]);
end;

function ExplainCompilerMessage(const Line: string): string;
const
  Kinds: array[0..4] of string = ('Fatal: ', 'Error: ', 'Warning: ', 'Note: ', 'Hint: ');
var
  M, Expected, Found, K: string;
  P: Integer;
begin
  Result := '';
  M := Line;
  { the text after "Error: ", "Fatal: ", "Warning: " }
  for K in Kinds do
  begin
    P := Pos(K, M);
    if P > 0 then
    begin
      M := Copy(M, P + Length(K), MaxInt);
      Break;
    end;
  end;

  if StartsText('Syntax error, ', M) then
  begin
    Expected := Quoted(M, 1);
    Found := Quoted(M, 2);
    if (Expected = ';') and (UpperCase(Found) = 'ELSE') then
      Exit('There is a ; before else. The statement before else ends without one: ' +
        'if A then X else Y;  (with begin..end: if A then begin ... end else ...).');
    if (Expected = ';') and (Found = '.') then
      Exit('Something is not closed before the final "end.": each begin (and case, try, record, class) ' +
        'needs its own end;.');
    if Expected = ';' then
      Exit('A semicolon is missing — usually at the end of the line before this one. Statements are ' +
        'separated by ;.');
    if (Expected = '.') and (Found = ';') then
      Exit('The last end of a program or unit has a full stop: end. — or there is one end; too many ' +
        'before it.');
    if Found = ':=' then
      Exit('A condition compares with = (one sign); := gives a value: if Count = 0 then ...');
    if (Expected = 'BEGIN') or (Expected = 'IMPLEMENTATION') then
      Exit(Format('The compiler expected %s here: look at the lines before — a declaration may be unfinished, ' +
        'or there is an end too many.', [Expected]));
    if Expected = ')' then
      Exit('A ) is missing, or a , between the values of a call.');
    Exit(Format('The compiler expected %s here, but found %s. Look at this line and the one before: often ' +
      'something is missing (a ), an end, a ;) or there is one too many.', [Expected, Found]));
  end;

  if StartsText('Identifier not found', M) then
    Exit(Format('%s is not known here. Check the spelling (case does not matter); declare it before the ' +
      'line that uses it (var, const, procedure); or add the unit that has it to uses.', [Quoted(M, 1)]));

  if StartsText('Incompatible types:', M) then
    Exit(TypesAdvice(Quoted(M, 1), Quoted(M, 2)));

  if StartsText('Incompatible type for arg no.', M) then
  begin
    P := Pos('.', M) + 2;
    Exit('Value ' + Trim(Copy(M, P, PosEx(':', M, P) - P)) + ' of the call is of the wrong type. ' +
      TypesAdvice(Quoted(M, 1), Quoted(M, 2)));
  end;

  if StartsText('Wrong number of parameters specified for call to', M) then
    Exit(Format('%s is called with more or fewer values than it takes (the next message shows its ' +
      'declaration). Giving a method to an event? Write @ before it: OnClick := @%s;', [Quoted(M, 1), Quoted(M, 1)]));

  if StartsText('Illegal expression', M) then
    Exit('This is not a statement. A value is given with := (Count := 5;, not Count = 5;), and a value ' +
      'or a comparison alone must be used in something: an assignment, an if, a call.');

  if StartsText('Forward declaration not solved', M) then
    Exit(Format('%s is declared (in a class, or the interface part of a unit) but its body is missing: ' +
      'write it in the implementation part. In VS Code, Ctrl+Shift+C in the class writes it for you.',
      [StringReplace(Quoted(M, 1), ';', '', [])]));

  if StartsText('Duplicate identifier', M) then
    Exit(Format('%s is declared twice in the same place. Rename one; a local variable may not have the ' +
      'name of a parameter of its routine.', [Quoted(M, 1)]));

  if StartsText('Can''t find unit', M) then
  begin
    Found := Trim(Copy(M, 17, MaxInt));
    if Pos(' ', Found) > 0 then
      Found := Copy(Found, 1, Pos(' ', Found) - 1);
    Exit(Format('No unit named %s is found. Check the spelling. A unit of the project goes in src/ (or a ' +
      'folder of [build] unit_paths); one of a library: add the library to [dependencies] in pastel.toml.',
      [Found]));
  end;

  if StartsText('Unexpected end of file', M) then
    Exit('The file ended too early: an end is missing (each begin, case, try, record and class needs one), ' +
      'or a { comment is not closed.');

  if StartsText('String exceeds line', M) then
    Exit('A text in quotes is not closed on this line: a '' is missing. A quote inside a text is written ' +
      'twice: ''It''''s done''.');

  if StartsText('Variable identifier expected', M) then
    Exit('This place needs a variable: a var or out parameter changes what it is given, so it cannot be a ' +
      'value like 5 or a constant.');

  if StartsText('method identifier expected', M) then
    Exit('This method is not in its class: add it to the class declaration (the same name and parameters), ' +
      'or fix the name here.');

  if StartsText('duplicate case label', M) then
    Exit('Two branches of this case have the same value.');

  if StartsText('overloaded functions have the same parameter list', M) then
    Exit('Two routines have the same name and the same parameters: rename one, or make their parameters ' +
      'differ.');

  if StartsText('Constant and CASE types do not match', M) then
    Exit('The values of the branches are of another type than the value case tests. case works with ' +
      'whole numbers, letters and enumerations; for texts use if ... else if.');

  if StartsText('Can''t determine which overloaded function to call', M) then
    Exit('Several routines of this name fit the values given. Make the values'' types clear (a typed ' +
      'variable, or Double(X), Integer(X)).');

  if StartsText('Abstract methods can''t be called directly', M) then
    Exit('This method has no body here (abstract): call it on a class that overrides it.');

  { warnings }
  if (Pos('does not seem to be initialized', M) > 0) and (Pos('managed type', M) > 0) then
    Exit(Format('%s starts empty, so this is usually harmless; giving it a value first makes it clear.',
      [Quoted(M, 1)]));
  if Pos('does not seem to be initialized', M) > 0 then
    Exit(Format('%s is used before it got a value: give it one first (%s := 0;). A local variable starts ' +
      'with whatever was in memory.', [Quoted(M, 1), Quoted(M, 1)]));
  if StartsText('Function result does not seem to be set', M) then
    Exit('The function can end without giving Result a value: set Result on every way through it.');
  if StartsText('Constructing a class', M) then
    Exit(Format('%s has an abstract method (no body): create a class that inherits from it and overrides ' +
      'the method, and create that one.', [Quoted(M, 1)]));
  if StartsText('range check error while evaluating constants', M) then
    Exit('The value does not fit the type (a Byte holds 0 to 255): use a bigger type, like Integer.');
  if Pos('is deprecated', M) > 0 then
    Exit('This will go away in a later version; the message (or its documentation) says what to use instead.');
  if StartsText('Unreachable code', M) then
    Exit('This code can never run (after an Exit, or in an if whose condition is always False).');
end;

end.
