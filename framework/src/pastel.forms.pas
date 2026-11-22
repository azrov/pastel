{ Pastel - building forms from .pform data.

  The code Pastel generates for each .pform file registers the form's source
  here. When a form is created, its controls are built from that source and
  properties and events are set through RTTI, like Delphi does with .dfm.
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.
  Part of the Pastel project, MIT License. }
unit Pastel.Forms;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI, Pastel.PForm;

type
  { reads a .pform file (on a phone: from the computer); False when it cannot }
  TFormFetcher = function(const FilePath: string; Lines: TStrings): Boolean;

  TFormSource = class
  public
    FormClassName: string;
    Source: string;       { .pform text compiled into the program }
    FilePath: string;     { .pform file on disk, for hot reload ('' in release) }
    { the views: Home.tablet.pform is 'tablet'; Objects: TFormSource with its text and file }
    Views: TStringList;
    destructor Destroy; override;
  end;

{ Called by generated code. }
procedure RegisterFormSource(const AFormClassName, ASource, AFilePath: string);
{ The registered source for a form, searching its class hierarchy. }
function FindFormSource(Form: TForm): TFormSource;
{ Called by generated code: a view of a form (Home.tablet.pform): property
  values for one kind of screen. View: phone, tablet, desktop or tv. }
procedure RegisterFormView(const AFormClassName, AView, ASource, AFilePath: string);
{ The view a form uses on a kind of screen ('' for none): its own, or tablet for a TV without one. }
function ViewForScreen(Form: TForm; AClass: TScreenClass): string;
{ Applies the form's view for the kind of screen: the values the view sets
  replace the form's (and come back when another kind of screen has no view). }
procedure ApplyFormView(Form: TForm; AClass: TScreenClass);
{ The texts of the form's view files on disk (hot reload watches them). }
function FormViewFilesText(Form: TForm): string;

{ What the user changed in the controls (typed text, checked boxes, chosen
  items, the page of tabs), by control name; hot reload puts it back. }
function CaptureState(Form: TForm): TStringList;
procedure RestoreState(Form: TForm; State: TStringList);
{ The form's state as one text, for a phone that stops the app in the
  background: what is in its controls, and its SaveState (after OnSaveState). }
function FormStateText(Form: TForm): string;
{ That text back into the form (its controls, its SaveState). }
procedure RestoreFormStateText(Form: TForm; const Text: string);

{ Creates the controls described by Root on Form, then binds fields.
  Raises EPFormError on problems (unknown type, property or event). }
procedure BuildForm(Form: TForm; Root: TPFormNode);
{ Hot reload of frames: reads the .pform files of the frames again (Fetch reads
  a file on a phone); True when one changed (their forms are then built again). }
function RefreshFrameSources(Fetch: TFormFetcher = nil): Boolean;

type
  { A part of forms with a .pform and code of its own, used on many forms:
    an address block, a customer card. Its .pform starts like a form's, with a
    type whose name ends in Frame:
      // Address.pform
      object AddressFrame: TAddressFrame
        object StreetEdit: TEdit
        end
      end
    and a form puts it where it wants it, as often as it wants:
      object Billing: TAddressFrame
      end
      object Shipping: TAddressFrame
      end
    Its controls are its own (Billing.StreetEdit, Shipping.StreetEdit); its
    events go to its own methods. "pastel new frame Address" makes one. }
  TFrame = class(TColumn)
  private
    FSourceClass: string;
    procedure Load;
  public
    constructor Create(AOwner: TComponent); override;
    { a frame of a type the program does not have (the designer's preview): built from that type's .pform }
    constructor CreateFor(AOwner: TComponent; const AClassName: string);
    { Called after the controls are made: the generated code fills its fields. }
    procedure BindControls; virtual;
    function BindControl(const AName: string; AClass: TControlClass): TControl;
    function BindComponent(const AName: string; AClass: TComponentClass): TComponent;
    { its type as the .pform says it (TAddressFrame) }
    function FrameClassName: string;
  end;

var
  { Internal: False skips event handlers that do not exist instead of an
    error. Used by tools that load a form without its code (preview, check). }
  StrictEvents: Boolean = True;

implementation

uses
  TypInfo, StrUtils, Pastel.Graphics, Pastel.Lang;

{ texts people read are translated (assets/lang/); names, files and colors not }
function Shown(const PropName, Value: string): string;
var
  Indent: Integer;
begin
  case LowerCase(PropName) of
    'text', 'caption', 'title', 'placeholder', 'hint', 'items':
      begin
        { tree lines keep their indentation }
        Indent := 0;
        while (Indent < Length(Value)) and (Value[Indent + 1] = ' ') do
          Inc(Indent);
        Result := Copy(Value, 1, Indent) + Translate(Copy(Value, Indent + 1, MaxInt));
      end;
  else
    Result := Value;
  end;
end;

var
  Sources: TStringList = nil;

destructor TFormSource.Destroy;
begin
  Views.Free;
  inherited Destroy;
end;

procedure RegisterFormSource(const AFormClassName, ASource, AFilePath: string);
var
  S: TFormSource;
  I: Integer;
begin
  I := Sources.IndexOf(AFormClassName);
  if I >= 0 then
    S := TFormSource(Sources.Objects[I])
  else
  begin
    S := TFormSource.Create;
    Sources.AddObject(AFormClassName, S);
  end;
  S.FormClassName := AFormClassName;
  S.Source := ASource;
  S.FilePath := AFilePath;
end;

function FindFormSource(Form: TForm): TFormSource;
var
  C: TClass;
  I: Integer;
begin
  C := Form.ClassType;
  while C <> nil do
  begin
    I := Sources.IndexOf(C.ClassName);
    if I >= 0 then
      Exit(TFormSource(Sources.Objects[I]));
    C := C.ClassParent;
  end;
  Result := nil;
end;

function EnumNames(T: PTypeInfo): string;
var
  D: PTypeData;
  I: Integer;
begin
  D := GetTypeData(T);
  Result := '';
  for I := D^.MinValue to D^.MaxValue do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + GetEnumName(T, I);
  end;
end;

{ "Center" is accepted for aiCenter: the lowercase prefix of the first
  enum value is added when the plain name does not match. }
function FindEnumValue(T: PTypeInfo; const Name: string): Integer;
var
  First, Prefix: string;
  I: Integer;
begin
  Result := GetEnumValue(T, Name);
  if Result >= 0 then
    Exit;
  First := GetEnumName(T, GetTypeData(T)^.MinValue);
  Prefix := '';
  for I := 1 to Length(First) do
    if First[I] in ['a'..'z'] then
      Prefix := Prefix + First[I]
    else
      Break;
  if Prefix <> '' then
    Result := GetEnumValue(T, Prefix + Name);
end;

type
  TPendingRef = record
    Instance: TObject;
    Info: PPropInfo;
    Name: string;
    Line: Integer;
  end;

var
  PendingRefs: array of TPendingRef;

procedure AddPendingRef(Instance: TObject; Info: PPropInfo; const AName: string; ALine: Integer);
begin
  SetLength(PendingRefs, Length(PendingRefs) + 1);
  PendingRefs[High(PendingRefs)].Instance := Instance;
  PendingRefs[High(PendingRefs)].Info := Info;
  PendingRefs[High(PendingRefs)].Name := AName;
  PendingRefs[High(PendingRefs)].Line := ALine;
end;

procedure ResolvePendingRefs(Form: TComponent);
var
  R: TPendingRef;
  C: TComponent;
  Want: TClass;
begin
  try
    for R in PendingRefs do
    begin
      C := Form.FindComponent(R.Name);
      Want := GetTypeData(R.Info^.PropType)^.ClassType;
      if C = nil then
        raise EPFormError.CreateAt(R.Line, Format('there is no component named "%s" in the form', [R.Name]));
      if not C.InheritsFrom(Want) then
        raise EPFormError.CreateAt(R.Line, Format('%s is a %s, not a %s', [R.Name, C.ClassName, Want.ClassName]));
      SetObjectProp(R.Instance, R.Info, C);
    end;
  finally
    PendingRefs := nil;
  end;
end;

procedure SetProp(Instance: TObject; Form: TComponent; P: TPFormProp);
var
  PI: PPropInfo;
  T: PTypeInfo;
  Color: TColor32;
  N: Int64;
  E, I: Integer;
  F: Double;
  M: TMethod;
  FS: TFormatSettings;
  PropName: string;
  Dot: Integer;
  Sub: TObject;
  Ref: TComponent;
  L, Names: TStringList;

  procedure Fail(const Msg: string);
  begin
    raise EPFormError.CreateAt(P.Line, Msg);
  end;

begin
  { Font.Size = 12: a property of an object property }
  PropName := P.Name;
  Dot := Pos('.', PropName);
  while Dot > 0 do
  begin
    PI := GetPropInfo(Instance, Copy(PropName, 1, Dot - 1));
    if (PI = nil) or (PI^.PropType^.Kind <> tkClass) then
      Fail(Format('%s has no object property "%s"', [Instance.ClassName, Copy(PropName, 1, Dot - 1)]));
    Sub := GetObjectProp(Instance, PI);
    if Sub = nil then
      Fail(Format('"%s" is empty', [Copy(PropName, 1, Dot - 1)]));
    Instance := Sub;
    PropName := Copy(PropName, Dot + 1, MaxInt);
    Dot := Pos('.', PropName);
  end;
  PI := GetPropInfo(Instance, PropName);
  if PI = nil then
    Fail(Format('%s has no property "%s"', [Instance.ClassName, PropName]));
  T := PI^.PropType;
  { Items = ('a', 'b'): TStrings properties are filled, not replaced }
  if (T^.Kind = tkClass) and (GetTypeData(T)^.ClassType.InheritsFrom(TStrings)) then
  begin
    if P.Kind <> pvList then
      Fail(Format('%s expects a list like (''one'', ''two'')', [P.Name]));
    L := TStringList.Create;
    try
      if P.Value <> '' then
        L.Text := StringReplace(P.Value, #10, LineEnding, [rfReplaceAll]);
      if (P.Value <> '') and (Copy(P.Value, Length(P.Value), 1) = #10) then
        L.Add('');
      for I := 0 to L.Count - 1 do
        L[I] := Shown(PropName, L[I]);
      if GetObjectProp(Instance, PI) <> nil then
        TStrings(GetObjectProp(Instance, PI)).Assign(L)
      else if PI^.SetProc <> nil then
        SetObjectProp(Instance, PI, L);
    finally
      L.Free;
    end;
    Exit;
  end;
  { PopupMenu = EditMenu: another component of the form, maybe declared later }
  if (T^.Kind = tkClass) and GetTypeData(T)^.ClassType.InheritsFrom(TComponent) then
  begin
    if P.Kind <> pvIdent then
      Fail(Format('%s expects the name of a component, like %s = EditMenu', [P.Name, P.Name]));
    Ref := Form.FindComponent(P.Value);
    if Ref = nil then
    begin
      AddPendingRef(Instance, PI, P.Value, P.Line);
      Exit;
    end;
    if not Ref.InheritsFrom(GetTypeData(T)^.ClassType) then
      Fail(Format('%s is a %s; %s needs a %s', [P.Value, Ref.ClassName, P.Name, GetTypeData(T)^.ClassType.ClassName]));
    SetObjectProp(Instance, PI, Ref);
    Exit;
  end;
  if PI^.SetProc = nil then
    Fail(Format('property "%s" is read-only', [P.Name]));
  if (P.Kind = pvList) then
    Fail(Format('%s expects one value, not a list', [P.Name]));
  if T^.Kind = tkSet then
  begin
    { Anchors = [Left, Top, Right] }
    if P.Kind <> pvSet then
      Fail(Format('%s expects a set like [%s]', [P.Name, EnumNames(GetTypeData(T)^.CompType)]));
    N := 0;
    Names := TStringList.Create;
    try
      Names.Text := P.Value;
      for I := 0 to Names.Count - 1 do
      begin
        E := FindEnumValue(GetTypeData(T)^.CompType, Trim(Names[I]));
        if E < 0 then
          Fail(Format('%s: "%s" is not one of %s', [P.Name, Names[I], EnumNames(GetTypeData(T)^.CompType)]));
        N := N or (Int64(1) shl E);
      end;
    finally
      Names.Free;
    end;
    SetOrdProp(Instance, PI, N);
    Exit;
  end;
  if P.Kind = pvSet then
    Fail(Format('%s expects one value, not a set', [P.Name]));
  case T^.Kind of
    tkInteger, tkInt64, tkQWord:
      begin
        if T^.Name = 'TColor32' then
        begin
          if (P.Kind <> pvString) or not TryParseColor(P.Value, Color) then
            Fail(Format('%s expects a color like ''#4F46E5''', [P.Name]));
          SetOrdProp(Instance, PI, Int64(Cardinal(Color)));
        end
        else
        begin
          { ModalResult = mrOk }
          if (P.Kind = pvIdent) and SameText(Copy(P.Value, 1, 2), 'mr') then
          begin
            N := -1;
            case LowerCase(P.Value) of
              'mrnone': N := 0;
              'mrok': N := 1;
              'mrcancel': N := 2;
              'mrabort': N := 3;
              'mrretry': N := 4;
              'mrignore': N := 5;
              'mryes': N := 6;
              'mrno': N := 7;
              'mrclose': N := 8;
            end;
            if N < 0 then
              Fail(Format('%s: "%s" is not one of mrOk, mrCancel, mrYes, mrNo, mrAbort, mrRetry, mrIgnore, mrClose',
                [P.Name, P.Value]));
          end
          else if (P.Kind <> pvNumber) or not TryStrToInt64(P.Value, N) then
            Fail(Format('%s expects a whole number', [P.Name]));
          SetOrdProp(Instance, PI, N);
        end;
      end;
    tkBool:
      begin
        if SameText(P.Value, 'True') and (P.Kind = pvIdent) then
          SetOrdProp(Instance, PI, 1)
        else if SameText(P.Value, 'False') and (P.Kind = pvIdent) then
          SetOrdProp(Instance, PI, 0)
        else
          Fail(Format('%s expects True or False', [P.Name]));
      end;
    tkEnumeration:
      begin
        E := -1;
        if P.Kind = pvIdent then
          E := FindEnumValue(T, P.Value);
        if E < 0 then
          Fail(Format('%s expects one of: %s', [P.Name, EnumNames(T)]));
        SetOrdProp(Instance, PI, E);
      end;
    tkSString, tkLString, tkAString:
      begin
        if P.Kind <> pvString then
          Fail(Format('%s expects text in quotes, like ''%s''', [P.Name, P.Value]));
        SetStrProp(Instance, PI, Shown(PropName, P.Value));
      end;
    tkUString, tkWString:
      begin
        if P.Kind <> pvString then
          Fail(Format('%s expects text in quotes, like ''%s''', [P.Name, P.Value]));
        SetUnicodeStrProp(Instance, PI, UTF8Decode(P.Value));
      end;
    tkFloat:
      begin
        FS := DefaultFormatSettings;
        FS.DecimalSeparator := '.';
        if (P.Kind <> pvNumber) or not TryStrToFloat(P.Value, F, FS) then
          Fail(Format('%s expects a number', [P.Name]));
        SetFloatProp(Instance, PI, F);
      end;
    tkMethod:
      begin
        if P.Kind <> pvIdent then
          Fail(Format('%s expects the name of a method, like %s = ButtonClick', [P.Name, P.Name]));
        M.Code := Form.MethodAddress(P.Value);
        if (M.Code = nil) and not StrictEvents then
          Exit;
        if M.Code = nil then
          Fail(Format('event handler "%s" was not found in %s. Add it to the form class: ' +
            'procedure %s(Sender: TObject);', [P.Value, Form.ClassName, P.Value]));
        M.Data := Form;
        SetMethodProp(Instance, PI, M);
      end;
  else
    Fail(Format('property "%s" cannot be set from a .pform file', [P.Name]));
  end;
end;

procedure SetProps(Instance: TObject; Form: TComponent; Node: TPFormNode);
var
  I: Integer;
begin
  for I := 0 to Node.Props.Count - 1 do
    SetProp(Instance, Form, Node.Prop(I));
end;

function RefreshFrameSources(Fetch: TFormFetcher): Boolean;
var
  I: Integer;
  Src: TFormSource;
  L: TStringList;
  Ok: Boolean;
begin
  Result := False;
  if Sources = nil then
    Exit;
  L := TStringList.Create;
  try
    for I := 0 to Sources.Count - 1 do
    begin
      Src := TFormSource(Sources.Objects[I]);
      if (Src.FilePath = '') or not AnsiEndsText('Frame', Src.FormClassName) then
        Continue;
      L.Clear;
      try
        if Assigned(Fetch) then
          Ok := Fetch(Src.FilePath, L)
        else
        begin
          L.LoadFromFile(Src.FilePath);
          Ok := True;
        end;
      except
        Ok := False;      { being written: next time }
      end;
      if Ok and (L.Text <> '') and (TrimRight(L.Text) <> TrimRight(Src.Source)) then
      begin
        Src.Source := L.Text;
        Result := True;
      end;
    end;
  finally
    L.Free;
  end;
end;

procedure BuildChildren(Form: TComponent; Parent: TControl; Node: TPFormNode); forward;

{ ---- frames ---- }

function FrameSourceOf(const AClassName: string): TFormSource;
var
  I: Integer;
begin
  I := Sources.IndexOf(AClassName);
  if I >= 0 then
    Result := TFormSource(Sources.Objects[I])
  else
    Result := nil;
end;

constructor TFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Load;
end;

constructor TFrame.CreateFor(AOwner: TComponent; const AClassName: string);
begin
  FSourceClass := AClassName;
  inherited Create(AOwner);
  Load;
end;

procedure TFrame.Load;
var
  C: TClass;
  Src: TFormSource;
  Root: TPFormNode;
  Saved: array of TPendingRef;
begin
  Src := nil;
  if FSourceClass <> '' then
    Src := FrameSourceOf(FSourceClass)
  else
  begin
    C := ClassType;
    while (C <> nil) and (C <> TFrame) and (Src = nil) do
    begin
      Src := FrameSourceOf(C.ClassName);
      C := C.ClassParent;
    end;
  end;
  if Src = nil then
    Exit;
  { a frame is made while its form is being built: the form's references wait }
  Saved := PendingRefs;
  PendingRefs := nil;
  Root := ParsePForm(Src.Source);
  try
    SetProps(Self, Self, Root);
    BuildChildren(Self, Self, Root);
    ResolvePendingRefs(Self);
    BindControls;
  finally
    Root.Free;
    PendingRefs := Saved;
  end;
end;

procedure TFrame.BindControls;
begin
end;

function TFrame.FrameClassName: string;
begin
  if FSourceClass <> '' then
    Result := FSourceClass
  else
    Result := ClassName;
end;

function TFrame.BindControl(const AName: string; AClass: TControlClass): TControl;
var
  C: TComponent;
begin
  C := FindComponent(AName);
  if (C = nil) or not C.InheritsFrom(AClass) then
    raise EPFormError.CreateAt(0, Format('%s has no %s named %s', [ClassName, AClass.ClassName, AName]));
  Result := TControl(C);
end;

function TFrame.BindComponent(const AName: string; AClass: TComponentClass): TComponent;
begin
  Result := FindComponent(AName);
  if (Result = nil) or not Result.InheritsFrom(AClass) then
    raise EPFormError.CreateAt(0, Format('%s has no %s named %s', [ClassName, AClass.ClassName, AName]));
end;

procedure BuildChildren(Form: TComponent; Parent: TControl; Node: TPFormNode);
var
  I: Integer;
  ChildNode: TPFormNode;
  Cls: TControlClass;
  NV: TComponentClass;
  C: TControl;
  Comp: TComponent;
begin
  for I := 0 to Node.Children.Count - 1 do
  begin
    ChildNode := Node.Child(I);
    Cls := FindControlClass(ChildNode.ClassName_);
    NV := nil;
    if Cls = nil then
      NV := FindNonVisualClass(ChildNode.ClassName_);
    { a frame the program has no type for (the designer): made from its .pform }
    if (Cls = nil) and (NV = nil) and (FrameSourceOf(ChildNode.ClassName_) <> nil) then
    begin
      if Form.FindComponent(ChildNode.Name) <> nil then
        raise EPFormError.CreateAt(ChildNode.Line, Format('the name "%s" is used twice', [ChildNode.Name]));
      C := TFrame.CreateFor(Form, ChildNode.ClassName_);
      C.Name := ChildNode.Name;
      C.Parent := Parent;
      SetProps(C, Form, ChildNode);
      Continue;
    end;
    if (Cls = nil) and (NV = nil) then
      raise EPFormError.CreateAt(ChildNode.Line,
        Format('unknown component type "%s"', [ChildNode.ClassName_]));
    if NV <> nil then
    begin
      { a component without a place on the form: TTimer... }
      if Form.FindComponent(ChildNode.Name) <> nil then
        raise EPFormError.CreateAt(ChildNode.Line, Format('the name "%s" is used twice', [ChildNode.Name]));
      Comp := NV.Create(Form);
      try
        Comp.Name := ChildNode.Name;
      except
        on E: Exception do
          raise EPFormError.CreateAt(ChildNode.Line, E.Message);
      end;
      SetProps(Comp, Form, ChildNode);
      if ChildNode.Children.Count > 0 then
        raise EPFormError.CreateAt(ChildNode.Line, Format('a %s cannot hold other objects', [ChildNode.ClassName_]));
      Continue;
    end;
    if Form.FindComponent(ChildNode.Name) <> nil then
      raise EPFormError.CreateAt(ChildNode.Line,
        Format('the name "%s" is used twice', [ChildNode.Name]));
    { the generated code makes a field of that name in the form class }
    if (GetPropInfo(TForm, ChildNode.Name) <> nil) or (TForm.MethodAddress(ChildNode.Name) <> nil) or
       SameText(ChildNode.Name, 'Name') or SameText(ChildNode.Name, 'Tag') then
      raise EPFormError.CreateAt(ChildNode.Line,
        Format('"%s" is already the name of a property of every form; call the control e.g. %s%s',
        [ChildNode.Name, ChildNode.Name, Copy(ChildNode.ClassName_, 2, MaxInt)]));
    C := Cls.Create(Form);
    try
      C.Name := ChildNode.Name;
    except
      on E: Exception do
        raise EPFormError.CreateAt(ChildNode.Line, E.Message);
    end;
    C.Parent := Parent;
    SetProps(C, Form, ChildNode);
    BuildChildren(Form, C, ChildNode);
  end;
end;

const
  StateProps: array[0..5] of string = ('Text', 'Checked', 'ItemIndex', 'Position', 'TabIndex', 'SelStart');

function KeepsState(C: TComponent; const Prop: string): Boolean;
begin
  { text the user typed, not texts the .pform sets (labels, buttons) }
  if Prop = 'Text' then
    Result := C is TCustomEdit
  else if Prop = 'SelStart' then
    Result := False
  else
    Result := IsPublishedProp(C, Prop);
end;

{ what the user did in the controls Owner owns; a frame's ones too, as Frame/Control }
procedure CaptureOf(Owner: TComponent; const Prefix: string; Into: TStringList);
var
  I: Integer;
  C: TComponent;
  P: string;
begin
  for I := 0 to Owner.ComponentCount - 1 do
  begin
    C := Owner.Components[I];
    if (C.Name = '') or not (C is TControl) then
      Continue;
    for P in StateProps do
      if KeepsState(C, P) then
        Into.Values[Prefix + C.Name + '.' + C.ClassName + '.' + P] := GetPropValue(C, P, True);
    if C is TFrame then
      CaptureOf(C, Prefix + C.Name + '/', Into);
  end;
end;

function CaptureState(Form: TForm): TStringList;
begin
  Result := TStringList.Create;
  CaptureOf(Form, '', Result);
end;

procedure RestoreState(Form: TForm; State: TStringList);
var
  I, J: Integer;
  Parts, Path: TStringArray;
  C: TComponent;
begin
  for I := 0 to State.Count - 1 do
  begin
    Parts := State.Names[I].Split(['.']);
    if Length(Parts) <> 3 then
      Continue;
    { Frame/Control: through the frame }
    Path := Parts[0].Split(['/']);
    C := Form;
    for J := 0 to High(Path) do
      if C <> nil then
        C := C.FindComponent(Path[J]);
    { only the same kind of control gets its state back }
    if (C = nil) or (C.ClassName <> Parts[1]) or not IsPublishedProp(C, Parts[2]) then
      Continue;
    try
      SetPropValue(C, Parts[2], State.ValueFromIndex[I]);
    except
      { a value that does not fit any more (an item index out of range...) }
    end;
  end;
end;

{ one line each: \ \n \r for the text of a memo }
function EscapeLine(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
end;

function UnescapeLine(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '\') and (I < Length(S)) then
    begin
      Inc(I);
      case S[I] of
        'n': Result := Result + #10;
        'r': Result := Result + #13;
      else
        Result := Result + S[I];
      end;
    end
    else
      Result := Result + S[I];
    Inc(I);
  end;
end;

const
  StateHeader = 'pastel-state 1';
  AppPart = '[app]';

function FormStateText(Form: TForm): string;
var
  L, Controls: TStringList;
  I: Integer;
begin
  if Assigned(Form.OnSaveState) then
    Form.OnSaveState(Form);
  L := TStringList.Create;
  Controls := CaptureState(Form);
  try
    L.Add(StateHeader);
    for I := 0 to Controls.Count - 1 do
      L.Add(Controls.Names[I] + '=' + EscapeLine(Controls.ValueFromIndex[I]));
    L.Add(AppPart);
    for I := 0 to Form.SaveState.Count - 1 do
      L.Add(EscapeLine(Form.SaveState[I]));
    Result := L.Text;
  finally
    Controls.Free;
    L.Free;
  end;
end;

procedure RestoreFormStateText(Form: TForm; const Text: string);
var
  L, Controls: TStringList;
  I: Integer;
  InApp: Boolean;
begin
  L := TStringList.Create;
  Controls := TStringList.Create;
  try
    L.Text := Text;
    if (L.Count = 0) or (L[0] <> StateHeader) then
      Exit;
    InApp := False;
    Form.SaveState.Clear;
    for I := 1 to L.Count - 1 do
      if not InApp and (L[I] = AppPart) then
        InApp := True
      else if InApp then
        Form.SaveState.Add(UnescapeLine(L[I]))
      else if Pos('=', L[I]) > 0 then
        Controls.Add(Copy(L[I], 1, Pos('=', L[I]) - 1) + '=' + UnescapeLine(Copy(L[I], Pos('=', L[I]) + 1, MaxInt)));
    RestoreState(Form, Controls);
  finally
    Controls.Free;
    L.Free;
  end;
end;

procedure BuildForm(Form: TForm; Root: TPFormNode);
begin
  PendingRefs := nil;
  { scripts and FindComponent know the form by its .pform name }
  if (Form.Name = '') and IsValidIdent(Root.Name) then
  try
    Form.Name := Root.Name;
  except
    on EComponentError do ;
  end;
  SetProps(Form, Form, Root);
  BuildChildren(Form, Form, Root);
  ResolvePendingRefs(Form);
  try
    Form.BindControls;
  except
    on E: EPFormError do
      raise;
    on E: Exception do
      raise EPFormError.CreateAt(Root.Line, E.Message);
  end;
end;

{ ---- views: Home.tablet.pform, Home.phone.pform, Home.tv.pform ---- }

procedure RegisterFormView(const AFormClassName, AView, ASource, AFilePath: string);
var
  S, V: TFormSource;
  I: Integer;
begin
  I := Sources.IndexOf(AFormClassName);
  if I < 0 then
  begin
    S := TFormSource.Create;
    S.FormClassName := AFormClassName;
    Sources.AddObject(AFormClassName, S);
  end
  else
    S := TFormSource(Sources.Objects[I]);
  if S.Views = nil then
  begin
    S.Views := TStringList.Create;
    S.Views.OwnsObjects := True;
  end;
  I := S.Views.IndexOf(LowerCase(AView));
  if I >= 0 then
    V := TFormSource(S.Views.Objects[I])
  else
  begin
    V := TFormSource.Create;
    S.Views.AddObject(LowerCase(AView), V);
  end;
  V.FormClassName := AFormClassName;
  V.Source := ASource;
  V.FilePath := AFilePath;
end;

const
  ScreenViewNames: array[TScreenClass] of string = ('phone', 'tablet', 'desktop', 'tv');
  ViewStateName = 'PastelViewState';

function ViewForScreen(Form: TForm; AClass: TScreenClass): string;
var
  Src: TFormSource;
begin
  Result := '';
  Src := FindFormSource(Form);
  if (Src = nil) or (Src.Views = nil) then
    Exit;
  Result := ScreenViewNames[AClass];
  if Src.Views.IndexOf(Result) >= 0 then
    Exit;
  { a TV is a big landscape screen: a tablet's view suits it }
  if (AClass = scTV) and (Src.Views.IndexOf('tablet') >= 0) then
    Exit('tablet');
  Result := '';
end;

type
  { the values a view replaced, to put them back: "Component.Property=value" }
  TViewState = class(TComponent)
  public
    Saved: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TViewState.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Saved := TStringList.Create;
end;

destructor TViewState.Destroy;
begin
  Saved.Free;
  inherited Destroy;
end;

function ViewText(V: TFormSource): string;
var
  L: TStringList;
begin
  Result := V.Source;
  if (V.FilePath <> '') and FileExists(V.FilePath) then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(V.FilePath);
      Result := L.Text;
    finally
      L.Free;
    end;
  end;
end;

function FormViewFilesText(Form: TForm): string;
var
  Src: TFormSource;
  I: Integer;
begin
  Result := '';
  Src := FindFormSource(Form);
  if (Src = nil) or (Src.Views = nil) then
    Exit;
  for I := 0 to Src.Views.Count - 1 do
    if TFormSource(Src.Views.Objects[I]).FilePath <> '' then
      Result := Result + Src.Views[I] + ':' + ViewText(TFormSource(Src.Views.Objects[I]));
end;

procedure ApplyFormView(Form: TForm; AClass: TScreenClass);
var
  Src, V: TFormSource;
  Name, Key, PropName: string;
  State: TViewState;
  Root: TPFormNode;
  I, Dot: Integer;
  C: TComponent;

  function Target(const CompName: string): TComponent;
  begin
    if CompName = '' then
      Result := Form
    else
      Result := Form.FindComponent(CompName);
  end;

  { the value before the view changes it, once }
  procedure Remember(Comp: TComponent; const CompName: string; P: TPFormProp);
  var
    Info: PPropInfo;
  begin
    PropName := P.Name;
    Dot := Pos('.', PropName);
    if Dot > 0 then
      Exit;      { a property of a property (Font.Size): set, not put back }
    Info := GetPropInfo(Comp, PropName);
    if (Info = nil) or (Info^.PropType^.Kind in [tkClass, tkMethod]) then
      Exit;
    Key := CompName + '.' + PropName;
    if State.Saved.IndexOfName(Key) < 0 then
      State.Saved.Add(Key + '=' + string(GetPropValue(Comp, PropName, True)));
  end;

  procedure Apply(Node: TPFormNode; const CompName: string);
  var
    K: Integer;
    Comp: TComponent;
  begin
    Comp := Target(CompName);
    if Comp = nil then
      raise EPFormError.CreateAt(Node.Line, Format('the view %s has "%s", which the form does not have',
        [Name, CompName]));
    for K := 0 to Node.Props.Count - 1 do
    begin
      Remember(Comp, CompName, Node.Prop(K));
      SetProp(Comp, Form, Node.Prop(K));
    end;
    for K := 0 to Node.Children.Count - 1 do
      Apply(Node.Child(K), Node.Child(K).Name);
  end;

begin
  Name := ViewForScreen(Form, AClass);
  { nothing to do: the same view, already applied (or no view, none applied) }
  if (Name = Form.View) and ((Form.FindComponent(ViewStateName) <> nil) = (Name <> '')) then
    Exit;
  C := Form.FindComponent(ViewStateName);
  if C = nil then
  begin
    State := TViewState.Create(Form);
    State.Name := ViewStateName;
  end
  else
    State := TViewState(C);
  { the form's own values back }
  for I := 0 to State.Saved.Count - 1 do
  begin
    Key := State.Saved.Names[I];
    Dot := Pos('.', Key);
    C := Target(Copy(Key, 1, Dot - 1));
    if C <> nil then
    try
      SetPropValue(C, Copy(Key, Dot + 1, MaxInt), State.Saved.ValueFromIndex[I]);
    except
      { a value that does not fit any more }
    end;
  end;
  State.Saved.Clear;
  Form.View := Name;
  if Name = '' then
    Exit;
  Src := FindFormSource(Form);
  V := TFormSource(Src.Views.Objects[Src.Views.IndexOf(Name)]);
  Root := ParsePForm(ViewText(V));
  try
    PendingRefs := nil;
    Apply(Root, '');
    ResolvePendingRefs(Form);
  finally
    Root.Free;
  end;
end;

procedure ViewHook(Form: TForm; AClass: TScreenClass);
begin
  try
    ApplyFormView(Form, AClass);
  except
    on E: Exception do
      WriteLn(StdErr, Form.ClassName, ', view: ', E.Message);
  end;
end;

initialization
  RegisterControl(TFrame);
  Sources := TStringList.Create;
  Sources.Sorted := True;
  Sources.OwnsObjects := True;
  FormViewHook := @ViewHook;

finalization
  Sources.Free;

end.
