{ Pastel - screen readers: what is on the screen, for people who cannot see it.

  Pastel draws its controls itself, so it tells the system what they are: on
  Android TalkBack reads each control (its kind, its text, checked or not),
  and a double tap clicks it - nothing to do in the app. A control whose text
  does not say what it does gets an AccessibleName:

    object DeleteButton: TButton
      Icon = 'trash'
      AccessibleName = 'Delete the appointment'
    end

  Computers: Windows' Narrator and Linux's Orca are not reached yet.
  Part of the Pastel project, MIT License. }
unit Pastel.Accessibility;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  TPixelRectFunc = function(const R: TRectI): TRectI;

{ The controls a screen reader sees, a line each:
  id, parent's id, x, y, w, h (pixels), role (Android's class), text, hint, flags. }
function AccessibilityTree(Form: TForm; Pixels: TPixelRectFunc): string;
{ The control of an id of the tree (nil: it is gone). }
function AccessibleControl(Id: Integer): TControl;
{ A screen reader's action: 16 click, 1 focus, 4096 scroll forward, 8192 back (Android's numbers). }
procedure AccessibilityAction(Form: TForm; Id, Action: Integer);
{ The role and the text a screen reader gets for a control. }
procedure AccessibleInfo(C: TControl; out Role, Text, Hint, Flags: string);

implementation

uses
  TypInfo, Pastel.Controls;

var
  Known: TFPList;      { controls by id - 1 }

type
  TForget = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

var
  Forget: TForget;

procedure TForget.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    I := Known.IndexOf(AComponent);
    if I >= 0 then
      Known[I] := nil;     { ids stay what they were }
  end;
end;

function IdOf(C: TControl): Integer;
begin
  Result := Known.IndexOf(C);
  if Result < 0 then
  begin
    Result := Known.Add(C);
    C.FreeNotification(Forget);
  end;
  Inc(Result);
end;

function AccessibleControl(Id: Integer): TControl;
begin
  if (Id >= 1) and (Id <= Known.Count) then
    Result := TControl(Known[Id - 1])
  else
    Result := nil;
end;

function Is_(C: TControl; const ClassName_: string): Boolean;
var
  K: TClass;
begin
  K := C.ClassType;
  while K <> nil do
  begin
    if SameText(K.ClassName, ClassName_) then
      Exit(True);
    K := K.ClassParent;
  end;
  Result := False;
end;

function StrProp(C: TControl; const Name: string): string;
var
  P: PPropInfo;
begin
  Result := '';
  P := GetPropInfo(C, Name);
  if (P <> nil) and (P^.PropType^.Kind in [tkAString, tkSString, tkUString, tkWString, tkLString]) then
    Result := GetStrProp(C, P);
end;

procedure AccessibleInfo(C: TControl; out Role, Text, Hint, Flags: string);
var
  P: PPropInfo;
begin
  Role := '';
  Text := '';
  Hint := '';
  Flags := '';
  if Is_(C, 'TButton') then Role := 'Button'
  else if Is_(C, 'TSwitch') then Role := 'Switch'
  else if Is_(C, 'TCheckBox') then Role := 'CheckBox'
  else if Is_(C, 'TRadioButton') then Role := 'RadioButton'
  else if Is_(C, 'TCustomEdit') then Role := 'EditText'
  else if Is_(C, 'TLabel') then Role := 'TextView'
  else if Is_(C, 'TComboBox') then Role := 'Spinner'
  else if Is_(C, 'TListBox') or Is_(C, 'TListView') or Is_(C, 'TGrid') or Is_(C, 'TTreeView') then Role := 'ListView'
  else if Is_(C, 'TScrollBox') then Role := 'ScrollView'
  else if Is_(C, 'TImage') then Role := 'ImageView'
  else if Is_(C, 'TSlider') then Role := 'SeekBar'
  else if Is_(C, 'TProgressBar') or Is_(C, 'TSpinner') then Role := 'ProgressBar'
  else if Is_(C, 'TDatePicker') or Is_(C, 'TTimeEdit') then Role := 'EditText';
  Text := C.AccessibleName;
  if Text = '' then
  begin
    Text := StrProp(C, 'Text');
    if Text = '' then
      Text := StrProp(C, 'Caption');
  end;
  if Role = 'EditText' then
    Hint := StrProp(C, 'Placeholder');
  if Hint = '' then
    Hint := C.Hint;
  if C.Enabled then
    Flags := Flags + 'e';
  P := GetPropInfo(C, 'Checked');
  if (P <> nil) and (P^.PropType^.Kind = tkBool) then
  begin
    Flags := Flags + 'c';
    if GetOrdProp(C, P) <> 0 then
      Flags := Flags + 'k';
  end;
  if (C.ParentForm <> nil) and (C.ParentForm.Focused = C) then
    Flags := Flags + 'f';
  if Role = 'EditText' then
    Flags := Flags + 't';
  if (Role = 'Button') or (Role = 'Switch') or (Role = 'CheckBox') or (Role = 'RadioButton') or (Role = 'Spinner') or
     (Role = 'EditText') or (Role = 'SeekBar') or Is_(C, 'TMenuItem') then
    Flags := Flags + 'l';
  if (Role = 'ScrollView') or (Role = 'ListView') then
    Flags := Flags + 's';
end;

function Clean(const S: string): string;
begin
  Result := StringReplace(StringReplace(S, #9, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

procedure Walk(C: TControl; ParentId: Integer; Pixels: TPixelRectFunc; Lines: TStrings; const Clip: TRectI);
var
  Role, Text, Hint, Flags: string;
  R, Seen: TRectI;
  Id, I, Mine: Integer;
begin
  if not C.Visible then
    Exit;
  Seen := C.Bounds.Intersect(Clip);
  if (Seen.W <= 0) or (Seen.H <= 0) then
    Exit;
  AccessibleInfo(C, Role, Text, Hint, Flags);
  Mine := ParentId;
  { a control with something to say or do; plain boxes add only their children }
  if (Role <> '') or (Text <> '') or (C.AccessibleName <> '') then
  begin
    Id := IdOf(C);
    R := Pixels(Seen);
    Lines.Add(Format('%d'#9'%d'#9'%d'#9'%d'#9'%d'#9'%d'#9'%s'#9'%s'#9'%s'#9'%s',
      [Id, ParentId, R.X, R.Y, R.W, R.H, Role, Clean(Text), Clean(Hint), Flags]));
    Mine := Id;
    { a list, a label: their parts are drawn, not children }
    if (Role = 'TextView') or (Role = 'Button') or (Role = 'EditText') then
      Exit;
  end;
  for I := 0 to C.ChildCount - 1 do
    Walk(C.Children[I], Mine, Pixels, Lines, Seen);
end;

function AccessibilityTree(Form: TForm; Pixels: TPixelRectFunc): string;
var
  L: TStringList;
  Top: TPopup;
begin
  L := TStringList.Create;
  try
    Top := Form.TopPopup;
    { a dialog over the form: only the dialog is there for the reader }
    if (Top <> nil) and (Top.Modal or (Top.Side <> psAnchor)) then
      Walk(Top, 0, Pixels, L, Top.Bounds)
    else
    begin
      Walk(Form, 0, Pixels, L, Form.Bounds);
      if Top <> nil then
        Walk(Top, 0, Pixels, L, Top.Bounds);
    end;
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure AccessibilityAction(Form: TForm; Id, Action: Integer);
var
  C: TControl;
  X, Y: Integer;
begin
  C := AccessibleControl(Id);
  if (C = nil) or (C.ParentForm = nil) then
    Exit;
  X := C.Bounds.X + C.Bounds.W div 2;
  Y := C.Bounds.Y + C.Bounds.H div 2;
  case Action of
    16:      { click: as a tap at its middle }
      begin
        Form.HandleMouseMove(X, Y);
        Form.HandleMouseDown(X, Y);
        Form.HandleMouseUp(X, Y);
      end;
    1:
      C.SetFocus;
    4096, 8192:
      begin
        Form.HandleMouseMove(X, Y);
        if Action = 4096 then
          Form.HandleMouseWheel(0, -3)
        else
          Form.HandleMouseWheel(0, 3);
      end;
  end;
  NeedsRepaint := True;
end;

initialization
  Known := TFPList.Create;
  Forget := TForget.Create(nil);

finalization
  Forget.Free;
  Known.Free;
end.
