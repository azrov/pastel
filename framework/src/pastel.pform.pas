{ Pastel - reader for .pform files.

  A .pform file describes a form as a tree of objects, like Delphi's .dfm:

    object MainForm: TMainForm
      Title = 'Hello'
      object SendButton: TButton
        Text = 'Send'
        OnClick = SendClick
      end
    end

  Values are 'strings' (with '' for a quote), numbers, or identifiers
  (True/False, enum values, event handler names). Comments: // and braces.
  Used both by the pastel tool (code generation) and by apps (loading).
  Part of the Pastel project, MIT License. }
unit Pastel.PForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  EPFormError = class(Exception)
  public
    Line: Integer;
    constructor CreateAt(ALine: Integer; const Msg: string);
  end;

  TPFormValueKind = (pvString, pvNumber, pvIdent);

  TPFormProp = class
  public
    Name: string;
    Kind: TPFormValueKind;
    Value: string;
    Line: Integer;
  end;

  TPFormNode = class
  public
    Name: string;
    ClassName_: string;
    Line: Integer;
    Props: TFPList;      { of TPFormProp }
    Children: TFPList;   { of TPFormNode }
    constructor Create;
    destructor Destroy; override;
    function Prop(Index: Integer): TPFormProp;
    function Child(Index: Integer): TPFormNode;
    function FindProp(const AName: string): TPFormProp;
  end;

{ Parses a .pform source. Raises EPFormError with a line number on errors. }
function ParsePForm(const Src: string): TPFormNode;
function ParsePFormFile(const FileName: string): TPFormNode;

{ Calls Proc for every object below Root (not Root itself), depth first. }
type
  TPFormVisitor = procedure(Node: TPFormNode; Data: Pointer);
procedure VisitPForm(Root: TPFormNode; Proc: TPFormVisitor; Data: Pointer);

implementation

constructor EPFormError.CreateAt(ALine: Integer; const Msg: string);
begin
  inherited CreateFmt('line %d: %s', [ALine, Msg]);
  Line := ALine;
end;

constructor TPFormNode.Create;
begin
  inherited Create;
  Props := TFPList.Create;
  Children := TFPList.Create;
end;

destructor TPFormNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to Props.Count - 1 do
    TPFormProp(Props[I]).Free;
  for I := 0 to Children.Count - 1 do
    TPFormNode(Children[I]).Free;
  Props.Free;
  Children.Free;
  inherited Destroy;
end;

function TPFormNode.Prop(Index: Integer): TPFormProp;
begin
  Result := TPFormProp(Props[Index]);
end;

function TPFormNode.Child(Index: Integer): TPFormNode;
begin
  Result := TPFormNode(Children[Index]);
end;

function TPFormNode.FindProp(const AName: string): TPFormProp;
var
  I: Integer;
begin
  for I := 0 to Props.Count - 1 do
    if SameText(Prop(I).Name, AName) then
      Exit(Prop(I));
  Result := nil;
end;

type
  TTokKind = (tkEOF, tkIdent, tkString, tkNumber, tkSymbol);

  TLexer = record
    Src: string;
    P, Line: Integer;
    Kind: TTokKind;
    Text: string;
    TokLine: Integer;
  end;

procedure LexError(var L: TLexer; const Msg: string);
begin
  raise EPFormError.CreateAt(L.TokLine, Msg);
end;

procedure NextToken(var L: TLexer);
var
  C: Char;
  Start: Integer;
begin
  { skip spaces and comments }
  repeat
    while (L.P <= Length(L.Src)) and (L.Src[L.P] in [' ', #9, #10, #13]) do
    begin
      if L.Src[L.P] = #10 then
        Inc(L.Line);
      Inc(L.P);
    end;
    if (L.P < Length(L.Src)) and (L.Src[L.P] = '/') and (L.Src[L.P + 1] = '/') then
    begin
      while (L.P <= Length(L.Src)) and (L.Src[L.P] <> #10) do
        Inc(L.P);
      Continue;
    end;
    if (L.P <= Length(L.Src)) and (L.Src[L.P] = '{') then
    begin
      while (L.P <= Length(L.Src)) and (L.Src[L.P] <> '}') do
      begin
        if L.Src[L.P] = #10 then
          Inc(L.Line);
        Inc(L.P);
      end;
      Inc(L.P);
      Continue;
    end;
    Break;
  until False;

  L.TokLine := L.Line;
  L.Text := '';
  if L.P > Length(L.Src) then
  begin
    L.Kind := tkEOF;
    Exit;
  end;
  C := L.Src[L.P];
  case C of
    'A'..'Z', 'a'..'z', '_':
      begin
        Start := L.P;
        while (L.P <= Length(L.Src)) and (L.Src[L.P] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
          Inc(L.P);
        L.Kind := tkIdent;
        L.Text := Copy(L.Src, Start, L.P - Start);
      end;
    '0'..'9', '-':
      begin
        Start := L.P;
        Inc(L.P);
        while (L.P <= Length(L.Src)) and (L.Src[L.P] in ['0'..'9', '.']) do
          Inc(L.P);
        L.Kind := tkNumber;
        L.Text := Copy(L.Src, Start, L.P - Start);
        if L.Text = '-' then
          LexError(L, 'expected a number after "-"');
      end;
    '''':
      begin
        L.Kind := tkString;
        Inc(L.P);
        repeat
          if (L.P > Length(L.Src)) or (L.Src[L.P] in [#10, #13]) then
            LexError(L, 'unterminated string (strings use single quotes: ''text'')');
          if L.Src[L.P] = '''' then
          begin
            if (L.P < Length(L.Src)) and (L.Src[L.P + 1] = '''') then
            begin
              L.Text := L.Text + '''';
              Inc(L.P, 2);
              Continue;
            end;
            Inc(L.P);
            Break;
          end;
          L.Text := L.Text + L.Src[L.P];
          Inc(L.P);
        until False;
      end;
    ':', '=', '.':
      begin
        L.Kind := tkSymbol;
        L.Text := C;
        Inc(L.P);
      end;
    '"':
      LexError(L, 'strings use single quotes: ''text''');
  else
    LexError(L, 'unexpected character "' + C + '"');
  end;
end;

function Describe(const L: TLexer): string;
begin
  case L.Kind of
    tkEOF: Result := 'end of file';
    tkString: Result := 'string ''' + L.Text + '''';
  else
    Result := '"' + L.Text + '"';
  end;
end;

function ParseObject(var L: TLexer): TPFormNode;
var
  Node: TPFormNode;
  Prop: TPFormProp;
  PropName: string;
  PropLine: Integer;
begin
  { current token is "object" }
  Node := TPFormNode.Create;
  try
    Node.Line := L.TokLine;
    NextToken(L);
    if L.Kind <> tkIdent then
      LexError(L, 'expected a name after "object", found ' + Describe(L));
    Node.Name := L.Text;
    NextToken(L);
    if (L.Kind <> tkSymbol) or (L.Text <> ':') then
      LexError(L, 'expected ":" after "object ' + Node.Name + '"');
    NextToken(L);
    if L.Kind <> tkIdent then
      LexError(L, 'expected a type like TButton after "' + Node.Name + ':"');
    Node.ClassName_ := L.Text;
    NextToken(L);

    repeat
      if L.Kind = tkEOF then
        raise EPFormError.CreateAt(Node.Line, 'object ' + Node.Name + ' has no "end"');
      if L.Kind <> tkIdent then
        LexError(L, 'expected a property, "object" or "end", found ' + Describe(L));
      if SameText(L.Text, 'end') then
      begin
        NextToken(L);
        Break;
      end;
      if SameText(L.Text, 'object') then
      begin
        Node.Children.Add(ParseObject(L));
        Continue;
      end;
      PropName := L.Text;
      PropLine := L.TokLine;
      NextToken(L);
      while (L.Kind = tkSymbol) and (L.Text = '.') do
      begin
        NextToken(L);
        if L.Kind <> tkIdent then
          LexError(L, 'expected a name after "."');
        PropName := PropName + '.' + L.Text;
        NextToken(L);
      end;
      if (L.Kind <> tkSymbol) or (L.Text <> '=') then
        LexError(L, 'expected "=" after "' + PropName + '"');
      NextToken(L);
      Prop := TPFormProp.Create;
      Prop.Name := PropName;
      Prop.Line := PropLine;
      Prop.Value := L.Text;
      case L.Kind of
        tkString: Prop.Kind := pvString;
        tkNumber: Prop.Kind := pvNumber;
        tkIdent: Prop.Kind := pvIdent;
      else
        Prop.Free;
        LexError(L, 'expected a value for "' + PropName + '"');
      end;
      if Node.FindProp(PropName) <> nil then
      begin
        Prop.Free;
        raise EPFormError.CreateAt(PropLine, '"' + PropName + '" is set twice');
      end;
      Node.Props.Add(Prop);
      NextToken(L);
    until False;
    Result := Node;
  except
    Node.Free;
    raise;
  end;
end;

function ParsePForm(const Src: string): TPFormNode;
var
  L: TLexer;
begin
  L.Src := Src;
  L.P := 1;
  L.Line := 1;
  if Copy(Src, 1, 3) = #$EF#$BB#$BF then
    L.P := 4;
  NextToken(L);
  if (L.Kind <> tkIdent) or not SameText(L.Text, 'object') then
    LexError(L, 'a .pform file must start with "object Name: TType"');
  Result := ParseObject(L);
  if L.Kind <> tkEOF then
  begin
    Result.Free;
    LexError(L, 'unexpected ' + Describe(L) + ' after the last "end"');
  end;
end;

function ParsePFormFile(const FileName: string): TPFormNode;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(FileName);
    Result := ParsePForm(S.Text);
  finally
    S.Free;
  end;
end;

procedure VisitPForm(Root: TPFormNode; Proc: TPFormVisitor; Data: Pointer);
var
  I: Integer;
begin
  for I := 0 to Root.Children.Count - 1 do
  begin
    Proc(Root.Child(I), Data);
    VisitPForm(Root.Child(I), Proc, Data);
  end;
end;

end.
