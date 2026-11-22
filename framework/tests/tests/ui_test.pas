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
    procedure PhoneKeyboardEditsTheCopy;
    procedure PhoneKeyboardKeepsTheEditsRules;
    procedure Utf16Positions;
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
    procedure TextThatWrapsInARowGetsItsHeight;
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
    procedure FreeLayoutLikeDelphi;
    procedure CanvasScales;
    procedure OnlyWhatChangedIsRepainted;
    procedure ATooNarrowRowShrinksWhatGrows;
    procedure GridColumnsOfNumbersDatesAndChecks;
    procedure GridFilterAndCsv;
    procedure AFlowWrapsItsChildren;
    procedure BindingRulesCheckValues;
    procedure GridRowsAndSorting;
    procedure GridLoadsJson;
    procedure GridLongTextIsQuick;
    procedure TreeFromLines;
    procedure ThemeValues;
    procedure BindingNames;
    procedure BackgroundImageAndButtonColor;
    procedure BindingLoadsAndSaves;
    procedure MaxContentWidthCenters;
    procedure ArrowsMoveFocusLikeARemote;
    procedure ViewsForScreenClasses;
    procedure EditHasCutCopyPaste;
    procedure ComboTouchPick;
    procedure DialogsWithoutWaiting;
    procedure FormShownWithoutWaiting;
    procedure FileDialogWithoutWaiting;
    procedure ToastShowsAndGoes;
    procedure DrawerOpensAndCloses;
    procedure PullDownToRefresh;
    procedure BottomTabs;
    procedure FilesDropped;
    procedure RowsMovedByGrip;
    procedure StateKeptWhenStopped;
    procedure MaskEditShape;
    procedure ChartDrawsAndClicks;
  private
    FChartHit: string;
    procedure ChartHit(Sender: TObject; SeriesIndex, ItemIndex: Integer);
  private
    FAnswers: string;
    FClicks: Integer;
    procedure CountClick(Sender: TObject);
    procedure GotFiles(Sender: TObject; const Files: TStringArray);
    procedure GotMove(Sender: TObject; FromIndex, ToIndex: Integer);
    procedure SavingState(Sender: TObject);
    procedure GotModal(Sender: TObject; ModalResult: Integer);
    procedure GotInput(Sender: TObject; Ok: Boolean; const Value: string);
    procedure GotFile(Sender: TObject; Ok: Boolean; const FileName: string);
    function TopButton(const Name: string): TButton;
  end;

  { a form class of its own: its .pform and views are registered by name }
  TViewTestForm = class(TForm)
  end;

implementation

uses
  StrUtils, Pastel.PForm, Pastel.Forms, Pastel.Controls, Pastel.Menus, Pastel.Grids, Pastel.Binding, fpjson, Pastel.Json,
  Pastel.Lang, Pastel.Dialogs, Pastel.Inputs, Pastel.Charts;

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

{ the phone's keyboard (Android) sends the whole text and selection after each change }
procedure TUITests.PhoneKeyboardEditsTheCopy;
var
  E: TEdit;
  Changes: Integer;
begin
  E := NewEdit(Form);
  E.SetFocus;
  E.Text := 'Merhaba';
  { a word being composed, then its correction }
  E.ImeChange('Merhaba dün', 11, 11, 8, 11);
  AssertEquals('Merhaba dün', E.Text);
  AssertEquals(11, E.SelStart);
  E.ImeChange('Merhaba dünya', 14, 14, 8, 14);
  AssertEquals('Merhaba dünya', E.Text);
  AssertEquals(14, E.SelStart, 'bytes: ü is two');
  E.ImeChange('Merhaba Dünya ', 15, 15, -1, -1);
  AssertEquals('Merhaba Dünya ', E.Text, 'the keyboard corrected the word');
  { an emoji, then Backspace over it }
  E.ImeChange('Merhaba Dünya 👋', 19, 19, -1, -1);
  AssertEquals('Merhaba Dünya 👋', E.Text);
  E.ImeChange('Merhaba Dünya ', 15, 15, -1, -1);
  AssertEquals('Merhaba Dünya ', E.Text);
  { a selection made by the keyboard (select all) }
  E.ImeChange('Merhaba Dünya ', 0, 15, -1, -1);
  AssertEquals('Merhaba Dünya ', E.SelText);
  { one undo step for the whole typing }
  Changes := 0;
  while E.CanUndo and (Changes < 20) do
  begin
    E.Undo;
    Inc(Changes);
  end;
  AssertEquals('Merhaba', E.Text, 'undo goes back to before the keyboard');
end;

procedure TUITests.PhoneKeyboardKeepsTheEditsRules;
var
  E: TEdit;
  M: TMaskEdit;
  Changed: Integer;
begin
  E := NewEdit(Form);
  E.MaxLength := 5;
  E.SetFocus;
  E.ImeChange('abcdefgh', 8, 8, -1, -1);
  AssertEquals('abcde', E.Text, 'MaxLength: the rest is not taken (the copy is put right)');
  E.ReadOnly := True;
  E.ImeChange('xyz', 3, 3, -1, -1);
  AssertEquals('abcde', E.Text, 'read only');
  M := TMaskEdit.Create(Form);
  M.Parent := Form;
  M.EditMask := '(000) 000 00 00';
  M.SetFocus;
  { the keyboard's copy of a mask: it typed a letter and a digit at the first place }
  M.ImeChange('(a5___) ___ __ __', 3, 3, -1, -1);
  AssertEquals('(5__) ___ __ __', M.Text, 'only the digit, in its place');
  Changed := Length(M.Text);
  AssertEquals(15, Changed);
end;

procedure TUITests.Utf16Positions;
begin
  AssertEquals(0, Utf16ToByteIndex('aü👋b', 0));
  AssertEquals(1, Utf16ToByteIndex('aü👋b', 1));
  AssertEquals(3, Utf16ToByteIndex('aü👋b', 2), 'ü: two bytes, one unit');
  AssertEquals(7, Utf16ToByteIndex('aü👋b', 4), '👋: four bytes, two units');
  AssertEquals(8, Utf16ToByteIndex('aü👋b', 5));
  AssertEquals(8, Utf16ToByteIndex('aü👋b', 99), 'past the end: the end');
  AssertEquals(2, ByteToUtf16Index('aü👋b', 3));
  AssertEquals(4, ByteToUtf16Index('aü👋b', 7));
  AssertEquals(5, ByteToUtf16Index('aü👋b', 8));
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

{ a card that grows beside a fixed spacer: its text wraps at the width it
  gets, and the card is as high as its lines (not as one line at the row's
  whole width) }
procedure TUITests.TextThatWrapsInARowGetsItsHeight;
var
  R: TRow;
  C: TCard;
  S: TSpacer;
  L: TLabel;
  W, H, One: Integer;
begin
  R := TRow.Create(Form);
  R.Parent := Form;
  R.Align := aiCenter;
  C := TCard.Create(Form);
  C.Grow := 1;
  C.Parent := R;
  S := TSpacer.Create(Form);
  S.Grow := 0;
  S.Width := 200;
  S.Parent := R;
  L := TLabel.Create(Form);
  L.WordWrap := True;
  L.Text := 'Hello! I am the assistant of the cafe. Ask me about the menu.';
  L.Parent := C;
  L.GetSize(0, W, One);
  { a row just wide enough for the text on one line, without the spacer }
  R.GetSize(W + 10, W, H);
  AssertTrue(H >= 2 * One, 'measured at the width the card gets: two lines');
  Render;
  AssertTrue(C.Bounds.H >= L.Bounds.H, 'the card holds its text');
  AssertTrue(L.Bounds.H >= 2 * One, 'drawn on two lines');
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

procedure TUITests.FreeLayoutLikeDelphi;
var
  Root: TPFormNode;
  F: TForm;
  Ok, Memo, Bar, Fill: TControl;
begin
  Root := ParsePForm('object F: TForm'#10'  Layout = Free'#10'  Width = 400'#10'  Height = 300'#10 +
    '  object Bar: TPanel'#10'    Dock = Top'#10'    Height = 40'#10'  end'#10 +
    '  object Memo: TMemo'#10'    Left = 10'#10'    Top = 50'#10'    Width = 380'#10'    Height = 200'#10 +
    '    Anchors = [Left, Top, Right, Bottom]'#10'  end'#10 +
    '  object Ok: TButton'#10'    Text = ''OK'''#10'    Left = 300'#10'    Top = 260'#10'    Anchors = [Right, Bottom]'#10'  end'#10 +
    '  object Side: TPanel'#10'    Dock = Fill'#10'    Visible = False'#10'  end'#10 +
    'end');
  F := TForm.Create(nil);
  try
    BuildForm(F, Root);
    Ok := TControl(F.FindComponent('Ok'));
    Memo := TControl(F.FindComponent('Memo'));
    Bar := TControl(F.FindComponent('Bar'));
    Fill := TControl(F.FindComponent('Side'));
    AssertTrue(TControl(F.FindComponent('Memo')).Anchors = [akLeft, akTop, akRight, akBottom], 'a set in the .pform');
    F.Layout(400, 300);
    AssertEquals(300, Ok.Bounds.X, 'where Left says');
    AssertEquals(260, Ok.Bounds.Y);
    AssertTrue(Ok.Bounds.W < 200, 'its own size, not the width of the form');
    AssertEquals(0, Bar.Bounds.Y, 'docked at the top');
    AssertEquals(400, Bar.Bounds.W, 'as wide as the form');
    F.Layout(500, 400);
    AssertEquals(400, Ok.Bounds.X, 'anchored right and bottom: it moves with the corner');
    AssertEquals(360, Ok.Bounds.Y);
    AssertEquals(10, Memo.Bounds.X, 'anchored on all sides: it grows');
    AssertEquals(480, Memo.Bounds.W);
    AssertEquals(300, Memo.Bounds.H);
    AssertFalse(Fill.Visible);
  finally
    F.Free;
    Root.Free;
  end;
  try
    ParsePForm('object F: TForm'#10'  Anchors = [Left, 3]'#10'end').Free;
    Fail('a number in a set');
  except
    on E: EPFormError do ;
  end;
end;

procedure TUITests.BackgroundImageAndButtonColor;
var
  Pic: TCanvas32;
  FileName: string;
  B: TButton;
begin
  FileName := GetTempDir + 'pastel-bg-test.png';
  Pic := TCanvas32.Create;
  try
    Pic.SetSize(20, 10);
    Pic.Clear(RGB(0, 128, 0));
    Pic.SaveToPNG(FileName);
  finally
    Pic.Free;
  end;
  try
    Form.BackgroundImage := FileName;
    AssertEquals(Ord(ifCover), Ord(Form.BackgroundFit), 'it fills the form by default');
    B := TButton.Create(Form);
    B.Parent := Form;
    B.Text := 'Buy';
    B.Color := RGB(200, 0, 0);
    Render;
    AssertEquals(Cardinal(RGB(0, 128, 0)), Cardinal(Canvas.GetPixel(395, 295)), 'the picture is behind the controls');
    AssertEquals(Cardinal(RGB(200, 0, 0)), Cardinal(Canvas.GetPixel(B.Bounds.X + 3, B.Bounds.Y + B.Bounds.H div 2)),
      'the button has its own color');
    Form.BackgroundImage := 'no-such-picture.png';
    Render;     { a missing picture is not drawn and does not stop the form }
    AssertTrue(Canvas.GetPixel(395, 295) <> RGB(0, 128, 0));
  finally
    SysUtils.DeleteFile(FileName);
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

procedure TUITests.ATooNarrowRowShrinksWhatGrows;
var
  Row: TRow;
  E: TEdit;
  B, B2: TButton;
  W: TStringList;
begin
  Row := TRow.Create(Form);
  Row.Parent := Form;
  Row.Name := 'Bar';
  E := TEdit.Create(Form);
  E.Parent := Row;
  E.Grow := 1;                     { wants 200 }
  B := TButton.Create(Form);
  B.Parent := Row;
  B.Text := 'Search';
  Form.Padding := 0;
  Form.Layout(260, 100);
  AssertTrue(B.Bounds.X + B.Bounds.W <= 260, 'the button is inside the window');
  AssertTrue(E.Bounds.W < 200, 'the edit gave some of its width');
  { when even that is not enough, tools hear of it }
  B2 := TButton.Create(Form);
  B2.Parent := Row;
  B2.Text := 'Another long button';
  W := TStringList.Create;
  LayoutWarnings := W;
  try
    Form.Layout(260, 100);
    AssertEquals(1, W.Count);
    AssertEquals('Bar', W.Names[0]);
    AssertEquals(MinShrink, E.Bounds.W, 'not narrower than MinShrink');
  finally
    LayoutWarnings := nil;
    W.Free;
  end;
end;

procedure TUITests.OnlyWhatChangedIsRepainted;
var
  E: TEdit;
  B: TButton;
  Full: TCanvas32;
  X, Y: Integer;
begin
  E := TEdit.Create(Form);
  E.Parent := Form;
  B := TButton.Create(Form);
  B.Parent := Form;
  B.Text := 'Go';
  Render;
  AssertFalse(NeedsRepaint or NeedsPartialRepaint, 'all painted');
  E.SetFocus;
  E.Text := 'hello';
  AssertFalse(NeedsRepaint, 'typing does not repaint the window');
  AssertTrue(NeedsPartialRepaint, 'only the edit');
  AssertTrue((DirtyArea.Y < E.Bounds.Y) and (DirtyArea.Y + DirtyArea.H < B.Bounds.Y + B.Bounds.H),
    'the edit, not the button');
  Form.RenderArea(Canvas, DirtyArea);
  Full := TCanvas32.Create;
  try
    Full.SetSize(400, 300);
    Form.Render(Full);
    for Y := 0 to 299 do
      for X := 0 to 399 do
        if Canvas.GetPixel(X, Y) <> Full.GetPixel(X, Y) then
          Fail(Format('pixel %d,%d differs from a full repaint', [X, Y]));
  finally
    Full.Free;
  end;
  InvalidateArea(RectI(0, 0, 10, 10));
  InvalidateArea(RectI(50, 60, 10, 10));
  AssertEquals(60, DirtyArea.W, 'both areas');
  AssertEquals(70, DirtyArea.H);
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

procedure TUITests.GridLongTextIsQuick;
var
  G: TGrid;
  Long: string;
  I: Integer;
  T0: QWord;
begin
  { a database's text column: 100 KB in each cell, and lines }
  Long := DupeString('lorem ipsum dolor sit amet ', 4000);
  G := TGrid.Create(Form);
  G.Parent := Form;
  G.Grow := 1;
  G.AddColumn('Id', 50);
  G.AddColumn('Body', 200);
  for I := 1 to 200 do
    G.AddRow([IntToStr(I), Long]);
  G.AddRow(['x', 'first line'#10'second line']);
  T0 := GetTickCount64;
  Render;
  Render;
  AssertTrue(GetTickCount64 - T0 < 1500, Format('painted in %d ms', [GetTickCount64 - T0]));
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

procedure TUITests.GridColumnsOfNumbersDatesAndChecks;
var
  G: TGrid;
  A: TJSONArray;
  O: TJSONArray;
begin
  UseLanguage('en');
  G := TGrid.Create(nil);
  A := TJSONArray(ParseJson('[{"total": 1380.6, "on": "2026-11-03", "paid": true}, ' +
    '{"total": 250, "on": "2026-11-04 09:30", "paid": false}, {"total": 99.5, "on": "2025-01-02", "paid": true}]'));
  try
    G.AddColumn('Total').Field := 'total';
    G.Columns[0].Kind := gkMoney;
    G.AddColumn('On').Field := 'on';
    G.Columns[1].Kind := gkDate;
    G.AddColumn('Paid').Field := 'paid';
    G.Columns[2].Kind := gkCheck;
    G.LoadJson(A);
    AssertEquals('1380.6', G.Cells[0, 0], 'the cell keeps the value');
    AssertEquals('1,380.60', G.Columns[0].DisplayText(G.Cells[0, 0]), 'shown as money');
    AssertTrue(G.Columns[0].Alignment = taRight, 'numbers at the right');
    AssertEquals('11/3/2026', G.Columns[1].DisplayText(G.Cells[1, 0]));
    AssertEquals('11/4/2026 09:30', G.Columns[1].DisplayText(G.Cells[1, 1]));
    G.SortBy(0);
    AssertEquals('99.5', G.Cells[0, 0], 'numbers sort as numbers');
    G.SortBy(1);
    AssertEquals('2025-01-02', G.Cells[1, 0], 'dates sort as dates');
    G.Editable := True;
    G.ToggleCheck(2, 0);
    AssertEquals('0', G.Cells[2, 0]);
    O := G.ToJson;
    try
      AssertEquals('[{"total":99.5,"on":"2025-01-02","paid":false},{"total":1380.6,"on":"2026-11-03","paid":true},' +
        '{"total":250,"on":"2026-11-0409:30","paid":false}]', StringReplace(O.AsJSON, ' ', '', [rfReplaceAll]),
        'numbers and true/false as such');
    finally
      O.Free;
    end;
    Form.Width := 400;
    G.Parent := Form;
    G.Height := 200;
    Render;                 { check boxes and icons are drawn without trouble }
  finally
    A.Free;
  end;
end;

procedure TUITests.GridFilterAndCsv;
var
  G: TGrid;
begin
  G := TGrid.Create(nil);
  try
    G.AddColumn('Name');
    G.AddColumn('Phone');
    G.AddRow(['Ayşe Yılmaz', '0532']);
    G.AddRow(['Ali Can', '0533']);
    G.AddRow(['Zeynep "Z" Kaya', '0544']);
    G.Filter('ayşe');
    AssertEquals(1, G.RowCount);
    G.Cells[1, 0] := '0500';
    G.Filter('053');
    AssertEquals(1, G.RowCount, 'Ali; Ayşe has 0500 now');
    G.Filter('');
    AssertEquals(3, G.RowCount);
    AssertEquals('0500', G.Cells[1, 0], 'changes made while filtered stay');
    AssertEquals('Name;Phone'#13#10'Ayşe Yılmaz;0500'#13#10'Ali Can;0533'#13#10'"Zeynep ""Z"" Kaya";0544'#13#10,
      G.ToCsv(';'));
  finally
    G.Free;
  end;
end;

procedure TUITests.AFlowWrapsItsChildren;
var
  F: TFlow;
  I: Integer;
  B: TButton;
begin
  F := TFlow.Create(Form);
  F.Parent := Form;
  for I := 1 to 6 do
  begin
    B := TButton.Create(Form);
    B.Text := 'Button ' + IntToStr(I);
    B.Width := 120;
    B.Parent := F;
  end;
  Form.Layout(300, 300);
  AssertEquals(F.Children[0].Bounds.Y, F.Children[1].Bounds.Y, 'two in the first line');
  AssertTrue(F.Children[2].Bounds.Y > F.Children[1].Bounds.Y, 'the third on the next line');
  AssertEquals(F.Children[0].Bounds.X, F.Children[2].Bounds.X, 'from the left again');
  AssertTrue(F.Bounds.H >= 3 * F.Children[0].Bounds.H, 'three lines high');
end;

procedure TUITests.BindingRulesCheckValues;
var
  B: TDataBinding;
  NameEdit, EmailEdit, AgeEdit, CodeEdit: TEdit;
  Problem: TLabel;

  function NewEdit(const N: string): TEdit;
  begin
    Result := TEdit.Create(Form);
    Result.Name := N;
    Result.Parent := Form;
  end;

begin
  UseLanguage('en');
  NameEdit := NewEdit('NameEdit');
  EmailEdit := NewEdit('EmailEdit');
  AgeEdit := NewEdit('AgeEdit');
  CodeEdit := NewEdit('CodeEdit');
  Problem := TLabel.Create(Form);
  Problem.Parent := Form;
  B := TDataBinding.Create(Form);
  B.Bind(NameEdit);
  B.Bind(EmailEdit);
  B.Bind(AgeEdit);
  B.Bind(CodeEdit);
  B.Rules.Text := 'NameEdit=required, min 2' + LineEnding + 'EmailEdit=email' + LineEnding +
    'AgeEdit=number, range 0..120' + LineEnding + 'CodeEdit=pattern ^[A-Z]{2}\d{1,3}$';
  B.ErrorLabel := Problem;
  AssertFalse(B.Validate, 'the name is missing');
  AssertEquals('Fill this in', NameEdit.Error);
  AssertEquals('Fill this in', Problem.Text);
  AssertEquals('Fill this in', NameEdit.Hint, 'as its tooltip');
  NameEdit.Text := 'Ayşe';
  EmailEdit.Text := 'not-an-address';
  AgeEdit.Text := '130';
  CodeEdit.Text := 'tr12';
  AssertFalse(B.Validate);
  AssertEquals('', NameEdit.Error);
  AssertEquals('This is not an e-mail address', EmailEdit.Error);
  AssertEquals('Give a number from 0 to 120', AgeEdit.Error);
  AssertEquals('This is not in the right form', CodeEdit.Error);
  AssertEquals(3, B.Problems.Count);
  EmailEdit.Text := '';
  AgeEdit.Text := '34';
  CodeEdit.Text := 'TR12';
  AssertTrue(B.Validate, 'empty values are only checked by required');
  AssertEquals('', Problem.Text);
  UseLanguage('tr');
  NameEdit.Text := '';
  B.Validate;
  AssertEquals('Bunu doldurun', NameEdit.Error, 'in the language');
  UseLanguage('en');
end;

procedure TUITests.MaxContentWidthCenters;
var
  E: TEdit;
begin
  Form.Padding := 10;
  Form.MaxContentWidth := 200;
  E := NewEdit(Form);
  Render;
  AssertEquals(200, E.Bounds.W, 'the content is at most 200 wide');
  AssertEquals(100, E.Bounds.X, 'in the middle of the 400 wide form');
  Form.MaxContentWidth := 0;
  Render;
  AssertEquals(380, E.Bounds.W, 'all the width without it');
end;

procedure TUITests.ArrowsMoveFocusLikeARemote;
var
  Row: TRow;
  A, B, C: TButton;
  E: TEdit;

  function Btn(Parent: TControl; const Name: string): TButton;
  begin
    Result := TButton.Create(Form);
    Result.Name := Name;
    Result.Text := Name;
    Result.Parent := Parent;
  end;

begin
  { A  B / the edit / C }
  Row := TRow.Create(Form);
  Row.Parent := Form;
  A := Btn(Row, 'A');
  B := Btn(Row, 'B');
  E := NewEdit(Form);
  C := Btn(Form, 'C');
  Render;
  ArrowKeysMoveFocus := True;
  try
    Key(KEY_DOWN);
    AssertTrue(Form.Focused = A, 'the first press chooses the first control');
    Key(KEY_RIGHT);
    AssertTrue(Form.Focused = B, 'right: the button beside it');
    Key(KEY_DOWN);
    AssertTrue(Form.Focused = E, 'down: the edit below');
    Key(KEY_DOWN);
    AssertTrue(Form.Focused = C, 'down again: the button below the edit');
    Key(KEY_DOWN);
    AssertTrue(Form.Focused = C, 'nothing further down: it stays');
    Key(KEY_UP);
    Key(KEY_UP);
    AssertTrue(Form.Focused = B, 'up twice: the button above nearest to the middle of the edit');
    Key(KEY_LEFT);
    AssertTrue(Form.Focused = A);
    AssertTrue(Form.FocusVisible, 'the focus is shown');
  finally
    ArrowKeysMoveFocus := False;
  end;
  Key(KEY_RIGHT);
  AssertTrue(Form.Focused = A, 'without a remote the arrows do not move the focus');
  if (E = nil) or (C = nil) then ;
end;

procedure TUITests.ViewsForScreenClasses;
const
  Src = 'object ViewTest: TViewTestForm' + LineEnding +
    '  Padding = 8' + LineEnding +
    '  object Heading: TLabel' + LineEnding +
    '    Text = ''Hi''' + LineEnding +
    '    FontSize = 20' + LineEnding +
    '  end' + LineEnding +
    '  object Side: TLabel' + LineEnding +
    '    Visible = False' + LineEnding +
    '  end' + LineEnding +
    'end';
  Tablet = 'object ViewTest: TViewTestForm' + LineEnding +
    '  Padding = 32' + LineEnding +
    '  MaxContentWidth = 500' + LineEnding +
    '  object Heading: TLabel' + LineEnding +
    '    FontSize = 30' + LineEnding +
    '  end' + LineEnding +
    '  object Side: TLabel' + LineEnding +
    '    Visible = True' + LineEnding +
    '  end' + LineEnding +
    'end';
var
  F: TViewTestForm;
  Root: TPFormNode;
  T, S: TLabel;
begin
  RegisterFormSource('TViewTestForm', Src, '');
  RegisterFormView('TViewTestForm', 'tablet', Tablet, '');
  F := TViewTestForm.Create(nil);
  Root := ParsePForm(Src);
  try
    BuildForm(F, Root);
    T := TLabel(F.FindControl('Heading'));
    S := TLabel(F.FindControl('Side'));
    F.SetScreenClass(scPhone);
    AssertEquals('', F.View, 'no phone view: the form as it is');
    AssertEquals(20, T.FontSize);
    F.SetScreenClass(scTablet);
    AssertEquals('tablet', F.View);
    AssertEquals(30, T.FontSize, 'the tablet view''s values');
    AssertEquals(32, F.Padding);
    AssertEquals(500, F.MaxContentWidth);
    AssertTrue(S.Visible, 'shown on tablets');
    AssertEquals('Hi', T.Text, 'what the view does not say stays');
    F.SetScreenClass(scTV);
    AssertEquals('tablet', F.View, 'a TV without a view of its own uses the tablet''s');
    F.SetScreenClass(scDesktop);
    AssertEquals('', F.View);
    AssertEquals(20, T.FontSize, 'back to the form''s values');
    AssertEquals(8, F.Padding);
    AssertEquals(0, F.MaxContentWidth, 'also those the form did not set');
    AssertFalse(S.Visible);
  finally
    Root.Free;
    F.Free;
  end;
end;

procedure TUITests.GotModal(Sender: TObject; ModalResult: Integer);
begin
  FAnswers := FAnswers + ModalResultCaption(ModalResult) + ';';
end;

procedure TUITests.GotInput(Sender: TObject; Ok: Boolean; const Value: string);
begin
  FAnswers := FAnswers + BoolToStr(Ok, 'ok', 'no') + ':' + Value + ';';
end;

procedure TUITests.GotFile(Sender: TObject; Ok: Boolean; const FileName: string);
begin
  FAnswers := FAnswers + BoolToStr(Ok, 'ok', 'no') + ':' + ExtractFileName(FileName) + ';';
end;

function TUITests.TopButton(const Name: string): TButton;
begin
  AssertTrue(Form.PopupCount > 0, 'a dialog is open');
  Result := TButton(Form.TopPopup.FindComponent(Name));
  AssertTrue(Result <> nil, Name);
end;

procedure TUITests.DialogsWithoutWaiting;
var
  E: TEdit;
begin
  MainForm := Form;
  try
    FAnswers := '';
    Ask('Delete?', @GotModal);
    AssertEquals('', FAnswers, 'returns at once');
    Click(TopButton('YesButton'));
    AssertEquals('Yes;', FAnswers);
    ProcessReleases;
    AssertEquals(0, Form.PopupCount, 'closed and freed');
    MessageDlg('Save?', 'Notes', [mrYes, mrNo, mrCancel], @GotModal);
    Key(KEY_ESCAPE);
    AssertEquals('Yes;Cancel;', FAnswers, 'Escape is Cancel');
    ShowMessage('Saved', TModalDoneEvent(nil));
    Click(TopButton('OkButton'));
    ProcessReleases;
    InputQuery('Name', 'Your name:', 'Ada', @GotInput);
    E := TEdit(Form.TopPopup.FindComponent('InputEdit'));
    E.Text := 'Grace';
    Click(TopButton('OkButton'));
    InputQuery('Name', '', 'x', @GotInput);
    Click(TopButton('CancelButton'));
    AssertEquals('Yes;Cancel;ok:Grace;no:;', FAnswers);
    ProcessReleases;
    AssertEquals(0, Form.PopupCount);
  finally
    MainForm := nil;
  end;
end;

procedure TUITests.FormShownWithoutWaiting;
var
  Main, Dlg: TForm;
  B: TButton;
  Closes: Integer;
begin
  Main := Form;
  MainForm := Main;
  Dlg := TForm.Create(nil);
  try
    Dlg.Title := 'Appointment';
    B := TButton.Create(Dlg);
    B.Name := 'SaveButton';
    B.ModalResult := mrOk;
    B.Parent := Dlg;
    FAnswers := '';
    Dlg.ShowModal(@GotModal);
    AssertEquals('', FAnswers, 'returns at once');
    AssertTrue(Dlg.ParentPopup <> nil, 'shown in a dialog');
    Click(B);
    AssertEquals('OK;', FAnswers);
    AssertTrue(Dlg.Parent = nil, 'the form left the dialog');
    ProcessReleases;
    AssertEquals(0, Main.PopupCount);
    { again: the same form can be shown once more }
    Dlg.ShowModal(@GotModal);
    Dlg.ModalResult := mrCancel;
    AssertEquals('OK;Cancel;', FAnswers);
    ProcessReleases;
    Closes := Main.PopupCount;
    AssertEquals(0, Closes);
  finally
    MainForm := nil;
    Dlg.Free;
  end;
end;

procedure TUITests.FileDialogWithoutWaiting;
var
  Dir: string;
  N: TEdit;
begin
  MainForm := Form;
  UseNativeDialogs := False;
  Dir := GetTempDir + 'pastel-filedlg' + PathDelim;
  ForceDirectories(Dir);
  with TStringList.Create do
  try
    Text := 'x';
    SaveToFile(Dir + 'a.txt');
  finally
    Free;
  end;
  try
    FAnswers := '';
    OpenFileDialog(Dir, 'Text|*.txt', 'Open', @GotFile);
    AssertEquals('', FAnswers, 'returns at once');
    N := TEdit(Form.TopPopup.FindComponent('FileNameEdit'));
    N.Text := 'a.txt';
    TopButton('OkButton').Click;      { the dialog is wider than the test's window }
    AssertEquals('ok:a.txt;', FAnswers);
    ProcessReleases;
    SelectFolderDialog(Dir, 'Folder', @GotFile);
    TopButton('CancelButton').Click;
    AssertEquals('ok:a.txt;no:;', FAnswers);
    ProcessReleases;
    AssertEquals(0, Form.PopupCount);
  finally
    DeleteFile(Dir + 'a.txt');
    RemoveDir(Dir);
    UseNativeDialogs := True;
    MainForm := nil;
  end;
end;

procedure TUITests.CountClick(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TUITests.ToastShowsAndGoes;
var
  B: TButton;
  Clicked: Integer;
begin
  MainForm := Form;
  try
    B := TButton.Create(Form);
    B.Parent := Form;
    B.Height := 260;            { under the toast too }
    B.OnClick := @CountClick;
    FClicks := 0;
    ShowToast('Saved');
    AssertEquals('Saved', Form.ToastText);
    Render;
    Click(B);
    Clicked := FClicks;
    AssertEquals(1, Clicked, 'a click goes through the toast');
    Sleep(2100);
    ProcessTimers(GetTickCount64);
    AssertEquals('', Form.ToastText, 'gone after a moment');
  finally
    MainForm := nil;
  end;
end;

procedure TUITests.DrawerOpensAndCloses;
const
  Src = 'object F: TForm'#10'  object MenuButton: TButton'#10'    Text = ''Menu'''#10'  end'#10 +
    '  object Menu: TDrawer'#10'    object HomeItem: TButton'#10'      Text = ''Home'''#10'    end'#10'  end'#10 +
    '  object Sheet: TBottomSheet'#10'    object Pick: TButton'#10'      Text = ''Pick'''#10'    end'#10'  end'#10 +
    '  object Below: TLabel'#10'    Text = ''x'''#10'  end'#10'end';
var
  Root: TPFormNode;
  F: TForm;
  Menu: TDrawer;
  Sheet: TBottomSheet;
  Item: TButton;
  Below: TControl;
begin
  F := TForm.Create(nil);
  try
    Root := ParsePForm(Src);
    BuildForm(F, Root);
    Root.Free;
    Menu := TDrawer(F.FindComponent('Menu'));
    Sheet := TBottomSheet(F.FindComponent('Sheet'));
    Item := TButton(F.FindComponent('HomeItem'));
    Below := TControl(F.FindComponent('Below'));
    F.Layout(360, 640);
    AssertFalse(Menu.Visible, 'not on the form until Open');
    AssertTrue(Below.Bounds.Y < 120, 'takes no room on the form');
    Menu.Open;
    F.Layout(360, 640);
    AssertTrue(Menu.IsOpen);
    AssertEquals(0, Menu.Bounds.X, 'from the left side');
    AssertEquals(640, Menu.Bounds.H, 'the whole height');
    AssertTrue(Menu.Bounds.W < 360, 'not the whole width');
    AssertTrue(Item.Bounds.X < Menu.Bounds.W, 'its items in it');
    { a tap beside it closes it }
    F.HandleMouseDown(350, 300);
    F.HandleMouseUp(350, 300);
    AssertFalse(Menu.IsOpen, 'closed by a tap beside it');
    Menu.Toggle;
    AssertTrue(Menu.IsOpen);
    F.HandleKeyDown(KEY_ESCAPE, False, False);
    AssertFalse(Menu.IsOpen, 'closed by Back');
    Sheet.Open;
    F.Layout(360, 640);
    AssertEquals(0, Sheet.Bounds.X);
    AssertEquals(360, Sheet.Bounds.W, 'the whole width');
    AssertTrue(Sheet.Bounds.Y > 400, 'at the bottom');
    Sheet.Close;
  finally
    F.Free;
  end;
end;

procedure TUITests.PullDownToRefresh;
var
  L: TListView;
  X, Y: Integer;
begin
  L := TListView.Create(Form);
  L.Parent := Form;
  L.Height := 200;
  L.OnRefresh := @CountClick;
  FClicks := 0;
  Render;
  X := L.Bounds.X + 20;
  Y := L.Bounds.Y + 20;
  Form.HandleMouseMove(X, Y);
  { a mouse wheel at the top does not pull }
  Form.HandleMouseWheel(0, 3);
  Sleep(200);
  ProcessTimers(GetTickCount64);
  AssertEquals(0, FClicks, 'not by a mouse wheel');
  { a finger: pulled far enough, then let go }
  WheelFromTouch := True;
  Form.HandleMouseWheel(0, 2);
  Form.HandleMouseWheel(0, 2);
  Render;
  WheelFromTouch := False;
  Sleep(200);
  ProcessTimers(GetTickCount64);
  AssertEquals(1, FClicks, 'refreshed');
  AssertTrue(L.Refreshing);
  L.Refreshing := False;
  { not far enough: nothing }
  WheelFromTouch := True;
  Form.HandleMouseWheel(0, 1);
  WheelFromTouch := False;
  Sleep(200);
  ProcessTimers(GetTickCount64);
  AssertEquals(1, FClicks, 'a short pull does nothing');
  { F5 on a computer }
  L.SetFocus;
  Form.HandleKeyDown(KEY_F1 + 4, False, False);
  AssertEquals(2, FClicks, 'F5');
end;

procedure TUITests.BottomTabs;
var
  T: TTabControl;
  A, B: TTabSheet;
begin
  T := TTabControl.Create(Form);
  T.Parent := Form;
  T.Grow := 1;
  T.TabPosition := tpBottom;
  A := TTabSheet.Create(Form);
  A.Caption := 'Home';
  A.TabIcon := 'home';
  A.Parent := T;
  B := TTabSheet.Create(Form);
  B.Caption := 'Search';
  B.TabIcon := 'search';
  B.Parent := T;
  Render;
  AssertTrue(T.TabRect(A).Y > A.Bounds.Y, 'the tabs below the page');
  AssertEquals(T.Bounds.W div 2, T.TabRect(A).W, 'the width shared out');
  Click(B);
  ClickAt(T.TabRect(B).X + 10, T.TabRect(B).Y + 10);
  AssertEquals(1, T.TabIndex);
end;

procedure TUITests.MaskEditShape;
var
  M: TMaskEdit;
begin
  M := TMaskEdit.Create(Form);
  M.Parent := Form;
  M.EditMask := '(000) 000 00 00';
  AssertEquals('(___) ___ __ __', M.Text, 'empty places');
  Render;
  M.SetFocus;
  AssertTrue(Form.Focused = M, 'focused');
  Form.HandleTextInput('532a12-34567');
  AssertEquals('(532) 123 45 67', M.Text, 'the digits in their places, the rest left out');
  AssertEquals('5321234567', M.Value);
  AssertTrue(M.IsComplete);
  Key(KEY_BACKSPACE);
  AssertEquals('(532) 123 45 6_', M.Text, 'Backspace empties the place before');
  AssertFalse(M.IsComplete);
  Key(KEY_BACKSPACE);
  Key(KEY_BACKSPACE);
  AssertEquals('(532) 123 4_ __', M.Text, 'over the space');
  M.Text := '5551';
  AssertEquals('(555) 1__ __ __', M.Text, 'set from code: in the places');
  M.Value := '';
  AssertEquals('(___) ___ __ __', M.Text);
  AssertEquals(Ord(ktNumber), Ord(M.KeyboardKind), 'digits: the number keyboard');
  M.EditMask := '>LL-000;0;*';
  Form.HandleTextInput('ab123');
  AssertEquals('AB-123', M.Text);
  AssertEquals('AB123', M.Value);
end;

procedure TUITests.ChartHit(Sender: TObject; SeriesIndex, ItemIndex: Integer);
begin
  FChartHit := Format('%d,%d', [SeriesIndex, ItemIndex]);
end;

procedure TUITests.ChartDrawsAndClicks;
var
  Ch: TChart;
  Rows: TJSONArray;
  I: Integer;
begin
  Ch := TChart.Create(Form);
  Ch.Parent := Form;
  Ch.Height := 240;
  Rows := TJSONArray(GetJSON('[{"m":"Jan","a":10,"b":"4.5"},{"m":"Feb","a":20,"b":6}]'));
  try
    Ch.LoadJson(Rows, 'm', ['a', 'b']);
  finally
    Rows.Free;
  end;
  AssertEquals(2, Ch.SeriesCount);
  AssertEquals('b', Ch.SeriesName(1));
  AssertEquals(2, Ch.Labels.Count);
  Ch.OnItemClick := @ChartHit;
  for I := 0 to 3 do
  begin
    Ch.Kind := TChartKind(I);
    Render;
  end;
  Ch.Kind := ckBar;
  Render;
  FChartHit := '';
  { the right half: Feb }
  ClickAt(Ch.Bounds.X + Ch.Bounds.W * 3 div 4, Ch.Bounds.Y + Ch.Bounds.H div 2);
  AssertEquals('1', Copy(FChartHit, Length(FChartHit), 1), 'the second label: ' + FChartHit);
  Ch.Clear;
  AssertEquals(0, Ch.SeriesCount);
  Render;
end;

procedure TUITests.GotFiles(Sender: TObject; const Files: TStringArray);
begin
  FAnswers := FAnswers + TControl(Sender).Name + ':' + string.Join(',', Files) + ';';
end;

procedure TUITests.FilesDropped;
var
  P: TPanel;
  L: TLabel;
begin
  P := TPanel.Create(Form);
  P.Name := 'DropZone';
  P.Height := 100;
  P.Parent := Form;
  L := TLabel.Create(Form);
  L.Text := 'Drop here';
  L.Parent := P;
  P.OnDropFiles := @GotFiles;
  Form.Name := 'Main';
  Form.OnDropFiles := @GotFiles;
  Render;
  FAnswers := '';
  AssertTrue(Form.HandleDropFiles(L.Bounds.X + 2, L.Bounds.Y + 2, ['/tmp/a.txt', '/tmp/b.png']));
  AssertEquals('DropZone:/tmp/a.txt,/tmp/b.png;', FAnswers, 'the control under it (from its label)');
  FAnswers := '';
  AssertTrue(Form.HandleDropFiles(5, 280, ['/tmp/c']));
  AssertEquals('Main:/tmp/c;', FAnswers, 'elsewhere: the form');
end;

procedure TUITests.GotMove(Sender: TObject; FromIndex, ToIndex: Integer);
begin
  FAnswers := FAnswers + IntToStr(FromIndex) + '>' + IntToStr(ToIndex) + ';';
end;

procedure TUITests.RowsMovedByGrip;
var
  L: TListBox;
  G: TListView;
  GX, RH, Y0: Integer;
begin
  L := TListBox.Create(Form);
  L.Parent := Form;
  L.Height := 140;
  L.Items.CommaText := 'a,b,c,d';
  L.AllowReorder := True;
  L.OnReorder := @GotMove;
  Render;
  FAnswers := '';
  GX := L.Bounds.X + L.Bounds.W - 4 - ReorderGripWidth div 2;
  RH := L.Font.LineHeight + 12;
  Y0 := L.Bounds.Y + 2;
  AssertTrue(L.DragsAt(GX, Y0 + RH div 2), 'a finger on the grip drags');
  AssertFalse(L.DragsAt(L.Bounds.X + 10, Y0 + RH div 2), 'elsewhere it scrolls');
  { a by its grip below c }
  Form.HandleMouseMove(GX, Y0 + RH div 2);
  Form.HandleMouseDown(GX, Y0 + RH div 2);
  Form.HandleMouseMove(GX, Y0 + RH * 2 + RH div 2);
  Form.HandleMouseMove(GX, Y0 + RH * 3);
  Form.HandleMouseUp(GX, Y0 + RH * 3);
  AssertEquals('b,c,a,d', L.Items.CommaText);
  AssertEquals('0>2;', FAnswers);
  AssertEquals(2, L.ItemIndex);
  { Ctrl+Up moves the selected one }
  L.SetFocus;
  Form.HandleKeyDown(KEY_UP, False, True);
  AssertEquals('b,a,c,d', L.Items.CommaText);
  { a list view }
  G := TListView.Create(Form);
  G.Parent := Form;
  G.Height := 160;
  G.AddColumn('Name');
  G.RowCount := 3;
  G.Cells[0, 0] := 'x';
  G.Cells[0, 1] := 'y';
  G.Cells[0, 2] := 'z';
  G.AllowReorder := True;
  G.OnReorder := @GotMove;
  Render;
  G.Row := 2;
  G.SetFocus;
  Form.HandleKeyDown(KEY_UP, False, True);
  AssertEquals('x', G.Cells[0, 0]);
  AssertEquals('z', G.Cells[0, 1]);
  AssertEquals('y', G.Cells[0, 2]);
end;

procedure TUITests.SavingState(Sender: TObject);
begin
  TForm(Sender).SaveState.Values['page'] := '3';
end;

procedure TUITests.StateKeptWhenStopped;
const
  Src = 'object F: TForm'#10'  object NoteMemo: TMemo'#10'  end'#10'  object Agree: TCheckBox'#10'  end'#10 +
    '  object Size: TComboBox'#10'    Items = (''S'', ''M'', ''L'')'#10'  end'#10'end';
var
  Root: TPFormNode;
  F, G: TForm;
  Text: string;
begin
  F := TForm.Create(nil);
  G := TForm.Create(nil);
  try
    Root := ParsePForm(Src);
    BuildForm(F, Root);
    BuildForm(G, Root);
    Root.Free;
    TMemo(F.FindComponent('NoteMemo')).Text := 'line one'#10'line \ two = x';
    TCheckBox(F.FindComponent('Agree')).Checked := True;
    TComboBox(F.FindComponent('Size')).ItemIndex := 2;
    F.OnSaveState := @SavingState;
    Text := FormStateText(F);
    { the app started again: a new form gets it back }
    RestoreFormStateText(G, Text);
    AssertEquals('line one'#10'line \ two = x', TMemo(G.FindComponent('NoteMemo')).Text);
    AssertTrue(TCheckBox(G.FindComponent('Agree')).Checked);
    AssertEquals(2, TComboBox(G.FindComponent('Size')).ItemIndex);
    AssertEquals('3', G.SaveState.Values['page'], 'the app''s own values');
    RestoreFormStateText(G, 'something else');
    AssertEquals('3', G.SaveState.Values['page'], 'not a state: nothing changes');
  finally
    G.Free;
    F.Free;
  end;
end;

procedure TUITests.ComboTouchPick;
var
  C: TComboBox;
  P: TPopup;
  I, X, Y: Integer;
begin
  C := TComboBox.Create(Form);
  C.Parent := Form;
  for I := 1 to 5 do
    C.Items.Add('Customer ' + IntToStr(I));
  Render;
  { a tap as the phone sends it: move, down, up, then the finger leaves }
  X := C.Bounds.X + 20; Y := C.Bounds.Y + 10;
  Form.HandleMouseMove(X, Y); Form.HandleMouseDown(X, Y, 1, 1); Form.HandleMouseUp(X, Y, 1); Form.HandleMouseLeave;
  AssertTrue(C.DroppedDown, 'open');
  P := Form.TopPopup;
  Render;
  X := P.Bounds.X + 20; Y := P.Bounds.Y + P.Bounds.H div 2;
  Form.HandleMouseMove(X, Y); Form.HandleMouseDown(X, Y, 1, 1); Form.HandleMouseUp(X, Y, 1); Form.HandleMouseLeave;
  Render;
  AssertFalse(C.DroppedDown, 'closed');
  AssertTrue(C.ItemIndex >= 0, 'picked');
end;

procedure TUITests.EditHasCutCopyPaste;
var
  E: TEdit;
  P: TPopup;
  I: Integer;
  Shown: string;

  function Bar: TPopup;
  begin
    if Form.PopupCount = 0 then
      Exit(nil);
    Result := Form.TopPopup;
  end;

  function Press(const Text: string): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    if Bar = nil then
      Exit;
    for K := 0 to Bar.ChildCount - 1 do
      if Bar.Children[K].Visible and (TButton(Bar.Children[K]).Text = Text) then
      begin
        Click(Bar.Children[K]);
        Exit(True);
      end;
  end;

begin
  E := NewEdit(Form);
  E.Text := 'hello world';
  Render;
  Clip := '';
  ClickAt(E.Bounds.X + 10, E.Bounds.Y + 5, 1, 3);      { right click: no selection yet }
  P := Bar;
  AssertTrue(P <> nil, 'a bar over the edit');
  Shown := '';
  for I := 0 to P.ChildCount - 1 do
    if P.Children[I].Visible then
      Shown := Shown + TButton(P.Children[I]).Text + ',';
  AssertEquals('Select all,', Shown, 'without a selection or a clipboard: only Select all');
  AssertTrue(Press('Select all'));
  AssertEquals(11, E.SelLength);
  ClickAt(E.Bounds.X + 10, E.Bounds.Y + 5, 1, 3);
  AssertTrue(Press('Copy'), 'with a selection: Copy');
  AssertEquals('hello world', Clip);
  E.SelStart := Length(E.Text);
  ClickAt(E.Bounds.X + 10, E.Bounds.Y + 5, 1, 3);
  AssertTrue(Press('Paste'), 'with a clipboard: Paste');
  AssertEquals('hello worldhello world', E.Text);
  E.Password := True;
  E.SelectAll;
  ClickAt(E.Bounds.X + 10, E.Bounds.Y + 5, 1, 3);
  AssertFalse(Press('Copy'), 'a password is not copied');
  Bar.Close;
  UseLanguage('tr');
  try
    ClickAt(E.Bounds.X + 10, E.Bounds.Y + 5, 1, 3);
    AssertTrue(Press('Yapıştır'), 'in the app''s language');
  finally
    UseLanguage('en');
  end;
end;

initialization
  RegisterTests(TUITests);
end.
