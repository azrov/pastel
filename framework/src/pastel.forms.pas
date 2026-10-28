{ Pastel - building forms from .pform data.

  The code Pastel generates for each .pform file registers the form's source
  here. When a form is created, its controls are built from that source and
  properties and events are set through RTTI, like Delphi does with .dfm.
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

{ Creates the controls described by Root on Form, then binds fields.
  Raises EPFormError on problems (unknown type, property or event). }
procedure BuildForm(Form: TForm; Root: TPFormNode);

var
  { False: event handlers that do not exist are skipped instead of being an
    error. Used by tools that load a form without its code (preview, check). }
  StrictEvents: Boolean = True;

implementation

uses
  TypInfo, Pastel.Graphics;

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

procedure SetProp(Instance: TObject; Form: TForm; P: TPFormProp);
var
  PI: PPropInfo;
  T: PTypeInfo;
  Color: TColor32;
  N: Int64;
  E: Integer;
  F: Double;
  M: TMethod;
  FS: TFormatSettings;

  procedure Fail(const Msg: string);
  begin
    raise EPFormError.CreateAt(P.Line, Msg);
  end;

begin
  if Pos('.', P.Name) > 0 then
    Fail('nested properties like "' + P.Name + '" are not supported yet');
  PI := GetPropInfo(Instance, P.Name);
  if PI = nil then
    Fail(Format('%s has no property "%s"', [Instance.ClassName, P.Name]));
  if PI^.SetProc = nil then
    Fail(Format('property "%s" is read-only', [P.Name]));
  T := PI^.PropType;
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
          if (P.Kind <> pvNumber) or not TryStrToInt64(P.Value, N) then
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
        SetStrProp(Instance, PI, P.Value);
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
  C: TControl;
begin
  for I := 0 to Node.Children.Count - 1 do
  begin
    ChildNode := Node.Child(I);
    Cls := FindControlClass(ChildNode.ClassName_);
    if Cls = nil then
      raise EPFormError.CreateAt(ChildNode.Line,
        Format('unknown component type "%s"', [ChildNode.ClassName_]));
    if Form.FindComponent(ChildNode.Name) <> nil then
      raise EPFormError.CreateAt(ChildNode.Line,
        Format('the name "%s" is used twice', [ChildNode.Name]));
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

procedure BuildForm(Form: TForm; Root: TPFormNode);
begin
  SetProps(Form, Form, Root);
  BuildChildren(Form, Form, Root);
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
