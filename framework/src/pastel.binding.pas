{ Pastel - data binding: fills a form's controls from a record and back.

    object PersonData: TDataBinding
      Fields = ('NameEdit', 'EmailEdit', 'ActiveCheck', 'AgeSlider=age_years')
    end

    PersonData.Load(Db.QueryOne('select * from people where id = ?', [Id]));
    ...
    Row := TJSONObject.Create;
    PersonData.Save(Row);            // name, email, active, age_years
    if PersonData.Modified then ...

  'NameEdit' alone binds the field 'name' (the name without the control's
  kind, in snake_case: FullNameEdit -> full_name). An edit or memo shows the
  value as text, a check box or switch a boolean, a slider or progress bar
  a number, a combo box its text, a list box the selected item.
  Load and Save also work with objects (their published properties) and
  with a row of a TGrid (columns by Field or Title).
  Part of the Pastel project, MIT License. }
unit Pastel.Binding;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.UI;

type
  EBindingError = class(Exception);

  TDataBinding = class(TComponent)
  private
    FFields: TStringList;
    FSnapshot: string;
    FOnLoad: TNotifyEvent;
    function GetFields: TStrings;
    procedure SetFields(AValue: TStrings);
    function GetModified: Boolean;
    function Snapshot: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The control of a binding line. }
    function ControlOf(Index: Integer): TControl;
    { The field of a binding line. }
    function FieldOf(Index: Integer): string;
    { Adds a binding from code; Field '' derives it from the name. }
    procedure Bind(Control: TControl; const Field: string = '');
    { The control's value as text / sets it from text. }
    function GetValue(Control: TControl): string;
    procedure SetValue(Control: TControl; const Value: string);
    { Fills the controls from the object's fields (missing ones: empty). }
    procedure Load(Data: TJSONObject); overload;
    { Writes the controls into Data, replacing those fields. }
    procedure Save(Data: TJSONObject); overload;
    { The same with an object's published properties. }
    procedure LoadObject(Obj: TObject);
    procedure SaveObject(Obj: TObject);
    { The same with a row of a grid (Pastel.Grids). }
    procedure LoadRow(Grid: TControl; Row: Integer);
    procedure SaveRow(Grid: TControl; Row: Integer);
    { Empties all bound controls (a new record). }
    procedure Clear;
    { A new JSON object with the controls' values; the caller frees it. }
    function ToJson: TJSONObject;
    { The current values count as saved: Modified is False. }
    procedure MarkSaved;
    { The user changed a value since the last Load or MarkSaved. }
    property Modified: Boolean read GetModified;
  published
    { 'ControlName' or 'ControlName=field', one per line. }
    property Fields: TStrings read GetFields write SetFields;
    property OnLoad: TNotifyEvent read FOnLoad write FOnLoad;
  end;

{ FullNameEdit -> full_name }
function FieldFromControlName(const Name: string): string;

implementation

uses
  TypInfo, Variants, Pastel.Controls, Pastel.Grids;

const
  Kinds: array[0..21] of string = ('CheckBox', 'ComboBox', 'ListBox', 'ListView', 'TreeView', 'Edit', 'Memo',
    'Check', 'Combo', 'Switch', 'Slider', 'Progress', 'Label', 'Radio', 'Image', 'List', 'Box', 'Field',
    'Input', 'Spin', 'Picker', 'Text');

function FieldFromControlName(const Name: string): string;
var
  N, K: string;
  I: Integer;
begin
  N := Name;
  for K in Kinds do
    if (Length(N) > Length(K)) and SameText(Copy(N, Length(N) - Length(K) + 1, MaxInt), K) then
    begin
      SetLength(N, Length(N) - Length(K));
      Break;
    end;
  Result := '';
  for I := 1 to Length(N) do
  begin
    if (N[I] in ['A'..'Z']) and (I > 1) and not (N[I - 1] in ['A'..'Z', '_']) then
      Result := Result + '_';
    Result := Result + LowerCase(N[I]);
  end;
end;

constructor TDataBinding.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFields := TStringList.Create;
end;

destructor TDataBinding.Destroy;
begin
  FFields.Free;
  inherited Destroy;
end;

function TDataBinding.GetFields: TStrings;
begin
  Result := FFields;
end;

procedure TDataBinding.SetFields(AValue: TStrings);
begin
  FFields.Assign(AValue);
end;

function TDataBinding.ControlOf(Index: Integer): TControl;
var
  N: string;
  C: TComponent;
begin
  N := Trim(FFields.Names[Index]);
  if N = '' then
    N := Trim(FFields[Index]);
  C := nil;
  if Owner <> nil then
    C := Owner.FindComponent(N);
  if not (C is TControl) then
    raise EBindingError.CreateFmt('%s: there is no control "%s" on the form', [Name, N]);
  Result := TControl(C);
end;

function TDataBinding.FieldOf(Index: Integer): string;
begin
  if Pos('=', FFields[Index]) > 0 then
    Result := Trim(FFields.ValueFromIndex[Index])
  else
    Result := FieldFromControlName(Trim(FFields[Index]));
end;

procedure TDataBinding.Bind(Control: TControl; const Field: string);
begin
  if Control.Owner <> Owner then
    raise EBindingError.CreateFmt('%s: %s is on another form', [Name, Control.Name]);
  if Field = '' then
    FFields.Add(Control.Name)
  else
    FFields.Add(Control.Name + '=' + Field);
end;

function TDataBinding.GetValue(Control: TControl): string;
begin
  if Control is TCheckBox then
    Result := BoolToStr(TCheckBox(Control).Checked, 'true', 'false')
  else if Control is TListBox then
    Result := TListBox(Control).SelectedText
  else if Control is TSlider then
    Result := IntToStr(TSlider(Control).Position)
  else if Control is TProgressBar then
    Result := IntToStr(TProgressBar(Control).Position)
  else if Control is TImage then
    Result := TImage(Control).FileName
  else if Control is TTreeView then
    Result := TTreeView(Control).Text
  else if IsPublishedProp(Control, 'Text') then
    Result := GetStrProp(Control, 'Text')
  else
    raise EBindingError.CreateFmt('%s: %s (%s) has no value to bind', [Name, Control.Name, Control.ClassName]);
end;

procedure TDataBinding.SetValue(Control: TControl; const Value: string);
var
  B: Boolean;
begin
  if Control is TCheckBox then
  begin
    B := SameText(Value, 'true') or (Value = '1') or SameText(Value, 'yes') or SameText(Value, 't');
    TCheckBox(Control).Checked := B;
  end
  else if Control is TListBox then
    TListBox(Control).ItemIndex := TListBox(Control).Items.IndexOf(Value)
  else if Control is TSlider then
    TSlider(Control).Position := StrToIntDef(Value, TSlider(Control).Min)
  else if Control is TProgressBar then
    TProgressBar(Control).Position := StrToIntDef(Value, 0)
  else if Control is TImage then
    TImage(Control).FileName := Value
  else if Control is TTreeView then
    TTreeView(Control).Selected := TTreeView(Control).FindNode(Value)
  else if IsPublishedProp(Control, 'Text') and (GetPropInfo(Control, 'Text')^.SetProc <> nil) then
    SetStrProp(Control, 'Text', Value)
  else
    raise EBindingError.CreateFmt('%s: %s (%s) has no value to bind', [Name, Control.Name, Control.ClassName]);
end;

function TDataBinding.Snapshot: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FFields.Count - 1 do
    if Trim(FFields[I]) <> '' then
      Result := Result + GetValue(ControlOf(I)) + #1;
end;

procedure TDataBinding.MarkSaved;
begin
  FSnapshot := Snapshot;
end;

function TDataBinding.GetModified: Boolean;
begin
  Result := Snapshot <> FSnapshot;
end;

function JsonText(D: TJSONData): string;
begin
  if (D = nil) or (D.JSONType = jtNull) then
    Result := ''
  else if D.JSONType = jtBoolean then
    Result := BoolToStr(D.AsBoolean, 'true', 'false')
  else if D.JSONType in [jtObject, jtArray] then
    Result := D.AsJSON
  else
    Result := D.AsString;
end;

procedure TDataBinding.Load(Data: TJSONObject);
var
  I: Integer;
begin
  for I := 0 to FFields.Count - 1 do
    if Trim(FFields[I]) <> '' then
      if Data = nil then
        SetValue(ControlOf(I), '')
      else
        SetValue(ControlOf(I), JsonText(Data.Find(FieldOf(I))));
  MarkSaved;
  if Assigned(FOnLoad) then
    FOnLoad(Self);
end;

procedure TDataBinding.Save(Data: TJSONObject);
var
  I, Old: Integer;
  C: TControl;
  F, V: string;
  N: Int64;
  X: Double;
  FS: TFormatSettings;
  Was: TJSONData;
  WasNumber: Boolean;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  for I := 0 to FFields.Count - 1 do
  begin
    if Trim(FFields[I]) = '' then
      Continue;
    C := ControlOf(I);
    F := FieldOf(I);
    V := GetValue(C);
    Was := Data.Find(F);
    WasNumber := (Was <> nil) and (Was.JSONType = jtNumber);
    Old := Data.IndexOfName(F);
    if Old >= 0 then
      Data.Delete(Old);
    if C is TCheckBox then
      Data.Add(F, V = 'true')
    else if (C is TSlider) or (C is TProgressBar) then
      Data.Add(F, StrToInt64Def(V, 0))
    { a field that was a number stays a number when the text is one }
    else if WasNumber and TryStrToInt64(Trim(V), N) then
      Data.Add(F, N)
    else if WasNumber and TryStrToFloat(Trim(V), X, FS) then
      Data.Add(F, X)
    else
      Data.Add(F, V);
  end;
end;

function TDataBinding.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Save(Result);
  except
    Result.Free;
    raise;
  end;
end;

function FindProp(Obj: TObject; const Field: string): PPropInfo;
var
  Clean: string;
begin
  Result := GetPropInfo(Obj, Field);
  if Result = nil then
  begin
    { full_name -> FullName }
    Clean := StringReplace(Field, '_', '', [rfReplaceAll]);
    Result := GetPropInfo(Obj, Clean);
  end;
end;

procedure TDataBinding.LoadObject(Obj: TObject);
var
  I: Integer;
  P: PPropInfo;
  V: string;
begin
  for I := 0 to FFields.Count - 1 do
  begin
    if Trim(FFields[I]) = '' then
      Continue;
    P := FindProp(Obj, FieldOf(I));
    if P = nil then
      raise EBindingError.CreateFmt('%s: %s has no property "%s"', [Name, Obj.ClassName, FieldOf(I)]);
    if P^.PropType^.Kind = tkBool then
      V := BoolToStr(GetOrdProp(Obj, P) <> 0, 'true', 'false')
    else
      V := VarToStr(GetPropValue(Obj, P));
    SetValue(ControlOf(I), V);
  end;
  MarkSaved;
  if Assigned(FOnLoad) then
    FOnLoad(Self);
end;

procedure TDataBinding.SaveObject(Obj: TObject);
var
  I: Integer;
  P: PPropInfo;
  V: string;
begin
  for I := 0 to FFields.Count - 1 do
  begin
    if Trim(FFields[I]) = '' then
      Continue;
    P := FindProp(Obj, FieldOf(I));
    if (P = nil) or (P^.SetProc = nil) then
      raise EBindingError.CreateFmt('%s: %s has no property "%s" to write', [Name, Obj.ClassName, FieldOf(I)]);
    V := GetValue(ControlOf(I));
    try
      case P^.PropType^.Kind of
        tkBool: SetOrdProp(Obj, P, Ord(V = 'true'));
        tkInteger, tkInt64, tkQWord: SetOrdProp(Obj, P, StrToInt64(Trim(V)));
        tkFloat: SetFloatProp(Obj, P, StrToFloat(Trim(V)));
      else
        SetPropValue(Obj, P, V);
      end;
    except
      on E: EConvertError do
        raise EBindingError.CreateFmt('%s: "%s" is not a number', [FieldOf(I), V]);
    end;
  end;
end;

function GridColumn(G: TGrid; const Field: string): Integer;
var
  I: Integer;
begin
  for I := 0 to G.ColCount - 1 do
    if SameText(G.Columns[I].Field, Field) or ((G.Columns[I].Field = '') and SameText(G.Columns[I].Title, Field)) then
      Exit(I);
  Result := -1;
end;

procedure TDataBinding.LoadRow(Grid: TControl; Row: Integer);
var
  I, C: Integer;
  G: TGrid;
begin
  G := Grid as TGrid;
  for I := 0 to FFields.Count - 1 do
  begin
    if Trim(FFields[I]) = '' then
      Continue;
    C := GridColumn(G, FieldOf(I));
    if (C >= 0) and (Row >= 0) and (Row < G.RowCount) then
      SetValue(ControlOf(I), G.Cells[C, Row])
    else
      SetValue(ControlOf(I), '');
  end;
  MarkSaved;
  if Assigned(FOnLoad) then
    FOnLoad(Self);
end;

procedure TDataBinding.SaveRow(Grid: TControl; Row: Integer);
var
  I, C: Integer;
  G: TGrid;
begin
  G := Grid as TGrid;
  for I := 0 to FFields.Count - 1 do
  begin
    if Trim(FFields[I]) = '' then
      Continue;
    C := GridColumn(G, FieldOf(I));
    if C >= 0 then
      G.Cells[C, Row] := GetValue(ControlOf(I));
  end;
end;

procedure TDataBinding.Clear;
var
  I: Integer;
begin
  for I := 0 to FFields.Count - 1 do
    if Trim(FFields[I]) <> '' then
      SetValue(ControlOf(I), '');
  MarkSaved;
end;

initialization
  RegisterNonVisual(TDataBinding);
end.
