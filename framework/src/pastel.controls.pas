{ Pastel - more controls: check boxes, radio buttons, switches, lists,
  drop-downs, pictures, scrolling areas, tabs, progress bars, sliders,
  spinners, splitters, tool bars and status bars. They are registered for .pform files like the basic ones.
  Part of the Pastel project, MIT License. }
unit Pastel.Controls;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  { A box with a check mark and a text; Checked toggles on click and Space. }
  TCheckBox = class(TControl)
  private
    FText: string;
    FChecked: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetText(const AValue: string);
  protected
    procedure SetChecked(AValue: Boolean); virtual;
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    procedure PaintMark(C: TCanvas32; X, Y: Integer); virtual;
    function MarkWidth: Integer; virtual;
    function MarkHeight: Integer; virtual;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure Toggle; virtual;
  published
    property Text: string read FText write SetText;
    property Checked: Boolean read FChecked write SetChecked default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { One choice of several: checking it unchecks the radio buttons next to it
    (with the same parent). }
  TRadioButton = class(TCheckBox)
  protected
    procedure SetChecked(AValue: Boolean); override;
    procedure PaintMark(C: TCanvas32; X, Y: Integer); override;
    procedure Toggle; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  end;

  { An on/off switch with an optional text after it. }
  TSwitch = class(TCheckBox)
  protected
    procedure PaintMark(C: TCanvas32; X, Y: Integer); override;
    function MarkWidth: Integer; override;
    function MarkHeight: Integer; override;
  end;

  { A list of texts to choose from. Only the rows that show are drawn, so it
    handles many thousands of items. }
  TListBox = class(TControl)
  private
    FItems: TStringList;
    FItemIndex, FTop, FItemHeight, FHotIndex: Integer;
    FHotTrack, FDraggingBar: Boolean;
    FDragOffset: Integer;
    FAllowReorder: Boolean;
    FMoveFrom, FMoveTo: Integer;           { a row moved by its grip: -1 when none }
    FOnReorder: TReorderEvent;
    FOnChange, FOnDblClick, FOnItemClick: TNotifyEvent;
    function GripAt(X, Y: Integer): Integer;
    procedure MoveRow(AFrom, ATo: Integer);
    procedure SetAllowReorder(AValue: Boolean);
    procedure ItemsChanged(Sender: TObject);
    procedure SetItems(AValue: TStrings);
    function GetItems: TStrings;
    procedure SetItemIndex(AValue: Integer);
    procedure SetItemHeight(AValue: Integer);
    function RowHeight: Integer;
    function ContentHeight: Integer;
    function InnerHeight: Integer;
    procedure ClampTop;
    function IndexAt(Y: Integer): Integer;
    function BarRect: TRectI;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure TextInput(const S: string); override;
  public
    function DragsAt(X, Y: Integer): Boolean; override;
    function DragData(X, Y: Integer): string; override;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Scrolls so the item shows. }
    procedure MakeVisible(Index: Integer);
    function Font: TPastelFont;
    { The selected text, '' when nothing is selected. }
    function SelectedText: string;
    { Used by TComboBox: the row under the mouse is highlighted. }
    property HotTrack: Boolean read FHotTrack write FHotTrack;
    { A click on an item (also when it was selected already). }
    property OnItemClick: TNotifyEvent read FOnItemClick write FOnItemClick;
  published
    property OnDropFiles;
    property Items: TStrings read GetItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    { Height of a row; 0: from the font. }
    property ItemHeight: Integer read FItemHeight write SetItemHeight default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { A double click or Enter on an item. }
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
    { Rows can be moved: by the grip (≡) at their right, or Ctrl+Up/Down. }
    property AllowReorder: Boolean read FAllowReorder write SetAllowReorder default False;
    { A row was moved (Items is in the new order already). }
    property OnReorder: TReorderEvent read FOnReorder write FOnReorder;
  end;

  { A drop-down list. }
  { A panel that slides over the window from its left (or right) side: the
    menu of a phone app (the "hamburger" menu). It holds controls like a
    column; it is not on the form until Open. Back (Escape) or a tap beside it
    closes it.
      object Menu: TDrawer
        object HomeItem: TButton
          Text = 'Home'
          Style = Flat
          OnClick = HomeItemClick
        end
      end
      procedure THomeForm.MenuButtonClick(Sender: TObject);
      begin
        Menu.Open;
      end; }
  TDrawer = class(TPopup)
  private
    FHome: TForm;
    FOnOpen: TNotifyEvent;
    function GetSide: TPopupSide;
    procedure SetSide(AValue: TPopupSide);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Open;
    procedure Toggle;
    function IsOpen: Boolean;
  published
    property Width;
    property Padding default 16;
    property Gap default 4;
    property Color;
    { psLeft or psRight; a TBottomSheet is psBottom }
    property Side: TPopupSide read GetSide write SetSide default psLeft;
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    property OnClose;
  end;

  { The same from the bottom of the window, as high as its content (choices,
    details, a short form). }
  TBottomSheet = class(TDrawer)
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Side default psBottom;
  end;

  TComboBox = class(TControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FPlaceholder: string;
    FPopup: TPopup;
    FList: TListBox;
    FOnChange: TNotifyEvent;
    procedure ItemsChanged(Sender: TObject);
    procedure SetItems(AValue: TStrings);
    function GetItems: TStrings;
    procedure SetItemIndex(AValue: Integer);
    procedure SetPlaceholder(const AValue: string);
    function GetText: string;
    procedure SetText(const AValue: string);
    procedure ListClicked(Sender: TObject);
    procedure Choose(Index: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure TextInput(const S: string); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure DropDown;
    procedure CloseUp;
    function DroppedDown: Boolean;
  published
    property Items: TStrings read GetItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    { The chosen item; setting it chooses the item with that text. }
    property Text: string read GetText write SetText stored False;
    { Shown when nothing is chosen. }
    property Placeholder: string read FPlaceholder write SetPlaceholder;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TImageFit = Pastel.UI.TImageFit;

  { A picture from a PNG, JPEG or BMP file. }
  TImage = class(TControl)
  private
    FPicture: TBitmap32;
    FFileName, FUrl: string;
    FFit: TImageFit;
    FError: string;
    procedure SetFileName(const AValue: string);
    procedure SetUrl(const AValue: string);
    procedure SetFit(AValue: TImageFit);
    procedure LoadPicture;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Loads a picture from a stream (e.g. a resource or a download). }
    procedure LoadFromStream(Stream: TStream);
    property Picture: TBitmap32 read FPicture;
  published
    property OnDropFiles;
    { Why the picture could not be loaded, '' when it was. }
    property LoadError: string read FError;
    { A file next to the program, in assets/ or a full path. }
    property FileName: string read FFileName write SetFileName;
    { Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size. }
    property Fit: TImageFit read FFit write SetFit default ifContain;
    { A picture from the web (uses Pastel.WebImages: fetched on a thread, kept in a cache folder). }
    property Url: string read FUrl write SetUrl;
  end;

  { A column whose content can be taller than the box: it scrolls. }
  TScrollBox = class(TColumn)
  private
    FScrollY, FContentH: Integer;
    FDragging: Boolean;
    FDragOffset: Integer;
    FPullRefresh: TPullRefresh;
    function GetOnRefresh: TNotifyEvent;
    procedure SetOnRefresh(AValue: TNotifyEvent);
    function GetRefreshing: Boolean;
    procedure SetRefreshing(AValue: Boolean);
    function BarRect: TRectI;
    procedure SetScrollY(AValue: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
  public
    procedure ScrollIntoView(C: TControl); override;
    property ScrollY: Integer read FScrollY write SetScrollY;
    property ContentHeight: Integer read FContentH;
    { True while OnRefresh's work goes on: set it to False when it is done. }
    property Refreshing: Boolean read GetRefreshing write SetRefreshing;
  published
    { Pull down to refresh (a finger past the top): called, the circle turns until Refreshing := False. }
    property OnRefresh: TNotifyEvent read GetOnRefresh write SetOnRefresh;
  end;

  { One page of a TTabControl. }
  TTabSheet = class(TColumn)
  private
    FCaption, FTabIcon: string;
    procedure SetCaption(const AValue: string);
    procedure SetTabIcon(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
    { The icon of its tab (Pastel's icons: 'home', 'search', 'settings'...),
      above the caption on tabs at the bottom. }
    property TabIcon: string read FTabIcon write SetTabIcon;
  end;

  { Tabs above the pages (a computer's), or below them across the whole width
    with icons (a phone app's bottom navigation). }
  TTabPosition = (tpTop, tpBottom);

  { Pages with tabs above them; its children are TTabSheets. }
  TTabControl = class(TControl)
  private
    FTabPosition: TTabPosition;
    procedure SetTabPosition(AValue: TTabPosition);
  private
    FTabIndex: Integer;
    FOnChange: TNotifyEvent;
    FTabRects: array of TRectI;
    procedure SetTabIndex(AValue: Integer);
    function HeaderHeight: Integer;
    function SheetCount: Integer;
    function Sheet(Index: Integer): TTabSheet;
    procedure SyncSheets;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure PaintBottomTabs(C: TCanvas32);
  public
    constructor Create(AOwner: TComponent); override;
    function ActiveSheet: TTabSheet;
    procedure ScrollIntoView(C: TControl); override;
    { Where the tab of a page is. }
    function TabRect(ASheet: TTabSheet): TRectI;
  published
    property TabIndex: Integer read FTabIndex write SetTabIndex default 0;
    property TabPosition: TTabPosition read FTabPosition write SetTabPosition default tpTop;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { How far a task is: Position of Max; Indeterminate when that is not known. }
  TProgressBar = class(TControl)
  private
    FPosition, FMax: Integer;
    FIndeterminate: Boolean;
    procedure SetPosition(AValue: Integer);
    procedure SetMax(AValue: Integer);
    procedure SetIndeterminate(AValue: Boolean);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Position: Integer read FPosition write SetPosition default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Indeterminate: Boolean read FIndeterminate write SetIndeterminate default False;
  end;

  { Choose a number by dragging a knob. }
  TSlider = class(TControl)
  private
    FMin, FMax, FPosition, FStep: Integer;
    FOnChange: TNotifyEvent;
    procedure SetMin(AValue: Integer);
    procedure SetMax(AValue: Integer);
    procedure SetPosition(AValue: Integer);
    function TrackRect: TRectI;
    function ValueAt(X: Integer): Integer;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    { Arrow keys and the wheel move by this much. }
    property Step: Integer read FStep write FStep default 1;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { A turning circle of dots: something is happening. }
  TSpinner = class(TControl)
  private
    FActive: Boolean;
    procedure SetActive(AValue: Boolean);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Active: Boolean read FActive write SetActive default True;
  end;

  { A bar between two controls of a TRow (or a TColumn) that the user drags
    to share the room between them. It changes the Width (in a column: the
    Height) of the control before it; give that one a Width and the one after
    it Grow = 1. }
  TSplitter = class(TControl)
  private
    FMinSize: Integer;
    FDragging: Boolean;
    FStartPos, FStartSize: Integer;
    FOnMoved: TNotifyEvent;
    function Vertical: Boolean;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function FillsAcross: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
  public
    class function DesktopOnly: Boolean; override;
    constructor Create(AOwner: TComponent); override;
    { The control it resizes: the visible one before it; nil when there is none. }
    function Target: TControl;
    { Gives the target this size (clamped between MinSize and the room there is). }
    procedure MoveTo(Size: Integer);
  published
    { The smallest size of the controls on both sides. }
    property MinSize: Integer read FMinSize write FMinSize default 80;
    { The user let go of it at a new place. }
    property OnMoved: TNotifyEvent read FOnMoved write FOnMoved;
  end;

  { A row of buttons at the top of a form, under the menu: put TButtons with
    Style = Flat in it (and a TSpacer to push the rest to the right). }
  TToolBar = class(TRow)
  protected
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { A line at the bottom of a form that says what is going on. Text is shown
    when it has no children; otherwise put TLabels in it (a TSpacer between
    them pushes the next ones to the right). }
  TStatusBar = class(TRow)
  private
    FText: string;
    procedure SetText(const AValue: string);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    class function DesktopOnly: Boolean; override;
    constructor Create(AOwner: TComponent); override;
  published
    property Text: string read FText write SetText;
  end;

{ Where a file named in a .pform (pictures) is: a full path, next to the
  program, in assets/ next to it or in the current folder. }
function FindAppFile(const FileName: string): string;

implementation

uses
  Math, StrUtils, Pastel.Assets, Pastel.Icons;

{ ---- TDrawer ---- }

constructor TDrawer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Side := psLeft;
  Radius := 0;
  Padding := 16;
  Gap := 4;
  { not on the form until Open; the designer shows it where it is }
  Visible := (AOwner <> nil) and (csDesigning in AOwner.ComponentState);
end;

function TDrawer.GetSide: TPopupSide;
begin
  Result := inherited Side;
end;

procedure TDrawer.SetSide(AValue: TPopupSide);
begin
  inherited Side := AValue;
end;

procedure TDrawer.Open;
var
  F: TForm;
begin
  if IsOpen then
    Exit;
  F := FHome;
  if F = nil then
  begin
    F := ParentForm;
    if F = nil then
      F := MainForm;
    FHome := F;
  end;
  if F = nil then
    Exit;
  { out of the form's layout, above it }
  if Parent <> nil then
    Parent := nil;
  Visible := True;
  PopupCentered(F);
  if Assigned(FOnOpen) then
    FOnOpen(Self);
end;

procedure TDrawer.Toggle;
begin
  if IsOpen then
    Close
  else
    Open;
end;

function TDrawer.IsOpen: Boolean;
begin
  Result := Shown;
end;

constructor TBottomSheet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Side := psBottom;
  Radius := 16;
end;

function FindAppFile(const FileName: string): string;
var
  Dir: string;
begin
  if (FileName = '') or FileExists(FileName) then
    Exit(FileName);
  Dir := ExtractFilePath(ParamStr(0));
  for Result in [Dir + FileName, Dir + 'assets' + PathDelim + FileName, 'assets' + PathDelim + FileName] do
    if FileExists(Result) then
      Exit;
  Result := FileName;
end;

procedure PaintFocusRing(Ctrl: TControl; C: TCanvas32; const R: TRectI; Radius: Integer);
var
  F: TForm;
begin
  F := Ctrl.ParentForm;
  if (F <> nil) and (F.Focused = Ctrl) and F.FocusVisible then
    DrawFocus(C, R, Radius);
end;

procedure PaintChevron(C: TCanvas32; CX, CY: Integer; Down: Boolean; Col: TColor32);
begin
  if Down then
  begin
    C.DrawLine(CX - 4, CY - 2, CX, CY + 2, 1.6, Col);
    C.DrawLine(CX, CY + 2, CX + 4, CY - 2, 1.6, Col);
  end
  else
  begin
    C.DrawLine(CX - 4, CY + 2, CX, CY - 2, 1.6, Col);
    C.DrawLine(CX, CY - 2, CX + 4, CY + 2, 1.6, Col);
  end;
end;

{ ---- TCheckBox ---- }

procedure TCheckBox.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
end;

procedure TCheckBox.SetChecked(AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  Invalidate;
  if Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

function TCheckBox.MarkWidth: Integer;
begin
  Result := UIStyle.CheckSize;
end;

function TCheckBox.MarkHeight: Integer;
begin
  Result := UIStyle.CheckSize;
end;

procedure TCheckBox.Measure(AvailWidth: Integer; out W, H: Integer);
var
  F: TPastelFont;
begin
  F := GetFont(Theme.FontSize);
  W := MarkWidth;
  if FText <> '' then
    Inc(W, 8 + F.TextWidth(FText));
  H := Math.Max(MarkHeight + 4, F.LineHeight + 4);
end;

procedure TCheckBox.PaintMark(C: TCanvas32; X, Y: Integer);
var
  Border: TColor32;
  S, R: Integer;
  K: Single;
begin
  S := UIStyle.CheckSize;
  R := UIStyle.CheckRadius;
  K := S / 18;     { the tick was drawn for 18 pixels }
  if FChecked then
  begin
    if Enabled then Border := Theme.Accent else Border := Theme.Disabled;
    C.FillRoundRect(X, Y, S, S, R, Border);
    C.DrawLine(X + 4.5 * K, Y + 9.5 * K, X + 7.8 * K, Y + 12.8 * K, 2, Theme.OnAccent);
    C.DrawLine(X + 7.8 * K, Y + 12.8 * K, X + 13.5 * K, Y + 5.5 * K, 2, Theme.OnAccent);
  end
  else
  begin
    if IsHovered and Enabled then Border := Theme.BorderHover
    else if UIStyle.FieldLook = flBox then Border := Theme.Border
    else Border := Theme.Outline;
    if not Enabled then
      Border := Theme.Disabled;
    C.FillRoundRect(X, Y, S, S, R, Theme.Surface);
    if UIStyle.SwitchLook = swMaterial then
      C.StrokeRoundRect(X, Y, S, S, R, 2, Border)
    else
      C.StrokeRoundRect(X, Y, S, S, R, 1.5, Border);
  end;
end;

procedure TCheckBox.Paint(C: TCanvas32);
var
  F: TPastelFont;
  MY: Integer;
  Col: TColor32;
begin
  F := GetFont(Theme.FontSize);
  MY := Bounds.Y + (Bounds.H - MarkHeight) div 2;
  PaintFocusRing(Self, C, RectI(Bounds.X, MY, MarkWidth, MarkHeight), Math.Min(MarkHeight div 2, UIStyle.CheckRadius + 2));
  PaintMark(C, Bounds.X, MY);
  if FText <> '' then
  begin
    if Enabled then Col := Theme.Text else Col := Theme.Disabled;
    C.PushClip(Bounds);
    C.DrawText(F, Bounds.X + MarkWidth + 8, Bounds.Y + (Bounds.H - F.LineHeight) div 2, FText, Col);
    C.PopClip;
  end;
end;

function TCheckBox.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TCheckBox.Cursor: TCursorKind;
begin
  if Enabled then Result := ckHand else Result := ckArrow;
end;

procedure TCheckBox.Toggle;
begin
  Checked := not Checked;
end;

procedure TCheckBox.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  if Inside and Enabled then
    Toggle;
end;

function TCheckBox.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := Key = KEY_SPACE;
  if Result and Enabled then
    Toggle;
end;

{ ---- TRadioButton ---- }

procedure TRadioButton.SetChecked(AValue: Boolean);
var
  I: Integer;
  Sib: TControl;
begin
  if AValue and (Parent <> nil) then
    for I := 0 to Parent.ChildCount - 1 do
    begin
      Sib := Parent.Children[I];
      if (Sib <> Self) and (Sib is TRadioButton) and TRadioButton(Sib).Checked then
        TRadioButton(Sib).SetChecked(False);
    end;
  inherited SetChecked(AValue);
end;

procedure TRadioButton.Toggle;
begin
  Checked := True;
end;

procedure TRadioButton.PaintMark(C: TCanvas32; X, Y: Integer);
var
  Col: TColor32;
  H, Ring: Single;
begin
  H := UIStyle.CheckSize / 2;
  if UIStyle.SwitchLook = swMaterial then Ring := 2 else Ring := 1.5;
  if FChecked then
  begin
    if Enabled then Col := Theme.Accent else Col := Theme.Disabled;
    if UIStyle.SwitchLook = swMaterial then
    begin
      { Material: a ring and a dot, both in the accent }
      C.FillCircle(X + H, Y + H, H, Col);
      C.FillCircle(X + H, Y + H, H - Ring, Theme.Surface);
      C.FillCircle(X + H, Y + H, H * 0.5, Col);
    end
    else
    begin
      C.FillCircle(X + H, Y + H, H, Col);
      C.FillCircle(X + H, Y + H, H * 0.4, Theme.OnAccent);
    end;
  end
  else
  begin
    if IsHovered and Enabled then Col := Theme.BorderHover
    else if UIStyle.FieldLook = flBox then Col := Theme.Border
    else Col := Theme.Outline;
    if not Enabled then
      Col := Theme.Disabled;
    C.FillCircle(X + H, Y + H, H, Col);
    C.FillCircle(X + H, Y + H, H - Ring, Theme.Surface);
  end;
end;

{ arrows move to the next radio button next to this one }
function TRadioButton.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  I, J, Step: Integer;
  Sib: TControl;
begin
  if (Key = KEY_UP) or (Key = KEY_LEFT) or (Key = KEY_DOWN) or (Key = KEY_RIGHT) then
  begin
    Result := True;
    if Parent = nil then Exit;
    if (Key = KEY_UP) or (Key = KEY_LEFT) then Step := -1 else Step := 1;
    I := 0;
    while (I < Parent.ChildCount) and (Parent.Children[I] <> Self) do
      Inc(I);
    J := I + Step;
    while (J >= 0) and (J < Parent.ChildCount) do
    begin
      Sib := Parent.Children[J];
      if (Sib is TRadioButton) and Sib.Visible and Sib.Enabled then
      begin
        TRadioButton(Sib).Checked := True;
        Sib.SetFocus;
        Exit;
      end;
      Inc(J, Step);
    end;
    Exit;
  end;
  Result := inherited KeyDown(Key, Shift, Ctrl);
end;

{ ---- TSwitch ---- }

function TSwitch.MarkWidth: Integer;
begin
  case UIStyle.SwitchLook of
    swFluent: Result := 40;
    swMaterial: Result := 52;
  else
    Result := 36;
  end;
end;

function TSwitch.MarkHeight: Integer;
begin
  case UIStyle.SwitchLook of
    swMaterial: Result := 32;
  else
    Result := 18;
  end;
end;

procedure TSwitch.PaintMark(C: TCanvas32; X, Y: Integer);
var
  Track, Knob: TColor32;
  W, H: Integer;
  R: Single;
begin
  W := MarkWidth;
  case UIStyle.SwitchLook of
    swFluent:
      begin
        { Windows 11: an outline with a small dot when off, filled when on }
        H := 20;
        Y := Y - 1;
        if FChecked and Enabled then
        begin
          if IsHovered then Track := Theme.AccentHover else Track := Theme.Accent;
          C.FillRoundRect(X, Y, W, H, H / 2, Track);
          if IsHovered then R := 7 else R := 6;
          C.FillCircle(X + W - 10, Y + H / 2, R, Theme.OnAccent);
        end
        else
        begin
          if Enabled then Knob := Theme.TextMuted else Knob := Theme.Disabled;
          if IsHovered and Enabled then
            C.FillRoundRect(X, Y, W, H, H / 2, WithAlpha(Theme.Text, $0A));
          C.StrokeRoundRect(X, Y, W, H, H / 2, 1, Knob);
          if IsHovered and Enabled then R := 7 else R := 6;
          if FChecked then
            C.FillCircle(X + W - 10, Y + H / 2, R, Knob)
          else
            C.FillCircle(X + 10, Y + H / 2, R, Knob);
        end;
      end;
    swMaterial:
      begin
        { Material 3: a big round track; the knob grows when on }
        H := 32;
        if FChecked then
        begin
          if Enabled then Track := Theme.Accent else Track := WithAlpha(Theme.Text, $1F);
          C.FillRoundRect(X, Y, W, H, H / 2, Track);
          if Enabled then Knob := Theme.OnAccent else Knob := Theme.Surface;
          C.FillCircle(X + W - 16, Y + 16, 12, Knob);
        end
        else
        begin
          if Enabled then Knob := Theme.Outline else Knob := Theme.Disabled;
          C.FillRoundRect(X, Y, W, H, H / 2, Mix(Theme.Surface, Theme.Text, 0.08));
          C.StrokeRoundRect(X, Y, W, H, H / 2, 2, Knob);
          if IsHovered and Enabled then
            C.FillCircle(X + 16, Y + 16, 9, Theme.TextMuted)
          else
            C.FillCircle(X + 16, Y + 16, 8, Knob);
        end;
      end;
  else
    Y := Y - 1;
    if not Enabled then
      Track := Theme.Disabled
    else if FChecked then
      Track := Theme.Accent
    else if IsHovered then
      Track := Theme.BorderHover
    else
      Track := Theme.Border;
    C.FillRoundRect(X, Y, 36, 20, 10, Track);
    if FChecked then
      C.FillCircle(X + 26, Y + 10, 7.5, Theme.Surface)
    else
      C.FillCircle(X + 10, Y + 10, 7.5, Theme.Surface);
  end;
end;

{ ---- TListBox ---- }

constructor TListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FHotIndex := -1;
  FMoveFrom := -1;
end;

destructor TListBox.Destroy;
begin
  FItems.OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

function TListBox.Font: TPastelFont;
begin
  Result := GetFont(Theme.FontSize);
end;

procedure TListBox.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := FItems.Count - 1;
  ClampTop;
  Changed;
end;

function TListBox.GetItems: TStrings;
begin
  Result := FItems;
end;

procedure TListBox.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);
end;

procedure TListBox.SetItemIndex(AValue: Integer);
begin
  AValue := EnsureRange(AValue, -1, FItems.Count - 1);
  if FItemIndex = AValue then Exit;
  FItemIndex := AValue;
  if FItemIndex >= 0 then
    MakeVisible(FItemIndex);
  Invalidate;
  if Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

procedure TListBox.SetItemHeight(AValue: Integer);
begin
  FItemHeight := Math.Max(0, AValue);
  Changed;
end;

function TListBox.SelectedText: string;
begin
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
    Result := FItems[FItemIndex]
  else
    Result := '';
end;

function TListBox.RowHeight: Integer;
begin
  if FItemHeight > 0 then
    Result := FItemHeight
  else
    Result := Font.LineHeight + 12;
end;

function TListBox.ContentHeight: Integer;
begin
  Result := FItems.Count * RowHeight;
end;

function TListBox.InnerHeight: Integer;
begin
  Result := Math.Max(0, Bounds.H - 4);
end;

procedure TListBox.ClampTop;
begin
  if Bounds.H = 0 then
    Exit;     { not laid out yet (and maybe no fonts: a .pform check) }
  FTop := EnsureRange(FTop, 0, Math.Max(0, ContentHeight - InnerHeight));
end;

procedure TListBox.MakeVisible(Index: Integer);
var
  Y: Integer;
begin
  if (Index < 0) or (Bounds.H = 0) then
    Exit;
  Y := Index * RowHeight;
  if Y < FTop then
    FTop := Y;
  if Y + RowHeight > FTop + InnerHeight then
    FTop := Y + RowHeight - InnerHeight;
  ClampTop;
  Invalidate;
end;

function TListBox.IndexAt(Y: Integer): Integer;
begin
  Result := (Y - Bounds.Y - 2 + FTop) div RowHeight;
  if (Y < Bounds.Y + 2) or (Result < 0) or (Result >= FItems.Count) then
    Result := -1;
end;

function TListBox.BarRect: TRectI;
var
  H, Len, Pos: Integer;
begin
  H := InnerHeight;
  if ContentHeight <= H then
    Exit(RectI(0, 0, 0, 0));
  Len := Math.Max(24, H * H div ContentHeight);
  Pos := (H - Len) * FTop div Math.Max(1, ContentHeight - H);
  Result := RectI(Bounds.X + Bounds.W - 9, Bounds.Y + 2 + Pos, 6, Len);
end;

procedure TListBox.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 200;
  H := Math.Max(1, Math.Min(Math.Max(FItems.Count, 3), 8)) * RowHeight + 4;
end;

procedure TListBox.Paint(C: TCanvas32);
var
  GX: Integer;
  F: TPastelFont;
  I, First, Last, Y, RH: Integer;
  Bg, Fg, Border: TColor32;
  Bar: TRectI;
begin
  F := Font;
  RH := RowHeight;
  ClampTop;
  if IsFocused and not FHotTrack then
  begin
    DrawFocus(C, Self, Bounds, Theme.Radius);
    Border := Theme.Accent;
  end
  else
    Border := Theme.Border;
  if not FHotTrack then
  begin
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);
    C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Border);
  end;
  C.PushClip(RectI(Bounds.X + 1, Bounds.Y + 2, Bounds.W - 2, Bounds.H - 4));
  First := FTop div RH;
  Last := Math.Min(FItems.Count - 1, (FTop + InnerHeight) div RH);
  for I := First to Last do
  begin
    Y := Bounds.Y + 2 + I * RH - FTop;
    Fg := Theme.Text;
    Bg := 0;
    if I = FItemIndex then
    begin
      if IsFocused or FHotTrack then
      begin
        Bg := Theme.Accent;
        Fg := Theme.OnAccent;
      end
      else
        Bg := Theme.SecondaryPressed;
    end
    else if (I = FHotIndex) and Enabled then
      Bg := Theme.SecondaryHover;
    if not Enabled then
      Fg := Theme.Disabled;
    if Bg <> 0 then
      C.FillRoundRect(Bounds.X + 4, Y + 1, Bounds.W - 8, RH - 2, 6, Bg);
    C.DrawText(F, Bounds.X + 12, Y + (RH - F.LineHeight) div 2, FItems[I], Fg);
  end;
  { the grips; while a row moves, where it goes }
  if FAllowReorder then
  begin
    GX := Bounds.X + Bounds.W - 4 - ReorderGripWidth;
    if BarRect.H > 0 then
      Dec(GX, 12);
    for I := First to Last do
    begin
      Y := Bounds.Y + 2 + I * RH - FTop;
      if (I = FItemIndex) and (IsFocused or FHotTrack) then
        DrawGrip(C, GX, Y, ReorderGripWidth, RH, Theme.OnAccent)
      else
        DrawGrip(C, GX, Y, ReorderGripWidth, RH, Theme.TextMuted);
    end;
    if FMoveFrom >= 0 then
    begin
      Y := Bounds.Y + 2 + FMoveTo * RH - FTop;
      C.FillRoundRect(Bounds.X + 4, Y - 1, Bounds.W - 8, 3, 1.5, Theme.Accent);
    end;
  end;
  C.PopClip;
  Bar := BarRect;
  if Bar.H > 0 then
    C.FillRoundRect(Bar.X, Bar.Y, Bar.W, Bar.H, 3, WithAlpha(Theme.TextMuted, $90));
end;

function TListBox.Focusable: Boolean;
begin
  Result := Enabled and not FHotTrack;
end;

{ the row whose grip (the ≡ at its right) is at X, Y; -1 when none }
function TListBox.GripAt(X, Y: Integer): Integer;
var
  Right: Integer;
begin
  Result := -1;
  if not FAllowReorder then
    Exit;
  Right := Bounds.X + Bounds.W - 4;
  if BarRect.H > 0 then
    Dec(Right, 12);
  if (X >= Right - ReorderGripWidth) and (X < Right) then
    Result := IndexAt(Y);
end;

function TListBox.DragsAt(X, Y: Integer): Boolean;
begin
  Result := (GripAt(X, Y) >= 0) or inherited DragsAt(X, Y);
end;

function TListBox.DragData(X, Y: Integer): string;
begin
  Result := SelectedText;
end;

procedure TListBox.SetAllowReorder(AValue: Boolean);
begin
  FAllowReorder := AValue;
  Invalidate;
end;

{ AFrom goes to the place ATo (an index in the new order) }
procedure TListBox.MoveRow(AFrom, ATo: Integer);
begin
  ATo := EnsureRange(ATo, 0, FItems.Count - 1);
  if (AFrom < 0) or (AFrom >= FItems.Count) or (AFrom = ATo) then
    Exit;
  FItems.Move(AFrom, ATo);
  FItemIndex := ATo;
  MakeVisible(ATo);
  Invalidate;
  if Assigned(FOnReorder) then
    FOnReorder(Self, AFrom, ATo);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TListBox.MouseDown(X, Y: Integer);
var
  I: Integer;
  Bar: TRectI;
  F: TForm;
begin
  FMoveFrom := GripAt(X, Y);
  if FMoveFrom >= 0 then
  begin
    { picked up by its grip: it follows the mouse (the finger) until let go }
    FMoveTo := FMoveFrom;
    ItemIndex := FMoveFrom;
    Exit;
  end;
  Bar := BarRect;
  if (Bar.H > 0) and (X >= Bar.X - 4) then
  begin
    FDraggingBar := True;
    if (Y >= Bar.Y) and (Y < Bar.Y + Bar.H) then
      FDragOffset := Y - Bar.Y
    else
      FDragOffset := Bar.H div 2;
    MouseMove(X, Y);
    Exit;
  end;
  I := IndexAt(Y);
  if I < 0 then
    Exit;
  if not FHotTrack then
    ItemIndex := I;
  F := ParentForm;
  if (F <> nil) and (F.ClickCount = 2) and (I = FItemIndex) and Assigned(FOnDblClick) then
    FOnDblClick(Self);
end;

procedure TListBox.MouseMove(X, Y: Integer);
var
  I, H, Len: Integer;
  F: TForm;
begin
  F := ParentForm;
  if (FMoveFrom >= 0) and (F <> nil) and (F.Captured = Self) then
  begin
    { the gap nearest to the mouse: before row FMoveTo }
    FMoveTo := EnsureRange((Y - Bounds.Y - 2 + FTop + RowHeight div 2) div RowHeight, 0, FItems.Count);
    { near the edges the list scrolls }
    if Y < Bounds.Y + RowHeight div 2 then
      FTop := FTop - RowHeight div 3
    else if Y > Bounds.Y + Bounds.H - RowHeight div 2 then
      FTop := FTop + RowHeight div 3;
    ClampTop;
    Invalidate;
    Exit;
  end;
  if FDraggingBar and (F <> nil) and (F.Captured = Self) then
  begin
    H := InnerHeight;
    Len := BarRect.H;
    FTop := (Y - FDragOffset - Bounds.Y - 2) * Math.Max(1, ContentHeight - H) div Math.Max(1, H - Len);
    ClampTop;
    Invalidate;
    Exit;
  end;
  I := IndexAt(Y);
  if I <> FHotIndex then
  begin
    FHotIndex := I;
    if FHotTrack and (I >= 0) then
      FItemIndex := I;
    Invalidate;
  end;
end;

procedure TListBox.MouseUp(X, Y: Integer; Inside: Boolean);
var
  I, From: Integer;
begin
  if FMoveFrom >= 0 then
  begin
    From := FMoveFrom;
    FMoveFrom := -1;
    I := FMoveTo;
    if I > From then
      Dec(I);             { the gap counted the row itself }
    MoveRow(From, I);
    Invalidate;
    Exit;
  end;
  if FDraggingBar then
  begin
    FDraggingBar := False;
    Exit;
  end;
  I := IndexAt(Y);
  if Inside and (I >= 0) then
  begin
    if FHotTrack then
      FItemIndex := I;
    if Assigned(FOnItemClick) then
      FOnItemClick(Self);
  end;
end;

function TListBox.MouseWheel(DX, DY: Integer): Boolean;
begin
  Result := ContentHeight > InnerHeight;
  if not Result then
    Exit;
  Dec(FTop, DY * RowHeight * 3);
  ClampTop;
  Invalidate;
end;

function TListBox.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  Page: Integer;
begin
  Result := True;
  Page := Math.Max(1, InnerHeight div RowHeight - 1);
  { Ctrl+Up/Down moves the row (AllowReorder) }
  if Ctrl and FAllowReorder and (FItemIndex >= 0) and ((Key = KEY_UP) or (Key = KEY_DOWN)) then
  begin
    if Key = KEY_UP then
      MoveRow(FItemIndex, FItemIndex - 1)
    else
      MoveRow(FItemIndex, FItemIndex + 1);
    Exit;
  end;
  case Key of
    KEY_UP: ItemIndex := Math.Max(0, FItemIndex - 1);
    KEY_DOWN: ItemIndex := Math.Min(FItems.Count - 1, FItemIndex + 1);
    KEY_PAGEUP: ItemIndex := Math.Max(0, FItemIndex - Page);
    KEY_PAGEDOWN: ItemIndex := Math.Min(FItems.Count - 1, FItemIndex + Page);
    KEY_HOME: ItemIndex := 0;
    KEY_END: ItemIndex := FItems.Count - 1;
    KEY_ENTER, KEY_KP_ENTER:
      if (FItemIndex >= 0) and Assigned(FOnDblClick) then
        FOnDblClick(Self)
      else
        Result := False;
  else
    Result := False;
  end;
end;

{ typing a letter goes to the next item that starts with it }
procedure TListBox.TextInput(const S: string);
var
  I, J: Integer;
begin
  if (S = '') or (FItems.Count = 0) then
    Exit;
  for J := 1 to FItems.Count do
  begin
    I := (FItemIndex + J) mod FItems.Count;
    if AnsiStartsText(S, FItems[I]) then
    begin
      ItemIndex := I;
      Exit;
    end;
  end;
end;

{ ---- TComboBox ---- }

constructor TComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
end;

destructor TComboBox.Destroy;
begin
  if (FPopup <> nil) and FPopup.Shown then
    FPopup.Close;
  FItems.OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

procedure TComboBox.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := FItems.Count - 1;
  Changed;
end;

function TComboBox.GetItems: TStrings;
begin
  Result := FItems;
end;

procedure TComboBox.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);
end;

procedure TComboBox.SetItemIndex(AValue: Integer);
begin
  AValue := EnsureRange(AValue, -1, FItems.Count - 1);
  if FItemIndex = AValue then Exit;
  FItemIndex := AValue;
  Invalidate;
  if Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

procedure TComboBox.SetPlaceholder(const AValue: string);
begin
  FPlaceholder := AValue;
  Invalidate;
end;

function TComboBox.GetText: string;
begin
  if FItemIndex >= 0 then
    Result := FItems[FItemIndex]
  else
    Result := '';
end;

procedure TComboBox.SetText(const AValue: string);
begin
  ItemIndex := FItems.IndexOf(AValue);
end;

function TComboBox.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.Shown;
end;

procedure TComboBox.DropDown;
var
  F: TForm;
  RH: Integer;
begin
  F := ParentForm;
  if (F = nil) or DroppedDown or (FItems.Count = 0) then
    Exit;
  if FPopup = nil then
  begin
    FPopup := TPopup.Create(Self);
    FPopup.Padding := 4;
    FList := TListBox.Create(FPopup);
    FList.HotTrack := True;
    FList.Parent := FPopup;
    FList.OnItemClick := @ListClicked;
  end;
  FList.Items := FItems;
  RH := FList.RowHeight;
  FList.Height := Math.Min(FItems.Count, 8) * RH + 4;
  FPopup.Width := Bounds.W;
  FList.ItemIndex := FItemIndex;
  FPopup.Popup(F, Bounds);
  FList.MakeVisible(Math.Max(0, FItemIndex));
  Invalidate;
end;

procedure TComboBox.CloseUp;
begin
  if DroppedDown then
    FPopup.Close;
  Invalidate;
end;

procedure TComboBox.Choose(Index: Integer);
begin
  CloseUp;
  ItemIndex := Index;
end;

procedure TComboBox.ListClicked(Sender: TObject);
begin
  Choose(FList.ItemIndex);
  SetFocus;
end;

procedure TComboBox.Measure(AvailWidth: Integer; out W, H: Integer);
var
  F: TPastelFont;
  I: Integer;
begin
  F := GetFont(Theme.FontSize);
  W := 160;
  for I := 0 to FItems.Count - 1 do
    W := Math.Max(W, F.TextWidth(FItems[I]) + 56);
  W := Math.Min(W, 360);
  H := FieldHeight(F.LineHeight);
end;

procedure TComboBox.Paint(C: TCanvas32);
var
  F: TPastelFont;
  Col: TColor32;
  S: string;
begin
  F := GetFont(Theme.FontSize);
  PaintField(C, Bounds, IsFocused, IsHovered, Enabled, True, False, Look);
  S := GetText;
  Col := Theme.Text;
  if S = '' then
  begin
    S := FPlaceholder;
    Col := Theme.Placeholder;
  end;
  if not Enabled then
    Col := Theme.Disabled;
  C.PushClip(RectI(Bounds.X + UIStyle.FieldPadX, Bounds.Y, Bounds.W - 28 - UIStyle.FieldPadX, Bounds.H));
  C.DrawText(F, Bounds.X + UIStyle.FieldPadX, Bounds.Y + (Bounds.H - F.LineHeight) div 2, S, Col);
  C.PopClip;
  PaintChevron(C, Bounds.X + Bounds.W - 18, Bounds.Y + Bounds.H div 2, not DroppedDown, Theme.TextMuted);
end;

function TComboBox.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TComboBox.Cursor: TCursorKind;
begin
  if Enabled then Result := ckHand else Result := ckArrow;
end;

procedure TComboBox.MouseDown(X, Y: Integer);
begin
  if DroppedDown then
    CloseUp
  else
    DropDown;
end;

function TComboBox.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := True;
  if DroppedDown then
    case Key of
      KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END:
        FList.KeyDown(Key, Shift, Ctrl);
      KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
        Choose(FList.ItemIndex);
      KEY_ESCAPE, KEY_TAB:
        begin
          CloseUp;
          Result := Key = KEY_ESCAPE;
        end;
    else
      Result := False;
    end
  else
    case Key of
      KEY_UP: ItemIndex := Math.Max(0, FItemIndex - 1);
      KEY_DOWN:
        if KeyAlt then DropDown else ItemIndex := Math.Min(FItems.Count - 1, FItemIndex + 1);
      KEY_HOME: ItemIndex := 0;
      KEY_END: ItemIndex := FItems.Count - 1;
      KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: DropDown;
    else
      if Key = KEY_F1 + 3 then     { F4 }
        DropDown
      else
        Result := False;
    end;
  Invalidate;
end;

procedure TComboBox.TextInput(const S: string);
var
  I, J: Integer;
begin
  if S = '' then
    Exit;
  for J := 1 to FItems.Count do
  begin
    I := (FItemIndex + J) mod FItems.Count;
    if AnsiStartsText(S, FItems[I]) then
    begin
      if DroppedDown then
      begin
        FList.ItemIndex := I;
        FList.MakeVisible(I);
      end
      else
        ItemIndex := I;
      Exit;
    end;
  end;
end;

{ ---- TImage ---- }

constructor TImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPicture := TBitmap32.Create;
end;

destructor TImage.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

procedure TImage.SetFileName(const AValue: string);
begin
  FFileName := AValue;
  FError := '';
  FPicture.SetSize(0, 0);
  if AValue <> '' then
  try
    if not FileExists(AValue) and AssetExists(AValue) then
      LoadPicture
    else
      FPicture.LoadFromFile(FindAppFile(AValue));
  except
    on E: Exception do
      FError := E.Message;
  end;
  Changed;
end;

procedure TImage.LoadPicture;
var
  S: TStream;
begin
  S := OpenAsset(FFileName);
  try
    FPicture.LoadFromStream(S);
  finally
    S.Free;
  end;
end;

procedure TImage.LoadFromStream(Stream: TStream);
begin
  FError := '';
  FPicture.LoadFromStream(Stream);
  Changed;
end;

procedure TImage.SetFit(AValue: TImageFit);
begin
  FFit := AValue;
  Invalidate;
end;

procedure TImage.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  if FPicture.Empty then
  begin
    W := 64;
    H := 64;
    Exit;
  end;
  W := FPicture.Width;
  H := FPicture.Height;
  { a fixed width or height keeps the proportions }
  if (Width > 0) and (Height = 0) then
    H := Round(FPicture.Height * Width / FPicture.Width)
  else if (Height > 0) and (Width = 0) then
    W := Round(FPicture.Width * Height / FPicture.Height)
  else if (Width = 0) and (W > AvailWidth) and (AvailWidth > 0) then
  begin
    H := Round(H * AvailWidth / W);
    W := AvailWidth;
  end;
end;

procedure TImage.SetUrl(const AValue: string);
begin
  if FUrl = AValue then
    Exit;
  FUrl := AValue;
  Invalidate;
end;

procedure TImage.Paint(C: TCanvas32);
var
  Scale: Double;
  W, H: Integer;
  Pic: TBitmap32;
  Failed: Boolean;
begin
  Pic := FPicture;
  if (FUrl <> '') and Assigned(WebImageHook) then
  begin
    WebImageHook(FUrl, Pic, Failed);
    if Failed then
      FError := 'the picture could not be fetched';
    if Pic = nil then
      Pic := FPicture;
  end;
  if Pic.Empty then
  begin
    if csDesigning in ComponentState then
      C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, 4, 1, Theme.Border);
    Exit;
  end;
  case FFit of
    ifStretch:
      begin
        W := Bounds.W;
        H := Bounds.H;
      end;
    ifCenter:
      begin
        W := Pic.Width;
        H := Pic.Height;
      end;
  else
    if FFit = ifCover then
      Scale := Math.Max(Bounds.W / Pic.Width, Bounds.H / Pic.Height)
    else
      Scale := Math.Min(Bounds.W / Pic.Width, Bounds.H / Pic.Height);
    W := Math.Max(1, Round(Pic.Width * Scale));
    H := Math.Max(1, Round(Pic.Height * Scale));
  end;
  C.PushClip(Bounds);
  C.DrawBitmap(Pic, Bounds.X + (Bounds.W - W) div 2, Bounds.Y + (Bounds.H - H) div 2, W, H, True,
    255 - 155 * Ord(not Enabled));
  C.PopClip;
end;

{ ---- TScrollBox ---- }

procedure TScrollBox.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  inherited Measure(AvailWidth, W, H);
  H := Math.Min(H, 240);    { give it Grow or a Height to use more room }
end;

procedure TScrollBox.Arrange(const R: TRectI);
var
  CW, CH: Integer;
begin
  inherited Measure(R.W - 10, CW, CH);
  FContentH := CH;
  FScrollY := EnsureRange(FScrollY, 0, Math.Max(0, FContentH - R.H));
  inherited Arrange(RectI(R.X, R.Y - FScrollY, Math.Max(0, R.W - 10 * Ord(FContentH > R.H)),
    Math.Max(R.H, FContentH)));
  { the box itself stays where it was put; only its content moved }
  SetBoundsOnly(R);
end;

function TScrollBox.BarRect: TRectI;
var
  Len, Pos: Integer;
begin
  if FContentH <= Bounds.H then
    Exit(RectI(0, 0, 0, 0));
  Len := Math.Max(24, Bounds.H * Bounds.H div FContentH);
  Pos := (Bounds.H - Len) * FScrollY div Math.Max(1, FContentH - Bounds.H);
  Result := RectI(Bounds.X + Bounds.W - 7, Bounds.Y + Pos, 6, Len);
end;

procedure TScrollBox.Paint(C: TCanvas32);
var
  Bar: TRectI;
begin
  C.PushClip(Bounds);
  inherited Paint(C);
  C.PopClip;
  Bar := BarRect;
  if Bar.H > 0 then
    C.FillRoundRect(Bar.X, Bar.Y, Bar.W, Bar.H, 3, WithAlpha(Theme.TextMuted, $90));
  if FPullRefresh <> nil then
    FPullRefresh.Paint(C);
end;

function TScrollBox.GetOnRefresh: TNotifyEvent;
begin
  if FPullRefresh = nil then
    Result := nil
  else
    Result := FPullRefresh.OnRefresh;
end;

procedure TScrollBox.SetOnRefresh(AValue: TNotifyEvent);
begin
  if FPullRefresh = nil then
    FPullRefresh := TPullRefresh.Create(Self);
  FPullRefresh.OnRefresh := AValue;
end;

function TScrollBox.GetRefreshing: Boolean;
begin
  Result := (FPullRefresh <> nil) and FPullRefresh.Refreshing;
end;

procedure TScrollBox.SetRefreshing(AValue: Boolean);
begin
  if FPullRefresh = nil then
    FPullRefresh := TPullRefresh.Create(Self);
  FPullRefresh.Refreshing := AValue;
end;

procedure TScrollBox.SetScrollY(AValue: Integer);
begin
  AValue := EnsureRange(AValue, 0, Math.Max(0, FContentH - Bounds.H));
  if AValue = FScrollY then Exit;
  FScrollY := AValue;
  Changed;
end;

function TScrollBox.MouseWheel(DX, DY: Integer): Boolean;
begin
  if (FPullRefresh <> nil) and FPullRefresh.Wheel(DY, FScrollY <= 0) then
    Exit(True);
  Result := FContentH > Bounds.H;
  if Result then
    ScrollY := FScrollY - DY * 48;
end;

procedure TScrollBox.MouseDown(X, Y: Integer);
var
  Bar: TRectI;
begin
  Bar := BarRect;
  FDragging := (Bar.H > 0) and (X >= Bounds.X + Bounds.W - 12);
  if not FDragging then
    Exit;
  if (Y >= Bar.Y) and (Y < Bar.Y + Bar.H) then
    FDragOffset := Y - Bar.Y
  else
    FDragOffset := Bar.H div 2;
  MouseMove(X, Y);
end;

procedure TScrollBox.MouseMove(X, Y: Integer);
var
  Len: Integer;
begin
  if not FDragging then
    Exit;
  Len := BarRect.H;
  ScrollY := (Y - FDragOffset - Bounds.Y) * Math.Max(1, FContentH - Bounds.H) div Math.Max(1, Bounds.H - Len);
end;

procedure TScrollBox.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  FDragging := False;
end;

procedure TScrollBox.ScrollIntoView(C: TControl);
var
  TopY, BottomY: Integer;
begin
  { positions inside the content, without the scrolling }
  TopY := C.Bounds.Y - Bounds.Y + FScrollY;
  BottomY := TopY + C.Bounds.H;
  if TopY - 8 < FScrollY then
    ScrollY := TopY - 8
  else if BottomY + 8 > FScrollY + Bounds.H then
    ScrollY := BottomY + 8 - Bounds.H;
  inherited ScrollIntoView(C);
end;

{ ---- TTabSheet, TTabControl ---- }

constructor TTabSheet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Padding := 16;
  Gap := 12;
end;

procedure TTabSheet.SetCaption(const AValue: string);
begin
  FCaption := AValue;
  Changed;
end;

constructor TTabControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

function TTabControl.SheetCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ChildCount - 1 do
    if Children[I] is TTabSheet then
      Inc(Result);
end;

function TTabControl.Sheet(Index: Integer): TTabSheet;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to ChildCount - 1 do
    if Children[I] is TTabSheet then
    begin
      if N = Index then
        Exit(TTabSheet(Children[I]));
      Inc(N);
    end;
  Result := nil;
end;

function TTabControl.ActiveSheet: TTabSheet;
begin
  Result := Sheet(FTabIndex);
end;

procedure TTabControl.SyncSheets;
var
  I: Integer;
begin
  { only the active page is shown, laid out and reached with Tab }
  for I := 0 to SheetCount - 1 do
    Sheet(I).Visible := I = FTabIndex;
end;

procedure TTabControl.SetTabIndex(AValue: Integer);
begin
  if SheetCount > 0 then
    AValue := EnsureRange(AValue, 0, SheetCount - 1);
  if FTabIndex = AValue then
  begin
    SyncSheets;
    Exit;
  end;
  FTabIndex := AValue;
  SyncSheets;
  Changed;
  if Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

function TTabControl.HeaderHeight: Integer;
var
  I: Integer;
  Icons: Boolean;
begin
  Result := GetFont(Theme.FontSize, True).LineHeight + 20;
  if FTabPosition = tpBottom then
  begin
    Icons := False;
    for I := 0 to SheetCount - 1 do
      Icons := Icons or (Sheet(I).TabIcon <> '');
    Result := GetFont(Theme.FontSize - 2).LineHeight + 16;
    if Icons then
      Inc(Result, 26);
  end;
end;

procedure TTabControl.SetTabPosition(AValue: TTabPosition);
begin
  if FTabPosition = AValue then
    Exit;
  FTabPosition := AValue;
  Changed;
end;

procedure TTabSheet.SetTabIcon(const AValue: string);
begin
  if FTabIcon = AValue then
    Exit;
  FTabIcon := AValue;
  if Parent <> nil then
    Parent.Invalidate;
end;

procedure TTabControl.Measure(AvailWidth: Integer; out W, H: Integer);
var
  I, SW, SH: Integer;
begin
  SyncSheets;
  W := 0;
  H := 0;
  for I := 0 to SheetCount - 1 do
  begin
    Sheet(I).GetSize(AvailWidth, SW, SH);
    W := Math.Max(W, SW);
    H := Math.Max(H, SH);     { all pages: the size does not jump when switching }
  end;
  Inc(H, HeaderHeight);
end;

procedure TTabControl.Arrange(const R: TRectI);
var
  S: TTabSheet;
  F: TPastelFont;
  I, X, TW: Integer;
begin
  inherited Arrange(R);
  SyncSheets;
  F := GetFont(Theme.FontSize, True);
  SetLength(FTabRects, SheetCount);
  if FTabPosition = tpBottom then
  begin
    { below the page, the whole width shared out }
    for I := 0 to SheetCount - 1 do
      FTabRects[I] := RectI(R.X + R.W * I div Math.Max(1, SheetCount), R.Y + R.H - HeaderHeight,
        R.W * (I + 1) div Math.Max(1, SheetCount) - R.W * I div Math.Max(1, SheetCount), HeaderHeight);
    S := ActiveSheet;
    if S <> nil then
      S.Arrange(RectI(R.X, R.Y, R.W, Math.Max(0, R.H - HeaderHeight)));
    Exit;
  end;
  X := R.X + 4;
  for I := 0 to SheetCount - 1 do
  begin
    TW := F.TextWidth(Sheet(I).Caption) + 28;
    FTabRects[I] := RectI(X, R.Y, TW, HeaderHeight);
    Inc(X, TW + 2);
  end;
  S := ActiveSheet;
  if S <> nil then
    S.Arrange(RectI(R.X, R.Y + HeaderHeight, R.W, Math.Max(0, R.H - HeaderHeight)));
end;

procedure TTabControl.Paint(C: TCanvas32);
var
  F: TPastelFont;
  I: Integer;
  Col: TColor32;
  TR: TRectI;
begin
  if FTabPosition = tpBottom then
  begin
    PaintBottomTabs(C);
    if ActiveSheet <> nil then
      ActiveSheet.Paint(C);
    Exit;
  end;
  F := GetFont(Theme.FontSize, True);
  C.FillRect(Bounds.X, Bounds.Y + HeaderHeight - 1, Bounds.W, 1, Theme.Border);
  for I := 0 to High(FTabRects) do
  begin
    TR := FTabRects[I];
    if I = FTabIndex then
    begin
      Col := Theme.Accent;
      C.FillRoundRect(TR.X + 6, TR.Y + TR.H - 3, TR.W - 12, 3, 1.5, Theme.Accent);
      if IsFocused and ParentForm.FocusVisible then
        C.FillRoundRect(TR.X, TR.Y + 4, TR.W, TR.H - 10, 6, Theme.FocusRing);
    end
    else
      Col := Theme.TextMuted;
    if not Enabled then
      Col := Theme.Disabled;
    C.DrawText(F, TR.X + 14, TR.Y + (TR.H - F.LineHeight) div 2, Sheet(I).Caption, Col);
  end;
  if ActiveSheet <> nil then
    ActiveSheet.Paint(C);
end;

function TTabControl.Focusable: Boolean;
begin
  Result := Enabled and (SheetCount > 1);
end;

function TTabControl.Cursor: TCursorKind;
begin
  Result := ckHand;
end;

{ a phone app's bottom navigation: a line above, icon over caption, the chosen one in the accent color }
procedure TTabControl.PaintBottomTabs(C: TCanvas32);
var
  F: TPastelFont;
  I, IconSize, Y: Integer;
  Col: TColor32;
  TR: TRectI;
  S: TTabSheet;
begin
  F := GetFont(Theme.FontSize - 2);
  IconSize := 24;
  if High(FTabRects) >= 0 then
  begin
    TR := FTabRects[0];
    C.FillRect(Bounds.X, TR.Y, Bounds.W, TR.H, Theme.Surface);
    C.FillRect(Bounds.X, TR.Y, Bounds.W, 1, Theme.Border);
  end;
  for I := 0 to High(FTabRects) do
  begin
    TR := FTabRects[I];
    S := Sheet(I);
    if I = FTabIndex then
      Col := Theme.Accent
    else
      Col := Theme.TextMuted;
    if not Enabled then
      Col := Theme.Disabled;
    if (I = FTabIndex) and IsFocused and ParentForm.FocusVisible then
      C.FillRoundRect(TR.X + 4, TR.Y + 4, TR.W - 8, TR.H - 8, 8, Theme.FocusRing);
    Y := TR.Y + 8;
    if S.TabIcon <> '' then
    begin
      DrawIcon(C, S.TabIcon, TR.X + (TR.W - IconSize) div 2, Y, IconSize, Col);
      Inc(Y, IconSize + 2);
    end;
    C.DrawText(F, TR.X + (TR.W - F.TextWidth(S.Caption)) div 2, Y, S.Caption, Col);
  end;
end;

procedure TTabControl.MouseDown(X, Y: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FTabRects) do
    if FTabRects[I].Contains(X, Y) then
    begin
      TabIndex := I;
      Exit;
    end;
end;

function TTabControl.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := True;
  case Key of
    KEY_LEFT: TabIndex := Math.Max(0, FTabIndex - 1);
    KEY_RIGHT: TabIndex := Math.Min(SheetCount - 1, FTabIndex + 1);
    KEY_HOME: TabIndex := 0;
    KEY_END: TabIndex := SheetCount - 1;
  else
    Result := False;
  end;
end;

function TTabControl.TabRect(ASheet: TTabSheet): TRectI;
var
  I: Integer;
begin
  for I := 0 to High(FTabRects) do
    if Sheet(I) = ASheet then
      Exit(FTabRects[I]);
  Result := RectI(0, 0, 0, 0);
end;

procedure TTabControl.ScrollIntoView(C: TControl);
begin
  inherited ScrollIntoView(C);
end;

{ ---- TProgressBar ---- }

constructor TProgressBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMax := 100;
end;

procedure TProgressBar.SetPosition(AValue: Integer);
begin
  AValue := EnsureRange(AValue, 0, FMax);
  if FPosition = AValue then Exit;
  FPosition := AValue;
  Invalidate;
end;

procedure TProgressBar.SetMax(AValue: Integer);
begin
  FMax := Math.Max(1, AValue);
  FPosition := Math.Min(FPosition, FMax);
  Invalidate;
end;

procedure TProgressBar.SetIndeterminate(AValue: Boolean);
begin
  FIndeterminate := AValue;
  Invalidate;
end;

procedure TProgressBar.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 200;
  H := UIStyle.ProgressHeight;
end;

procedure TProgressBar.Paint(C: TCanvas32);
var
  W, X, Seg: Integer;
  T: Double;
begin
  if UIStyle.FieldLook = flUnderline then
    { Fluent: a thin line under the bar }
    C.FillRect(Bounds.X, Bounds.Y + Bounds.H div 2, Bounds.W, 1, Theme.Outline)
  else
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Bounds.H / 2, Theme.Secondary);
  if FIndeterminate then
  begin
    { a piece running from left to right }
    Seg := Bounds.W div 3;
    T := (AnimationTime mod 1400) / 1400;
    X := Bounds.X - Seg + Round(T * (Bounds.W + Seg));
    C.PushClip(Bounds);
    C.FillRoundRect(X, Bounds.Y, Seg, Bounds.H, Bounds.H / 2, Theme.Accent);
    C.PopClip;
    if Visible and Enabled then
      RequestAnimation(Self);
    Exit;
  end;
  W := Round(Bounds.W * FPosition / FMax);
  if W > 0 then
    C.FillRoundRect(Bounds.X, Bounds.Y, Math.Max(W, Bounds.H), Bounds.H, Bounds.H / 2, Theme.Accent);
end;

{ ---- TSlider ---- }

constructor TSlider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMax := 100;
  FStep := 1;
end;

procedure TSlider.SetMin(AValue: Integer);
begin
  FMin := AValue;
  if FMax < FMin then FMax := FMin;
  SetPosition(FPosition);
  Invalidate;
end;

procedure TSlider.SetMax(AValue: Integer);
begin
  FMax := AValue;
  if FMin > FMax then FMin := FMax;
  SetPosition(FPosition);
  Invalidate;
end;

procedure TSlider.SetPosition(AValue: Integer);
begin
  AValue := EnsureRange(AValue, FMin, FMax);
  if FPosition = AValue then Exit;
  FPosition := AValue;
  Invalidate;
  if Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

function TSlider.TrackRect: TRectI;
begin
  Result := RectI(Bounds.X + 9, Bounds.Y + Bounds.H div 2 - 2, Math.Max(1, Bounds.W - 18), 4);
end;

function TSlider.ValueAt(X: Integer): Integer;
var
  T: TRectI;
begin
  T := TrackRect;
  Result := FMin + Round((X - T.X) / T.W * (FMax - FMin));
  if FStep > 1 then
    Result := FMin + Round((Result - FMin) / FStep) * FStep;
end;

procedure TSlider.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 200;
  H := 24;
end;

procedure TSlider.Paint(C: TCanvas32);
var
  T: TRectI;
  KX: Integer;
  Col: TColor32;
  R: Single;
begin
  T := TrackRect;
  if FMax > FMin then
    KX := T.X + Round(T.W * (FPosition - FMin) / (FMax - FMin))
  else
    KX := T.X;
  if Enabled then Col := Theme.Accent else Col := Theme.Disabled;
  R := UIStyle.SliderThumb;
  if UIStyle.FieldLook = flBox then
    C.FillRoundRect(T.X, T.Y, T.W, T.H, 2, Theme.Secondary)
  else
    C.FillRoundRect(T.X, T.Y, T.W, T.H, 2, Mix(Theme.Surface, Theme.Outline, 0.5));
  C.FillRoundRect(T.X, T.Y, KX - T.X, T.H, 2, Col);
  if IsFocused and ParentForm.FocusVisible then
  begin
    if UIStyle.FocusLook = fkRing then
      C.FillCircle(KX, T.Y + 2, R + 4, Theme.FocusRing)
    else
      DrawFocus(C, RectI(Round(KX - R), Round(T.Y + 2 - R), Round(2 * R), Round(2 * R)), R);
  end;
  case UIStyle.SwitchLook of
    swFluent:
      begin
        { a white knob with the accent in its middle (bigger under the mouse) }
        C.FillCircle(KX, T.Y + 2.5, R + 0.5, WithAlpha(Theme.Shadow, $50));
        C.FillCircle(KX, T.Y + 2, R, Theme.Surface);
        if IsHovered or IsPressed then
          C.FillCircle(KX, T.Y + 2, R * 0.7, Col)
        else
          C.FillCircle(KX, T.Y + 2, R * 0.55, Col);
      end;
    swMaterial:
      C.FillCircle(KX, T.Y + 2, R, Col);
  else
    C.FillCircle(KX, T.Y + 2.5, R + 0.5, WithAlpha(Theme.Shadow, $50));
    C.FillCircle(KX, T.Y + 2, R, Col);
    C.FillCircle(KX, T.Y + 2, R - 2, Theme.Surface);
  end;
end;

function TSlider.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TSlider.Cursor: TCursorKind;
begin
  Result := ckHand;
end;

procedure TSlider.MouseDown(X, Y: Integer);
begin
  Position := ValueAt(X);
end;

procedure TSlider.MouseMove(X, Y: Integer);
var
  F: TForm;
begin
  F := ParentForm;
  if (F <> nil) and (F.Captured = Self) then
    Position := ValueAt(X);
end;

function TSlider.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  Big: Integer;
begin
  Result := True;
  Big := Math.Max(FStep, (FMax - FMin) div 10);
  case Key of
    KEY_LEFT, KEY_DOWN: Position := FPosition - FStep;
    KEY_RIGHT, KEY_UP: Position := FPosition + FStep;
    KEY_PAGEDOWN: Position := FPosition - Big;
    KEY_PAGEUP: Position := FPosition + Big;
    KEY_HOME: Position := FMin;
    KEY_END: Position := FMax;
  else
    Result := False;
  end;
end;

function TSlider.MouseWheel(DX, DY: Integer): Boolean;
begin
  Result := IsFocused;
  if Result then
    Position := FPosition + DY * FStep;
end;

{ ---- TSpinner ---- }

constructor TSpinner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := True;
end;

procedure TSpinner.SetActive(AValue: Boolean);
begin
  FActive := AValue;
  Invalidate;
end;

procedure TSpinner.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 24;
  H := 24;
end;

procedure TSpinner.Paint(C: TCanvas32);
var
  I, Phase: Integer;
  R, CX, CY, A: Double;
begin
  if not FActive then
    Exit;
  CX := Bounds.X + Bounds.W / 2;
  CY := Bounds.Y + Bounds.H / 2;
  R := Math.Min(Bounds.W, Bounds.H) / 2 - 3;
  Phase := (AnimationTime div 90) mod 8;
  for I := 0 to 7 do
  begin
    A := I * Pi / 4;
    C.FillCircle(CX + R * Sin(A), CY - R * Cos(A), Math.Max(1.5, R / 4.5),
      WithAlpha(Theme.Accent, 40 + 215 * ((I - Phase + 8) mod 8) div 7));
  end;
  if Visible then
    RequestAnimation(Self);
end;

{ ---- TSplitter ---- }

class function TSplitter.DesktopOnly: Boolean;
begin
  Result := True;
end;
constructor TSplitter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMinSize := 80;
end;

function TSplitter.Vertical: Boolean;
begin
  Result := not ((Parent is TBox) and TBox(Parent).Horizontal);
end;

procedure TSplitter.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 8;
  H := 8;
end;

function TSplitter.FillsAcross: Boolean;
begin
  Result := True;
end;

function TSplitter.Cursor: TCursorKind;
begin
  if Vertical then Result := ckSizeNS else Result := ckSizeWE;
end;

procedure TSplitter.Paint(C: TCanvas32);
var
  Col: TColor32;
begin
  if FDragging or IsHovered then Col := Theme.Accent else Col := Theme.Border;
  if Vertical then
    C.FillRect(Bounds.X, Bounds.Y + Bounds.H div 2, Bounds.W, 1, Col)
  else
    C.FillRect(Bounds.X + Bounds.W div 2, Bounds.Y, 1, Bounds.H, Col);
end;

function TSplitter.Target: TControl;
var
  I: Integer;
begin
  Result := nil;
  if Parent = nil then
    Exit;
  for I := Parent.IndexOfChild(Self) - 1 downto 0 do
    if Parent.Children[I].Visible then
      Exit(Parent.Children[I]);
end;

procedure TSplitter.MoveTo(Size: Integer);
var
  T: TControl;
  Room: Integer;
begin
  T := Target;
  if T = nil then
    Exit;
  if Vertical then
    Room := Parent.Bounds.Y + Parent.Bounds.H - T.Bounds.Y - Bounds.H - FMinSize
  else
    Room := Parent.Bounds.X + Parent.Bounds.W - T.Bounds.X - Bounds.W - FMinSize;
  if (Room > 0) and (Size > Room) then
    Size := Room;
  if Size < FMinSize then
    Size := FMinSize;
  if Vertical then
    T.Height := Size
  else
    T.Width := Size;
end;

procedure TSplitter.MouseDown(X, Y: Integer);
var
  T: TControl;
begin
  T := Target;
  if T = nil then
    Exit;
  FDragging := True;
  if Vertical then
  begin
    FStartPos := Y;
    FStartSize := T.Bounds.H;
  end
  else
  begin
    FStartPos := X;
    FStartSize := T.Bounds.W;
  end;
  Invalidate;
end;

procedure TSplitter.MouseMove(X, Y: Integer);
begin
  if not FDragging then
    Exit;
  if Vertical then
    MoveTo(FStartSize + Y - FStartPos)
  else
    MoveTo(FStartSize + X - FStartPos);
end;

procedure TSplitter.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  if not FDragging then
    Exit;
  FDragging := False;
  Invalidate;
  if Assigned(FOnMoved) then
    FOnMoved(Self);
end;

{ ---- TToolBar ---- }

constructor TToolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Padding := 6;
  Gap := 4;
end;

procedure TToolBar.Paint(C: TCanvas32);
begin
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Surface);
  C.FillRect(Bounds.X, Bounds.Y + Bounds.H - 1, Bounds.W, 1, Theme.Border);
  PaintChildren(C);
end;

{ ---- TStatusBar ---- }

class function TStatusBar.DesktopOnly: Boolean;
begin
  Result := True;
end;
constructor TStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Padding := 6;
  Gap := 16;
end;

procedure TStatusBar.SetText(const AValue: string);
begin
  if FText = AValue then
    Exit;
  FText := AValue;
  Invalidate;
end;

procedure TStatusBar.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  inherited Measure(AvailWidth, W, H);
  if H < GetFont(Theme.FontSize, False).LineHeight + 2 * Padding then
    H := GetFont(Theme.FontSize, False).LineHeight + 2 * Padding;
end;

procedure TStatusBar.Paint(C: TCanvas32);
var
  F: TPastelFont;
begin
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Surface);
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, 1, Theme.Border);
  if (ChildCount = 0) and (FText <> '') then
  begin
    F := GetFont(Theme.FontSize, False);
    C.PushClip(Bounds);
    C.DrawText(F, Bounds.X + Padding + 4, Bounds.Y + (Bounds.H - F.LineHeight) div 2, FText, Theme.TextMuted);
    C.PopClip;
  end;
  PaintChildren(C);
end;

initialization
  RegisterControl(TCheckBox);
  RegisterControl(TRadioButton);
  RegisterControl(TSwitch);
  RegisterControl(TListBox);
  RegisterControl(TComboBox);
  RegisterControl(TDrawer);
  RegisterControl(TBottomSheet);
  RegisterControl(TImage);
  RegisterControl(TScrollBox);
  RegisterControl(TTabControl);
  RegisterControl(TTabSheet);
  RegisterControl(TProgressBar);
  RegisterControl(TSlider);
  RegisterControl(TSpinner);
  RegisterControl(TSplitter);
  RegisterControl(TToolBar);
  RegisterControl(TStatusBar);
end.
