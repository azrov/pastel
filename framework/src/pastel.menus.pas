{ Pastel - menus: a menu bar, pop-up (right click) menus and keyboard
  shortcuts.

    object MainMenu: TMenuBar
      object FileMenu: TMenuItem
        Caption = 'File'
        object OpenItem: TMenuItem
          Caption = 'Open...'
          ShortCut = 'Ctrl+O'
          OnClick = OpenClick
        end
        object Sep1: TMenuItem
          Caption = '-'
        end
      end
    end

  A TPopupMenu holds TMenuItems too; a control shows it on a right click
  when its PopupMenu names it. Shortcuts work while the window has the
  keyboard, also when the menu is closed; TAction shortcuts too.
  Part of the Pastel project, MIT License. }
unit Pastel.Menus;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  TMenuView = class;

  { One command of a menu; items inside it make a submenu. Caption '-' is a line. }
  TMenuItem = class(TControl)
  private
    FCaption, FShortCut: string;
    FChecked: Boolean;
    FIcon: string;
    FOnClick: TNotifyEvent;
    FAction: TBasicAction;
    procedure SetCaption(const AValue: string);
    procedure SetAction(AValue: TBasicAction);
  protected
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    function Cursor: TCursorKind; override;
  public
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Runs OnClick (or the action). }
    procedure Click;
    function IsSeparator: Boolean;
    function HasSubmenu: Boolean;
    { Caption, ShortCut, Enabled and Checked, from the action when there is one. }
    function DisplayCaption: string;
    function DisplayShortCut: string;
    function IsEnabled: Boolean;
    function IsChecked: Boolean;
    { Icon, or the action's icon }
    function DisplayIcon: string;
  published
    property Caption: string read FCaption write SetCaption;
    { Like 'Ctrl+S', 'Ctrl+Shift+Z', 'F5', 'Delete'. }
    property ShortCut: string read FShortCut write FShortCut;
    property Checked: Boolean read FChecked write FChecked default False;
    { A built-in icon before the caption ('save', 'print'...; Pastel.Icons); the action's when empty. }
    property Icon: string read FIcon write FIcon;
    property Action: TBasicAction read FAction write SetAction;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  { The bar with menus at the top of a window (put it first, in a form with Padding = 0). }
  TMenuBar = class(TControl)
  private
    FOpen: TMenuView;
    FOpenItem: TMenuItem;
    procedure ViewClosed(Sender: TObject);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
  public
    destructor Destroy; override;
    { Opens the menu of a top-level item (keyboard: Alt and F10 open the first). }
    procedure OpenMenu(Item: TMenuItem);
    procedure CloseMenu;
    function OpenItem: TMenuItem;
  end;

  { A menu shown at the mouse, from a control's PopupMenu or from code. }
  TPopupMenu = class(TControl)
  private
    FView: TMenuView;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Shows the menu at a point of the form. }
    procedure Popup(Form: TForm; X, Y: Integer);
  end;

  { The open list of a menu (internal). }
  TMenuView = class(TPopup)
  private
    FSource: TControl;          { the TMenuItem, TPopupMenu with the items }
    FHot: Integer;
    FSub: TMenuView;
    FParentView: TMenuView;
    FBar: TMenuBar;
    FRowY: array of Integer;
    function Items: TFPList;
    function RowHeight(Item: TMenuItem): Integer;
    function IndexAt(Y: Integer): Integer;
    procedure OpenSub(Index: Integer);
    procedure CloseSub;
    procedure Activate(Index: Integer);
    procedure MoveHot(Step: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    procedure MouseDown(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  public
    constructor CreateFor(AOwner: TComponent; ASource: TControl);
    destructor Destroy; override;
    { Closes this view, its submenus and the views it came from. }
    procedure CloseAll;
  end;

{ Where an item of an open menu is shown (for test scripts); False when it is not shown. }
function MenuItemRect(Item: TMenuItem; out R: TRectI): Boolean;

{ Parses 'Ctrl+Shift+S' into a key and modifiers; False when it is not a shortcut. }
function ParseShortCut(const S: string; out Key: LongInt; out Shift, Ctrl, Alt: Boolean): Boolean;
{ Runs the menu item or action of the form whose shortcut is this key. }
function HandleShortCut(Form: TForm; Key: LongInt; Shift, Ctrl: Boolean): Boolean;

implementation

uses
  Math, Pastel.Icons;

function KeyName(const S: string): LongInt;
var
  N: Integer;
  L: string;
begin
  L := LowerCase(S);
  case L of
    'enter', 'return': Result := KEY_ENTER;
    'tab': Result := KEY_TAB;
    'esc', 'escape': Result := KEY_ESCAPE;
    'space': Result := KEY_SPACE;
    'del', 'delete': Result := KEY_DELETE;
    'ins', 'insert': Result := KEY_INSERT;
    'backspace': Result := KEY_BACKSPACE;
    'left': Result := KEY_LEFT;
    'right': Result := KEY_RIGHT;
    'up': Result := KEY_UP;
    'down': Result := KEY_DOWN;
    'home': Result := KEY_HOME;
    'end': Result := KEY_END;
    'pgup', 'pageup': Result := KEY_PAGEUP;
    'pgdn', 'pagedown': Result := KEY_PAGEDOWN;
    'plus': Result := Ord('+');
    'minus': Result := Ord('-');
  else
    if (Length(L) >= 2) and (L[1] = 'f') and TryStrToInt(Copy(L, 2, 2), N) and (N >= 1) and (N <= 12) then
      Result := KEY_F1 + N - 1
    else if Length(L) = 1 then
      Result := Ord(L[1])
    else
      Result := 0;
  end;
end;

function ParseShortCut(const S: string; out Key: LongInt; out Shift, Ctrl, Alt: Boolean): Boolean;
var
  Parts: TStringArray;
  I: Integer;
begin
  Key := 0;
  Shift := False;
  Ctrl := False;
  Alt := False;
  if Trim(S) = '' then
    Exit(False);
  Parts := StringReplace(Trim(S), '++', '+plus', []).Split(['+']);
  for I := 0 to High(Parts) - 1 do
    case LowerCase(Trim(Parts[I])) of
      'shift': Shift := True;
      'ctrl', 'control', 'cmd': Ctrl := True;
      'alt', 'option': Alt := True;
    else
      Exit(False);
    end;
  Key := KeyName(Trim(Parts[High(Parts)]));
  Result := Key <> 0;
end;

{ every menu item and action of the form, wherever it is }
procedure CollectCommands(Root: TComponent; List: TFPList);
var
  I: Integer;
begin
  for I := 0 to Root.ComponentCount - 1 do
  begin
    if (Root.Components[I] is TMenuItem) or (Root.Components[I] is TAction) then
      List.Add(Root.Components[I]);
    CollectCommands(Root.Components[I], List);
  end;
end;

function HandleShortCut(Form: TForm; Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  List: TFPList;
  I: Integer;
  K: LongInt;
  S, C, A: Boolean;
  Obj: TComponent;
  SC: string;
begin
  Result := False;
  if (Key >= Ord('A')) and (Key <= Ord('Z')) then
    Key := Key + 32;
  { Alt or F10 alone: open the first menu of the bar }
  List := TFPList.Create;
  try
    CollectCommands(Form, List);
    for I := 0 to List.Count - 1 do
    begin
      Obj := TComponent(List[I]);
      if Obj is TMenuItem then
      begin
        if not TMenuItem(Obj).IsEnabled or TMenuItem(Obj).IsSeparator then
          Continue;
        SC := TMenuItem(Obj).DisplayShortCut;
      end
      else
      begin
        if not TAction(Obj).Enabled then
          Continue;
        SC := TAction(Obj).ShortCut;
      end;
      if not ParseShortCut(SC, K, S, C, A) then
        Continue;
      if (K >= Ord('A')) and (K <= Ord('Z')) then
        K := K + 32;
      if (K = Key) and (S = Shift) and (C = Ctrl) and (A = KeyAlt) then
      begin
        if Obj is TMenuItem then
          TMenuItem(Obj).Click
        else
          TAction(Obj).Execute;
        Exit(True);
      end;
    end;
    { F10 opens the menu bar }
    if (Key = KEY_F1 + 9) and not Shift and not Ctrl then
      for I := 0 to Form.ComponentCount - 1 do
        if (Form.Components[I] is TMenuBar) and (TMenuBar(Form.Components[I]).ChildCount > 0) then
        begin
          TMenuBar(Form.Components[I]).OpenMenu(TMenuItem(TMenuBar(Form.Components[I]).Children[0]));
          Exit(True);
        end;
  finally
    List.Free;
  end;
end;

procedure ShowPopupMenu(Menu: TControl; Form: TForm; X, Y: Integer);
begin
  if Menu is TPopupMenu then
    TPopupMenu(Menu).Popup(Form, X, Y);
end;

var
  OpenViews: TFPList = nil;

function MenuItemRect(Item: TMenuItem; out R: TRectI): Boolean;
var
  I, J: Integer;
  V: TMenuView;
  L: TFPList;
begin
  Result := False;
  for I := OpenViews.Count - 1 downto 0 do
  begin
    V := TMenuView(OpenViews[I]);
    if not V.Shown then
      Continue;
    L := V.Items;
    try
      J := L.IndexOf(Item);
      if (J >= 0) and (J < High(V.FRowY)) then
      begin
        R := RectI(V.Bounds.X, V.FRowY[J], V.Bounds.W, V.FRowY[J + 1] - V.FRowY[J]);
        Exit(True);
      end;
    finally
      L.Free;
    end;
  end;
end;

{ ---- TMenuItem ---- }

procedure TMenuItem.SetCaption(const AValue: string);
begin
  FCaption := AValue;
  Changed;
end;

procedure TMenuItem.SetAction(AValue: TBasicAction);
begin
  if FAction = AValue then Exit;
  if FAction <> nil then
    FAction.RemoveFreeNotification(Self);
  FAction := AValue;
  if FAction <> nil then
    FAction.FreeNotification(Self);
  Changed;
end;

procedure TMenuItem.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
    FAction := nil;
end;

function TMenuItem.IsSeparator: Boolean;
begin
  Result := FCaption = '-';
end;

function TMenuItem.HasSubmenu: Boolean;
var
  I: Integer;
begin
  for I := 0 to ChildCount - 1 do
    if (Children[I] is TMenuItem) and Children[I].Visible then
      Exit(True);
  Result := False;
end;

function TMenuItem.DisplayCaption: string;
begin
  Result := FCaption;
  if (Result = '') and (FAction is TAction) then
    Result := TAction(FAction).Caption;
end;

function TMenuItem.DisplayShortCut: string;
begin
  Result := FShortCut;
  if (Result = '') and (FAction is TAction) then
    Result := TAction(FAction).ShortCut;
end;

function TMenuItem.IsEnabled: Boolean;
begin
  Result := Enabled and not ((FAction is TAction) and not TAction(FAction).Enabled);
end;

function TMenuItem.DisplayIcon: string;
begin
  Result := FIcon;
  if (Result = '') and (FAction is TAction) then
    Result := TAction(FAction).Icon;
end;

function TMenuItem.IsChecked: Boolean;
begin
  Result := FChecked or ((FAction is TAction) and TAction(FAction).Checked);
end;

procedure TMenuItem.Click;
begin
  if not IsEnabled then
    Exit;
  if FAction <> nil then
    FAction.Execute
  else if Assigned(FOnClick) then
    FOnClick(Self);
end;

function TMenuItem.Cursor: TCursorKind;
begin
  Result := ckArrow;
end;

{ a top-level item in a menu bar opens its menu }
procedure TMenuItem.MouseDown(X, Y: Integer);
var
  Bar: TMenuBar;
begin
  if not (Parent is TMenuBar) then
    Exit;
  Bar := TMenuBar(Parent);
  if Bar.OpenItem = Self then
    Bar.CloseMenu
  else
    Bar.OpenMenu(Self);
end;

{ with a menu of the bar open, moving to another item opens its menu }
procedure TMenuItem.MouseMove(X, Y: Integer);
var
  Bar: TMenuBar;
begin
  if not (Parent is TMenuBar) then
    Exit;
  Bar := TMenuBar(Parent);
  if (Bar.OpenItem <> nil) and (Bar.OpenItem <> Self) then
    Bar.OpenMenu(Self);
end;

{ ---- TMenuBar ---- }

destructor TMenuBar.Destroy;
begin
  CloseMenu;
  inherited Destroy;
end;

function TMenuBar.OpenItem: TMenuItem;
begin
  if (FOpen <> nil) and FOpen.Shown then
    Result := FOpenItem
  else
    Result := nil;
end;

procedure TMenuBar.Measure(AvailWidth: Integer; out W, H: Integer);
var
  F: TPastelFont;
  I: Integer;
begin
  F := GetFont(Theme.FontSize);
  W := 0;
  for I := 0 to ChildCount - 1 do
    if (Children[I] is TMenuItem) and Children[I].Visible then
      Inc(W, F.TextWidth(TMenuItem(Children[I]).DisplayCaption) + 24);
  H := F.LineHeight + 14;
end;

procedure TMenuBar.Arrange(const R: TRectI);
var
  F: TPastelFont;
  I, X, W: Integer;
  Item: TMenuItem;
begin
  inherited Arrange(R);
  F := GetFont(Theme.FontSize);
  X := R.X + 4;
  for I := 0 to ChildCount - 1 do
    if Children[I] is TMenuItem then
    begin
      Item := TMenuItem(Children[I]);
      if not Item.Visible then
        Continue;
      W := F.TextWidth(Item.DisplayCaption) + 24;
      Item.Arrange(RectI(X, R.Y + 3, W, R.H - 6));
      Inc(X, W);
    end;
end;

procedure TMenuBar.Paint(C: TCanvas32);
var
  F: TPastelFont;
  I: Integer;
  Item: TMenuItem;
  Col: TColor32;
begin
  F := GetFont(Theme.FontSize);
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Surface);
  C.FillRect(Bounds.X, Bounds.Y + Bounds.H - 1, Bounds.W, 1, Theme.Border);
  for I := 0 to ChildCount - 1 do
    if (Children[I] is TMenuItem) and Children[I].Visible then
    begin
      Item := TMenuItem(Children[I]);
      if Item = OpenItem then
        C.FillRoundRect(Item.Bounds.X, Item.Bounds.Y, Item.Bounds.W, Item.Bounds.H, 6, Theme.SecondaryPressed)
      else if (ParentForm <> nil) and (ParentForm.Hovered = Item) then
        C.FillRoundRect(Item.Bounds.X, Item.Bounds.Y, Item.Bounds.W, Item.Bounds.H, 6, Theme.SecondaryHover);
      if Item.IsEnabled then Col := Theme.Text else Col := Theme.Disabled;
      C.DrawText(F, Item.Bounds.X + 12, Item.Bounds.Y + (Item.Bounds.H - F.LineHeight) div 2,
        Item.DisplayCaption, Col);
    end;
end;

procedure TMenuBar.ViewClosed(Sender: TObject);
begin
  if Sender = FOpen then
    FOpenItem := nil;
  Invalidate;
end;

procedure TMenuBar.OpenMenu(Item: TMenuItem);
var
  F: TForm;
begin
  F := ParentForm;
  if (F = nil) or not Item.IsEnabled then
    Exit;
  CloseMenu;
  if not Item.HasSubmenu then
  begin
    Item.Click;     { a top-level item without a menu is a command }
    Exit;
  end;
  FOpen := TMenuView.CreateFor(Self, Item);
  FOpen.FBar := Self;
  FOpen.OnClose := @ViewClosed;
  FOpenItem := Item;
  FOpen.Popup(F, Item.Bounds);
  FOpen.SetFocus;
  Invalidate;
end;

procedure TMenuBar.CloseMenu;
var
  V: TMenuView;
begin
  V := FOpen;
  FOpen := nil;
  FOpenItem := nil;
  if V <> nil then
  begin
    V.OnClose := nil;
    V.CloseAll;
    V.Free;
  end;
  Invalidate;
end;

{ ---- TPopupMenu ---- }

constructor TPopupMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Visible := False;     { it has no place on the form }
end;

destructor TPopupMenu.Destroy;
begin
  if FView <> nil then
  begin
    FView.CloseAll;
    FreeAndNil(FView);
  end;
  inherited Destroy;
end;

procedure TPopupMenu.Popup(Form: TForm; X, Y: Integer);
begin
  if FView <> nil then
  begin
    FView.CloseAll;
    FreeAndNil(FView);
  end;
  FView := TMenuView.CreateFor(Self, Self);
  FView.Popup(Form, RectI(X, Y - 4, 1, 1));
  FView.SetFocus;
end;

{ ---- TMenuView ---- }

constructor TMenuView.CreateFor(AOwner: TComponent; ASource: TControl);
begin
  inherited Create(AOwner);
  FSource := ASource;
  FHot := -1;
  Padding := 6;
  OpenViews.Add(Self);
end;

destructor TMenuView.Destroy;
begin
  CloseSub;
  if OpenViews <> nil then
    OpenViews.Remove(Self);
  inherited Destroy;
end;

function TMenuView.Items: TFPList;
var
  I: Integer;
begin
  Result := TFPList.Create;
  for I := 0 to FSource.ChildCount - 1 do
    if (FSource.Children[I] is TMenuItem) and FSource.Children[I].Visible then
      Result.Add(FSource.Children[I]);
end;

function TMenuView.RowHeight(Item: TMenuItem): Integer;
begin
  if Item.IsSeparator then
    Result := 9
  else
    Result := GetFont(Theme.FontSize).LineHeight + 12;
end;

procedure TMenuView.Measure(AvailWidth: Integer; out W, H: Integer);
var
  L: TFPList;
  I, CW, SW: Integer;
  F: TPastelFont;
  Item: TMenuItem;
begin
  F := GetFont(Theme.FontSize);
  L := Items;
  try
    CW := 0;
    SW := 0;
    H := 2 * Padding;
    for I := 0 to L.Count - 1 do
    begin
      Item := TMenuItem(L[I]);
      CW := Math.Max(CW, F.TextWidth(Item.DisplayCaption));
      SW := Math.Max(SW, F.TextWidth(Item.DisplayShortCut));
      Inc(H, RowHeight(Item));
    end;
    W := Math.Max(160, 2 * Padding + 28 + CW + 32 + SW + 20);
  finally
    L.Free;
  end;
end;

procedure TMenuView.Arrange(const R: TRectI);
var
  L: TFPList;
  I, Y: Integer;
begin
  SetBoundsOnly(R);
  L := Items;
  try
    SetLength(FRowY, L.Count + 1);
    Y := R.Y + Padding;
    for I := 0 to L.Count - 1 do
    begin
      FRowY[I] := Y;
      Inc(Y, RowHeight(TMenuItem(L[I])));
    end;
    FRowY[L.Count] := Y;
  finally
    L.Free;
  end;
end;

procedure TMenuView.Paint(C: TCanvas32);
var
  L: TFPList;
  I, Y, RH: Integer;
  F: TPastelFont;
  Item: TMenuItem;
  Fg, Muted: TColor32;
begin
  inherited Paint(C);     { the panel: shadow, background, border }
  F := GetFont(Theme.FontSize);
  L := Items;
  try
    for I := 0 to L.Count - 1 do
    begin
      if I >= High(FRowY) then
        Break;
      Item := TMenuItem(L[I]);
      Y := FRowY[I];
      RH := FRowY[I + 1] - Y;
      if Item.IsSeparator then
      begin
        C.FillRect(Bounds.X + 8, Y + 4, Bounds.W - 16, 1, Theme.Border);
        Continue;
      end;
      Fg := Theme.Text;
      Muted := Theme.TextMuted;
      if not Item.IsEnabled then
      begin
        Fg := Theme.Disabled;
        Muted := Theme.Disabled;
      end
      else if I = FHot then
      begin
        C.FillRoundRect(Bounds.X + 4, Y, Bounds.W - 8, RH, 6, Theme.Accent);
        Fg := Theme.OnAccent;
        Muted := Theme.OnAccent;
      end;
      if Item.IsChecked then
      begin
        C.DrawLine(Bounds.X + 13, Y + RH / 2, Bounds.X + 16.5, Y + RH / 2 + 3.5, 1.8, Fg);
        C.DrawLine(Bounds.X + 16.5, Y + RH / 2 + 3.5, Bounds.X + 22, Y + RH / 2 - 3.5, 1.8, Fg);
      end
      else if Item.DisplayIcon <> '' then
        DrawIcon(C, Item.DisplayIcon, Bounds.X + 9, Y + (RH - 16) div 2, 16, Muted);
      C.DrawText(F, Bounds.X + Padding + 28, Y + (RH - F.LineHeight) div 2, Item.DisplayCaption, Fg);
      if Item.HasSubmenu then
      begin
        C.DrawLine(Bounds.X + Bounds.W - 20, Y + RH / 2 - 4, Bounds.X + Bounds.W - 16, Y + RH / 2, 1.6, Muted);
        C.DrawLine(Bounds.X + Bounds.W - 16, Y + RH / 2, Bounds.X + Bounds.W - 20, Y + RH / 2 + 4, 1.6, Muted);
      end
      else if Item.DisplayShortCut <> '' then
        C.DrawText(F, Bounds.X + Bounds.W - Padding - 12 - F.TextWidth(Item.DisplayShortCut),
          Y + (RH - F.LineHeight) div 2, Item.DisplayShortCut, Muted);
    end;
  finally
    L.Free;
  end;
end;

function TMenuView.Focusable: Boolean;
begin
  Result := True;    { the keys go to the open menu }
end;

function TMenuView.IndexAt(Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRowY) - 1 do
    if (Y >= FRowY[I]) and (Y < FRowY[I + 1]) then
      Exit(I);
  Result := -1;
end;

procedure TMenuView.CloseSub;
begin
  if FSub <> nil then
  begin
    FSub.CloseSub;
    FSub.Close;
    FreeAndNil(FSub);
  end;
end;

procedure TMenuView.OpenSub(Index: Integer);
var
  L: TFPList;
  Item: TMenuItem;
  F: TForm;
begin
  L := Items;
  try
    Item := TMenuItem(L[Index]);
  finally
    L.Free;
  end;
  if (FSub <> nil) and (FSub.FSource = Item) then
    Exit;
  CloseSub;
  if not Item.HasSubmenu or not Item.IsEnabled then
    Exit;
  F := ParentForm;
  if F = nil then
    Exit;
  FSub := TMenuView.CreateFor(Self, Item);
  FSub.FParentView := Self;
  FSub.Popup(F, RectI(Bounds.X, FRowY[Index], Bounds.W, FRowY[Index + 1] - FRowY[Index]), True);
end;

procedure TMenuView.CloseAll;
var
  TopItem: TMenuView;
begin
  CloseSub;
  TopItem := Self;
  while TopItem.FParentView <> nil do
    TopItem := TopItem.FParentView;
  if TopItem <> Self then
  begin
    TopItem.CloseAll;
    Exit;
  end;
  Close;
end;

procedure TMenuView.Activate(Index: Integer);
var
  L: TFPList;
  Item: TMenuItem;
begin
  if Index < 0 then
    Exit;
  L := Items;
  try
    Item := TMenuItem(L[Index]);
  finally
    L.Free;
  end;
  if Item.IsSeparator or not Item.IsEnabled then
    Exit;
  if Item.HasSubmenu then
  begin
    OpenSub(Index);
    Exit;
  end;
  { close first: the command may open a dialog }
  CloseAll;
  Item.Click;
end;

procedure TMenuView.MoveHot(Step: Integer);
var
  L: TFPList;
  I, N: Integer;
begin
  L := Items;
  try
    N := L.Count;
    if N = 0 then
      Exit;
    I := FHot;
    repeat
      I := (I + Step + N) mod N;
      if I < 0 then I := N - 1;
    until (not TMenuItem(L[I]).IsSeparator and TMenuItem(L[I]).IsEnabled) or (I = FHot);
    FHot := I;
  finally
    L.Free;
  end;
  Invalidate;
end;

procedure TMenuView.MouseMove(X, Y: Integer);
var
  I: Integer;
begin
  I := IndexAt(Y);
  if I <> FHot then
  begin
    FHot := I;
    Invalidate;
    if I >= 0 then
      OpenSub(I);
  end;
end;

procedure TMenuView.MouseDown(X, Y: Integer);
begin
end;

procedure TMenuView.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  if Inside then
    Activate(IndexAt(Y));
end;

function TMenuView.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  Bar: TMenuBar;
  Idx: Integer;
begin
  Result := True;
  case Key of
    KEY_DOWN: MoveHot(1);
    KEY_UP: MoveHot(-1);
    KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: Activate(FHot);
    KEY_RIGHT:
      begin
        if FHot >= 0 then
          OpenSub(FHot);
        if FSub <> nil then
        begin
          FSub.SetFocus;
          FSub.MoveHot(1);
        end
        else
          Result := False;      { the top menu: on to the next menu of the bar }
      end;
    KEY_LEFT:
      if FParentView <> nil then
      begin
        FParentView.SetFocus;
        FParentView.CloseSub;
      end;
    KEY_ESCAPE:
      if FParentView <> nil then
      begin
        FParentView.SetFocus;
        FParentView.CloseSub;
      end
      else
        CloseAll;
  else
    Result := False;
  end;
  { left and right in the top menu move along the bar }
  Bar := FBar;
  if (Bar <> nil) and ((Key = KEY_LEFT) or (Key = KEY_RIGHT)) and (FParentView = nil) and
     ((Key = KEY_LEFT) or not Result) then
  begin
    Idx := Bar.IndexOfChild(Bar.OpenItem);
    repeat
      if Key = KEY_LEFT then Dec(Idx) else Inc(Idx);
      Idx := (Idx + Bar.ChildCount) mod Bar.ChildCount;
    until (Bar.Children[Idx] is TMenuItem) and Bar.Children[Idx].Visible;
    Bar.OpenMenu(TMenuItem(Bar.Children[Idx]));
    if Bar.FOpen <> nil then
    begin
      Bar.FOpen.SetFocus;
      Bar.FOpen.MoveHot(1);
    end;
    Result := True;
  end;
end;

initialization
  OpenViews := TFPList.Create;
  RegisterControl(TMenuBar);
  RegisterControl(TMenuItem);
  RegisterControl(TPopupMenu);
  ShortcutHook := @HandleShortCut;
  PopupMenuHook := @ShowPopupMenu;
finalization
  FreeAndNil(OpenViews);
end.
