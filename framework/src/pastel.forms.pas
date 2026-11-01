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
  TFormSource = class
  public
    FormClassName: string;
    Source: string;       { .pform text compiled into the program }
    FilePath: string;     { .pform file on disk, for hot reload ('' in release) }
  end;

{ Called by generated code. }
procedure RegisterFormSource(const AFormClassName, ASource, AFilePath: string);
{ The registered source for a form, searching its class hierarchy. }
function FindFormSource(Form: TForm): TFormSource;

{ What the user changed in the controls (typed text, checked boxes, chosen
  items, the page of tabs), by control name; hot reload puts it back. }
function CaptureState(Form: TForm): TStringList;
procedure RestoreState(Form: TForm; State: TStringList);

{ Creates the controls described by Root on Form, then binds fields.
  Raises EPFormError on problems (unknown type, property or event). }
procedure BuildForm(Form: TForm; Root: TPFormNode);

var
  { Internal: False skips event handlers that do not exist instead of an
    error. Used by tools that load a form without its code (preview, check). }
  StrictEvents: Boolean = True;

implementation

uses
  TypInfo, Pastel.Graphics, Pastel.Lang;

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

procedure ResolvePendingRefs(Form: TForm);
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

procedure SetProp(Instance: TObject; Form: TForm; P: TPFormProp);
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

procedure SetProps(Instance: TObject; Form: TForm; Node: TPFormNode);
var
  I: Integer;
begin
  for I := 0 to Node.Props.Count - 1 do
    SetProp(Instance, Form, Node.Prop(I));
end;

procedure BuildChildren(Form: TForm; Parent: TControl; Node: TPFormNode);
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

function CaptureState(Form: TForm): TStringList;
var
  I: Integer;
  C: TComponent;
  P: string;
begin
  Result := TStringList.Create;
  for I := 0 to Form.ComponentCount - 1 do
  begin
    C := Form.Components[I];
    if (C.Name = '') or not (C is TControl) then
      Continue;
    for P in StateProps do
      if KeepsState(C, P) then
        Result.Values[C.Name + '.' + C.ClassName + '.' + P] := GetPropValue(C, P, True);
  end;
end;

procedure RestoreState(Form: TForm; State: TStringList);
var
  I: Integer;
  Parts: TStringArray;
  C: TComponent;
begin
  for I := 0 to State.Count - 1 do
  begin
    Parts := State.Names[I].Split(['.']);
    if Length(Parts) <> 3 then
      Continue;
    C := Form.FindComponent(Parts[0]);
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

initialization
  Sources := TStringList.Create;
  Sources.Sorted := True;
  Sources.OwnsObjects := True;

finalization
  Sources.Free;

end.
