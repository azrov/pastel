{ Pastel - tools that look at .pform files without running the app:
  "pastel check" (validation), "pastel schema" (what controls and properties
  exist, for editors) and "pastel preview" (render a form to a PNG).
  They use the framework's own controls and RTTI, so they always agree with
  what the app will do at run time.
  Part of the Pastel project, MIT License. }
unit Pastel.Inspect;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TIssue = record
    FileName: string;
    Line: Integer;
    Severity: string;     { error, warning }
    Message: string;
  end;
  TIssues = array of TIssue;

{ Checks one .pform text. FileName is used to find the form's .pas file
  (same folder and name) for event handler checks. }
function CheckFormText(const FileName, Text: string): TIssues;
{ Checks every .pform under Root/src; paths in the result are relative. }
function CheckProject(const Root: string): TIssues;
procedure PrintIssues(const Issues: TIssues; AsJson: Boolean);

function SchemaJson: string;

{ Renders a form to a PNG. Returns '' or an error in compiler style.
  If LayoutFile is given, the position of every control is written there
  as JSON (used by the visual designer). }
function PreviewForm(const FileName, Text, OutFile, LayoutFile: string;
  AWidth, AHeight: Integer): string;

function JsonStr(const S: string): string;

implementation

uses
  TypInfo, Pastel.Console, Pastel.PForm, Pastel.UI, Pastel.Forms, Pastel.Graphics, Pastel.Controls,
  Pastel.Icons, Pastel.Project, Pastel.Builder;

function JsonStr(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
    else
      if C < ' ' then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

procedure AddIssue(var Issues: TIssues; const FileName: string; Line: Integer;
  const Severity, Msg: string);
begin
  SetLength(Issues, Length(Issues) + 1);
  Issues[High(Issues)].FileName := FileName;
  Issues[High(Issues)].Line := Line;
  Issues[High(Issues)].Severity := Severity;
  Issues[High(Issues)].Message := Msg;
end;

function StripLinePrefix(const Msg: string): string;
begin
  if Copy(Msg, 1, 5) = 'line ' then
    Result := Copy(Msg, Pos(': ', Msg) + 2, MaxInt)
  else
    Result := Msg;
end;

{ Names of all procedures declared in a Pascal file. Simple on purpose:
  it only needs to find event handlers like "procedure SendClick(". }
function DeclaredProcedures(const PasFile: string): TStringList;
var
  Src: TStringList;
  Line, Lower, Name: string;
  I, P: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.CaseSensitive := False;
  Result.Duplicates := dupIgnore;
  if not FileExists(PasFile) then
    Exit;
  Src := TStringList.Create;
  try
    Src.LoadFromFile(PasFile);
    for I := 0 to Src.Count - 1 do
    begin
      Line := Trim(Src[I]);
      Lower := LowerCase(Line);
      if Copy(Lower, 1, 10) <> 'procedure ' then
        Continue;
      Name := Trim(Copy(Line, 11, MaxInt));
      P := 1;
      while (P <= Length(Name)) and (Name[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
        Inc(P);
      Name := Copy(Name, 1, P - 1);
      if Pos('.', Name) > 0 then
        Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
      if Name <> '' then
        Result.Add(Name);
    end;
  finally
    Src.Free;
  end;
end;

type
  TEventCheck = record
    Handlers: TStringList;
    PasFile, FileName: string;
    Issues: ^TIssues;
  end;
  PEventCheck = ^TEventCheck;

{ Parameter list of an event handler, e.g. '(Sender: TObject)'. }
function EventSignature(T: PTypeInfo): string;
begin
  case T^.Name of
    'TCloseQueryEvent': Result := '(Sender: TObject; var CanClose: Boolean)';
  else
    Result := '(Sender: TObject)';
  end;
end;

procedure CheckNodeEvents(Node: TPFormNode; Cls: TClass; Data: Pointer);
var
  E: PEventCheck;
  I: Integer;
  P: TPFormProp;
  PI: PPropInfo;
begin
  E := PEventCheck(Data);
  if Cls = nil then
    Exit;
  for I := 0 to Node.Props.Count - 1 do
  begin
    P := Node.Prop(I);
    PI := GetPropInfo(Cls, P.Name);
    if (PI = nil) or (PI^.PropType^.Kind <> tkMethod) or (P.Kind <> pvIdent) then
      Continue;
    if E^.Handlers.IndexOf(P.Value) < 0 then
      AddIssue(E^.Issues^, E^.FileName, P.Line, 'error',
        Format('event handler "%s" is not declared in %s; add: procedure %s%s;',
          [P.Value, ExtractFileName(E^.PasFile), P.Value, EventSignature(PI^.PropType)]));
  end;
end;

procedure VisitEvents(Node: TPFormNode; Data: Pointer);
begin
  CheckNodeEvents(Node, FindControlClass(Node.ClassName_), Data);
end;

type
  TLineSearch = record
    Name: string;
    Line: Integer;
  end;
  PLineSearch = ^TLineSearch;

procedure FindLine(Node: TPFormNode; Data: Pointer);
begin
  if SameText(Node.Name, PLineSearch(Data)^.Name) then
    PLineSearch(Data)^.Line := Node.Line;
end;

{ Lays the form out at its size (every page of its tab controls) and reports
  rows whose controls do not fit: the last ones would be cut off. }
procedure CheckLayout(Form: TForm; Root: TPFormNode; const FileName: string; var Issues: TIssues);
var
  Warnings: TStringList;
  Tabs: TFPList;
  I, J, K, W, H, Needed, Avail: Integer;
  S: TLineSearch;
  Parts: TStringArray;

  procedure FindTabs(C: TControl);
  var
    N: Integer;
  begin
    if C is TTabControl then
      Tabs.Add(C);
    for N := 0 to C.ChildCount - 1 do
      FindTabs(C.Children[N]);
  end;

begin
  if InitFonts <> '' then
    Exit;     { no fonts here: sizes of texts are unknown }
  W := Form.Width;
  H := Form.Height;
  if W <= 0 then W := 480;
  if H <= 0 then H := 360;
  Warnings := TStringList.Create;
  Warnings.Sorted := True;
  Warnings.Duplicates := dupIgnore;
  Tabs := TFPList.Create;
  LayoutWarnings := Warnings;
  try
    FindTabs(Form);
    Form.Layout(W, H);
    for I := 0 to Tabs.Count - 1 do
      for J := 0 to TTabControl(Tabs[I]).ChildCount - 1 do
        if TTabControl(Tabs[I]).Children[J] is TTabSheet then
        begin
          TTabControl(Tabs[I]).TabIndex := J;
          Form.Layout(W, H);
        end;
    for K := 0 to Warnings.Count - 1 do
    begin
      S.Name := Warnings.Names[K];
      S.Line := Root.Line;
      VisitPForm(Root, @FindLine, @S);
      Parts := Warnings.ValueFromIndex[K].Split([',']);
      Needed := StrToIntDef(Parts[0], 0);
      Avail := StrToIntDef(Parts[1], 0);
      AddIssue(Issues, FileName, S.Line, 'warning',
        Format('%s: its controls need %d pixels but there are %d at the form''s size (%dx%d); the last ones are cut off. ' +
        'Give it more room, shorter texts, Grow = 1 on a control that may get narrower, or put the controls in two rows',
        [S.Name, Needed, Avail, W, H]));
    end;
  finally
    LayoutWarnings := nil;
    Tabs.Free;
    Warnings.Free;
  end;
end;

function CheckFormText(const FileName, Text: string): TIssues;
var
  Root: TPFormNode;
  Form: TForm;
  E: TEventCheck;
  Built: Boolean;
begin
  Result := nil;
  try
    Root := ParsePForm(Text);
  except
    on Ex: EPFormError do
    begin
      AddIssue(Result, FileName, Ex.Line, 'error', StripLinePrefix(Ex.Message));
      Exit;
    end;
  end;
  try
    if (Length(Root.ClassName_) < 2) or (UpCase(Root.ClassName_[1]) <> 'T') then
      AddIssue(Result, FileName, Root.Line, 'error',
        Format('the form type should start with T, like T%s', [Root.ClassName_]));
    StrictEvents := False;
    Form := TForm.Create(nil);
    try
      Built := False;
      try
        BuildForm(Form, Root);
        Built := True;
      except
        on Ex: EPFormError do
          AddIssue(Result, FileName, Ex.Line, 'error', StripLinePrefix(Ex.Message));
        on Ex: Exception do
          AddIssue(Result, FileName, Root.Line, 'error', Ex.Message);
      end;
      if Built then
        CheckLayout(Form, Root, FileName, Result);
    finally
      Form.Free;
      StrictEvents := True;
    end;
    { event handlers must exist in the form's code }
    E.PasFile := ChangeFileExt(FileName, '.pas');
    if FileExists(E.PasFile) then
    begin
      E.Handlers := DeclaredProcedures(E.PasFile);
      try
        E.FileName := FileName;
        E.Issues := @Result;
        CheckNodeEvents(Root, TForm, @E);
        VisitPForm(Root, @VisitEvents, @E);
      finally
        E.Handlers.Free;
      end;
    end;
  finally
    Root.Free;
  end;
end;

procedure FindPForms(const Root, Rel: string; List: TStrings);
var
  SR: TSearchRec;
begin
  if FindFirst(Root + Rel + PathDelim + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        FindPForms(Root, Rel + PathDelim + SR.Name, List)
      else if LowerCase(ExtractFileExt(SR.Name)) = '.pform' then
        List.Add(Rel + PathDelim + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function CheckProject(const Root: string): TIssues;
var
  Files, Src: TStringList;
  Rel: string;
  One: TIssues;
  I: Integer;
begin
  Result := nil;
  Files := TStringList.Create;
  Src := TStringList.Create;
  try
    FindPForms(Root, 'src', Files);
    Files.Sort;
    for Rel in Files do
    begin
      Src.LoadFromFile(Root + Rel);
      One := CheckFormText(Root + Rel, Src.Text);
      for I := 0 to High(One) do
      begin
        One[I].FileName := Rel;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := One[I];
      end;
    end;
  finally
    Files.Free;
    Src.Free;
  end;
end;

procedure PrintIssues(const Issues: TIssues; AsJson: Boolean);
var
  I: Integer;
  Line: string;
begin
  if AsJson then
  begin
    Write('[');
    for I := 0 to High(Issues) do
    begin
      if I > 0 then
        Write(',');
      Write(Format('{"file":%s,"line":%d,"severity":%s,"message":%s}',
        [JsonStr(Issues[I].FileName), Issues[I].Line, JsonStr(Issues[I].Severity),
         JsonStr(Issues[I].Message)]));
    end;
    WriteLn(']');
    Exit;
  end;
  for I := 0 to High(Issues) do
  begin
    if Issues[I].Severity = 'error' then
      Line := Format('%s(%d) Error: %s', [Issues[I].FileName, Issues[I].Line, Issues[I].Message])
    else
      Line := Format('%s(%d) Warning: %s', [Issues[I].FileName, Issues[I].Line, Issues[I].Message]);
    if Issues[I].Severity = 'error' then
      WriteLn(Red(Line))
    else
      WriteLn(Yellow(Line));
  end;
end;

{ ---- schema ---- }

function Describe(const ClassName, Prop: string): string;
begin
  case Prop of
    'Width': Result := 'Fixed width in pixels. 0 = as wide as the content.';
    'Height': Result := 'Fixed height in pixels. 0 = as tall as the content.';
    'Grow': Result := 'Share of the free space in a row or column (0 = none).';
    'Visible': Result := 'Shows or hides the control.';
    'Enabled': Result := 'False makes the control grey and ignores input.';
    'Gap': Result := 'Space between children, in pixels.';
    'Padding': Result := 'Space inside the edges, in pixels.';
    'Align': Result := 'Position of children across the stacking direction.';
    'Justify': Result := 'Position of children along the stacking direction.';
    'Color':
      if (ClassName = 'TLabel') then
        Result := 'Text color, like ''#4F46E5''.'
      else
        Result := 'Background color, like ''#FFFFFF''.';
    'BorderColor': Result := 'Border color, like ''#D9DCE3''.';
    'BorderWidth': Result := 'Border thickness in pixels.';
    'Radius': Result := 'Corner rounding in pixels.';
    'Text': Result := 'The text shown.';
    'FontSize': Result := 'Text size in pixels.';
    'Bold': Result := 'Bold text.';
    'TextAlign': Result := 'Horizontal text position.';
    'Style': Result := 'Look of the button.';
    'Placeholder': Result := 'Grey hint shown while the edit is empty.';
    'Title': Result := 'Window title.';
    'OnClick': Result := 'Runs when the button is clicked or pressed with Enter/Space.';
    'OnChange': Result := 'Runs whenever the text changes.';
    'OnSubmit': Result := 'Runs when Enter is pressed in the edit.';
    'OnCreate': Result := 'Runs after the form is created (and after each hot reload).';
    'OnCloseQuery': Result := 'Runs when the window is about to close. Set CanClose := False to keep it open.';
    'OnClose': Result := 'Runs when the window closes.';
    'OnResize': Result := 'Runs after the window size changed.';
    'Resizable': Result := 'Can the user resize and maximize the window?';
    'MinWidth': Result := 'Smallest window width the user can resize to.';
    'MinHeight': Result := 'Smallest window height the user can resize to.';
    'WindowState': Result := 'Normal, Maximized, Minimized or FullScreen. Can also be changed from code.';
    'AlwaysOnTop': Result := 'Keeps the window above other windows.';
  else
    Result := '';
  end;
end;

function ShortEnumName(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in ['a'..'z']) do
    Inc(I);
  if I <= Length(S) then
    Result := Copy(S, I, MaxInt)
  else
    Result := S;
end;

function ClassJson(Cls: TClass; IsForm: Boolean): string;
var
  Props: PPropList;
  Count, I, V: Integer;
  T: PTypeInfo;
  Kind, Extra, Items: string;
  Names: TStringList;
  First: Boolean;
begin
  Count := GetPropList(Cls.ClassInfo, Props);
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Items := '';
    for I := 0 to Count - 1 do
    begin
      if Props^[I]^.SetProc = nil then
        Continue;
      if (Props^[I]^.Name = 'Name') or (Props^[I]^.Name = 'Tag') then
        Continue;
      T := Props^[I]^.PropType;
      Extra := '';
      case T^.Kind of
        tkInteger, tkInt64, tkQWord:
          if T^.Name = 'TColor32' then Kind := 'color' else Kind := 'integer';
        tkBool: Kind := 'boolean';
        tkEnumeration:
          begin
            Kind := 'enum';
            Extra := ',"values":[';
            for V := GetTypeData(T)^.MinValue to GetTypeData(T)^.MaxValue do
            begin
              if V > GetTypeData(T)^.MinValue then
                Extra := Extra + ',';
              Extra := Extra + JsonStr(ShortEnumName(GetEnumName(T, V)));
            end;
            Extra := Extra + ']';
          end;
        tkSString, tkLString, tkAString, tkUString, tkWString:
          begin
            Kind := 'string';
            if Props^[I]^.Name = 'Icon' then
            begin
              { the designer offers the icon names }
              Extra := ',"suggest":[';
              for V := 0 to High(IconNames) do
              begin
                if V > 0 then
                  Extra := Extra + ',';
                Extra := Extra + JsonStr(IconNames[V]);
              end;
              Extra := Extra + ']';
            end;
          end;
        tkFloat: Kind := 'number';
        tkSet:
          begin
            { Anchors = [Left, Top] }
            Kind := 'set';
            Extra := ',"values":[';
            with GetTypeData(GetTypeData(T)^.CompType)^ do
              for V := MinValue to MaxValue do
              begin
                if V > MinValue then
                  Extra := Extra + ',';
                Extra := Extra + JsonStr(ShortEnumName(GetEnumName(GetTypeData(T)^.CompType, V)));
              end;
            Extra := Extra + ']';
            if Props^[I]^.Default <> LongInt($80000000) then
            begin
              Extra := Extra + ',"default":"';
              First := True;
              with GetTypeData(GetTypeData(T)^.CompType)^ do
                for V := MinValue to MaxValue do
                  if (Props^[I]^.Default and (1 shl V)) <> 0 then
                  begin
                    if not First then
                      Extra := Extra + ', ';
                    Extra := Extra + ShortEnumName(GetEnumName(GetTypeData(T)^.CompType, V));
                    First := False;
                  end;
              Extra := Extra + '"';
            end;
          end;
        tkMethod:
          begin
            Kind := 'event';
            Extra := ',"signature":' + JsonStr(EventSignature(T));
          end;
      else
        Continue;
      end;
      { the value it has when the .pform does not set it }
      if (T^.Kind in [tkInteger, tkBool, tkEnumeration]) and (Props^[I]^.Default <> LongInt($80000000)) then
        case T^.Kind of
          tkBool: Extra := Extra + ',"default":' + JsonStr(BoolToStr(Props^[I]^.Default <> 0, 'True', 'False'));
          tkEnumeration: Extra := Extra + ',"default":' + JsonStr(ShortEnumName(GetEnumName(T, Props^[I]^.Default)));
        else
          if T^.Name <> 'TColor32' then
            Extra := Extra + ',"default":' + JsonStr(IntToStr(Props^[I]^.Default));
        end;
      Names.Add(Format('{"name":%s,"type":%s%s,"doc":%s}',
        [JsonStr(Props^[I]^.Name), JsonStr(Kind), Extra,
         JsonStr(Describe(Cls.ClassName, Props^[I]^.Name))]));
    end;
    for I := 0 to Names.Count - 1 do
    begin
      if I > 0 then Items := Items + ',';
      Items := Items + Names[I];
    end;
  finally
    Names.Free;
    FreeMem(Props);
  end;
  Result := Format('{"name":%s,"container":%s,"form":%s,"nonvisual":%s,"project":%s,"properties":[%s]}',
    [JsonStr(Cls.ClassName), BoolToStr(Cls.InheritsFrom(TBox), 'true', 'false'),
     BoolToStr(IsForm, 'true', 'false'),
     { a component without a place on the form (TTimer, TAction...) }
     BoolToStr(not Cls.InheritsFrom(TControl), 'true', 'false'),
     { a control of the project (src/controls/), not of the framework }
     BoolToStr(not SameText(Copy(Cls.UnitName, 1, 7), 'Pastel.'), 'true', 'false'), Items]);
end;

function SchemaJson: string;
var
  I: Integer;
begin
  Result := '{"version":' + JsonStr(PastelVersion) + ',"frameworkDir":' + JsonStr(FrameworkDir) +
    ',"fpcSourceDir":' + JsonStr(FpcSourceDir) +
    ',"form":' + ClassJson(TForm, True) +
    ',"controls":[';
  for I := 0 to ControlClassCount - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + ClassJson(ControlClassAt(I), False);
  end;
  for I := 0 to NonVisualClassCount - 1 do
    Result := Result + ',' + ClassJson(NonVisualClassAt(I), False);
  Result := Result + ']}';
end;

{ ---- preview ---- }

function ControlJson(C: TControl; const AName, ParentName: string): string;
var
  Container, Row: Boolean;
begin
  Container := C is TBox;
  Row := Container and TBox(C).Horizontal;
  Result := Format('{"name":%s,"class":%s,"parent":%s,"x":%d,"y":%d,"w":%d,"h":%d,' +
    '"container":%s,"row":%s,"free":%s,"visible":%s,"dock":%s}',
    [JsonStr(AName), JsonStr(C.ClassName), JsonStr(ParentName), C.Bounds.X, C.Bounds.Y,
     C.Bounds.W, C.Bounds.H, BoolToStr(Container, 'true', 'false'),
     BoolToStr(Row, 'true', 'false'), BoolToStr(Container and (TBox(C).Layout = lkFree), 'true', 'false'),
     BoolToStr(C.Visible, 'true', 'false'), BoolToStr(C.Dock <> dkNone, 'true', 'false')]);
end;

procedure CollectLayout(C: TControl; const ParentName: string; List: TStrings);
var
  I: Integer;
begin
  for I := 0 to C.ChildCount - 1 do
  begin
    List.Add(ControlJson(C.Children[I], C.Children[I].Name, ParentName));
    CollectLayout(C.Children[I], C.Children[I].Name, List);
  end;
end;

function PreviewForm(const FileName, Text, OutFile, LayoutFile: string;
  AWidth, AHeight: Integer): string;
var
  Items: TStringList;
  Json: string;
  I: Integer;
  F: TFileStream;
  Root: TPFormNode;
  Form: TForm;
  Canvas: TCanvas32;
  W, H: Integer;
begin
  Result := InitFonts;
  if Result <> '' then
    Exit;
  try
    Root := ParsePForm(Text);
  except
    on E: EPFormError do
      Exit(Format('%s(%d) Error: %s', [FileName, E.Line, StripLinePrefix(E.Message)]));
  end;
  StrictEvents := False;
  Form := TForm.Create(nil);
  Canvas := TCanvas32.Create;
  try
    try
      BuildForm(Form, Root);
    except
      on E: EPFormError do
        Exit(Format('%s(%d) Error: %s', [FileName, E.Line, StripLinePrefix(E.Message)]));
      on E: Exception do
        Exit(Format('%s(%d) Error: %s', [FileName, Root.Line, E.Message]));
    end;
    W := AWidth;
    H := AHeight;
    if W <= 0 then W := Form.Width;
    if H <= 0 then H := Form.Height;
    if W <= 0 then W := 480;
    if H <= 0 then H := 360;
    Canvas.SetSize(W, H);
    Form.Layout(W, H);
    Form.Render(Canvas);
    Canvas.SaveToPNG(OutFile);
    if LayoutFile <> '' then
    begin
      Items := TStringList.Create;
      try
        Items.Add(ControlJson(Form, Root.Name, ''));
        CollectLayout(Form, Root.Name, Items);
        Json := Format('{"width":%d,"height":%d,"controls":[', [W, H]);
        for I := 0 to Items.Count - 1 do
        begin
          if I > 0 then Json := Json + ',';
          Json := Json + Items[I];
        end;
        Json := Json + ']}';
        F := TFileStream.Create(LayoutFile, fmCreate);
        try
          F.WriteBuffer(Json[1], Length(Json));
        finally
          F.Free;
        end;
      finally
        Items.Free;
      end;
    end;
    Result := '';
  finally
    StrictEvents := True;
    Canvas.Free;
    Form.Free;
    Root.Free;
  end;
end;

end.
