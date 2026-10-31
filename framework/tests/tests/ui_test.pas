unit UI_Test;

{ The controls without a window: a form laid out in memory, input sent to it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI;

type
  TUITests = class(TTestSuite)
  private
    Form: TForm;
    Canvas: TCanvas32;
    procedure Render;
    procedure ClickAt(X, Y: Integer; Clicks: Integer = 1; Button: Integer = 1);
    procedure Click(C: TControl; Clicks: Integer = 1; Button: Integer = 1);
    procedure Key(K: LongInt; Shift: Boolean = False; Ctrl: Boolean = False);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EditTypesAndSelects;
    procedure EditWordsAndDelete;
    procedure EditUndoRedo;
    procedure EditClipboard;
    procedure EditDoubleClickSelectsWord;
    procedure EditPasswordHidesText;
    procedure EditReadOnlyAndMaxLength;
    procedure MemoLinesAndEnter;
    procedure MemoUpDownKeepColumn;
    procedure MemoWrapsLongLines;
    procedure MemoScrollsWithWheel;
    procedure LabelWraps;
    procedure ModalPopupBlocksTheForm;
    procedure DropDownClosesOnClickOutside;
    procedure DialogButtonsWithKeys;
    procedure TabStaysInDialog;
    procedure TimersFire;
    procedure TooltipAfterAPause;
    procedure RightClickAsksForTheMenu;
    procedure DarkTheme;
    procedure ControlNamesMustNotHideFormProperties;
    procedure HotReloadKeepsWhatTheUserDid;
    procedure ListsAndReferencesInPForms;
    procedure CanvasScales;
    procedure GridRowsAndSorting;
    procedure GridLoadsJson;
    procedure TreeFromLines;
    procedure ThemeValues;
    procedure BindingNames;
    procedure BindingLoadsAndSaves;
  end;

implementation

uses
  Pastel.PForm, Pastel.Forms, Pastel.Controls, Pastel.Menus, Pastel.Grids, Pastel.Binding, fpjson, Pastel.Json;

var
  Clip: string;
  MenuShownFor: TControl = nil;

function GetClip: string;
begin
  Result := Clip;
end;

procedure SetClip(const S: string);
begin
  Clip := S;
end;

procedure TUITests.SetUp;
begin
  InitFonts;
  Canvas := TCanvas32.Create;
  Form := TForm.Create(nil);
  ClipboardGetText := @GetClip;
  ClipboardSetText := @SetClip;
end;

procedure TUITests.TearDown;
begin
  Form.Free;
  Canvas.Free;
  UseDarkTheme(False);
end;

procedure TUITests.Render;
begin
  Form.Layout(400, 300);
  Canvas.SetSize(400, 300);
  Form.Render(Canvas);
end;

procedure TUITests.ClickAt(X, Y: Integer; Clicks: Integer; Button: Integer);
begin
  Render;
  Form.HandleMouseMove(X, Y);
  Form.HandleMouseDown(X, Y, Button, Clicks);
  Form.HandleMouseUp(X, Y, Button);
end;

procedure TUITests.Click(C: TControl; Clicks: Integer; Button: Integer);
begin
  Render;
  ClickAt(C.Bounds.X + C.Bounds.W div 2, C.Bounds.Y + C.Bounds.H div 2, Clicks, Button);
end;

procedure TUITests.Key(K: LongInt; Shift: Boolean; Ctrl: Boolean);
begin
  Form.ShiftDown := Shift;
  Form.HandleKeyDown(K, Shift, Ctrl);
  Form.ShiftDown := False;
end;

function NewEdit(Form: TForm): TEdit;
begin
  Result := TEdit.Create(Form);
  Result.Parent := Form;
end;

procedure TUITests.EditTypesAndSelects;
var
  E: TEdit;
begin
  E := NewEdit(Form);
  E.SetFocus;
  Form.HandleTextInput('Merhaba dünya');
  AssertEquals('Merhaba dünya', E.Text);
  Key(KEY_LEFT, True);
  Key(KEY_LEFT, True);
  AssertEquals('ya', E.SelText);
  Form.HandleTextInput('!');
  AssertEquals('Merhaba dün!', E.Text);
  Key(KEY_HOME, True);
  AssertEquals('Merhaba dün!', E.SelText, 'shift+home selects to the start');
  Key(KEY_RIGHT);
  AssertEquals(0, E.SelLength, 'right ends the selection');
  AssertEquals(Length('Merhaba dün!'), E.SelStart);
end;

procedure TUITests.EditWordsAndDelete;
var
  E: TEdit;
begin
  E := NewEdit(Form);
  E.SetFocus;
  Form.HandleTextInput('bir iki üç');
  Key(KEY_LEFT, False, True);
  AssertEquals(Length('bir iki '), E.SelStart, 'ctrl+left to the start of the word');
  Key(KEY_BACKSPACE, False, True);
  AssertEquals('bir üç', E.Text, 'ctrl+backspace deletes a word');
  Key(Ord('a'), False, True);
  Key(KEY_DELETE);
  AssertEquals('', E.Text);
end;

procedure TUITests.EditUndoRedo;
var
  E: TEdit;
begin
  E := NewEdit(Form);
  E.SetFocus;
  Form.HandleTextInput('a');
  Form.HandleTextInput('b');
  Form.HandleTextInput('c');
  Key(KEY_BACKSPACE);
  AssertEquals('ab', E.Text);
  Key(Ord('z'), False, True);
  AssertEquals('abc', E.Text, 'undo the delete');
  Key(Ord('z'), False, True);
  AssertEquals('', E.Text, 'typing is one step');
  Key(Ord('y'), False, True);
  AssertEquals('abc', E.Text, 'redo');
end;

procedure TUITests.EditClipboard;
var
  E: TEdit;
begin
  E := NewEdit(Form);
  E.SetFocus;
  Form.HandleTextInput('kopya');
  Key(Ord('a'), False, True);
  Key(Ord('c'), False, True);
  AssertEquals('kopya', Clip);
  Key(Ord('x'), False, True);
  AssertEquals('', E.Text);
  Key(Ord('v'), False, True);
  Key(Ord('v'), False, True);
  AssertEquals('kopyakopya', E.Text);
  Clip := 'satır'#13#10'iki';
  Key(Ord('v'), False, True);
  AssertEquals('kopyakopyasatıriki', E.Text, 'one line in an edit');
end;

procedure TUITests.EditDoubleClickSelectsWord;
var
  E: TEdit;
  X: Integer;
begin
  E := NewEdit(Form);
  E.Text := 'hello brave world';
  Render;
  X := E.Bounds.X + 12 + E.Font.TextWidth('hello br');
  ClickAt(X, E.Bounds.Y + E.Bounds.H div 2);
  ClickAt(X, E.Bounds.Y + E.Bounds.H div 2, 2);
  AssertEquals('brave', E.SelText);
  ClickAt(X, E.Bounds.Y + E.Bounds.H div 2, 3);
  AssertEquals('hello brave world', E.SelText, 'triple click: all');
end;

procedure TUITests.EditPasswordHidesText;
var
  E: TEdit;
begin
  E := NewEdit(Form);
  E.Password := True;
  E.SetFocus;
  Form.HandleTextInput('gizli');
  Clip := 'old';
  Key(Ord('a'), False, True);
  Key(Ord('c'), False, True);
  AssertEquals('old', Clip, 'a password is not copied');
  Render;
  AssertEquals('gizli', E.Text);
end;

procedure TUITests.EditReadOnlyAndMaxLength;
var
  E: TEdit;
begin
  E := NewEdit(Form);
  E.MaxLength := 3;
  E.SetFocus;
  Form.HandleTextInput('abcdef');
  AssertEquals('abc', E.Text);
  E.ReadOnly := True;
  Form.HandleTextInput('x');
  Key(KEY_BACKSPACE);
  AssertEquals('abc', E.Text);
end;

procedure TUITests.MemoLinesAndEnter;
var
  M: TMemo;
begin
  M := TMemo.Create(Form);
  M.Parent := Form;
  M.SetFocus;
  Form.HandleTextInput('one');
  Key(KEY_ENTER);
  Form.HandleTextInput('two');
  AssertEquals('one'#10'two', M.Text);
  AssertEquals(2, M.Lines.Count);
  M.Lines.Add('three');
  AssertEquals('three', M.Lines[2]);
  M.Lines[0] := 'ONE';
  AssertEquals('ONE'#10'two'#10'three', M.Text);
  M.Lines.Delete(1);
  AssertEquals('ONE'#10'three', M.Text);
end;

procedure TUITests.MemoUpDownKeepColumn;
var
  M: TMemo;
begin
  M := TMemo.Create(Form);
  M.Parent := Form;
  M.Text := 'abcdef'#10'x'#10'abcdef';
  M.SetFocus;
  Render;
  M.SelStart := 4;           { after "abcd" }
  Key(KEY_DOWN);
  AssertEquals(Length('abcdef'#10'x'), M.SelStart, 'a short line: its end');
  Key(KEY_DOWN);
  AssertEquals(Length('abcdef'#10'x'#10'abcd'), M.SelStart, 'back to the column');
  Key(KEY_UP, True);
  AssertEquals(#10'abcd', M.SelText, 'shift+up selects to the same column above');
end;

procedure TUITests.MemoWrapsLongLines;
var
  M: TMemo;
  S: string;
begin
  M := TMemo.Create(Form);
  M.Parent := Form;
  M.Width := 160;
  S := 'kelime kelime kelime kelime kelime kelime kelime kelime';
  M.Text := S;
  M.SetFocus;
  Render;
  M.SelStart := 0;
  Key(KEY_DOWN);
  AssertTrue((M.SelStart > 0) and (M.SelStart < Length(S)), 'down moves to the second visual line');
  M.WordWrap := False;
  Render;
  M.SelStart := 0;
  Key(KEY_DOWN);
  AssertEquals(Length(S), M.SelStart, 'without wrapping there is one line');
end;

procedure TUITests.MemoScrollsWithWheel;
var
  M: TMemo;
  I: Integer;
  S: string;
begin
  M := TMemo.Create(Form);
  M.Parent := Form;
  M.Height := 80;
  S := '';
  for I := 1 to 50 do
    S := S + 'line ' + IntToStr(I) + #10;
  M.Text := S;
  Render;
  Form.HandleMouseMove(M.Bounds.X + 20, M.Bounds.Y + 20);
  Form.HandleMouseWheel(0, -3);
  Render;
  { the text moved: a click at the top is now in a later line }
  ClickAt(M.Bounds.X + 30, M.Bounds.Y + 15);
  AssertTrue(M.SelStart > Length('line 1'#10'line 2'#10), IntToStr(M.SelStart));
end;

procedure TUITests.LabelWraps;
var
  L: TLabel;
  W, H, H1: Integer;
begin
  L := TLabel.Create(Form);
  L.Text := 'Bu uzun bir metin, dar bir yere sığmayacak kadar uzun bir metin.';
  L.GetSize(1000, W, H1);
  L.WordWrap := True;
  L.GetSize(120, W, H);
  AssertTrue(W <= 120, 'fits the width');
  AssertTrue(H >= 3 * H1, 'several lines');
  L.Text := 'a'#10'b';
  L.WordWrap := False;
  L.GetSize(1000, W, H);
  AssertEquals(2 * H1, H, 'line breaks always count');
end;

procedure TUITests.ModalPopupBlocksTheForm;
var
  B: TButton;
  P: TPopup;
  Clicks: Integer;
  OkBtn: TButton;
begin
  B := TButton.Create(Form);
  B.Text := 'Behind';
  B.Parent := Form;
  P := TPopup.Create(Form);
  OkBtn := TButton.Create(P);
  OkBtn.Text := 'OK';
  OkBtn.ModalResult := mrOk;
  OkBtn.Parent := P;
  P.Modal := True;
  P.PopupCentered(Form);
  Render;
  Clicks := 0;
  AssertTrue(Form.HitTest(B.Bounds.X + 2, B.Bounds.Y + 2) = nil, 'the form behind cannot be clicked');
  AssertTrue(Form.Focused = OkBtn, 'the dialog has the focus');
  Click(OkBtn);
  AssertTrue(P.Closed, 'a ModalResult button closes the dialog');
  AssertEquals(mrOk, P.ModalResult);
  AssertEquals(0, Form.PopupCount);
  AssertEquals(0, Clicks);
end;

procedure TUITests.DropDownClosesOnClickOutside;
var
  B: TButton;
  P: TPopup;
  L: TLabel;
  Clicked: Boolean;
begin
  B := TButton.Create(Form);
  B.Text := 'Behind';
  B.Parent := Form;
  Render;
  P := TPopup.Create(Form);
  L := TLabel.Create(P);
  L.Text := 'item';
  L.Parent := P;
  P.Popup(Form, B.Bounds);
  Render;
  AssertTrue(P.Bounds.Y >= B.Bounds.Y + B.Bounds.H, 'below the anchor');
  Clicked := False;
  ClickAt(390, 290);
  AssertTrue(P.Closed, 'a click outside closes it');
  Key(KEY_ESCAPE);
  P.Popup(Form, B.Bounds);
  Key(KEY_ESCAPE);
  AssertTrue(P.Closed, 'escape closes it');
  AssertFalse(Clicked);
end;

procedure TUITests.DialogButtonsWithKeys;
var
  P: TPopup;
  OkBtn, CancelBtn: TButton;
  E: TEdit;
begin
  P := TPopup.Create(Form);
  E := TEdit.Create(P);
  E.Parent := P;
  OkBtn := TButton.Create(P);
  OkBtn.ModalResult := mrOk;
  OkBtn.Default := True;
  OkBtn.Parent := P;
  CancelBtn := TButton.Create(P);
  CancelBtn.ModalResult := mrCancel;
  CancelBtn.Cancel := True;
  CancelBtn.Parent := P;
  P.Modal := True;
  P.PopupCentered(Form);
  AssertTrue(Form.Focused = E);
  Key(KEY_ENTER);
  AssertEquals(mrOk, P.ModalResult, 'enter: the default button');
  P.PopupCentered(Form);
  Key(KEY_ESCAPE);
  AssertEquals(mrCancel, P.ModalResult, 'escape: the cancel button');
end;

procedure TUITests.TabStaysInDialog;
var
  Outside: TButton;
  P: TPopup;
  A, B: TButton;
  I: Integer;
begin
  Outside := TButton.Create(Form);
  Outside.Parent := Form;
  P := TPopup.Create(Form);
  A := TButton.Create(P);
  A.Parent := P;
  B := TButton.Create(P);
  B.Parent := P;
  P.Modal := True;
  P.PopupCentered(Form);
  for I := 1 to 5 do
  begin
    Key(KEY_TAB);
    AssertTrue((Form.Focused = A) or (Form.Focused = B), 'tab stays in the dialog');
  end;
  P.Close;
end;

var
  Ticks: Integer;

type
  TTick = class
    procedure Tick(Sender: TObject);
  end;

procedure TTick.Tick(Sender: TObject);
begin
  Inc(Ticks);
end;

procedure TUITests.TimersFire;
var
  T: TTimer;
  H: TTick;
  Next: Integer;
begin
  H := TTick.Create;
  T := TTimer.Create(nil);
  try
    Ticks := 0;
    T.Interval := 50;
    T.OnTimer := @H.Tick;
    Next := ProcessTimers(GetTickCount64);
    AssertTrue((Next > 0) and (Next <= 50), 'next in at most 50 ms');
    ProcessTimers(GetTickCount64 + 60);
    AssertEquals(1, Ticks);
    T.Enabled := False;
    ProcessTimers(GetTickCount64 + 1000);
    AssertEquals(1, Ticks, 'not when disabled');
  finally
    T.Free;
    H.Free;
  end;
end;

procedure TUITests.TooltipAfterAPause;
var
  B: TButton;
begin
  B := TButton.Create(Form);
  B.Text := 'Save';
  B.Hint := 'Saves the file (Ctrl+S)';
  B.Parent := Form;
  Render;
  Form.HandleMouseMove(B.Bounds.X + 5, B.Bounds.Y + 5);
  AssertFalse(Form.UpdateTooltip(GetTickCount64), 'not at once');
  AssertTrue(Form.UpdateTooltip(GetTickCount64 + 700), 'after a pause');
  Form.HandleMouseMove(B.Bounds.X + 30, B.Bounds.Y + 5);
  AssertFalse(Form.UpdateTooltip(GetTickCount64), 'gone after moving');
end;

procedure ShowMenu(Menu: TControl; Form: TForm; X, Y: Integer);
begin
  MenuShownFor := Menu;
end;

procedure TUITests.RightClickAsksForTheMenu;
var
  Box: TColumn;
  L: TLabel;
  Menu: TControl;
begin
  Menu := TControl.Create(Form);
  Box := TColumn.Create(Form);
  Box.PopupMenu := Menu;
  Box.Parent := Form;
  L := TLabel.Create(Form);
  L.Text := 'inside';
  L.Parent := Box;
  PopupMenuHook := @ShowMenu;
  try
    MenuShownFor := nil;
    Click(L, 1, 3);
    AssertTrue(MenuShownFor = Menu, 'the menu of the parent');
  finally
    PopupMenuHook := nil;
  end;
  Menu.Free;
  AssertTrue(Box.PopupMenu = nil, 'a freed menu is forgotten');
end;

procedure TUITests.DarkTheme;
var
  Light: TColor32;
begin
  Render;
  Light := Canvas.GetPixel(1, 1);
  UseDarkTheme(True);
  Render;
  AssertTrue(Theme.Dark);
  AssertTrue(Canvas.GetPixel(1, 1) <> Light, 'the background changes');
end;

procedure TUITests.ControlNamesMustNotHideFormProperties;
var
  Root: TPFormNode;
  F: TForm;
begin
  Root := ParsePForm('object F: TForm'#10'  object Hint: TLabel'#10'  end'#10'end');
  F := TForm.Create(nil);
  try
    try
      BuildForm(F, Root);
      Fail('accepted');
    except
      on E: EPFormError do
        AssertContains('already the name of a property', E.Message);
    end;
  finally
    F.Free;
    Root.Free;
  end;
end;

procedure TUITests.HotReloadKeepsWhatTheUserDid;
const
  V1 = 'object F: TForm'#10'  object Name: TEdit'#10'  end'#10'  object Agree: TCheckBox'#10'  end'#10 +
    '  object Size: TComboBox'#10'    Items = (''S'', ''M'', ''L'')'#10'  end'#10'  object Caption1: TLabel'#10 +
    '    Text = ''old'''#10'  end'#10'end';
  V2 = 'object F: TForm'#10'  object Name: TCheckBox'#10'  end'#10'  object Agree: TCheckBox'#10'    Text = ''I agree'''#10 +
    '  end'#10'  object Size: TComboBox'#10'    Items = (''S'', ''M'', ''L'')'#10'  end'#10'  object Caption1: TLabel'#10 +
    '    Text = ''new'''#10'  end'#10'end';
var
  Root: TPFormNode;
  F: TForm;
  State: TStringList;
begin
  F := TForm.Create(nil);
  State := nil;
  try
    Root := ParsePForm(StringReplace(V1, 'object Name:', 'object NameEdit:', []));
    BuildForm(F, Root);
    Root.Free;
    TEdit(F.FindComponent('NameEdit')).Text := 'typed';
    TCheckBox(F.FindComponent('Agree')).Checked := True;
    TComboBox(F.FindComponent('Size')).ItemIndex := 2;
    State := CaptureState(F);
    F.ClearControls;
    Root := ParsePForm(StringReplace(V2, 'object Name:', 'object NameEdit:', []));
    BuildForm(F, Root);
    Root.Free;
    RestoreState(F, State);
    AssertTrue(TCheckBox(F.FindComponent('Agree')).Checked, 'checked stays');
    AssertEquals(2, TComboBox(F.FindComponent('Size')).ItemIndex, 'the choice stays');
    AssertEquals('new', TLabel(F.FindComponent('Caption1')).Text, 'texts from the .pform change');
    AssertFalse(TCheckBox(F.FindComponent('NameEdit')).Checked, 'another kind of control starts fresh');
  finally
    State.Free;
    F.Free;
  end;
end;

procedure TUITests.ListsAndReferencesInPForms;
var
  Root: TPFormNode;
  F: TForm;
begin
  Root := ParsePForm('object F: TForm'#10'  object L: TListBox'#10'    Items = ('#10'      ''a'','#10'      ''b c'')'#10 +
    '    PopupMenu = M'#10'  end'#10'  object M: TPopupMenu'#10'  end'#10'  object T: TTimer'#10'    Interval = 250'#10'  end'#10'end');
  F := TForm.Create(nil);
  try
    BuildForm(F, Root);
    AssertEquals(2, TListBox(F.FindComponent('L')).Items.Count);
    AssertEquals('b c', TListBox(F.FindComponent('L')).Items[1]);
    AssertTrue(TListBox(F.FindComponent('L')).PopupMenu = F.FindComponent('M'), 'a reference to a later component');
    AssertEquals(250, TTimer(F.FindComponent('T')).Interval, 'a non-visual component');
  finally
    F.Free;
    Root.Free;
  end;
end;

procedure TUITests.CanvasScales;
var
  C: TCanvas32;
begin
  C := TCanvas32.Create;
  try
    C.Scale := 2;
    C.SetSize(50, 40);
    AssertEquals(100, C.PixelWidth);
    AssertEquals(50, C.Width, 'layout units stay');
    C.Clear(RGB(255, 255, 255));
    C.FillRect(10, 10, 5, 5, RGB(255, 0, 0));
    AssertEquals(Cardinal(RGB(255, 0, 0)), Cardinal(C.GetPixel(12, 12)));
    AssertEquals(Cardinal(RGB(255, 255, 255)), Cardinal(C.GetPixel(16, 12)), 'right of it');
  finally
    C.Free;
  end;
end;

procedure TUITests.GridRowsAndSorting;
var
  G: TGrid;
begin
  G := TGrid.Create(nil);
  try
    G.AddColumn('Name');
    G.AddColumn('Age', 80, taRight);
    G.AddRow(['Person 10', '9']);
    G.AddRow(['Person 9', '10']);
    G.AddRow(['Ali', '']);
    AssertEquals(3, G.RowCount);
    G.Row := 1;
    G.SortBy(0);
    AssertEquals('Ali', G[0, 0]);
    AssertEquals('Person 9', G[0, 1], 'numbers in text sort as numbers');
    AssertEquals(1, G.Row, 'the selection stays on its data');
    G.SortBy(1);
    AssertEquals('9', G[1, 0], 'a column of numbers');
    AssertEquals('', G[1, 2], 'empty cells last');
    G.SortBy(1, True);
    AssertEquals('10', G[1, 0]);
    G.DeleteRow(0);
    AssertEquals(2, G.RowCount);
    G.InsertRow(0, ['Can']);
    AssertEquals('Can', G[0, 0]);
    AssertEquals('', G[1, 0], 'missing values are empty');
    G[1, 0] := '3';
    AssertEquals('3', G.RowValues[0][1]);
    AssertEquals(1, G.FindRow(0, 'Person 10'));
    G.Clear;
    AssertEquals(0, G.RowCount);
    AssertEquals(-1, G.Row);
  finally
    G.Free;
  end;
end;

procedure TUITests.GridLoadsJson;
var
  G: TGrid;
  A: TJSONArray;
begin
  G := TGrid.Create(nil);
  A := TJSONArray(ParseJson('[{"id": 1, "name": "Ayşe", "note": null}, {"id": 2, "name": "Ali"}]'));
  try
    G.LoadJson(A);
    AssertEquals(3, G.ColCount, 'columns from the first row');
    AssertEquals('Ayşe', G[1, 0]);
    AssertEquals('', G[2, 0]);
    G.Free;
    G := TGrid.Create(nil);
    G.AddColumn('Name').Field := 'name';
    G.LoadJson(A);
    AssertEquals(1, G.ColCount);
    AssertEquals('Ali', G[0, 1]);
    A.Free;
    A := G.ToJson;
    AssertEquals('[{"name":"Ayşe"},{"name":"Ali"}]', ToJson(A));
  finally
    G.Free;
    A.Free;
  end;
end;

procedure TUITests.TreeFromLines;
var
  Root: TPFormNode;
  F: TForm;
  T: TTreeView;
begin
  Root := ParsePForm('object F: TForm'#10'  object T: TTreeView'#10 +
    '    Items = (''A'', ''  B'', ''    C'', ''  D'', ''E'')'#10'  end'#10'end');
  F := TForm.Create(nil);
  try
    BuildForm(F, Root);
    T := TTreeView(F.FindComponent('T'));
    AssertEquals(2, T.Count);
    AssertEquals(2, T.TopNodes[0].Count);
    AssertEquals('C', T.TopNodes[0][0][0].Text);
    AssertEquals('A/B/C', T.FindNode('A/B/C').Path);
    AssertTrue(T.FindNode('A/X') = nil);
    T.Selected := T.FindNode('A/B/C');
    AssertTrue(T.TopNodes[0].Expanded, 'selecting opens the parents');
    AssertEquals('A/B/C', T.Text);
    T.TopNodes[1].AddChild('F');
    AssertEquals('A'#10'  B'#10'    C'#10'  D'#10'E'#10'  F', T.Items.Text.TrimRight.Replace(#13, ''));
  finally
    F.Free;
    Root.Free;
  end;
end;

procedure TUITests.ThemeValues;
begin
  try
    AssertTrue(SetThemeValue('accent', '#0E9F6E'));
    AssertEquals(Cardinal(RGB($0E, $9F, $6E)), Cardinal(Theme.Accent));
    AssertTrue(Theme.AccentHover <> Theme.Accent, 'the hover shade follows');
    AssertTrue(SetThemeValue('radius', '12'));
    AssertEquals(12, Theme.Radius);
    AssertFalse(SetThemeValue('radius', 'big'));
    AssertFalse(SetThemeValue('nothing', '#fff'));
    AssertFalse(SetThemeValue('accent', 'green'));
  finally
    UseDarkTheme(False);
  end;
end;

type
  TPerson = class(TPersistent)
  private
    FFullName: string;
    FAge: Integer;
    FActive: Boolean;
  published
    property FullName: string read FFullName write FFullName;
    property Age: Integer read FAge write FAge;
    property Active: Boolean read FActive write FActive;
  end;

procedure TUITests.BindingNames;
begin
  AssertEquals('name', FieldFromControlName('NameEdit'));
  AssertEquals('full_name', FieldFromControlName('FullNameEdit'));
  AssertEquals('active', FieldFromControlName('ActiveCheckBox'));
  AssertEquals('city', FieldFromControlName('CityCombo'));
  AssertEquals('notes', FieldFromControlName('Notes'));
end;

procedure TUITests.BindingLoadsAndSaves;
var
  Root: TPFormNode;
  F: TForm;
  B: TDataBinding;
  O: TJSONObject;
  P: TPerson;
begin
  Root := ParsePForm('object F: TForm'#10 +
    '  object FullNameEdit: TEdit'#10'  end'#10 +
    '  object AgeEdit: TEdit'#10'  end'#10 +
    '  object ActiveCheck: TCheckBox'#10'  end'#10 +
    '  object CityCombo: TComboBox'#10'    Items = (''Bursa'', ''İzmir'')'#10'  end'#10 +
    '  object B: TDataBinding'#10'    Fields = (''FullNameEdit'', ''AgeEdit'', ''ActiveCheck'', ''CityCombo=town'')'#10'  end'#10 +
    'end');
  F := TForm.Create(nil);
  O := nil;
  P := TPerson.Create;
  try
    BuildForm(F, Root);
    B := TDataBinding(F.FindComponent('B'));
    O := ParseJsonObject('{"full_name": "Ayşe", "age": 34, "active": true, "town": "İzmir", "id": 7}');
    B.Load(O);
    AssertEquals('Ayşe', TEdit(F.FindComponent('FullNameEdit')).Text);
    AssertEquals('34', TEdit(F.FindComponent('AgeEdit')).Text);
    AssertTrue(TCheckBox(F.FindComponent('ActiveCheck')).Checked);
    AssertEquals(1, TComboBox(F.FindComponent('CityCombo')).ItemIndex);
    AssertFalse(B.Modified);
    TEdit(F.FindComponent('AgeEdit')).Text := '35';
    AssertTrue(B.Modified);
    B.Save(O);
    AssertEquals('{"id":7,"full_name":"Ayşe","age":35,"active":true,"town":"İzmir"}', ToJson(O),
      'numbers stay numbers, other fields stay');
    B.Fields.Delete(3);     { TPerson has no town }
    B.SaveObject(P);
    AssertEquals('Ayşe', P.FullName);
    AssertEquals(35, P.Age);
    AssertTrue(P.Active);
    B.Clear;
    AssertEquals('', TEdit(F.FindComponent('FullNameEdit')).Text);
    P.FullName := 'Ali';
    B.LoadObject(P);
    AssertEquals('Ali', TEdit(F.FindComponent('FullNameEdit')).Text);
  finally
    P.Free;
    O.Free;
    F.Free;
    Root.Free;
  end;
end;

initialization
  RegisterTests(TUITests);
end.
