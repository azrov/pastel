{ Pastel - controls, layout and input handling.

  Controls are TComponent descendants with published properties, so they can
  be created from .pform files the same way Delphi creates forms from .dfm.
  Layout is a small flexbox-style model: TColumn and TRow place children one
  after another, Grow shares the free space, Align/Justify position them.
  Part of the Pastel project, MIT License. }
unit Pastel.UI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics;

type
  TAlignItems = (aiStretch, aiStart, aiCenter, aiEnd);
  TJustify = (jsStart, jsCenter, jsEnd, jsSpaceBetween);
  { How a picture fills its place: Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size. }
  TImageFit = (ifContain, ifCover, ifStretch, ifCenter);
  { How a box places its children. Flow: below each other (or side by side in a row), the
    responsive way; Free: where their Left and Top say, like Delphi and Lazarus forms. }
  TLayoutKind = (lkFlow, lkFree);
  { The edges of a free-placed control that keep their distance to the parent's edges when
    the parent is resized: [Left, Top] stays put, [Left, Right] gets wider with it. }
  TAnchorKind = (akLeft, akTop, akRight, akBottom);
  TAnchors = set of TAnchorKind;
  { A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left. }
  TDock = (dkNone, dkTop, dkBottom, dkLeft, dkRight, dkFill);
  TTextAlign = (taLeft, taCenter, taRight);
  { bsFlat: no background until the mouse is on it (tool bars). }
  TButtonStyle = (bsPrimary, bsSecondary, bsDanger, bsFlat);
  { The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType):
    ktDefault lets the edit choose (TNumberEdit: numbers). }
  TKeyboardType = (ktDefault, ktText, ktNumber, ktDecimal, ktPhone, ktEmail, ktUrl, ktTime);
  { What the Enter key of a phone's on-screen keyboard says and does:
    rkNext goes to the next control, the others are Enter (OnSubmit). }
  TReturnKeyType = (rkDefault, rkDone, rkGo, rkNext, rkSearch, rkSend);
  { What kind of screen the app is on: a phone, a tablet, a computer's window, a TV.
    Forms can change with it (OnScreenClassChange, views: Home.tablet.pform). }
  TScreenClass = (scPhone, scTablet, scDesktop, scTV);
  TCursorKind = (ckArrow, ckIBeam, ckHand, ckSizeWE, ckSizeNS);
  TWindowState = (wsNormal, wsMaximized, wsMinimized, wsFullScreen);
  { Light, dark, or what the computer is set to. }
  TThemeMode = (tmLight, tmDark, tmSystem);
  TCloseQueryEvent = procedure(Sender: TObject; var CanClose: Boolean) of object;
  { Called when a dialog shown without waiting is closed: Sender is the dialog
    (the form, the popup), AResult the button chosen (mrOk, mrCancel...). In a
    form's method the parameter cannot be called ModalResult (a property of
    the form): AResult, like Delphi. }
  TModalDoneEvent = procedure(Sender: TObject; AResult: Integer) of object;
  { A row moved by its grip (lists with AllowReorder): from where to where. }
  TReorderEvent = procedure(Sender: TObject; FromIndex, ToIndex: Integer) of object;
  { Files dragged from the file manager and dropped on a control (computers). }
  TDropFilesEvent = procedure(Sender: TObject; const Files: TStringArray) of object;

  TForm = class;
  TPopup = class;

  TGestureState = (gsBegin, gsUpdate, gsEnd);
  { Two fingers (or Ctrl and the wheel on a computer): how much bigger since the
    last call (Scale 1.1: 10 % larger), how much turned (radians, clockwise), and
    their middle (the form's units). }
  TGestureInfo = record
    State: TGestureState;
    Scale, Rotation: Single;
    X, Y: Integer;
  end;
  TGestureEvent = procedure(Sender: TObject; const Gesture: TGestureInfo; var Handled: Boolean) of object;

  { dmAutomatic: pressing it and moving drags it (to a control with OnDragDrop) }
  TDragMode = (dmManual, dmAutomatic);
  { What is dragged: a text (an item's, an id) set in OnStartDrag; Cancel: no drag. }
  TStartDragEvent = procedure(Sender: TObject; var Data: string; var Cancel: Boolean) of object;
  { Source: the control it comes from; Accept: may it be dropped here (default True). }
  TDragOverEvent = procedure(Sender, Source: TObject; const Data: string; X, Y: Integer; var Accept: Boolean) of object;
  TDragDropEvent = procedure(Sender, Source: TObject; const Data: string; X, Y: Integer) of object;
  { Target: where it was dropped (nil: nowhere it was taken). }
  TEndDragEvent = procedure(Sender, Target: TObject; const Data: string) of object;

  { How an edit or a combo box is drawn: a box with a border (Pastel), a box
    with a line at the bottom (Fluent), an outline that gets thicker when
    focused (Material). }
  TFieldLook = (flBox, flUnderline, flOutline);
  { The keyboard's focus: a soft ring of the accent color (Pastel), or a line
    around in the text color (Fluent, Material). }
  TFocusLook = (fkRing, fkOutline);
  TSwitchLook = (swPill, swFluent, swMaterial);

  { A named look in a style file ([look.Name]), for a control's StyleLookup:
    what it sets instead of the style's (0 or -1: not set). }
  TStyleLook = class
  public
    Name: string;
    Color, HoverColor, PressedColor, TextColor, BorderColor: TColor32;
    Radius, BorderWidth, FontSize, PaddingX, PaddingY: Integer;
    Bold: Integer;           { -1: not set, 0: no, 1: yes }
    constructor Create;
    procedure Assign(Src: TStyleLook);
  end;

  { The sizes and shapes of the controls in a style (UseStyle); the colors
    are the Theme's, which a style sets too. Read it in a control of your own
    to look like the others. }
  TUIStyle = record
    { 'pastel', 'fluent', 'material' or a style file's name }
    Name: string;
    { buttons: the room around the text (both sides together), the corners
      (999: round ends), a border on secondary buttons, bold text }
    ButtonPadX, ButtonPadY, ButtonRadius, ButtonBorder: Integer;
    ButtonBold: Boolean;
    FlatPadX, FlatPadY: Integer;
    { flat buttons in the accent color (Material's text buttons) }
    FlatAccent: Boolean;
    { flat buttons shaded over what is under them (hover and press) }
    FlatOverlay: Boolean;
    { edits, combo boxes, date pickers: the room left and right of the text, above and below together }
    FieldPadX, FieldPadY, FieldRadius: Integer;
    FieldLook: TFieldLook;
    CheckSize, CheckRadius: Integer;
    SwitchLook: TSwitchLook;
    SliderThumb, ProgressHeight: Integer;
    PopupRadius, DialogRadius: Integer;
    FocusLook: TFocusLook;
    { dialogs: the default button first (Windows: OK Cancel), the others as flat buttons }
    DefaultButtonFirst, DialogFlatButtons: Boolean;
    { the Theme's Radius: cards, lists, grids }
    Radius: Integer;
  end;

  TControl = class(TComponent)
  private
    FOnDropFiles: TDropFilesEvent;
    FOnGesture: TGestureEvent;
    FDragMode: TDragMode;
    FAccessibleName: string;
    FOnStartDrag: TStartDragEvent;
    FOnDragOver: TDragOverEvent;
    FOnDragDrop: TDragDropEvent;
    FOnEndDrag: TEndDragEvent;
    FParent: TControl;
    FChildren: TFPList;
    FWidth, FHeight, FGrow: Integer;
    FLeft, FTop: Integer;
    FAnchors: TAnchors;
    FDock: TDock;
    FTabOrder: Integer;
    FTabStop: Boolean;
    FVisible, FEnabled: Boolean;
    FBounds: TRectI;
    FHint: string;
    FStyleLookup: string;
    FPopupMenu: TControl;
    FPopupForm: TForm;        { set on the root of a popup: the form it is shown on }
    procedure SetPopupMenu(AValue: TControl);
    procedure SetStyleLookup(const AValue: string);
    function GetChild(Index: Integer): TControl;
    function GetChildCount: Integer;
    procedure SetParent(AValue: TControl);
    procedure SetWidth(AValue: Integer);
    procedure SetHeight(AValue: Integer);
    procedure SetGrow(AValue: Integer);
    procedure SetLeft(AValue: Integer);
    procedure SetTop(AValue: Integer);
    procedure SetAnchors(AValue: TAnchors);
    procedure SetDock(AValue: TDock);
    procedure SetVisible(AValue: Boolean);
    procedure SetEnabled(AValue: Boolean);
  protected
    { Size the control wants, given the width available to it. }
    procedure Measure(AvailWidth: Integer; out W, H: Integer); virtual;
    procedure Arrange(const R: TRectI); virtual;
    procedure Paint(C: TCanvas32); virtual;
    procedure PaintChildren(C: TCanvas32);
    function Focusable: Boolean; virtual;
    { True: takes the whole height in a row (width in a column), whatever its Align (splitters). }
    function FillsAcross: Boolean; virtual;
    { The keyboard focus went to another control (or none). }
    procedure FocusLost; virtual;
    function Cursor: TCursorKind; virtual;
    procedure MouseDown(X, Y: Integer); virtual;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); virtual;
    procedure MouseMove(X, Y: Integer); virtual;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; virtual;
    procedure TextInput(const S: string); virtual;
    { The mouse wheel over the control; False lets the parent scroll. }
    function MouseWheel(DX, DY: Integer): Boolean; virtual;
    { Two fingers pinch or turn over it; False lets the parent have it. OnGesture first. }
    function Gesture(const G: TGestureInfo): Boolean; virtual;
    { What a drag of it carries before OnStartDrag (a list: the item's text). }
    function DragData(X, Y: Integer): string; virtual;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function IsHovered: Boolean;
    { Its StyleLookup's look in the style in use; nil: none. }
    function Look: TStyleLook;
    { A child got the focus: scrolling parents bring it into view. }
    procedure ScrollIntoView(C: TControl); virtual;
    function IsPressed: Boolean;
    function IsFocused: Boolean;
    procedure Changed;          { needs layout and repaint }
    { Sets Bounds without arranging children (scrolling containers). }
    procedure SetBoundsOnly(const R: TRectI);
  public
    { True when a press at X, Y starts a drag of the control's own (a list's
      grip): a finger there drags instead of scrolling. }
    function DragsAt(X, Y: Integer): Boolean; virtual;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate;       { needs repaint only }
    procedure SetFocus;
    function HitTest(X, Y: Integer): TControl;
    function ParentForm: TForm;
    { The popup the control is in, or nil. }
    function ParentPopup: TPopup;
    { Preferred size including explicit Width/Height. }
    procedure GetSize(AvailWidth: Integer; out W, H: Integer);
    { True for controls that only make sense with a mouse and a big window (a menu bar,
      a splitter, a status bar): the designer says they will not be on phones. }
    class function DesktopOnly: Boolean; virtual;
    property Parent: TControl read FParent write SetParent;
    property Children[Index: Integer]: TControl read GetChild;
    property ChildCount: Integer read GetChildCount;
    function IndexOfChild(C: TControl): Integer;
    property Bounds: TRectI read FBounds;
  public
    { Files dropped on it from the file manager (computers); the control under
      the place or the first one above it that has the event, else the form's. }
    property OnDropFiles: TDropFilesEvent read FOnDropFiles write FOnDropFiles;
    { Two fingers pinched or turned over it (a picture, a map, a drawing). }
    property OnGesture: TGestureEvent read FOnGesture write FOnGesture;
  published
    { What a screen reader (TalkBack) says for it, when its text does not say it
      (an icon button: 'Delete'). }
    property AccessibleName: string read FAccessibleName write FAccessibleName;
    { dmAutomatic: it can be dragged onto controls with OnDragDrop (a finger too). }
    property DragMode: TDragMode read FDragMode write FDragMode default dmManual;
    property OnStartDrag: TStartDragEvent read FOnStartDrag write FOnStartDrag;
    { Something dragged over it: Accept := False refuses it. }
    property OnDragOver: TDragOverEvent read FOnDragOver write FOnDragOver;
    { Dropped on it. }
    property OnDragDrop: TDragDropEvent read FOnDragDrop write FOnDragDrop;
    property OnEndDrag: TEndDragEvent read FOnEndDrag write FOnEndDrag;
    property Width: Integer read FWidth write SetWidth default 0;
    property Height: Integer read FHeight write SetHeight default 0;
    property Grow: Integer read FGrow write SetGrow default 0;
    { The place in a parent with Layout = Free (a TPanel, or a form with Layout = Free). }
    property Left: Integer read FLeft write SetLeft default 0;
    property Top: Integer read FTop write SetTop default 0;
    { In a parent with Layout = Free: which edges follow the parent's when it is resized. }
    property Anchors: TAnchors read FAnchors write SetAnchors default [akLeft, akTop];
    { In a parent with Layout = Free: docked to an edge (Top, Bottom, Left, Right) or Fill. }
    property Dock: TDock read FDock write SetDock default dkNone;
    { The Tab key goes through the controls of a parent in TabOrder (equal ones in their order in the .pform). }
    property TabOrder: Integer read FTabOrder write FTabOrder default 0;
    { False: the Tab key passes it by (a click still focuses it). }
    property TabStop: Boolean read FTabStop write FTabStop default True;
    property Visible: Boolean read FVisible write SetVisible default True;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    { Shown in a tooltip when the mouse rests on the control. }
    property Hint: string read FHint write FHint;
    { A TPopupMenu shown on a right click (or the menu key). }
    property PopupMenu: TControl read FPopupMenu write SetPopupMenu;
    { A [look.Name] of the style file in use: its colors, corners and sizes
      instead of the style's (buttons, labels, boxes, edits, combo boxes). }
    property StyleLookup: string read FStyleLookup write SetStyleLookup;
  end;

  TControlClass = class of TControl;

  { A command with a caption and a keyboard shortcut, used by menu items and
    buttons: one place for what happens, and for Enabled and Checked. }
  TAction = class(TBasicAction)
  private
    FCaption, FShortCut, FHint, FIcon: string;
    FEnabled, FChecked: Boolean;
    procedure SetEnabled(AValue: Boolean);
    procedure SetChecked(AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    function Execute: Boolean; override;
  published
    property Caption: string read FCaption write FCaption;
    { Like 'Ctrl+S', 'Ctrl+Shift+Z', 'F5', 'Delete'. }
    property ShortCut: string read FShortCut write FShortCut;
    property Hint: string read FHint write FHint;
    { A built-in icon for its buttons and menu items ('save', 'print'...). }
    property Icon: string read FIcon write FIcon;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    property Checked: Boolean read FChecked write SetChecked default False;
    property OnExecute;
  end;

  { A container that stacks its children vertically or horizontally. }
  TBox = class(TControl)
  private
    FRow: Boolean;
    FGap, FPadding: Integer;
    FAlign: TAlignItems;
    FJustify: TJustify;
    FColor, FBorderColor: TColor32;
    FRadius, FBorderWidth: Integer;
    FBackgroundImage: string;
    FBackgroundFit: TImageFit;
    FBackground: TBitmap32;
    FLayout: TLayoutKind;
    FMaxContentWidth: Integer;
    procedure SetLayout(AValue: TLayoutKind);
    procedure SetMaxContentWidth(AValue: Integer);
    function ContentRect(const R: TRectI): TRectI;
    procedure MeasureFree(out W, H: Integer);
    procedure ArrangeFree(const R: TRectI);
    procedure SetGap(AValue: Integer);
    procedure SetBackgroundImage(const AValue: string);
    procedure SetBackgroundFit(AValue: TImageFit);
    procedure SetPadding(AValue: Integer);
    procedure SetAlign(AValue: TAlignItems);
    procedure SetJustify(AValue: TJustify);
    procedure SetColor(AValue: TColor32);
    procedure SetBorderColor(AValue: TColor32);
    procedure SetRadius(AValue: Integer);
    procedure SetBorderWidth(AValue: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
    { The colors to paint with: Color/BorderColor, or the theme's for 0 in cards and forms. }
    function PaintColor: TColor32; virtual;
    function PaintBorderColor: TColor32; virtual;
    { Draws BackgroundImage into R. }
    procedure PaintBackground(C: TCanvas32; const R: TRectI);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { True for TRow: children are placed left to right. }
    property Horizontal: Boolean read FRow;
  published
    property OnDropFiles;
    { Flow (default): children below each other, or side by side in a row; Free: where their Left and Top say. }
    property Layout: TLayoutKind read FLayout write SetLayout default lkFlow;
    property Gap: Integer read FGap write SetGap default 0;
    property Padding: Integer read FPadding write SetPadding default 0;
    property Align: TAlignItems read FAlign write SetAlign default aiStretch;
    property Justify: TJustify read FJustify write SetJustify default jsStart;
    property Color: TColor32 read FColor write SetColor default 0;
    property BorderColor: TColor32 read FBorderColor write SetBorderColor default 0;
    property BorderWidth: Integer read FBorderWidth write SetBorderWidth default 0;
    property Radius: Integer read FRadius write SetRadius default 0;
    { A picture behind the children: a file in assets/, next to the program, or a full path. }
    property BackgroundImage: string read FBackgroundImage write SetBackgroundImage;
    property BackgroundFit: TImageFit read FBackgroundFit write SetBackgroundFit default ifCover;
    { The children use at most this width, in the middle: a form stays readable on a tablet, a TV or a
      wide window (0: all the width). }
    property MaxContentWidth: Integer read FMaxContentWidth write SetMaxContentWidth default 0;
  end;

  TColumn = class(TBox);

  { A box whose children stay where they are put (Left, Top), like a Delphi TPanel. }
  TPanel = class(TBox)
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Layout default lkFree;
  end;

  TRow = class(TBox)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TRectArray = array of TRectI;

  { A row that wraps: children are placed left to right, and continue on
    the next line when there is no room (chips, tags, buttons, small cards).
    Gap is the space between them, also between lines; in each line the
    ones with Grow share what is left. }
  TFlow = class(TBox)
  private
    function Lines(AWidth: Integer; out Sizes: TRectArray): Integer;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { A white rounded panel with a border (in the theme's colors). }
  TCard = class(TBox)
  protected
    function PaintColor: TColor32; override;
    function PaintBorderColor: TColor32; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { Empty space that takes the free room in a row or column. }
  TSpacer = class(TControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TLabel = class(TControl)
  private
    FText: string;
    FFontSize: Integer;
    FBold: Boolean;
    FColor: TColor32;
    FTextAlign: TTextAlign;
    FWordWrap: Boolean;
    procedure SetText(const AValue: string);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetFontSize(AValue: Integer);
    procedure SetBold(AValue: Boolean);
    procedure SetColor(AValue: TColor32);
    procedure SetTextAlign(AValue: TTextAlign);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    function Font: TPastelFont;
    { The lines the text is shown in, at a width (line breaks and wrapping). }
    function TextLines(AWidth: Integer): TStringArray;
  published
    property Text: string read FText write SetText;
    { Break long text into lines at the label's width. }
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    property FontSize: Integer read FFontSize write SetFontSize default 14;
    property Bold: Boolean read FBold write SetBold default False;
    property Color: TColor32 read FColor write SetColor default 0;
    property TextAlign: TTextAlign read FTextAlign write SetTextAlign default taLeft;
  end;

  TButton = class(TControl)
  private
    FText: string;
    FStyle: TButtonStyle;
    FOnClick: TNotifyEvent;
    FModalResult: Integer;
    FDefault, FCancel: Boolean;
    FAction: TBasicAction;
    FIcon: string;
    FColor, FTextColor: TColor32;
    procedure SetText(const AValue: string);
    procedure SetIcon(const AValue: string);
    procedure SetColor(AValue: TColor32);
    procedure SetTextColor(AValue: TColor32);
    function IconSize: Integer;
    function GetIcon: string;
    procedure SetStyle(AValue: TButtonStyle);
    procedure SetAction(AValue: TBasicAction);
    function GetText: string;
    procedure Padding(out PX, PY: Integer);
    function ButtonFont: TPastelFont;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    function IsEnabled: Boolean;
  public
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Click; virtual;
  published
    property Text: string read FText write SetText;
    property Style: TButtonStyle read FStyle write SetStyle default bsPrimary;
    { Any background color instead of the style's (hover and press shade it); 0: the style's. }
    property Color: TColor32 read FColor write SetColor default 0;
    { Any text and icon color; 0: the style's. }
    property TextColor: TColor32 read FTextColor write SetTextColor default 0;
    { A built-in icon ('save', 'add', 'delete'...; see Pastel.Icons) before the text, or alone. }
    property Icon: string read FIcon write SetIcon;
    { A click runs the action (and Text, Enabled come from it when not set). }
    property Action: TBasicAction read FAction write SetAction;
    { In a dialog: a click closes it with this result (mrOk, mrCancel...). }
    property ModalResult: Integer read FModalResult write FModalResult default 0;
    { Enter in the dialog clicks it. }
    property Default: Boolean read FDefault write FDefault default False;
    { Escape in the dialog clicks it. }
    property Cancel: Boolean read FCancel write FCancel default False;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  TEditState = record
    Text: string;
    Caret, Anchor: Integer;
  end;
  TEditStates = array of TEditState;
  TVisualLine = record
    StartPos, EndPos: Integer;     { byte range in Text, without the line break }
  end;

  { What a part of a code editor's text is (syntax highlighting); each has a
    color of the theme (SyntaxColor). }
  TSyntaxKind = (skText, skKeyword, skString, skNumber, skComment, skName, skSymbol, skError);
  { A part of the text: Start (bytes, from 1), Len bytes. }
  TSyntaxSpan = record
    Start, Len: Integer;
    Kind: TSyntaxKind;
  end;
  TSyntaxSpans = array of TSyntaxSpan;
  { Colors the text: add a span for each part that is not plain text. }
  THighlightEvent = procedure(Sender: TObject; const AText: string; var Spans: TSyntaxSpans) of object;
  { Word is what is typed before the caret (letters, digits, _ and dots:
    'orders.cu'); Items gets the words that may follow (only those that begin
    with the part after the last dot are shown). }
  TCompletionEvent = procedure(Sender: TObject; const Word: string; Items: TStrings) of object;

  { Text editing for TEdit and TMemo: caret, selection with mouse and
    keyboard, clipboard, undo/redo, scrolling; TMemo adds lines and wrapping. }
  TCustomEdit = class(TControl)
  private
    FText, FPlaceholder, FError, FHintBefore: string;
    FCaret, FAnchor: Integer;     { byte positions (1-based); the selection is between them }
    FComposeStart, FComposeEnd: Integer;   { the word a phone's keyboard is composing (bytes, 1-based); 0: none }
    FComposeText: string;                  { the text it was composed in (another text: none) }
    FScrollX, FScrollY: Integer;
    FDesiredX: Integer;
    FSelecting, FLastWasTyping, FScrollToCaret: Boolean;
    FUndo, FRedo: TEditStates;
    FVisual: array of TVisualLine;
    FVisualText: string;
    FVisualWidth: Integer;
    FLines: TStrings;
    FOnChange, FOnSubmit: TNotifyEvent;
    FOnHighlight: THighlightEvent;
    FKinds: array of TSyntaxKind;      { for each byte of FHighlightFor }
    FHighlightFor: string;
    FHighlighted: Boolean;
    FCompletions: TStringList;
    FOnCompletions: TCompletionEvent;
    FCompletePopup: TPopup;
    FCompleteList: TControl;
    FCompleteStart: Integer;          { where the word being completed begins (bytes) }
    procedure SetText(const AValue: string);
    procedure SetPlaceholder(const AValue: string);
    procedure SetPassword(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    function GetSelStart: Integer;
    function GetSelLength: Integer;
    function GetSelText: string;
    procedure SetSelStart(AValue: Integer);
    procedure SetSelLength(AValue: Integer);
    procedure SetSelText(const AValue: string);
    function CleanText(const S: string): string;
    function DisplayText(const S: string): string;
    function DisplayPos(const S: string; P: Integer): Integer;
    function SourcePos(const S: string; DP: Integer): Integer;
    function Padding: Integer;
    function InnerRect: TRectI;
    procedure BuildLines(AWidth: Integer);
    procedure EnsureLines;
    function LineOf(P: Integer): Integer;
    function XOf(P: Integer): Integer;
    function PosAt(X, Y: Integer): Integer;
    function SelStartPos: Integer;
    procedure SaveUndo(Typing: Boolean);
    procedure Restore(var FromStack, ToStack: TEditStates);
    procedure ReplaceSelection(const S: string; Typing: Boolean);
    procedure MoveCaret(P: Integer; Extend: Boolean);
    procedure ScrollToCaret;
    function WordLeft(P: Integer): Integer;
    function WordRight(P: Integer): Integer;
    function VerticalPos(P, Lines: Integer): Integer;
    procedure DoChange;
    procedure SetError(const AValue: string);
    procedure SetOnHighlight(AValue: THighlightEvent);
    function GetCompletions: TStrings;
    procedure SetCompletions(AValue: TStrings);
    procedure Highlight;
    procedure DrawLine(C: TCanvas32; F: TPastelFont; X, Y: Integer; const S: string; LineStart: Integer);
    function CompletionWord(out WordStart: Integer): string;
    procedure UpdateCompletion(Asked: Boolean);
  protected
    FMultiLine, FWordWrap, FReadOnly, FPassword: Boolean;
    FMaxLength: Integer;
    FKeyboardType: TKeyboardType;
    FReturnKeyType: TReturnKeyType;
    { the text set from code (Text := ...) as the edit keeps it (TMaskEdit: in its mask) }
    function NormalizeText(const S: string): string; virtual;
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure TextInput(const S: string); override;
    procedure FocusLost; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Font: TPastelFont;
    { Colors the text again (OnHighlight), when what it depends on changed. }
    procedure RehighlightText;
    { The completion list (typing a word shows it; Ctrl+Space too). }
    procedure ShowCompletions;
    procedure HideCompletions;
    function CompletionsShown: Boolean;
    { Puts Word in place of the word before the caret (the part after its last dot). }
    procedure Complete(const Word: string);
    procedure SelectAll;
    procedure CopyToClipboard;
    procedure CutToClipboard; virtual;
    procedure PasteFromClipboard; virtual;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    { Internal (Pastel.App on Android): the phone's keyboard changed its copy of the
      edit; Text is the whole new text, positions in bytes from 0 (-1: none). The
      change goes through TextInput and the edit's rules (MaxLength, a mask...). }
    procedure ImeChange(const AText: string; ASelStart, ASelEnd, AComposeStart, AComposeEnd: Integer);
    property CaretPos: Integer read FCaret;
    { The keyboard a phone shows: KeyboardType, or the edit's own choice for ktDefault (ktText for most). }
    function KeyboardKind: TKeyboardType; virtual;
    { False when the edit brings a picker of its own on a phone (TTimeEdit) instead of the keyboard. }
    function WantsKeyboard: Boolean; virtual;
    property MultiLine: Boolean read FMultiLine;
    property IsPassword: Boolean read FPassword;
    property ReturnKeyType: TReturnKeyType read FReturnKeyType write FReturnKeyType default rkDefault;
    { The selection: SelStart counts from 0 (bytes), like Delphi. }
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property SelText: string read GetSelText write SetSelText;
    property Text: string read FText write SetText;
    property Placeholder: string read FPlaceholder write SetPlaceholder;
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    { At most this many bytes; 0: no limit. }
    property MaxLength: Integer read FMaxLength write FMaxLength default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { A problem with the value ('Fill this in'): a red border, and the text
      as a tooltip; typing clears it. TDataBinding.Validate sets it. }
    property Error: string read FError write SetError;
    { Words offered while typing (table names, keywords...): a list below the
      caret; Up/Down choose, Enter or Tab put it in, Escape closes it. }
    property Completions: TStrings read GetCompletions write SetCompletions;
    { The words for what is typed, when they depend on it (the columns after 'orders.'). }
    property OnCompletions: TCompletionEvent read FOnCompletions write FOnCompletions;
    { Syntax highlighting: Pastel.Syntax has HighlightSql, HighlightPascal... }
    property OnHighlight: THighlightEvent read FOnHighlight write SetOnHighlight;
  end;

  { One line of text. }
  TEdit = class(TCustomEdit)
  published
    property Text;
    property Placeholder;
    property ReadOnly;
    property MaxLength;
    { Shows dots instead of the text. }
    property Password: Boolean read FPassword write SetPassword default False;
    { The phone's on-screen keyboard for it: numbers, a phone pad, e-mail... }
    property KeyboardType: TKeyboardType read FKeyboardType write FKeyboardType default ktDefault;
    { What the on-screen keyboard's Enter key says: Done, Next, Search... }
    property ReturnKeyType;
    property OnChange;
    { Enter was pressed. }
    property OnSubmit: TNotifyEvent read FOnSubmit write FOnSubmit;
  end;

  { Text with several lines; scrolls, wraps long lines. }
  TMemo = class(TCustomEdit)
  public
    constructor Create(AOwner: TComponent); override;
    { The text as lines: Memo.Lines.Add('...'), Memo.Lines[0]. }
    property Lines: TStrings read GetLines write SetLines;
  published
    property OnDropFiles;
    property Text;
    property Placeholder;
    property ReadOnly;
    property MaxLength;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default True;
    { The phone's on-screen keyboard for it. }
    property KeyboardType: TKeyboardType read FKeyboardType write FKeyboardType default ktDefault;
    property OnChange;
    property Completions;
    property OnCompletions;
    property OnHighlight;
  end;

  { Where a popup goes: below (or above) its anchor, centered; or along a side
    of the window, as a drawer or a bottom sheet (the window dimmed behind). }
  TPopupSide = (psAnchor, psLeft, psRight, psBottom);

  { A panel shown above the form: drop-down lists, menus, dialogs. }
  TPopup = class(TBox)
  private
    FModal, FClosed, FShown: Boolean;
    FSide: TPopupSide;
    FModalResult: Integer;
    FAnchor: TRectI;
    FAnchored, FPlaceRight: Boolean;
    FSavedFocus, FActiveControl: TControl;
    FOnClose: TNotifyEvent;
    FOnDone: TModalDoneEvent;
    FFreeWhenDone: Boolean;
  protected
    function PaintColor: TColor32; override;
    function PaintBorderColor: TColor32; override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Shows it on Form, below (or above) Anchor; centered when not given. }
    procedure Popup(Form: TForm; const Anchor: TRectI; PlaceRight: Boolean = False);
    procedure PopupCentered(Form: TForm);
    { Shows it centered with the form dimmed behind it and waits until it
      is closed; the result is ModalResult. }
    function ShowModal(Form: TForm): Integer; overload;
    { The same without waiting: returns at once, OnDone is called when it is
      closed (with ModalResult); FreeWhenDone frees it after that. Phones and
      browsers prefer it: nothing waits inside an event. }
    procedure ShowModal(Form: TForm; OnDone: TModalDoneEvent; FreeWhenDone: Boolean = False); overload;
    procedure Close(AModalResult: Integer = 0);
    property Modal: Boolean read FModal write FModal;
    property Closed: Boolean read FClosed;
    property Shown: Boolean read FShown;
    property ModalResult: Integer read FModalResult write FModalResult;
    { Along a side of the window (drawers, bottom sheets) instead of at its anchor. }
    property Side: TPopupSide read FSide write FSide;
    { Gets the focus when a modal popup opens; the first focusable control when nil. }
    property ActiveControl: TControl read FActiveControl write FActiveControl;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
  end;

  TTimer = class;

  { "Pull down to refresh" of a list (TListView, TGrid, TScrollBox): a finger
    that pulls the list down past its top shows a circle; let go far enough and
    OnRefresh is called, the circle turns until Refreshing := False. On a
    computer F5 does it. Used by the controls; their OnRefresh and Refreshing. }
  TPullRefresh = class(TComponent)
  private
    FControl: TControl;
    FPull: Integer;
    FRefreshing: Boolean;
    FTimer: TTimer;
    FOnRefresh: TNotifyEvent;
    procedure Released(Sender: TObject);
    procedure SetRefreshing(AValue: Boolean);
  public
    constructor Create(AControl: TControl); reintroduce;
    { a wheel step (a finger's on a phone) at the top: True when it pulls }
    function Wheel(DY: Integer; AtTop: Boolean): Boolean;
    function Key(K: LongInt): Boolean;
    procedure Paint(C: TCanvas32);
    property Refreshing: Boolean read FRefreshing write SetRefreshing;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
  end;

  { Calls OnTimer every Interval milliseconds while Enabled. }
  TTimer = class(TComponent)
  private
    FInterval: Integer;
    FEnabled: Boolean;
    FOnTimer: TNotifyEvent;
    FNext: QWord;
    procedure SetEnabled(AValue: Boolean);
    procedure SetInterval(AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Interval: Integer read FInterval write SetInterval default 1000;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    property OnTimer: TNotifyEvent read FOnTimer write FOnTimer;
  end;

  { The root of a window. Owns all controls created from its .pform file. }
  TForm = class(TBox)
  private
    FTitle: string;
    FFocused, FHover, FCaptured: TControl;
    FFocusVisible: Boolean;
    FPopups: TFPList;
    FTooltip: TPopup;
    FTooltipFor: TControl;
    FToastText: string;
    FToastTimer: TTimer;
    FSaveState: TStringList;
    FOnSaveState: TNotifyEvent;
    FHoverSince: QWord;
    FMouseX, FMouseY, FClickCount, FMouseButton: Integer;
    FShiftDown: Boolean;
    FWidthPx, FHeightPx: Integer;
    FOnCreate, FOnClose, FOnResize: TNotifyEvent;
    FOnCloseQuery: TCloseQueryEvent;
    FResizable, FAlwaysOnTop: Boolean;
    FMinWidth, FMinHeight: Integer;
    FWindowState: TWindowState;
    FThemeMode: TThemeMode;
    FScreenClass: TScreenClass;
    FScreenClassKnown: Boolean;
    FEditActions: TPopup;       { Cut, Copy, Paste, Select all over an edit }
    { a drag: from where it was pressed, what it carries, where it would go }
    FDragFrom, FDragTarget: TControl;
    FDragData: string;
    FDragDownX, FDragDownY: Integer;
    FDragging, FDragAccepted: Boolean;
    FOnScreenClassChange: TNotifyEvent;
    FView: string;
  public
    { Internal (Pastel.App): it has a window of its own }
    FWindowed: Boolean;
  private
    procedure DragMove(X, Y: Integer);
    procedure PaintDrag(C: TCanvas32);
    procedure ShowEditActions(Edit: TCustomEdit; X, Y: Integer);
    procedure ToastDone(Sender: TObject);
    procedure PaintToast(C: TCanvas32);
    procedure SetAppearance(AValue: TThemeMode);
    procedure SetTitle(const AValue: string);
    procedure SetResizable(AValue: Boolean);
    procedure SetAlwaysOnTop(AValue: Boolean);
    procedure SetMinWidth(AValue: Integer);
    procedure SetMinHeight(AValue: Integer);
    procedure SetWindowState(AValue: TWindowState);
    procedure CollectFocusable(C: TControl; List: TFPList);
    procedure PlacePopup(P: TPopup);
    function GetModalResult: Integer;
    procedure SetModalResult(AValue: Integer);
  protected
    function PaintColor: TColor32; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function HitTest(X, Y: Integer): TControl; reintroduce;
    { Popups (drop-downs, menus, dialogs), the last one on top. }
    procedure ShowPopup(P: TPopup);
    procedure ClosePopup(P: TPopup);
    function PopupCount: Integer;
    function PopupAt(Index: Integer): TPopup;
    function TopPopup: TPopup;
    { Shows or hides the tooltip; the application calls it while the mouse rests. }
    function UpdateTooltip(NowMs: QWord): Boolean;
    procedure HideTooltip;
    { A short message near the bottom for a moment (Android's Toast); clicks go
      through it. Pastel.Dialogs' ShowToast uses the phone's own on Android. }
    procedure ShowToast(const Msg: string; DurationMs: Integer = 2000);
    { The message shown by ShowToast ('' when none). }
    property ToastText: string read FToastText;
    procedure HandleMouseWheel(DX, DY: Integer);
    { A pinch or a turn at G.X, G.Y: to the control there, or the first above it that takes it. }
    procedure HandleGesture(const G: TGestureInfo);
    { Starts dragging C (DragMode = dmManual: from its MouseDown or OnMouseDown) with Data. }
    procedure BeginDrag(C: TControl; const Data: string);
    { True while something is dragged. }
    property Dragging: Boolean read FDragging;
    property DragTarget: TControl read FDragTarget;
    { The app's own values kept while a phone stops it in the background
      (OnSaveState fills it; in OnCreate it has them again, else it is empty):
        SaveState.Values['page'] := IntToStr(Page); }
    function SaveState: TStrings;
    { Files dropped at X, Y (the platform layer): to the OnDropFiles there. True when one took them. }
    function HandleDropFiles(X, Y: Integer; const Files: TStringArray): Boolean;
    { Right button: the control's PopupMenu. }
    procedure HandleContextMenu(X, Y: Integer);
    { Removes every control created from the .pform (used by hot reload). }
    procedure ClearControls;
    procedure Layout(AWidth, AHeight: Integer);
    procedure Render(C: TCanvas32);
    { Paints only Area (layout units): what changed since the last Render. }
    procedure RenderArea(C: TCanvas32; const Area: TRectI);
    procedure FocusControl(C: TControl);
    procedure FocusNext(Backward: Boolean);
    procedure HandleMouseMove(X, Y: Integer);
    procedure HandleMouseDown(X, Y: Integer; Button: Integer = 1; Clicks: Integer = 1);
    procedure HandleMouseUp(X, Y: Integer; Button: Integer = 1);
    procedure HandleMouseLeave;
    procedure HandleKeyDown(Key: LongInt; Shift, Ctrl: Boolean);
    procedure HandleTextInput(const S: string);
    function CurrentCursor: TCursorKind;
    function FindControl(const AName: string): TControl;
    { Points the form's fields at the controls created from the .pform.
      Overridden by the code Pastel generates from the .pform file. }
    procedure BindControls; virtual;
    { Used by BindControls: finds a control and checks its type. }
    function BindControl(const AName: string; AClass: TControlClass): TControl;
    { The same for components without a place on the form (TTimer...). }
    function BindComponent(const AName: string; AClass: TComponentClass): TComponent;
    property Focused: TControl read FFocused;
    property Hovered: TControl read FHover;
    property Captured: TControl read FCaptured;
    { 2 for a double click, 3 for a triple click (in MouseDown). }
    property ClickCount: Integer read FClickCount;
    { 1 left, 2 middle, 3 right (in MouseDown). }
    property MouseButton: Integer read FMouseButton;
    property ShiftDown: Boolean read FShiftDown write FShiftDown;
    property MouseX: Integer read FMouseX;
    property MouseY: Integer read FMouseY;
    { True when focus came from the keyboard (Tab): buttons show a focus ring. }
    property FocusVisible: Boolean read FFocusVisible;
    { Window commands. They take effect on the next pass of the event loop. }
    procedure Maximize;
    procedure Minimize;
    procedure Restore;
    procedure Close;
    { Asks OnCloseQuery; True if the window may close. }
    function CloseQuery: Boolean;
    { Shows this form as a dialog above the main window and waits until it
      is closed: by a button with a ModalResult, ModalResult := ..., Close
      (mrCancel) or Escape. Returns the ModalResult. }
    function ShowModal: Integer; overload;
    { The same without waiting: returns at once; OnDone(Self, ModalResult) is
      called when the dialog is closed. The way for phones (Delphi's
      ShowModal(procedure ...) on Android):
        AppointmentForm.ShowModal(@AppointmentClosed);
        ...
        procedure THomeForm.AppointmentClosed(Sender: TObject; AResult: Integer);
        begin
          if AResult = mrOk then Reload;
        end; }
    procedure ShowModal(OnDone: TModalDoneEvent); overload;
    { Shows the form in a window of its own beside the main one (computers;
      again: brings it to the front). Phones have one window: it is shown over
      the main form as without waiting (ShowModal(nil)). Close closes it. }
    procedure Show;
    { True while it has a window of its own (Show). }
    function Showing: Boolean;
    { Setting it in a dialog form closes the dialog with that result. }
    property ModalResult: Integer read GetModalResult write SetModalResult;
    { Called by the platform layer when the user changed the window state. }
    procedure WindowStateChanged(AState: TWindowState);
    { Called by the platform layer before laying the form out: the view for that kind
      of screen is applied (Home.tablet.pform) and OnScreenClassChange runs. }
    procedure SetScreenClass(AValue: TScreenClass);
    { Moves the focus to the nearest control left, right, up or down (a TV's remote, arrow keys
      on a phone); False when there is none in that direction. }
    function FocusInDirection(DX, DY: Integer): Boolean;
    { The remote's OK button: presses the focused button, ticks a check box, opens a list (Space, else Enter). }
    procedure ActivateFocused;
    { The kind of screen: scPhone, scTablet, scDesktop or scTV. }
    property ScreenClass: TScreenClass read FScreenClass;
    { The view applied: 'tablet' for Home.tablet.pform, '' for the form itself. }
    property View: string read FView write FView;
  published
    property Title: string read FTitle write SetTitle;
    { Can the user resize (and maximize) the window? }
    property Resizable: Boolean read FResizable write SetResizable default True;
    property MinWidth: Integer read FMinWidth write SetMinWidth default 200;
    property MinHeight: Integer read FMinHeight write SetMinHeight default 120;
    property WindowState: TWindowState read FWindowState write SetWindowState default wsNormal;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write SetAlwaysOnTop default False;
    { The colors of the app: Light, Dark or System (as the computer is set). }
    property Appearance: TThemeMode read FThemeMode write SetAppearance default tmLight;
    property OnCreate: TNotifyEvent read FOnCreate write FOnCreate;
    { A phone may stop an app in the background to free memory and start it
      again when the user comes back. What was typed, ticked and chosen comes
      back by itself; for more, put it into SaveState here (it is in
      SaveState again in OnCreate, when the app comes back). }
    property OnSaveState: TNotifyEvent read FOnSaveState write FOnSaveState;
    { Set CanClose to False to keep the window open, e.g. to ask about unsaved work. }
    property OnCloseQuery: TCloseQueryEvent read FOnCloseQuery write FOnCloseQuery;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property OnResize: TNotifyEvent read FOnResize write FOnResize;
    { The kind of screen became known or changed (a phone turned into a tablet's
      split screen, a window made narrow): show, hide or arrange controls for it. }
    property OnScreenClassChange: TNotifyEvent read FOnScreenClassChange write FOnScreenClassChange;
  end;

  TFormClass = class of TForm;

  TTheme = record
    Background, Surface, Text, TextMuted, Placeholder: TColor32;
    Accent, AccentHover, AccentPressed, OnAccent: TColor32;
    Secondary, SecondaryHover, SecondaryPressed: TColor32;
    Danger, DangerHover, DangerPressed: TColor32;
    Border, BorderHover, FocusRing, Disabled: TColor32;
    Shadow, Backdrop, Selection, TooltipBack, TooltipText: TColor32;
    Radius, FontSize: Integer;
    Dark: Boolean;
    { the border of edits and combo boxes (Material's darker outline); Border in the others }
    Outline: TColor32;
  end;

var
  Theme: TTheme;
  { The style in use; change it with UseStyle. }
  UIStyle: TUIStyle;
  { Internal: the text of a style file not loaded yet (an app's assets/styles/Name.pstyle); '' if none. }
  StyleFileHook: function(const Name: string): string = nil;
  { Internal: set by controls that move (spinners...); the application paints again soon. }
  AnimationRequested: Boolean = False;
  { Internal: one pass of the application's event loop, set by Pastel.App.
    TPopup.ShowModal calls it until the popup is closed. }
  ModalStep: procedure = nil;
  { Internal: keyboard shortcuts of menus and actions, set by Pastel.Menus. }
  ShortcutHook: function(Form: TForm; Key: LongInt; Shift, Ctrl: Boolean): Boolean = nil;
  { Internal: whether the computer is set to dark mode, set by Pastel.App. }
  SystemDarkHook: function: Boolean = nil;
  { Runs after UseDarkTheme set up the light or dark colors: changes to
    Theme go here. Pastel.App applies assets/theme.toml with it. }
  ThemeCustomizer: procedure = nil;
  { Internal: shows a TPopupMenu at a point, set by Pastel.Menus. }
  PopupMenuHook: procedure(Menu: TControl; Form: TForm; X, Y: Integer) = nil;
  { Alt is held (with KeyDown). }
  KeyAlt: Boolean = False;
  { Arrow keys a control does not use move the focus to the nearest control in that
    direction (a TV's remote). Pastel.App turns it on for Android. }
  ArrowKeysMoveFocus: Boolean = False;
  { Internal: applies a form's view for a kind of screen (Pastel.Forms sets it). }
  FormViewHook: procedure(Form: TForm; AClass: TScreenClass) = nil;
  { Internal: a picture from the web (set by Pastel.WebImages): nil while it comes. }
  WebImageHook: procedure(const Url: string; out B: TBitmap32; out Failed: Boolean) = nil;
  { The main window's form; dialogs are shown on it. Set by Pastel.App. }
  MainForm: TForm = nil;
  { Internal: a window of its own for a form (TForm.Show), and closing it; set by Pastel.App. }
  ShowFormHook: procedure(Form: TForm) = nil;
  CloseFormHook: function(Form: TForm): Boolean = nil;
  { Internal: a rectangle of layout units as pixels of the window (native views
    over it, Pastel.NativeViews). Set by Pastel.App. }
  WindowPixelRect: function(const R: TRectI): TRectI = nil;
  { Internal: set by controls when the layout changed; the application loop reads it. }
  NeedsLayout: Boolean = True;
  { Internal: everything needs painting. }
  NeedsRepaint: Boolean = True;
  { Internal: only DirtyArea needs painting (when NeedsRepaint is False). }
  NeedsPartialRepaint: Boolean = False;
  { Internal: what needs painting, in layout units. }
  DirtyArea: TRectI;
  { False: always paint the whole window (PASTEL_FULL_REPAINT=1). }
  PartialRepaint: Boolean = True;
  { Internal: the clock of animations stands still at this time (repaint checks); 0: runs. }
  FrozenTime: QWord = 0;
  { Internal: caret blink phase, toggled by the application loop. }
  CaretVisible: Boolean = True;
  { Internal: window properties changed; the platform layer applies them. }
  NeedsWindowSync: Boolean = False;
  { Internal: set by TForm.Close; the application loop handles it. }
  CloseRequested: Boolean = False;
  { Internal: when set, rows whose children do not fit add Name=needed,available
    (pastel check reports them). }
  LayoutWarnings: TStrings = nil;
  { Internal: clipboard access, provided by the platform layer. }
  ClipboardGetText: function: string = nil;
  { Internal: see ClipboardGetText. }
  ClipboardSetText: procedure(const S: string) = nil;

const
  { A growing control in a row that is too narrow gets no narrower than this. }
  MinShrink = 48;
  { Platform-independent key codes (same values as SDL key codes). }
  KEY_BACKSPACE = 8;
  KEY_TAB = 9;
  KEY_ENTER = 13;
  KEY_ESCAPE = 27;
  KEY_SPACE = 32;
  KEY_DELETE = 127;
  KEY_RIGHT = $4000004F;
  KEY_LEFT = $40000050;
  KEY_HOME = $4000004A;
  KEY_END = $4000004D;
  KEY_KP_ENTER = $40000058;
  KEY_UP = $40000052;
  KEY_DOWN = $40000051;
  KEY_PAGEUP = $4000004B;
  KEY_PAGEDOWN = $4000004E;
  KEY_INSERT = $40000049;
  KEY_F1 = $4000003A;       { F2 .. F12 follow }
  KEY_MENU = $40000076;
  KEY_APPLICATION = $40000065;

  { Results of dialogs (ModalResult) }
  mrNone = 0;
  mrOk = 1;
  mrCancel = 2;
  mrAbort = 3;
  mrRetry = 4;
  mrIgnore = 5;
  mrYes = 6;
  mrNo = 7;
  mrClose = 8;

{ Light or dark colors for every control; repaints. }
procedure UseDarkTheme(Dark: Boolean);
{ Styles: 'pastel' (the same everywhere), 'fluent' (Windows 11), 'material'
  (Android), 'auto' (the one of the platform it runs on: Fluent on Windows,
  Material on Android, Pastel elsewhere), or a style loaded from a .pstyle
  file (LoadStyle; an app's assets/styles/*.pstyle by their names). The
  light or dark theme stays. False: no such style. }
function UseStyle(const Name: string): Boolean;
{ The style 'auto' picks here. }
function PlatformStyle: string;
{ A style from the text of a .pstyle file (TOML: base = "material", [colors],
  [colors.dark], [button], [field]..., [look.Name]); '' or what is wrong. }
function LoadStyle(const Name, Text: string): string;
{ The styles there are (built in and loaded). }
function StyleNames: TStringArray;
{ A [look.Name] of the style in use (its dark one in the dark theme); nil: none. }
function FindLook(const Name: string): TStyleLook;
{ The keyboard's focus around R, as the style draws it. }
procedure DrawFocus(C: TCanvas32; const R: TRectI; Radius: Single);
{ The same for a focused control: the ring always (Pastel), the outline when
  the keyboard moved the focus (Fluent, Material). }
procedure DrawFocus(C: TCanvas32; Ctrl: TControl; const R: TRectI; Radius: Single);
{ The box of an edit, a combo box or a date picker in the style; Look may be nil. }
procedure PaintField(C: TCanvas32; const R: TRectI; Focused, Hovered, Enabled, Editable, Error: Boolean;
  Look: TStyleLook = nil);
{ The height of such a box for a line of text. }
function FieldHeight(LineHeight: Integer): Integer;
{ A radius of the style: -1 is the theme's Radius. }
function StyleRadius(R: Integer): Integer;
{ The color of a kind of code (syntax highlighting) in the light or dark theme. }
function SyntaxColor(Kind: TSyntaxKind): TColor32;
{ Changes one theme value by its name in assets/theme.toml: 'accent',
  'background', 'surface', 'text', 'border', 'danger', ... are colors
  ('#0EA5E9'); 'radius' and 'font_size' numbers. Hover and pressed shades
  follow the color. False for an unknown name or a bad value. }
function SetThemeValue(const Name, Value: string): Boolean;
{ Asks for a repaint of a part of the window (layout units). }
procedure InvalidateArea(const R: TRectI);
{ Asks for another frame soon (animations): of the whole window, or only
  of the control that moves. }
procedure RequestAnimation; overload;
{ The clock animations are drawn by (milliseconds); FrozenTime <> 0 stops it. }
function AnimationTime: QWord;
procedure RequestAnimation(Control: TControl); overload;

var
  { Set by the app while a finger drags a list (phones): what pulls to refresh. }
  WheelFromTouch: Boolean = False;
{ Runs the timers that are due; the milliseconds until the next one (-1: none). }
function ProcessTimers(NowMs: QWord): Integer;
const
  { the width of a list row's grip (AllowReorder) }
  ReorderGripWidth = 36;

{ A list row's grip, three short lines ("hold here to move"), in the middle of X, Y, W, H. }
procedure DrawGrip(C: TCanvas32; X, Y, W, H: Integer; Col: TColor32);
{ Frees Obj soon, outside the event that is running (a dialog closed by its own button). }
procedure ReleaseLater(Obj: TObject);
{ Calls Event(Sender) soon, outside the event that is running: answers that
  come at once are given the same way as those that come later. }
procedure CallLater(Event: TNotifyEvent; Sender: TObject);
{ Calls what CallLater was given, then frees what ReleaseLater was given
  (ProcessTimers does it too). }
procedure ProcessReleases;
{ Splits text into lines that fit Width (at spaces; long words are broken). }
function WrapText(Font: TPastelFont; const S: string; Width: Integer): TStringArray;

procedure RegisterControl(AClass: TControlClass);
function FindControlClass(const AName: string): TControlClass;
function ControlClassCount: Integer;
function ControlClassAt(Index: Integer): TControlClass;
{ Components without a place on the form (TTimer...) that .pform files can create. }
procedure RegisterNonVisual(AClass: TComponentClass);
function FindNonVisualClass(const AName: string): TComponentClass;
function NonVisualClassCount: Integer;
function NonVisualClassAt(Index: Integer): TComponentClass;

{ The text on the clipboard ('' when there is none or no window yet). }
function ClipboardText: string;
{ Puts text on the clipboard: Ctrl+V pastes it in this app and others. }
procedure CopyToClipboard(const S: string);

{ Positions in a UTF-8 string, from 0: UTF-16 units (Java's, JavaScript's) to
  bytes and back; a letter beyond the first 65536 (an emoji) is two units. }
function Utf16ToByteIndex(const S: string; U: Integer): Integer;
function ByteToUtf16Index(const S: string; B: Integer): Integer;

implementation

uses
  Math, Pastel.Icons, Pastel.Lang, Pastel.Toml;

{$I pastel.ui.styles.inc}

{ UTF-16 units (Java's positions) <-> bytes of UTF-8 (Pascal's), counted from 0 }
function ClipboardText: string;
begin
  if Assigned(ClipboardGetText) then
    Result := ClipboardGetText()
  else
    Result := '';
end;

procedure CopyToClipboard(const S: string);
begin
  if Assigned(ClipboardSetText) then
    ClipboardSetText(S);
end;

function Utf16ToByteIndex(const S: string; U: Integer): Integer;
var
  I, N, C: Integer;
begin
  I := 1;
  N := 0;
  while (I <= Length(S)) and (N < U) do
  begin
    C := Ord(S[I]);
    if C < $80 then Inc(I)
    else if C < $E0 then Inc(I, 2)
    else if C < $F0 then Inc(I, 3)
    else
    begin
      Inc(I, 4);
      Inc(N);       { a letter beyond the first 65536: two UTF-16 units }
    end;
    Inc(N);
  end;
  Result := Min(I - 1, Length(S));
end;

function ByteToUtf16Index(const S: string; B: Integer): Integer;
var
  I, C: Integer;
begin
  I := 1;
  Result := 0;
  while (I <= Length(S)) and (I <= B) do
  begin
    C := Ord(S[I]);
    if C < $80 then Inc(I)
    else if C < $E0 then Inc(I, 2)
    else if C < $F0 then Inc(I, 3)
    else
    begin
      Inc(I, 4);
      Inc(Result);
    end;
    Inc(Result);
  end;
end;

var
  ControlClasses: TStringList = nil;

procedure RegisterControl(AClass: TControlClass);
begin
  if ControlClasses.IndexOf(AClass.ClassName) < 0 then
    ControlClasses.AddObject(AClass.ClassName, TObject(AClass));
end;

function FindControlClass(const AName: string): TControlClass;
var
  I: Integer;
begin
  I := ControlClasses.IndexOf(AName);
  if I >= 0 then
    Result := TControlClass(ControlClasses.Objects[I])
  else
    Result := nil;
end;

var
  NonVisualClasses: TStringList = nil;

procedure RegisterNonVisual(AClass: TComponentClass);
begin
  if NonVisualClasses.IndexOf(AClass.ClassName) < 0 then
    NonVisualClasses.AddObject(AClass.ClassName, TObject(AClass));
end;

function FindNonVisualClass(const AName: string): TComponentClass;
var
  I: Integer;
begin
  I := NonVisualClasses.IndexOf(AName);
  if I >= 0 then
    Result := TComponentClass(NonVisualClasses.Objects[I])
  else
    Result := nil;
end;

function NonVisualClassCount: Integer;
begin
  Result := NonVisualClasses.Count;
end;

function NonVisualClassAt(Index: Integer): TComponentClass;
begin
  Result := TComponentClass(NonVisualClasses.Objects[Index]);
end;

function ControlClassCount: Integer;
begin
  Result := ControlClasses.Count;
end;

function ControlClassAt(Index: Integer): TControlClass;
begin
  Result := TControlClass(ControlClasses.Objects[Index]);
end;

procedure LightTheme;
begin
  Theme.Background := RGB($F4, $F5, $F8);
  Theme.Surface := RGB($FF, $FF, $FF);
  Theme.Text := RGB($1F, $22, $2B);
  Theme.TextMuted := RGB($6B, $70, $80);
  Theme.Placeholder := RGB($9A, $9E, $AB);
  Theme.Accent := RGB($4F, $46, $E5);
  Theme.AccentHover := RGB($43, $38, $CA);
  Theme.AccentPressed := RGB($37, $30, $A3);
  Theme.OnAccent := RGB($FF, $FF, $FF);
  Theme.Secondary := RGB($EE, $EF, $F3);
  Theme.SecondaryHover := RGB($E2, $E4, $EA);
  Theme.SecondaryPressed := RGB($D5, $D8, $E0);
  Theme.Danger := RGB($DC, $26, $26);
  Theme.DangerHover := RGB($B9, $1C, $1C);
  Theme.DangerPressed := RGB($99, $1B, $1B);
  Theme.Border := RGB($D9, $DC, $E3);
  Theme.BorderHover := RGB($B8, $BD, $C9);
  Theme.FocusRing := RGBA($4F, $46, $E5, $55);
  Theme.Disabled := RGB($C4, $C7, $CF);
  Theme.Shadow := RGBA(0, 0, 0, $28);
  Theme.Backdrop := RGBA($10, $12, $1A, $66);
  Theme.Selection := RGBA($4F, $46, $E5, $22);
  Theme.TooltipBack := RGB($2B, $2E, $38);
  Theme.TooltipText := RGB($FF, $FF, $FF);
  Theme.Radius := 8;
  Theme.FontSize := 14;
  Theme.Dark := False;
  ApplyStylePalette(False);
end;

procedure DarkTheme;
begin
  LightTheme;
  Theme.Background := RGB($16, $18, $1F);
  Theme.Surface := RGB($22, $25, $2E);
  Theme.Text := RGB($E8, $EA, $F0);
  Theme.TextMuted := RGB($9A, $A0, $B0);
  Theme.Placeholder := RGB($6F, $75, $85);
  Theme.Accent := RGB($7C, $74, $F6);
  Theme.AccentHover := RGB($8E, $87, $F8);
  Theme.AccentPressed := RGB($6A, $61, $EC);
  Theme.Secondary := RGB($2E, $32, $3D);
  Theme.SecondaryHover := RGB($38, $3D, $4A);
  Theme.SecondaryPressed := RGB($44, $4A, $58);
  Theme.Danger := RGB($EF, $44, $44);
  Theme.DangerHover := RGB($F8, $71, $71);
  Theme.Border := RGB($3A, $3F, $4C);
  Theme.BorderHover := RGB($55, $5B, $6B);
  Theme.FocusRing := RGBA($7C, $74, $F6, $66);
  Theme.Disabled := RGB($55, $5A, $68);
  Theme.Shadow := RGBA(0, 0, 0, $60);
  Theme.Backdrop := RGBA(0, 0, 0, $88);
  Theme.Selection := RGBA($7C, $74, $F6, $33);
  Theme.TooltipBack := RGB($E8, $EA, $F0);
  Theme.TooltipText := RGB($16, $18, $1F);
  Theme.Dark := True;
  ApplyStylePalette(True);
end;

procedure UseDarkTheme(Dark: Boolean);
begin
  if Dark then DarkTheme else LightTheme;
  if Assigned(ThemeCustomizer) then
    ThemeCustomizer();
  NeedsLayout := True;
  NeedsRepaint := True;
end;

function SetThemeValue(const Name, Value: string): Boolean;
var
  C: TColor32;
  N: Integer;
  Shade: TColor32;
begin
  Result := True;
  case LowerCase(Name) of
    'radius', 'font_size', 'fontsize':
      begin
        if not TryStrToInt(Trim(Value), N) or (N < 0) or (N > 64) then
          Exit(False);
        if LowerCase(Name) = 'radius' then
          Theme.Radius := N
        else if N >= 8 then
          Theme.FontSize := N
        else
          Exit(False);
        Exit;
      end;
  end;
  if not TryParseColor(Trim(Value), C) then
    Exit(False);
  if Theme.Dark then Shade := RGB(255, 255, 255) else Shade := RGB(0, 0, 0);
  case LowerCase(Name) of
    'accent':
      begin
        Theme.Accent := C;
        if StateLayers then
        begin
          { Fluent, Material: lighter towards the text on it }
          Theme.AccentHover := Mix(C, Theme.OnAccent, 0.1);
          Theme.AccentPressed := Mix(C, Theme.OnAccent, 0.18);
        end
        else
        begin
          Theme.AccentHover := Mix(C, Shade, 0.12);
          Theme.AccentPressed := Mix(C, Shade, 0.22);
        end;
        Theme.FocusRing := WithAlpha(C, $55);
        Theme.Selection := WithAlpha(C, $2A);
      end;
    'on_accent': Theme.OnAccent := C;
    'background': Theme.Background := C;
    'surface': Theme.Surface := C;
    'text': Theme.Text := C;
    'text_muted': Theme.TextMuted := C;
    'placeholder': Theme.Placeholder := C;
    'secondary':
      begin
        Theme.Secondary := C;
        Theme.SecondaryHover := Mix(C, Shade, 0.06);
        Theme.SecondaryPressed := Mix(C, Shade, 0.12);
      end;
    'danger':
      begin
        Theme.Danger := C;
        Theme.DangerHover := Mix(C, Shade, 0.12);
        Theme.DangerPressed := Mix(C, Shade, 0.22);
      end;
    'border':
      begin
        Theme.Border := C;
        Theme.BorderHover := Mix(C, Shade, 0.2);
      end;
    'outline': Theme.Outline := C;
    'disabled': Theme.Disabled := C;
    'tooltip_back': Theme.TooltipBack := C;
    'tooltip_text': Theme.TooltipText := C;
  else
    Result := False;
  end;
end;

procedure RequestAnimation;
begin
  AnimationRequested := True;
  NeedsRepaint := True;
end;

function AnimationTime: QWord;
begin
  if FrozenTime <> 0 then
    Result := FrozenTime
  else
    Result := GetTickCount64;
end;

procedure RequestAnimation(Control: TControl);
begin
  AnimationRequested := True;
  Control.Invalidate;
end;

function WrapText(Font: TPastelFont; const S: string; Width: Integer): TStringArray;
var
  Paras: TStringArray;
  Para, Line, Word: string;
  I, P, N: Integer;

  procedure Add(const L: string);
  begin
    SetLength(Result, N + 1);
    Result[N] := L;
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  Paras := StringReplace(S, #13#10, #10, [rfReplaceAll]).Split([#10]);
  if Length(Paras) = 0 then
    Add('');
  for Para in Paras do
  begin
    if (Width <= 0) or (Font.TextWidth(Para) <= Width) then
    begin
      Add(Para);
      Continue;
    end;
    Line := '';
    I := 1;
    while I <= Length(Para) do
    begin
      { the next word with the spaces after it }
      P := I;
      while (P <= Length(Para)) and (Para[P] <> ' ') do
        Inc(P);
      while (P <= Length(Para)) and (Para[P] = ' ') do
        Inc(P);
      Word := Copy(Para, I, P - I);
      I := P;
      if Font.TextWidth(TrimRight(Line + Word)) <= Width then
        Line := Line + Word
      else
      begin
        if Line <> '' then
          Add(TrimRight(Line));
        Line := '';
        { a word wider than the line: break it by characters }
        while Font.TextWidth(TrimRight(Word)) > Width do
        begin
          P := 1;
          while (P <= Length(Word)) do
          begin
            N := N;   { keep the counter }
            NextCodePoint(Word, P);
            if Font.TextWidth(Copy(Word, 1, P - 1)) > Width then
            begin
              P := PrevCharStart(Word, P);
              Break;
            end;
          end;
          if P <= 1 then
            NextCodePoint(Word, P);
          Add(Copy(Word, 1, P - 1));
          Word := Copy(Word, P, MaxInt);
        end;
        Line := Word;
      end;
    end;
    Add(TrimRight(Line));
  end;
end;

{ ---- timers ---- }

var
  Timers: TFPList = nil;

constructor TTimer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInterval := 1000;
  FEnabled := True;
  FNext := GetTickCount64 + FInterval;
  Timers.Add(Self);
end;

destructor TTimer.Destroy;
begin
  if Timers <> nil then
    Timers.Remove(Self);
  inherited Destroy;
end;

procedure TTimer.SetEnabled(AValue: Boolean);
begin
  if AValue and not FEnabled then
    FNext := GetTickCount64 + FInterval;
  FEnabled := AValue;
end;

procedure TTimer.SetInterval(AValue: Integer);
begin
  FInterval := Max(1, AValue);
  FNext := GetTickCount64 + FInterval;
end;

type
  TLaterCall = class
    Event: TNotifyEvent;
    Sender: TObject;
  end;

procedure DrawGrip(C: TCanvas32; X, Y, W, H: Integer; Col: TColor32);
var
  I, CX, CY: Integer;
begin
  CX := X + W div 2;
  CY := Y + H div 2;
  for I := -1 to 1 do
    C.FillRoundRect(CX - 8, CY + I * 5 - 1, 16, 2, 1, Col);
end;

var
  Releases: TFPList = nil;
  LaterCalls: TFPList = nil;

procedure CallLater(Event: TNotifyEvent; Sender: TObject);
var
  C: TLaterCall;
begin
  if not Assigned(Event) then
    Exit;
  if LaterCalls = nil then
    LaterCalls := TFPList.Create;
  C := TLaterCall.Create;
  C.Event := Event;
  C.Sender := Sender;
  LaterCalls.Add(C);
end;

procedure ReleaseLater(Obj: TObject);
begin
  if Obj = nil then
    Exit;
  if Releases = nil then
    Releases := TFPList.Create;
  if Releases.IndexOf(Obj) < 0 then
    Releases.Add(Obj);
end;

procedure ProcessReleases;
var
  L: TFPList;
  I: Integer;
  C: TLaterCall;
begin
  { the calls there are now (one may ask for more: those come next time; one
    that fails leaves the others waiting) }
  if LaterCalls <> nil then
  begin
    I := LaterCalls.Count;
    while (I > 0) and (LaterCalls.Count > 0) do
    begin
      Dec(I);
      C := TLaterCall(LaterCalls[0]);
      LaterCalls.Delete(0);
      try
        C.Event(C.Sender);
      finally
        C.Free;
      end;
    end;
  end;
  if (Releases = nil) or (Releases.Count = 0) then
    Exit;
  L := Releases;
  Releases := nil;
  try
    for I := 0 to L.Count - 1 do
      TObject(L[I]).Free;
  finally
    L.Free;
  end;
end;

function ProcessTimers(NowMs: QWord): Integer;
var
  I: Integer;
  T: TTimer;
  Due: TFPList;
begin
  ProcessReleases;
  Result := -1;
  Due := TFPList.Create;
  try
    for I := 0 to Timers.Count - 1 do
    begin
      T := TTimer(Timers[I]);
      if not T.FEnabled or not Assigned(T.FOnTimer) or (csDesigning in T.ComponentState) then
        Continue;
      if NowMs >= T.FNext then
        Due.Add(T);
    end;
    for I := 0 to Due.Count - 1 do
    begin
      T := TTimer(Due[I]);
      if Timers.IndexOf(T) < 0 then
        Continue;        { freed by an earlier timer }
      T.FNext := NowMs + QWord(T.FInterval);
      T.FOnTimer(T);
    end;
    for I := 0 to Timers.Count - 1 do
    begin
      T := TTimer(Timers[I]);
      if T.FEnabled and Assigned(T.FOnTimer) then
        if (Result < 0) or (Int64(T.FNext) - Int64(NowMs) < Result) then
          Result := Max(0, Int64(T.FNext) - Int64(NowMs));
    end;
  finally
    Due.Free;
  end;
end;

{ ---- TPullRefresh ---- }

const
  PullNeeded = 80;
  PullMost = 120;

constructor TPullRefresh.Create(AControl: TControl);
begin
  inherited Create(AControl);
  FControl := AControl;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 160;
  FTimer.OnTimer := @Released;
end;

function TPullRefresh.Wheel(DY: Integer; AtTop: Boolean): Boolean;
begin
  Result := False;
  if not Assigned(FOnRefresh) or FRefreshing or not WheelFromTouch then
    Exit;
  if (FPull = 0) and not (AtTop and (DY > 0)) then
    Exit;
  FPull := EnsureRange(FPull + DY * 32, 0, PullMost);
  { no more steps for a moment: the finger let go }
  FTimer.Enabled := False;
  FTimer.Enabled := FPull > 0;
  FControl.Invalidate;
  Result := True;
end;

procedure TPullRefresh.Released(Sender: TObject);
begin
  FTimer.Enabled := False;
  if WheelFromTouch then
  begin
    FTimer.Enabled := True;       { still held: wait }
    Exit;
  end;
  if FPull >= PullNeeded then
  begin
    FRefreshing := True;
    FControl.Invalidate;
    if Assigned(FOnRefresh) then
      FOnRefresh(FControl);
  end
  else
  begin
    FPull := 0;
    FControl.Invalidate;
  end;
end;

procedure TPullRefresh.SetRefreshing(AValue: Boolean);
begin
  FRefreshing := AValue;
  if not AValue then
    FPull := 0
  else
    FPull := PullNeeded;
  FControl.Invalidate;
end;

function TPullRefresh.Key(K: LongInt): Boolean;
begin
  Result := (K = KEY_F1 + 4) and Assigned(FOnRefresh) and not FRefreshing;
  if Result then
  begin
    Refreshing := True;
    FOnRefresh(FControl);
  end;
end;

{ a circle coming down from the top: an arc as long as the pull, turning while it refreshes }
procedure TPullRefresh.Paint(C: TCanvas32);
var
  CX, CY, R, A, Start, Len: Double;
  I, N: Integer;
  B: TRectI;
begin
  if (FPull <= 0) and not FRefreshing then
    Exit;
  B := FControl.Bounds;
  CX := B.X + B.W / 2;
  CY := B.Y + Math.Min(FPull, PullNeeded) - 24;
  C.PushClip(B);
  try
    C.FillCircle(CX, CY + 1.5, 21, WithAlpha(Theme.Shadow, (Cardinal(Theme.Shadow) shr 24) div 2));
    C.FillCircle(CX, CY, 20, Theme.Surface);
    R := 11;
    if FRefreshing then
    begin
      Start := (AnimationTime mod 1000) / 1000 * 2 * Pi;
      Len := 1.5 * Pi;
      RequestAnimation(FControl);
    end
    else
    begin
      Start := 0;
      Len := Math.Min(1, FPull / PullNeeded) * 1.8 * Pi;
    end;
    { the arc as dots close together }
    N := Math.Max(2, Round(Len * R / 2));
    for I := 0 to N do
    begin
      A := Start + Len * I / N;
      C.FillCircle(CX + R * Sin(A), CY - R * Cos(A), 1.6, Theme.Accent);
    end;
  finally
    C.PopClip;
  end;
end;

{ ---- TControl ---- }

constructor TControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChildren := TFPList.Create;
  FVisible := True;
  FEnabled := True;
  FAnchors := [akLeft, akTop];
  FTabStop := True;
end;

destructor TControl.Destroy;
var
  I: Integer;
  F: TForm;
begin
  F := ParentForm;
  if (F <> nil) and (F <> Self) then
  begin
    if F.FFocused = Self then F.FFocused := nil;
    if F.FHover = Self then F.FHover := nil;
    if F.FCaptured = Self then F.FCaptured := nil;
    if F.FTooltipFor = Self then F.FTooltipFor := nil;
    if F.FPopups <> nil then
      F.FPopups.Remove(Self);
  end;
  if FParent <> nil then
    FParent.FChildren.Remove(Self);
  for I := 0 to FChildren.Count - 1 do
    TControl(FChildren[I]).FParent := nil;
  FChildren.Free;
  NeedsLayout := True;
  inherited Destroy;
end;

function TControl.GetChild(Index: Integer): TControl;
begin
  Result := TControl(FChildren[Index]);
end;

function TControl.IndexOfChild(C: TControl): Integer;
begin
  Result := FChildren.IndexOf(C);
end;

function TControl.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

procedure TControl.SetParent(AValue: TControl);
begin
  if FParent = AValue then
    Exit;
  if FParent <> nil then
    FParent.FChildren.Remove(Self);
  FParent := AValue;
  if FParent <> nil then
    FParent.FChildren.Add(Self);
  Changed;
end;

procedure TControl.SetWidth(AValue: Integer);
begin
  if FWidth = AValue then Exit;
  FWidth := Max(0, AValue);
  Changed;
end;

procedure TControl.SetHeight(AValue: Integer);
begin
  if FHeight = AValue then Exit;
  FHeight := Max(0, AValue);
  Changed;
end;

procedure TControl.SetLeft(AValue: Integer);
begin
  if FLeft = AValue then Exit;
  FLeft := AValue;
  Changed;
end;

procedure TControl.SetTop(AValue: Integer);
begin
  if FTop = AValue then Exit;
  FTop := AValue;
  Changed;
end;

procedure TControl.SetAnchors(AValue: TAnchors);
begin
  if FAnchors = AValue then Exit;
  FAnchors := AValue;
  Changed;
end;

procedure TControl.SetDock(AValue: TDock);
begin
  if FDock = AValue then Exit;
  FDock := AValue;
  Changed;
end;

procedure TControl.SetGrow(AValue: Integer);
begin
  if FGrow = AValue then Exit;
  FGrow := Max(0, AValue);
  Changed;
end;

procedure TControl.SetVisible(AValue: Boolean);
begin
  if FVisible = AValue then Exit;
  FVisible := AValue;
  Changed;
end;

procedure TControl.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
  Invalidate;
end;

procedure TControl.Changed;
begin
  NeedsLayout := True;
  NeedsRepaint := True;
end;

procedure TControl.Invalidate;
begin
  InvalidateArea(FBounds.Inflate(8));     { with focus rings and shadows }
end;

procedure InvalidateArea(const R: TRectI);
begin
  if NeedsRepaint then
    Exit;
  if not PartialRepaint or (R.W <= 0) or (R.H <= 0) then
  begin
    NeedsRepaint := True;      { not laid out yet: everything }
    Exit;
  end;
  if NeedsPartialRepaint then
    DirtyArea := DirtyArea.Union(R)
  else
    DirtyArea := R;
  NeedsPartialRepaint := True;
end;

procedure TControl.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 0;
  H := 0;
end;

class function TControl.DesktopOnly: Boolean;
begin
  Result := False;
end;

procedure TControl.GetSize(AvailWidth: Integer; out W, H: Integer);
begin
  if FWidth > 0 then
    AvailWidth := FWidth;
  Measure(AvailWidth, W, H);
  if FWidth > 0 then W := FWidth;
  if FHeight > 0 then H := FHeight;
end;

procedure TControl.Arrange(const R: TRectI);
begin
  FBounds := R;
end;

procedure TControl.SetBoundsOnly(const R: TRectI);
begin
  FBounds := R;
end;

procedure TControl.Paint(C: TCanvas32);
begin
  PaintChildren(C);
end;

procedure TControl.PaintChildren(C: TCanvas32);
var
  I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do
    if TControl(FChildren[I]).FVisible then
      TControl(FChildren[I]).Paint(C);
end;

function TControl.Focusable: Boolean;
begin
  Result := False;
end;

function TControl.FillsAcross: Boolean;
begin
  Result := False;
end;

procedure TControl.FocusLost;
begin
end;

function TControl.Cursor: TCursorKind;
begin
  Result := ckArrow;
end;

procedure TControl.MouseDown(X, Y: Integer);
begin
end;

procedure TControl.MouseUp(X, Y: Integer; Inside: Boolean);
begin
end;

procedure TControl.MouseMove(X, Y: Integer);
begin
end;

function TControl.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := False;
end;

procedure TControl.TextInput(const S: string);
begin
end;

function TControl.ParentForm: TForm;
var
  C: TControl;
begin
  C := Self;
  while C.FParent <> nil do
    C := C.FParent;
  if C is TForm then
    Result := TForm(C)
  else
    Result := C.FPopupForm;
end;

function TControl.ParentPopup: TPopup;
var
  C: TControl;
begin
  C := Self;
  while (C <> nil) and not (C is TPopup) do
    C := C.FParent;
  Result := TPopup(C);
end;

procedure DrawFocus(C: TCanvas32; Ctrl: TControl; const R: TRectI; Radius: Single);
var
  F: TForm;
begin
  if UIStyle.FocusLook = fkOutline then
  begin
    F := Ctrl.ParentForm;
    if (F = nil) or not F.FocusVisible then
      Exit;
  end;
  DrawFocus(C, R, Radius);
end;

procedure TControl.SetStyleLookup(const AValue: string);
begin
  if FStyleLookup = AValue then
    Exit;
  FStyleLookup := AValue;
  Changed;
end;

function TControl.Look: TStyleLook;
begin
  if FStyleLookup = '' then
    Result := nil
  else
    Result := FindLook(FStyleLookup);
end;

procedure TControl.SetPopupMenu(AValue: TControl);
begin
  if FPopupMenu = AValue then
    Exit;
  if FPopupMenu <> nil then
    FPopupMenu.RemoveFreeNotification(Self);
  FPopupMenu := AValue;
  if FPopupMenu <> nil then
    FPopupMenu.FreeNotification(Self);
end;

procedure TControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FPopupMenu) then
    FPopupMenu := nil;
end;

function TControl.Gesture(const G: TGestureInfo): Boolean;
begin
  Result := False;
end;

function TControl.DragData(X, Y: Integer): string;
begin
  Result := '';
end;

function TControl.DragsAt(X, Y: Integer): Boolean;
begin
  Result := FDragMode = dmAutomatic;
end;

function TControl.MouseWheel(DX, DY: Integer): Boolean;
begin
  Result := False;
end;

procedure TControl.ScrollIntoView(C: TControl);
begin
  if FParent <> nil then
    FParent.ScrollIntoView(C);
end;

function TControl.IsHovered: Boolean;
var
  F: TForm;
begin
  F := ParentForm;
  Result := (F <> nil) and (F.FHover = Self) and ((F.FCaptured = nil) or (F.FCaptured = Self));
end;

function TControl.IsPressed: Boolean;
var
  F: TForm;
begin
  F := ParentForm;
  Result := (F <> nil) and (F.FCaptured = Self) and (F.FHover = Self);
end;

function TControl.IsFocused: Boolean;
var
  F: TForm;
begin
  F := ParentForm;
  Result := (F <> nil) and (F.FFocused = Self);
end;

procedure TControl.SetFocus;
var
  F: TForm;
begin
  F := ParentForm;
  if F <> nil then
    F.FocusControl(Self);
end;

function TControl.HitTest(X, Y: Integer): TControl;
var
  I: Integer;
  Hit: TControl;
begin
  Result := nil;
  if not FVisible or not FBounds.Contains(X, Y) then
    Exit;
  for I := FChildren.Count - 1 downto 0 do
  begin
    Hit := TControl(FChildren[I]).HitTest(X, Y);
    if Hit <> nil then
      Exit(Hit);
  end;
  Result := Self;
end;

{ ---- TBox ---- }

procedure TBox.SetMaxContentWidth(AValue: Integer);
begin
  if FMaxContentWidth = AValue then Exit;
  FMaxContentWidth := Max(0, AValue);
  Changed;
end;

{ the room inside the padding, at most MaxContentWidth wide, in the middle }
function TBox.ContentRect(const R: TRectI): TRectI;
begin
  Result := RectI(R.X + FPadding, R.Y + FPadding, Max(0, R.W - 2 * FPadding), Max(0, R.H - 2 * FPadding));
  if (FMaxContentWidth > 0) and (Result.W > FMaxContentWidth) then
  begin
    Inc(Result.X, (Result.W - FMaxContentWidth) div 2);
    Result.W := FMaxContentWidth;
  end;
end;

procedure TBox.SetGap(AValue: Integer);
begin
  if FGap = AValue then Exit;
  FGap := AValue;
  Changed;
end;

procedure TBox.SetPadding(AValue: Integer);
begin
  if FPadding = AValue then Exit;
  FPadding := AValue;
  Changed;
end;

procedure TBox.SetAlign(AValue: TAlignItems);
begin
  if FAlign = AValue then Exit;
  FAlign := AValue;
  Changed;
end;

procedure TBox.SetJustify(AValue: TJustify);
begin
  if FJustify = AValue then Exit;
  FJustify := AValue;
  Changed;
end;

procedure TBox.SetColor(AValue: TColor32);
begin
  FColor := AValue;
  Invalidate;
end;

procedure TBox.SetBorderColor(AValue: TColor32);
begin
  FBorderColor := AValue;
  Invalidate;
end;

procedure TBox.SetRadius(AValue: Integer);
begin
  FRadius := AValue;
  Invalidate;
end;

procedure TBox.SetBorderWidth(AValue: Integer);
begin
  FBorderWidth := AValue;
  Invalidate;
end;

procedure TBox.SetLayout(AValue: TLayoutKind);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  { free-placed children start at the very edge, like on a Delphi form; Padding can still be set after }
  if AValue = lkFree then
    FPadding := 0;
  Changed;
end;

procedure TBox.MeasureFree(out W, H: Integer);
var
  I, CW, CH: Integer;
  Child: TControl;
begin
  W := 0;
  H := 0;
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if not Child.Visible then
      Continue;
    Child.GetSize(0, CW, CH);
    case Child.FDock of
      dkNone:
        begin
          W := Max(W, Child.FLeft + CW);
          H := Max(H, Child.FTop + CH);
        end;
      dkTop, dkBottom: Inc(H, CH);
      dkLeft, dkRight: Inc(W, CW);
    end;
  end;
  Inc(W, FPadding);
  Inc(H, FPadding);
end;

{ docked children take the edges of the inner area (in order, Fill last); the others are
  placed at Left, Top, moved or stretched by how much the box differs from its design size }
procedure TBox.ArrangeFree(const R: TRectI);
var
  Client: TRectI;
  I, CW, CH, DX, DY, X, Y: Integer;
  Child: TControl;
begin
  Client := ContentRect(R);
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if not Child.Visible or (Child.FDock in [dkNone, dkFill]) then
      Continue;
    Child.GetSize(Client.W, CW, CH);
    case Child.FDock of
      dkTop:
        begin
          CH := Min(CH, Client.H);
          Child.Arrange(RectI(Client.X, Client.Y, Client.W, CH));
          Inc(Client.Y, CH);
          Dec(Client.H, CH);
        end;
      dkBottom:
        begin
          CH := Min(CH, Client.H);
          Child.Arrange(RectI(Client.X, Client.Y + Client.H - CH, Client.W, CH));
          Dec(Client.H, CH);
        end;
      dkLeft:
        begin
          CW := Min(CW, Client.W);
          Child.Arrange(RectI(Client.X, Client.Y, CW, Client.H));
          Inc(Client.X, CW);
          Dec(Client.W, CW);
        end;
      dkRight:
        begin
          CW := Min(CW, Client.W);
          Child.Arrange(RectI(Client.X + Client.W - CW, Client.Y, CW, Client.H));
          Dec(Client.W, CW);
        end;
    end;
  end;
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if Child.Visible and (Child.FDock = dkFill) then
      Child.Arrange(Client);
  end;
  { the design size is Width and Height; without them nothing moves }
  DX := 0;
  DY := 0;
  if Width > 0 then DX := R.W - Width;
  if Height > 0 then DY := R.H - Height;
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if not Child.Visible or (Child.FDock <> dkNone) then
      Continue;
    Child.GetSize(Max(0, R.W - Child.FLeft), CW, CH);
    X := R.X + Child.FLeft;
    Y := R.Y + Child.FTop;
    if akRight in Child.FAnchors then
    begin
      if akLeft in Child.FAnchors then Inc(CW, DX) else Inc(X, DX);
    end
    else if not (akLeft in Child.FAnchors) then
      Inc(X, DX div 2);
    if akBottom in Child.FAnchors then
    begin
      if akTop in Child.FAnchors then Inc(CH, DY) else Inc(Y, DY);
    end
    else if not (akTop in Child.FAnchors) then
      Inc(Y, DY div 2);
    Child.Arrange(RectI(X, Y, Max(0, CW), Max(0, CH)));
  end;
end;

procedure TBox.Measure(AvailWidth: Integer; out W, H: Integer);
var
  I, CW, CH, N, Inner, Fixed, GrowSum, Rest: Integer;
  Child: TControl;
begin
  if FLayout = lkFree then
  begin
    MeasureFree(W, H);
    Exit;
  end;
  W := 0;
  H := 0;
  N := 0;
  Inner := Max(0, AvailWidth - 2 * FPadding);
  if FMaxContentWidth > 0 then
    Inner := Min(Inner, FMaxContentWidth);
  { a row: the growing children get what the others leave, so a text that
    wraps is measured at the width it will have (not the whole row's) }
  Rest := -1;
  if FRow and (Inner > 0) then
  begin
    Fixed := 0;
    GrowSum := 0;
    for I := 0 to ChildCount - 1 do
    begin
      Child := Children[I];
      if not Child.Visible then
        Continue;
      Inc(N);
      if Child.Grow > 0 then
        Inc(GrowSum, Child.Grow)
      else
      begin
        Child.GetSize(Inner, CW, CH);
        Inc(Fixed, CW);
      end;
    end;
    if GrowSum > 0 then
      Rest := Max(MinShrink, Inner - Fixed - FGap * Max(0, N - 1));
    N := 0;
  end;
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if not Child.Visible then
      Continue;
    if (Rest >= 0) and (Child.Grow > 0) then
      Child.GetSize(Max(MinShrink, Rest * Child.Grow div GrowSum), CW, CH)
    else
      Child.GetSize(Inner, CW, CH);

    Inc(N);
    if FRow then
    begin
      Inc(W, CW);
      H := Max(H, CH);
    end
    else
    begin
      W := Max(W, CW);
      Inc(H, CH);
    end;
  end;
  if N > 1 then
    if FRow then Inc(W, FGap * (N - 1)) else Inc(H, FGap * (N - 1));
  Inc(W, 2 * FPadding);
  Inc(H, 2 * FPadding);
end;

procedure TBox.Arrange(const R: TRectI);
var
  Inner: TRectI;
  Sizes: array of Integer;
  Cross: array of Integer;
  I, N, Total, FreeSpace, GrowSum, Pos, Extra, Step, CW, CH, CrossSize, CrossPos, Main: Integer;
  Child: TControl;
  Items: TFPList;
begin
  inherited Arrange(R);
  if FLayout = lkFree then
  begin
    ArrangeFree(R);
    Exit;
  end;
  Inner := ContentRect(R);
  Items := TFPList.Create;
  try
    for I := 0 to ChildCount - 1 do
      if Children[I].Visible then
        Items.Add(Children[I]);
    N := Items.Count;
    if N = 0 then
      Exit;
    SetLength(Sizes, N);
    SetLength(Cross, N);
    Total := 0;
    GrowSum := 0;
    for I := 0 to N - 1 do
    begin
      Child := TControl(Items[I]);
      if FRow then
        Child.GetSize(Inner.W, CW, CH)
      else
        Child.GetSize(Inner.W, CW, CH);
      if FRow then
      begin
        Sizes[I] := CW;
        Cross[I] := CH;
      end
      else
      begin
        Sizes[I] := CH;
        Cross[I] := CW;
      end;
      Inc(Total, Sizes[I]);
      Inc(GrowSum, Child.Grow);
    end;
    if FRow then Main := Inner.W else Main := Inner.H;
    FreeSpace := Main - Total - FGap * (N - 1);

    { Too little room in a row: the growing children give some of their
      width (not below MinShrink), like flex-shrink in CSS. }
    if (FreeSpace < 0) and FRow and (GrowSum > 0) then
    begin
      Extra := -FreeSpace;
      for I := 0 to N - 1 do
        if (TControl(Items[I]).Grow > 0) and (TControl(Items[I]).Width = 0) then
        begin
          Step := Min(Max(0, Sizes[I] - MinShrink), (-FreeSpace) * TControl(Items[I]).Grow div GrowSum + 1);
          Step := Min(Step, Extra);
          Dec(Sizes[I], Step);
          Dec(Extra, Step);
        end;
      FreeSpace := -Extra;
    end;
    { still too little: the last children are cut off; tools report it }
    if (FreeSpace < 0) and FRow and (LayoutWarnings <> nil) and (Name <> '') then
      LayoutWarnings.Add(Format('%s=%d,%d', [Name, Main - FreeSpace, Main]));

    { Grow: share the free space. }
    if (FreeSpace > 0) and (GrowSum > 0) then
    begin
      Extra := FreeSpace;
      for I := 0 to N - 1 do
        if TControl(Items[I]).Grow > 0 then
        begin
          Step := FreeSpace * TControl(Items[I]).Grow div GrowSum;
          Inc(Sizes[I], Step);
          Dec(Extra, Step);
        end;
      { rounding leftovers go to the last growing child }
      for I := N - 1 downto 0 do
        if TControl(Items[I]).Grow > 0 then
        begin
          Inc(Sizes[I], Extra);
          Break;
        end;
      FreeSpace := 0;
    end;

    Pos := 0;
    Step := FGap;
    if FreeSpace > 0 then
      case FJustify of
        jsCenter: Pos := FreeSpace div 2;
        jsEnd: Pos := FreeSpace;
        jsSpaceBetween: if N > 1 then Step := FGap + FreeSpace div (N - 1);
      end;

    for I := 0 to N - 1 do
    begin
      Child := TControl(Items[I]);
      { a child of a row that got another width than it asked for: its height
        at that width (a text that wraps has more lines when narrower) }
      if FRow and (Child.Width = 0) then
      begin
        Child.GetSize(Sizes[I], CW, CH);
        Cross[I] := CH;
      end;
      if FRow then CrossSize := Inner.H else CrossSize := Inner.W;
      { Stretch fills the cross axis unless the child has a fixed size there. }
      if Child.FillsAcross or ((FAlign = aiStretch) and
         ((FRow and (Child.Height = 0)) or (not FRow and (Child.Width = 0)))) then
        Cross[I] := CrossSize
      else
        Cross[I] := Min(Cross[I], CrossSize);
      case FAlign of
        aiCenter: CrossPos := (CrossSize - Cross[I]) div 2;
        aiEnd: CrossPos := CrossSize - Cross[I];
      else
        CrossPos := 0;
      end;
      if FRow then
        Child.Arrange(RectI(Inner.X + Pos, Inner.Y + CrossPos, Sizes[I], Cross[I]))
      else
        Child.Arrange(RectI(Inner.X + CrossPos, Inner.Y + Pos, Cross[I], Sizes[I]));
      Inc(Pos, Sizes[I] + Step);
    end;
  finally
    Items.Free;
  end;
end;

function TBox.PaintColor: TColor32;
begin
  Result := FColor;
end;

function TBox.PaintBorderColor: TColor32;
begin
  Result := FBorderColor;
end;

constructor TBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBackgroundFit := ifCover;
end;

destructor TBox.Destroy;
begin
  FBackground.Free;
  inherited Destroy;
end;

procedure TBox.SetBackgroundImage(const AValue: string);
begin
  FBackgroundImage := AValue;
  FreeAndNil(FBackground);
  if AValue <> '' then
  begin
    FBackground := TBitmap32.Create;
    if not LoadAppPicture(AValue, FBackground) then
      FreeAndNil(FBackground);      { a picture that cannot be read is not drawn }
  end;
  Invalidate;
end;

procedure TBox.SetBackgroundFit(AValue: TImageFit);
begin
  FBackgroundFit := AValue;
  Invalidate;
end;

procedure TBox.PaintBackground(C: TCanvas32; const R: TRectI);
var
  Scale: Double;
  W, H: Integer;
begin
  if (FBackground <> nil) and not FBackground.Empty and (R.W > 0) and (R.H > 0) then
  begin
    case FBackgroundFit of
      ifStretch:
        begin
          W := R.W;
          H := R.H;
        end;
      ifCenter:
        begin
          W := FBackground.Width;
          H := FBackground.Height;
        end;
    else
      if FBackgroundFit = ifCover then
        Scale := Math.Max(R.W / FBackground.Width, R.H / FBackground.Height)
      else
        Scale := Math.Min(R.W / FBackground.Width, R.H / FBackground.Height);
      W := Math.Max(1, Round(FBackground.Width * Scale));
      H := Math.Max(1, Round(FBackground.Height * Scale));
    end;
    C.PushClip(R);
    C.DrawBitmap(FBackground, R.X + (R.W - W) div 2, R.Y + (R.H - H) div 2, W, H);
    C.PopClip;
  end;
end;

procedure TBox.Paint(C: TCanvas32);
var
  Col, Bor: TColor32;
  Rad, BW: Integer;
  L: TStyleLook;
begin
  Col := PaintColor;
  Bor := PaintBorderColor;
  Rad := FRadius;
  BW := FBorderWidth;
  L := Look;
  if L <> nil then
  begin
    { the look where the box sets nothing of its own }
    if (FColor = 0) and (L.Color <> 0) then Col := L.Color;
    if (FBorderColor = 0) and (L.BorderColor <> 0) then Bor := L.BorderColor;
    if (FRadius = 0) and (L.Radius >= 0) then Rad := L.Radius;
    if (FBorderWidth = 0) and (L.BorderWidth >= 0) then BW := L.BorderWidth;
  end;
  if (Cardinal(Col) shr 24) > 0 then
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Rad, Col);
  PaintBackground(C, Bounds);
  if (BW > 0) and ((Cardinal(Bor) shr 24) > 0) then
    C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Rad, BW, Bor);
  { a little extra room so children's focus rings are not cut off }
  C.PushClip(RectI(Bounds.X - 4, Bounds.Y - 4, Bounds.W + 8, Bounds.H + 8));
  PaintChildren(C);
  C.PopClip;
end;

constructor TPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLayout := lkFree;
end;

constructor TRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRow := True;
  FAlign := aiCenter;
end;

constructor TFlow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRow := True;
  FGap := 8;
  FAlign := aiCenter;
end;

{ the children's places relative to the inner top left; returns the height }
function TFlow.Lines(AWidth: Integer; out Sizes: TRectArray): Integer;
var
  I, X, Y, LineH, First, CW, CH, GrowSum, Extra, Shift: Integer;
  Child: TControl;

  procedure EndLine(Last: Integer);
  var
    K: Integer;
  begin
    { what is left goes to the growing ones; then centre in the line's height }
    Extra := AWidth - X + FGap;
    if (Extra > 0) and (GrowSum > 0) then
    begin
      Shift := 0;
      for K := First to Last do
        if Children[K].Visible then
        begin
          Sizes[K].X := Sizes[K].X + Shift;
          if Children[K].Grow > 0 then
          begin
            Sizes[K].W := Sizes[K].W + Extra * Children[K].Grow div GrowSum;
            Inc(Shift, Extra * Children[K].Grow div GrowSum);
          end;
        end;
    end;
    for K := First to Last do
      if Children[K].Visible then
        case FAlign of
          aiCenter: Sizes[K].Y := Y + (LineH - Sizes[K].H) div 2;
          aiEnd: Sizes[K].Y := Y + LineH - Sizes[K].H;
          aiStretch: begin Sizes[K].Y := Y; if Children[K].Height = 0 then Sizes[K].H := LineH; end;
        else
          Sizes[K].Y := Y;
        end;
  end;

begin
  SetLength(Sizes, ChildCount);
  X := 0;
  Y := 0;
  LineH := 0;
  First := 0;
  GrowSum := 0;
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if not Child.Visible then
      Continue;
    Child.GetSize(AWidth, CW, CH);
    CW := Min(CW, AWidth);
    if (X > 0) and (X + CW > AWidth) then
    begin
      EndLine(I - 1);
      Inc(Y, LineH + FGap);
      X := 0;
      LineH := 0;
      First := I;
      GrowSum := 0;
    end;
    Sizes[I] := RectI(X, Y, CW, CH);
    Inc(X, CW + FGap);
    LineH := Max(LineH, CH);
    Inc(GrowSum, Child.Grow);
  end;
  EndLine(ChildCount - 1);
  Result := Y + LineH;
end;

procedure TFlow.Measure(AvailWidth: Integer; out W, H: Integer);
var
  Sizes: TRectArray;
  Inner: Integer;
begin
  Inner := Max(0, AvailWidth - 2 * FPadding);
  H := Lines(Inner, Sizes) + 2 * FPadding;
  W := AvailWidth;
end;

procedure TFlow.Arrange(const R: TRectI);
var
  Sizes: TRectArray;
  I: Integer;
begin
  SetBoundsOnly(R);
  Lines(Max(0, R.W - 2 * FPadding), Sizes);
  for I := 0 to ChildCount - 1 do
    if Children[I].Visible then
      Children[I].Arrange(RectI(R.X + FPadding + Sizes[I].X, R.Y + FPadding + Sizes[I].Y, Sizes[I].W, Sizes[I].H));
end;

constructor TCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBorderWidth := 1;
  FRadius := 12;
  FPadding := 20;
  FGap := 12;
end;

function TCard.PaintColor: TColor32;
begin
  Result := FColor;
  if Result = 0 then
    Result := Theme.Surface;
end;

function TCard.PaintBorderColor: TColor32;
begin
  Result := FBorderColor;
  if Result = 0 then
    Result := Theme.Border;
end;

constructor TSpacer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGrow := 1;
end;

{ ---- TLabel ---- }

constructor TLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFontSize := 14;
end;

function TLabel.Font: TPastelFont;
var
  L: TStyleLook;
  Size: Integer;
  B: Boolean;
begin
  Size := FFontSize;
  B := FBold;
  L := Look;
  if L <> nil then
  begin
    { the look's size and boldness unless the label has its own }
    if (L.FontSize > 0) and (FFontSize = 14) then Size := L.FontSize;
    if (L.Bold = 1) and not FBold then B := True;
  end;
  Result := GetFont(Size, B);
end;

procedure TLabel.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
end;

procedure TLabel.SetFontSize(AValue: Integer);
begin
  if FFontSize = AValue then Exit;
  FFontSize := EnsureRange(AValue, 6, 200);
  Changed;
end;

procedure TLabel.SetBold(AValue: Boolean);
begin
  if FBold = AValue then Exit;
  FBold := AValue;
  Changed;
end;

procedure TLabel.SetColor(AValue: TColor32);
begin
  FColor := AValue;
  Invalidate;
end;

procedure TLabel.SetTextAlign(AValue: TTextAlign);
begin
  FTextAlign := AValue;
  Invalidate;
end;

procedure TLabel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  Changed;
end;

function TLabel.TextLines(AWidth: Integer): TStringArray;
begin
  if FWordWrap then
    Result := WrapText(Font, FText, AWidth)
  else
    Result := WrapText(Font, FText, 0);
end;

procedure TLabel.Measure(AvailWidth: Integer; out W, H: Integer);
var
  L: TStringArray;
  S: string;
begin
  L := TextLines(AvailWidth);
  W := 0;
  for S in L do
    W := Max(W, Font.TextWidth(S));
  if FWordWrap and (AvailWidth > 0) then
    W := Min(W, AvailWidth);
  H := Font.LineHeight * Max(1, Length(L));
end;

procedure TLabel.Paint(C: TCanvas32);
var
  F: TPastelFont;
  X, Y, TW: Integer;
  Col: TColor32;
  L: TStringArray;
  S: string;
begin
  F := Font;
  Col := FColor;
  if (Col = 0) and (Look <> nil) then
    Col := Look.TextColor;
  if Col = 0 then
    Col := Theme.Text;
  if not Enabled then
    Col := Theme.Disabled;
  L := TextLines(Bounds.W);
  Y := Bounds.Y + (Bounds.H - F.LineHeight * Length(L)) div 2;
  if Y < Bounds.Y then
    Y := Bounds.Y;
  C.PushClip(Bounds);
  for S in L do
  begin
    TW := F.TextWidth(S);
    case FTextAlign of
      taCenter: X := Bounds.X + (Bounds.W - TW) div 2;
      taRight: X := Bounds.X + Bounds.W - TW;
    else
      X := Bounds.X;
    end;
    C.DrawText(F, X, Y, S, Col);
    Inc(Y, F.LineHeight);
  end;
  C.PopClip;
end;

{ ---- TButton ---- }

{ ---- TAction ---- }

constructor TAction.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
end;

procedure TAction.SetEnabled(AValue: Boolean);
begin
  FEnabled := AValue;
  NeedsRepaint := True;
end;

procedure TAction.SetChecked(AValue: Boolean);
begin
  FChecked := AValue;
  NeedsRepaint := True;
end;

function TAction.Execute: Boolean;
begin
  Result := FEnabled and Assigned(OnExecute);
  if Result then
    OnExecute(Self);
end;

{ ---- TButton ---- }

procedure TButton.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
end;

function TButton.GetIcon: string;
begin
  Result := FIcon;
  if (Result = '') and (FAction is TAction) then
    Result := TAction(FAction).Icon;
end;

function TButton.GetText: string;
begin
  Result := FText;
  if (Result = '') and (FAction is TAction) then
    Result := TAction(FAction).Caption;
end;

procedure TButton.SetAction(AValue: TBasicAction);
begin
  if FAction = AValue then Exit;
  if FAction <> nil then
    FAction.RemoveFreeNotification(Self);
  FAction := AValue;
  if FAction <> nil then
    FAction.FreeNotification(Self);
  Changed;
end;

procedure TButton.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
    FAction := nil;
end;

function TButton.IsEnabled: Boolean;
begin
  Result := Enabled and not ((FAction is TAction) and not TAction(FAction).Enabled);
end;

procedure TButton.SetStyle(AValue: TButtonStyle);
begin
  FStyle := AValue;
  Invalidate;
end;

{ the room around the text in the style (or its look) }
procedure TButton.Padding(out PX, PY: Integer);
var
  L: TStyleLook;
begin
  if FStyle = bsFlat then
  begin
    PX := UIStyle.FlatPadX;
    PY := UIStyle.FlatPadY;
  end
  else
  begin
    PX := UIStyle.ButtonPadX;
    PY := UIStyle.ButtonPadY;
  end;
  L := Look;
  if L <> nil then
  begin
    if L.PaddingX >= 0 then PX := L.PaddingX;
    if L.PaddingY >= 0 then PY := L.PaddingY;
  end;
end;

function TButton.ButtonFont: TPastelFont;
var
  L: TStyleLook;
  Size: Integer;
  B: Boolean;
begin
  Size := Theme.FontSize;
  B := UIStyle.ButtonBold;
  L := Look;
  if L <> nil then
  begin
    if L.FontSize > 0 then Size := L.FontSize;
    if L.Bold >= 0 then B := L.Bold = 1;
  end;
  Result := GetFont(Size, B);
end;

procedure TButton.Measure(AvailWidth: Integer; out W, H: Integer);
var
  F: TPastelFont;
  PX, PY: Integer;
begin
  F := ButtonFont;
  Padding(PX, PY);
  W := F.TextWidth(GetText);
  if HasIcon(GetIcon) then
  begin
    if GetText <> '' then
      Inc(W, 6);
    Inc(W, IconSize);
  end;
  if GetText = '' then
    Inc(W, PY)            { an icon alone: nearly square }
  else
    Inc(W, PX);
  H := Max(F.LineHeight, IconSize) + PY;
end;

function TButton.IconSize: Integer;
begin
  Result := Round(Theme.FontSize * 1.4);
end;

procedure TButton.SetIcon(const AValue: string);
begin
  if FIcon = AValue then
    Exit;
  FIcon := AValue;
  Changed;
end;

procedure TButton.Paint(C: TCanvas32);
var
  F: TPastelFont;
  Bg, Fg, Bor: TColor32;
  IW, IS_, X, BW: Integer;
  Rad: Single;
  S: string;
  L: TStyleLook;
begin
  F := ButtonFont;
  S := GetText;
  L := Look;
  Bor := 0;
  case FStyle of
    bsSecondary:
      begin
        if IsPressed then Bg := Theme.SecondaryPressed
        else if IsHovered then Bg := Theme.SecondaryHover
        else Bg := Theme.Secondary;
        Fg := Theme.Text;
        if UIStyle.ButtonBorder > 0 then
          Bor := Theme.Border;
      end;
    bsFlat:
      begin
        if UIStyle.FlatAccent then Fg := Theme.Accent else Fg := Theme.Text;
        if UIStyle.FlatOverlay then
        begin
          { a shade of the text over whatever is under it }
          if IsPressed then Bg := WithAlpha(Fg, $1F)
          else if IsHovered then Bg := WithAlpha(Fg, $14)
          else Bg := 0;
        end
        else if IsPressed then Bg := Theme.SecondaryPressed
        else if IsHovered then Bg := Theme.SecondaryHover
        else Bg := 0;
      end;
    bsDanger:
      begin
        if IsPressed then Bg := Theme.DangerPressed
        else if IsHovered then Bg := Theme.DangerHover
        else Bg := Theme.Danger;
        { white on a dark red; a dark red on the light ones of dark themes }
        if Luminance(Theme.Danger) > 0.45 then
          Fg := Mix(Theme.Danger, $FF000000, 0.72)
        else
          Fg := RGB(255, 255, 255);
      end;
  else
    if IsPressed then Bg := Theme.AccentPressed
    else if IsHovered then Bg := Theme.AccentHover
    else Bg := Theme.Accent;
    Fg := Theme.OnAccent;
  end;
  if L <> nil then
  begin
    if L.Color <> 0 then
    begin
      if IsPressed then
      begin
        if L.PressedColor <> 0 then Bg := L.PressedColor else Bg := Mix(L.Color, $FF000000, 0.25);
      end
      else if IsHovered then
      begin
        if L.HoverColor <> 0 then Bg := L.HoverColor else Bg := Mix(L.Color, $FF000000, 0.12);
      end
      else
        Bg := L.Color;
    end;
    if L.TextColor <> 0 then Fg := L.TextColor;
    if L.BorderColor <> 0 then Bor := L.BorderColor;
  end;
  if (Cardinal(FColor) shr 24) > 0 then
  begin
    if IsPressed then Bg := Mix(FColor, $FF000000, 0.25)
    else if IsHovered then Bg := Mix(FColor, $FF000000, 0.12)
    else Bg := FColor;
  end;
  if (Cardinal(FTextColor) shr 24) > 0 then
    Fg := FTextColor;
  if not IsEnabled then
  begin
    if FStyle <> bsFlat then
      Bg := Theme.Secondary;
    Fg := Theme.Disabled;
  end;
  Rad := StyleRadius(UIStyle.ButtonRadius);
  if (L <> nil) and (L.Radius >= 0) then
    Rad := L.Radius;
  Rad := Min(Rad, Min(Bounds.W, Bounds.H) / 2);
  BW := UIStyle.ButtonBorder;
  if (L <> nil) and (L.BorderWidth >= 0) then
    BW := L.BorderWidth;
  if (Bor <> 0) and (BW = 0) then
    BW := 1;
  if IsFocused and ParentForm.FocusVisible then
    DrawFocus(C, Bounds, Rad);
  if (Bg = 0) and IsFocused and ParentForm.FocusVisible and (UIStyle.FocusLook = fkRing) then
    Bg := Theme.Secondary;
  if Bg <> 0 then
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Rad, Bg);
  if (Bor <> 0) and (BW > 0) and IsEnabled then
    C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Rad, BW, Bor);
  C.PushClip(Bounds);
  IW := 0;
  if HasIcon(GetIcon) then
  begin
    IS_ := IconSize;
    IW := IS_;
    if S <> '' then
      Inc(IW, 6);
  end;
  X := Bounds.X + (Bounds.W - IW - F.TextWidth(S)) div 2;
  if IW > 0 then
    DrawIcon(C, GetIcon, X, Bounds.Y + (Bounds.H - IS_) div 2, IS_, Fg);
  C.DrawText(F, X + IW, Bounds.Y + (Bounds.H - F.LineHeight) div 2, S, Fg);
  C.PopClip;
end;

procedure TButton.SetColor(AValue: TColor32);
begin
  FColor := AValue;
  Invalidate;
end;

procedure TButton.SetTextColor(AValue: TColor32);
begin
  FTextColor := AValue;
  Invalidate;
end;

function TButton.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TButton.Cursor: TCursorKind;
begin
  if IsEnabled then Result := ckHand else Result := ckArrow;
end;

procedure TButton.MouseDown(X, Y: Integer);
begin
  Invalidate;
end;

procedure TButton.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  Invalidate;
  if Inside and IsEnabled then
    Click;
end;

function TButton.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := (Key = KEY_ENTER) or (Key = KEY_KP_ENTER) or (Key = KEY_SPACE);
  if Result and IsEnabled then
    Click;
end;

procedure TButton.Click;
var
  P: TPopup;
begin
  if not IsEnabled then
    Exit;
  if FAction <> nil then
    FAction.Execute
  else if Assigned(FOnClick) then
    FOnClick(Self);
  if FModalResult <> mrNone then
  begin
    P := ParentPopup;
    if P <> nil then
      P.Close(FModalResult)
    else if (ParentForm <> nil) and ParentForm.FWindowed then
      ParentForm.ModalResult := FModalResult;      { a form in a window of its own: closed }
  end;
end;

{ ---- TPopup ---- }

constructor TPopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRadius := UIStyle.PopupRadius;
  FBorderWidth := 1;
  FPadding := 6;
  FClosed := True;
end;

function TPopup.PaintColor: TColor32;
begin
  Result := FColor;
  if Result = 0 then
    Result := Theme.Surface;
end;

function TPopup.PaintBorderColor: TColor32;
begin
  Result := FBorderColor;
  if Result = 0 then
    Result := Theme.Border;
end;

procedure TPopup.Paint(C: TCanvas32);
var
  I: Integer;
begin
  { a soft shadow }
  for I := 3 downto 1 do
    C.FillRoundRect(Bounds.X - I + 1, Bounds.Y - I + 3, Bounds.W + 2 * I - 2, Bounds.H + 2 * I - 2,
      FRadius + I, WithAlpha(Theme.Shadow, (Cardinal(Theme.Shadow) shr 24) div (I + 1)));
  inherited Paint(C);
end;

procedure TPopup.Popup(Form: TForm; const Anchor: TRectI; PlaceRight: Boolean);
begin
  FAnchor := Anchor;
  FAnchored := True;
  FPlaceRight := PlaceRight;
  Form.ShowPopup(Self);
end;

procedure TPopup.PopupCentered(Form: TForm);
begin
  FAnchored := False;
  Form.ShowPopup(Self);
end;

function TPopup.ShowModal(Form: TForm): Integer;
begin
  if not Assigned(ModalStep) then
    raise Exception.Create('ShowModal needs a running application (Application.Run)');
  FModal := True;
  FModalResult := mrNone;
  PopupCentered(Form);
  while not FClosed do
    ModalStep();
  Result := FModalResult;
end;

procedure TPopup.ShowModal(Form: TForm; OnDone: TModalDoneEvent; FreeWhenDone: Boolean);
begin
  FModal := True;
  FModalResult := mrNone;
  FOnDone := OnDone;
  FFreeWhenDone := FreeWhenDone;
  PopupCentered(Form);
end;

procedure TPopup.Close(AModalResult: Integer);
var
  F: TForm;
  Done: TModalDoneEvent;
begin
  if FClosed then
    Exit;
  if AModalResult <> mrNone then
    FModalResult := AModalResult;
  F := FPopupForm;
  if F <> nil then
    F.ClosePopup(Self);
  FClosed := True;
  if Assigned(FOnClose) then
    FOnClose(Self);
  Done := FOnDone;
  FOnDone := nil;
  if Assigned(Done) then
  begin
    if FModalResult = mrNone then
      FModalResult := mrCancel;
    Done(Self, FModalResult);
  end;
  if FFreeWhenDone then
  begin
    FFreeWhenDone := False;
    ReleaseLater(Self);
  end;
end;

{$I pastel.ui.edit.inc}

{ ---- TForm ---- }

constructor TForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPopups := TFPList.Create;
  FClickCount := 1;
  FMouseButton := 1;
  FPadding := 24;
  FGap := 12;
  FTitle := 'Pastel';
  FResizable := True;
  FMinWidth := 200;
  FMinHeight := 120;
end;

function TForm.SaveState: TStrings;
begin
  if FSaveState = nil then
    FSaveState := TStringList.Create;
  Result := FSaveState;
end;

destructor TForm.Destroy;
var
  I: Integer;
begin
  FreeAndNil(FSaveState);
  for I := FPopups.Count - 1 downto 0 do
  begin
    TPopup(FPopups[I]).FPopupForm := nil;
    TPopup(FPopups[I]).FClosed := True;
  end;
  FreeAndNil(FPopups);
  FreeAndNil(FTooltip);
  FreeAndNil(FEditActions);
  inherited Destroy;
end;

function TForm.PaintColor: TColor32;
begin
  Result := FColor;
  if Result = 0 then
    Result := Theme.Background;
end;

function TForm.HitTest(X, Y: Integer): TControl;
var
  I: Integer;
  P: TPopup;
begin
  for I := FPopups.Count - 1 downto 0 do
  begin
    P := TPopup(FPopups[I]);
    Result := P.HitTest(X, Y);
    if Result <> nil then
      Exit;
    if P.FModal then
      Exit(nil);       { nothing behind a dialog can be reached }
  end;
  Result := inherited HitTest(X, Y);
end;

procedure TForm.ShowPopup(P: TPopup);
var
  List: TFPList;
begin
  HideTooltip;
  if FPopups.IndexOf(P) < 0 then
    FPopups.Add(P);
  P.FPopupForm := Self;
  P.FClosed := False;
  P.FShown := True;
  P.FSavedFocus := FFocused;
  P.FreeNotification(Self);
  if P.FModal then
  begin
    List := TFPList.Create;
    try
      CollectFocusable(P, List);
      if (P.FActiveControl <> nil) and (List.IndexOf(P.FActiveControl) >= 0) then
        FocusControl(P.FActiveControl)
      else if List.Count > 0 then
        FocusControl(TControl(List[0]))
      else
        FocusControl(nil);
    finally
      List.Free;
    end;
  end;
  NeedsLayout := True;
  NeedsRepaint := True;
end;

function InTree(C, Root: TControl): Boolean;
begin
  while (C <> nil) and (C <> Root) do
    C := C.Parent;
  Result := C = Root;
end;

procedure TForm.ClosePopup(P: TPopup);
begin
  if FPopups.IndexOf(P) < 0 then
    Exit;
  FPopups.Remove(P);
  P.FClosed := True;
  P.FShown := False;
  if InTree(FCaptured, P) then FCaptured := nil;
  if InTree(FHover, P) then FHover := nil;
  if (FFocused = nil) or InTree(FFocused, P) then
  begin
    FFocused := nil;
    if (P.FSavedFocus <> nil) and (P.FSavedFocus.ParentForm = Self) then
      FocusControl(P.FSavedFocus);
  end;
  P.FSavedFocus := nil;
  NeedsLayout := True;
  NeedsRepaint := True;
end;

function TForm.PopupCount: Integer;
begin
  Result := FPopups.Count;
end;

function TForm.PopupAt(Index: Integer): TPopup;
begin
  Result := TPopup(FPopups[Index]);
end;

function TForm.TopPopup: TPopup;
begin
  if FPopups.Count = 0 then
    Result := nil
  else
    Result := TPopup(FPopups[FPopups.Count - 1]);
end;

procedure TForm.PlacePopup(P: TPopup);
var
  W, H, X, Y, MaxW, MaxH: Integer;
begin
  MaxW := Max(80, FWidthPx - 16);
  MaxH := Max(60, FHeightPx - 16);
  { along a side: the whole height (a drawer) or the whole width (a bottom sheet) }
  if P.FSide in [psLeft, psRight] then
  begin
    W := P.Width;
    if W <= 0 then
      W := 300;
    W := Min(W, FWidthPx * 85 div 100);
    if P.FSide = psLeft then
      X := 0
    else
      X := FWidthPx - W;
    P.Arrange(RectI(X, 0, W, FHeightPx));
    Exit;
  end;
  if P.FSide = psBottom then
  begin
    P.GetSize(FWidthPx, W, H);
    H := Min(H, FHeightPx * 85 div 100);
    { the rounded corners at the bottom go below the window }
    P.Arrange(RectI(0, FHeightPx - H, FWidthPx, H + P.FRadius));
    Exit;
  end;
  P.GetSize(MaxW, W, H);
  W := Min(W, MaxW);
  H := Min(H, MaxH);
  if not P.FAnchored then
  begin
    X := (FWidthPx - W) div 2;
    Y := Max(8, (FHeightPx - H) * 2 div 5);
  end
  else if P.FPlaceRight then
  begin
    X := P.FAnchor.X + P.FAnchor.W;
    Y := P.FAnchor.Y - P.FPadding;
    if X + W > FWidthPx - 8 then
      X := Max(8, P.FAnchor.X - W);
    if Y + H > FHeightPx - 8 then
      Y := Max(8, FHeightPx - 8 - H);
  end
  else
  begin
    X := P.FAnchor.X;
    Y := P.FAnchor.Y + P.FAnchor.H + 4;
    if (Y + H > FHeightPx - 8) and (P.FAnchor.Y - H - 4 >= 8) then
      Y := P.FAnchor.Y - H - 4
    else if Y + H > FHeightPx - 8 then
      H := Max(40, FHeightPx - 8 - Y);
  end;
  if X + W > FWidthPx - 8 then
    X := FWidthPx - 8 - W;
  X := Max(8, X);
  P.Arrange(RectI(X, Y, W, H));
end;

procedure TForm.HideTooltip;
begin
  if FTooltipFor <> nil then
  begin
    FTooltipFor := nil;
    NeedsRepaint := True;
  end;
end;

function TForm.UpdateTooltip(NowMs: QWord): Boolean;
var
  L: TLabel;
  W, H, X, Y: Integer;
begin
  Result := False;
  if (FHover = nil) or (FHover.Hint = '') or (FCaptured <> nil) or (FTooltipFor = FHover) or
     (NowMs < FHoverSince + 600) then
    Exit;
  if FTooltip = nil then
  begin
    FTooltip := TPopup.Create(nil);
    FTooltip.Padding := 6;
    FTooltip.BorderWidth := 0;
    FTooltip.Radius := 6;
    L := TLabel.Create(FTooltip);
    L.FontSize := 13;
    L.WordWrap := True;
    L.Parent := FTooltip;
  end;
  FTooltip.Color := Theme.TooltipBack;
  L := TLabel(FTooltip.Children[0]);
  L.Text := FHover.Hint;
  L.Color := Theme.TooltipText;
  FTooltip.GetSize(320, W, H);
  W := Min(W, 320);
  X := EnsureRange(FMouseX, 8, Max(8, FWidthPx - W - 8));
  Y := FMouseY + 22;
  if Y + H > FHeightPx - 4 then
    Y := Max(4, FMouseY - H - 8);
  FTooltip.Arrange(RectI(X, Y, W, H));
  FTooltipFor := FHover;
  NeedsRepaint := True;
  Result := True;
end;

procedure TForm.HandleGesture(const G: TGestureInfo);
var
  C: TControl;
  Handled: Boolean;
begin
  HideTooltip;
  C := HitTest(G.X, G.Y);
  while C <> nil do
  begin
    if C.Enabled then
    begin
      Handled := False;
      if Assigned(C.FOnGesture) then
        C.FOnGesture(C, G, Handled);
      if Handled or C.Gesture(G) then
      begin
        NeedsRepaint := True;
        Exit;
      end;
    end;
    C := C.Parent;
  end;
end;

procedure TForm.HandleMouseWheel(DX, DY: Integer);
var
  C: TControl;
begin
  HideTooltip;
  C := HitTest(FMouseX, FMouseY);
  while C <> nil do
  begin
    if C.Enabled and C.MouseWheel(DX, DY) then
    begin
      NeedsRepaint := True;
      Exit;
    end;
    C := C.Parent;
  end;
end;

function TForm.HandleDropFiles(X, Y: Integer; const Files: TStringArray): Boolean;
var
  C: TControl;
begin
  Result := False;
  if Length(Files) = 0 then
    Exit;
  C := HitTest(X, Y);
  while (C <> nil) and not Assigned(C.FOnDropFiles) do
    C := C.Parent;
  if C = nil then
    C := Self;
  if Assigned(C.FOnDropFiles) then
  begin
    C.FOnDropFiles(C, Files);
    NeedsRepaint := True;
    Result := True;
  end;
end;

procedure TForm.HandleContextMenu(X, Y: Integer);
var
  C, Hit: TControl;
begin
  Hit := HitTest(X, Y);
  C := Hit;
  while C <> nil do
  begin
    if C.FPopupMenu <> nil then
    begin
      if Assigned(PopupMenuHook) then
        PopupMenuHook(C.FPopupMenu, Self, X, Y);
      Exit;
    end;
    { an edit without a menu of its own: Cut, Copy, Paste, Select all }
    if C is TCustomEdit then
    begin
      ShowEditActions(TCustomEdit(C), X, Y);
      Exit;
    end;
    C := C.Parent;
  end;
end;

type
  { the little bar of Cut, Copy, Paste and Select all over an edit (a right
    click, or a finger held on it) }
  TEditActions = class(TPopup)
  public
    Edit: TCustomEdit;
    procedure ActionClick(Sender: TObject);
  end;

procedure TEditActions.ActionClick(Sender: TObject);
var
  E: TCustomEdit;
begin
  E := Edit;
  Close;
  if E = nil then
    Exit;
  case TComponent(Sender).Tag of
    1: E.CutToClipboard;
    2: E.CopyToClipboard;
    3: E.PasteFromClipboard;
    4: E.SelectAll;
  end;
  if E.ParentForm <> nil then
    E.ParentForm.FocusControl(E);
end;

procedure TForm.ShowEditActions(Edit: TCustomEdit; X, Y: Integer);
const
  Names: array[1..4] of string = ('Cut', 'Copy', 'Paste', 'Select all');
var
  A: TEditActions;
  B: TButton;
  I: Integer;
  Selected, CanPaste: Boolean;
begin
  if FEditActions = nil then
  begin
    A := TEditActions.Create(nil);
    A.FRow := True;
    A.Padding := 4;
    A.Gap := 2;
    for I := 1 to 4 do
    begin
      B := TButton.Create(A);
      B.Style := bsFlat;
      B.Tag := I;
      B.TabStop := False;
      B.OnClick := @A.ActionClick;
      B.Parent := A;
    end;
    FEditActions := A;
  end;
  A := TEditActions(FEditActions);
  if A.Shown and not A.Closed then
    A.Close;
  A.Edit := Edit;
  FocusControl(Edit);
  Selected := Edit.SelLength > 0;
  CanPaste := not Edit.ReadOnly and Assigned(ClipboardGetText) and (ClipboardGetText() <> '');
  for I := 0 to A.ChildCount - 1 do
  begin
    B := TButton(A.Children[I]);
    B.Text := Translate(Names[B.Tag]);
    case B.Tag of
      1: B.Visible := Selected and not Edit.ReadOnly and not Edit.IsPassword;
      2: B.Visible := Selected and not Edit.IsPassword;
      3: B.Visible := CanPaste;
      4: B.Visible := Edit.Text <> '';
    end;
  end;
  if not (A.Children[0].Visible or A.Children[1].Visible or A.Children[2].Visible or A.Children[3].Visible) then
    Exit;
  { under the edit (above it when there is no room) }
  A.Popup(Self, RectI(X - 8, Edit.Bounds.Y, 16, Edit.Bounds.H));
end;

procedure TForm.SetResizable(AValue: Boolean);
begin
  FResizable := AValue;
  NeedsWindowSync := True;
end;

procedure TForm.SetAlwaysOnTop(AValue: Boolean);
begin
  FAlwaysOnTop := AValue;
  NeedsWindowSync := True;
end;

procedure TForm.SetMinWidth(AValue: Integer);
begin
  FMinWidth := Max(1, AValue);
  NeedsWindowSync := True;
end;

procedure TForm.SetMinHeight(AValue: Integer);
begin
  FMinHeight := Max(1, AValue);
  NeedsWindowSync := True;
end;

procedure TForm.SetWindowState(AValue: TWindowState);
begin
  FWindowState := AValue;
  NeedsWindowSync := True;
end;

procedure TForm.WindowStateChanged(AState: TWindowState);
begin
  FWindowState := AState;
end;

procedure TForm.Maximize;
begin
  SetWindowState(wsMaximized);
end;

procedure TForm.Minimize;
begin
  SetWindowState(wsMinimized);
end;

procedure TForm.Restore;
begin
  SetWindowState(wsNormal);
end;

type
  { holds a form shown with ShowModal: its title above it }
  TFormHost = class(TPopup)
  protected
    procedure Arrange(const R: TRectI); override;
  public
    TitleLabel: TLabel;
    HostedForm: TForm;
    Done: TModalDoneEvent;
    procedure HostClosed(Sender: TObject; AModalResult: Integer);
  end;

{ a form shown without waiting is closed: the form leaves the host, then OnClose and OnDone }
procedure TFormHost.HostClosed(Sender: TObject; AModalResult: Integer);
var
  F: TForm;
  D: TModalDoneEvent;
begin
  F := HostedForm;
  D := Done;
  HostedForm := nil;
  Done := nil;
  if F <> nil then
  begin
    F.Parent := nil;
    if Assigned(F.FOnClose) then
      F.FOnClose(F);
  end;
  ReleaseLater(Self);
  if Assigned(D) then
    D(F, AModalResult);
end;

{ a form taller than the screen (a phone) gets the room under its title, not its design height }
procedure TFormHost.Arrange(const R: TRectI);
var
  Header, Form: TControl;
  Below: Integer;
begin
  inherited Arrange(R);
  if ChildCount < 2 then
    Exit;
  Header := Children[0];
  Form := Children[1];
  if Header.Visible then
    Below := Header.Bounds.Y + Header.Bounds.H
  else
    Below := R.Y;
  if Form.Bounds.Y + Form.Bounds.H > R.Y + R.H then
    Form.Arrange(RectI(R.X, Below, R.W, Max(0, R.Y + R.H - Below)));
end;

{ the dialog around a form shown by ShowModal: its title above it }
function NewFormHost(F: TForm): TFormHost;
var
  Header: TRow;
begin
  if (MainForm = nil) or (MainForm = F) then
    raise Exception.Create('ShowModal shows a form above the main window: create the main form first');
  if F.ParentPopup <> nil then
    raise Exception.Create(Format('%s is shown already', [F.Name]));
  Result := TFormHost.Create(nil);
  Result.Padding := 0;
  Result.Gap := 0;
  Header := TRow.Create(Result);
  Header.Padding := 16;
  Header.Parent := Result;
  Result.TitleLabel := TLabel.Create(Result);
  Result.TitleLabel.Bold := True;
  Result.TitleLabel.FontSize := 16;
  Result.TitleLabel.Text := F.FTitle;
  Result.TitleLabel.Parent := Header;
  Header.Visible := F.FTitle <> '';
  F.Parent := Result;
  F.FFocused := nil;
end;

procedure TForm.ShowModal(OnDone: TModalDoneEvent);
var
  Host: TFormHost;
begin
  Host := NewFormHost(Self);
  Host.HostedForm := Self;
  Host.Done := OnDone;
  Host.ShowModal(MainForm, @Host.HostClosed);
end;

function TForm.ShowModal: Integer;
var
  Host: TFormHost;
begin
  Host := NewFormHost(Self);
  try
    Result := Host.ShowModal(MainForm);
  finally
    Parent := nil;
    Host.Free;
  end;
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

function TForm.GetModalResult: Integer;
var
  P: TPopup;
begin
  P := ParentPopup;
  if P <> nil then
    Result := P.ModalResult
  else
    Result := mrNone;
end;

procedure TForm.SetModalResult(AValue: Integer);
var
  P: TPopup;
begin
  { a form in a window of its own: a button with a ModalResult closes it }
  if FWindowed and (AValue <> mrNone) then
  begin
    Close;
    Exit;
  end;
  P := ParentPopup;
  if (P <> nil) and (AValue <> mrNone) then
    P.Close(AValue);
end;

procedure TForm.Show;
begin
  if Assigned(ShowFormHook) then
    ShowFormHook(Self)
  else if ParentPopup = nil then
    ShowModal(TModalDoneEvent(nil));
end;

function TForm.Showing: Boolean;
begin
  Result := FWindowed;
end;

procedure TForm.Close;
var
  P: TPopup;
begin
  if FWindowed and Assigned(CloseFormHook) then
  begin
    if CloseQuery then
      CloseFormHook(Self);
    Exit;
  end;
  P := ParentPopup;
  if P <> nil then
  begin
    { a dialog form: closing it ends ShowModal }
    if CloseQuery then
      P.Close(mrCancel);
    Exit;
  end;
  CloseRequested := True;
end;

function TForm.CloseQuery: Boolean;
begin
  Result := True;
  if Assigned(FOnCloseQuery) then
    FOnCloseQuery(Self, Result);
end;

procedure TForm.SetTitle(const AValue: string);
begin
  FTitle := AValue;
  Invalidate;
end;

procedure TForm.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FFocused then FFocused := nil;
    if AComponent = FHover then FHover := nil;
    if AComponent = FCaptured then FCaptured := nil;
    if AComponent = FTooltipFor then FTooltipFor := nil;
    if AComponent = FDragFrom then begin FDragFrom := nil; FDragging := False; end;
    if AComponent = FDragTarget then FDragTarget := nil;
    if FPopups <> nil then
    begin
      FPopups.Remove(AComponent);
      for I := 0 to FPopups.Count - 1 do
        if TPopup(FPopups[I]).FSavedFocus = AComponent then
          TPopup(FPopups[I]).FSavedFocus := nil;
    end;
  end;
end;

procedure TForm.ClearControls;
begin
  { the view is applied again to the new controls }
  FScreenClassKnown := False;
  FFocused := nil;
  FHover := nil;
  FCaptured := nil;
  DestroyComponents;
  NeedsLayout := True;
  NeedsRepaint := True;
end;

procedure TForm.Layout(AWidth, AHeight: Integer);
var
  I: Integer;
begin
  FWidthPx := AWidth;
  FHeightPx := AHeight;
  Arrange(RectI(0, 0, AWidth, AHeight));
  for I := 0 to FPopups.Count - 1 do
    PlacePopup(TPopup(FPopups[I]));
  NeedsLayout := False;
  NeedsRepaint := True;
end;

procedure TForm.Render(C: TCanvas32);
var
  I: Integer;
  P: TPopup;
begin
  { first: what is invalidated while painting (animations) is for the next frame }
  NeedsRepaint := False;
  NeedsPartialRepaint := False;
  C.Clear(PaintColor);
  PaintBackground(C, RectI(0, 0, FWidthPx, FHeightPx));
  PaintChildren(C);
  for I := 0 to FPopups.Count - 1 do
  begin
    P := TPopup(FPopups[I]);
    if P.FModal or (P.FSide <> psAnchor) then
      C.FillRect(0, 0, FWidthPx, FHeightPx, Theme.Backdrop);
    P.Paint(C);
  end;
  { a TV's remote moves the focus: it must be seen on every control, from across the room }
  if ArrowKeysMoveFocus and FFocusVisible and (FFocused <> nil) and FFocused.Visible and
    not (FFocused is TButton) then
    C.StrokeRoundRect(FFocused.Bounds.X - 3, FFocused.Bounds.Y - 3, FFocused.Bounds.W + 6, FFocused.Bounds.H + 6,
      Theme.Radius + 3, 3, Theme.Accent);
  if (FTooltipFor <> nil) and (FTooltip <> nil) then
    FTooltip.Paint(C);
  if FToastText <> '' then
    PaintToast(C);
  if FDragging then
    PaintDrag(C);
end;

procedure TForm.ShowToast(const Msg: string; DurationMs: Integer);
begin
  FToastText := Msg;
  if FToastTimer = nil then
  begin
    FToastTimer := TTimer.Create(Self);
    FToastTimer.OnTimer := @ToastDone;
  end;
  FToastTimer.Enabled := False;
  FToastTimer.Interval := Max(500, DurationMs);
  FToastTimer.Enabled := FToastText <> '';
  NeedsRepaint := True;
end;

procedure TForm.ToastDone(Sender: TObject);
begin
  FToastTimer.Enabled := False;
  FToastText := '';
  NeedsRepaint := True;
end;

{ dark on light (light on dark) in a rounded box, above the bottom }
procedure TForm.PaintToast(C: TCanvas32);
var
  F: TPastelFont;
  Lines: TStringArray;
  I, W, H, X, Y, Pad: Integer;
begin
  F := GetFont(Theme.FontSize);
  Pad := 12;
  Lines := WrapText(F, FToastText, Max(80, Min(480, FWidthPx - 48) - 2 * Pad));
  W := 0;
  for I := 0 to High(Lines) do
    W := Max(W, F.TextWidth(Lines[I]));
  W := W + 2 * Pad;
  H := Length(Lines) * F.LineHeight + 2 * Pad - 4;
  X := (FWidthPx - W) div 2;
  Y := FHeightPx - H - Max(24, FHeightPx div 10);
  C.FillRoundRect(X, Y, W, H, H div 2 + 2, Theme.Text);
  for I := 0 to High(Lines) do
    C.DrawText(F, X + Pad, Y + Pad - 2 + I * F.LineHeight, Lines[I], Theme.Surface);
end;

procedure TForm.RenderArea(C: TCanvas32; const Area: TRectI);
begin
  C.PushClip(Area);
  try
    Render(C);
  finally
    C.PopClip;
  end;
end;

procedure TForm.CollectFocusable(C: TControl; List: TFPList);
var
  I, J: Integer;
  Kids: array of TControl;
  K: TControl;
begin
  if not C.Visible then
    Exit;
  if C.Focusable and C.FTabStop then
    List.Add(C);
  { the children in TabOrder; a stable sort keeps the .pform order for equal ones }
  SetLength(Kids, C.ChildCount);
  for I := 0 to C.ChildCount - 1 do
  begin
    K := C.Children[I];
    J := I;
    while (J > 0) and (Kids[J - 1].FTabOrder > K.FTabOrder) do
    begin
      Kids[J] := Kids[J - 1];
      Dec(J);
    end;
    Kids[J] := K;
  end;
  for I := 0 to High(Kids) do
    CollectFocusable(Kids[I], List);
end;

procedure TForm.SetAppearance(AValue: TThemeMode);
begin
  FThemeMode := AValue;
  if csLoading in ComponentState then
    Exit;
  case AValue of
    tmLight: UseDarkTheme(False);
    tmDark: UseDarkTheme(True);
    tmSystem: UseDarkTheme(Assigned(SystemDarkHook) and SystemDarkHook());
  end;
end;

procedure TForm.FocusControl(C: TControl);
var
  Old: TControl;
begin
  if (C <> nil) and not C.Focusable then
    C := nil;
  if FFocused = C then
    Exit;
  Old := FFocused;
  FFocused := C;
  CaretVisible := True;
  if Old <> nil then
  begin
    Old.FocusLost;
    Old.Invalidate;
  end;
  if C <> nil then
    C.Invalidate;
  if (C <> nil) and (C.Parent <> nil) then
    C.Parent.ScrollIntoView(C);
end;

procedure TForm.FocusNext(Backward: Boolean);
var
  List: TFPList;
  I: Integer;
begin
  List := TFPList.Create;
  try
    if (TopPopup <> nil) and TopPopup.FModal then
      CollectFocusable(TopPopup, List)    { Tab stays in the dialog }
    else
      CollectFocusable(Self, List);
    if List.Count = 0 then
      Exit;
    I := List.IndexOf(FFocused);
    if Backward then
    begin
      if I <= 0 then I := List.Count - 1 else Dec(I);
    end
    else if (I < 0) or (I >= List.Count - 1) then
      I := 0
    else
      Inc(I);
    FocusControl(TControl(List[I]));
    FFocusVisible := True;
  finally
    List.Free;
  end;
end;

procedure TForm.HandleMouseMove(X, Y: Integer);
var
  Hit: TControl;
begin
  if (Abs(X - FMouseX) > 3) or (Abs(Y - FMouseY) > 3) then
    HideTooltip;
  FMouseX := X;
  FMouseY := Y;
  Hit := HitTest(X, Y);
  if Hit <> FHover then
  begin
    if FHover <> nil then
      FHover.Invalidate;
    FHover := Hit;
    FHoverSince := GetTickCount64;
    HideTooltip;
    if Hit <> nil then
      Hit.Invalidate;
  end;
  if FDragging then
  begin
    DragMove(X, Y);
    Exit;
  end;
  { a press on a control that drags, moved far enough: a drag }
  if (FDragFrom <> nil) and (FCaptured <> nil) and ((Abs(X - FDragDownX) > 6) or (Abs(Y - FDragDownY) > 6)) then
  begin
    BeginDrag(FDragFrom, FDragFrom.DragData(FDragDownX, FDragDownY));
    if FDragging then
    begin
      DragMove(X, Y);
      Exit;
    end;
  end;
  if FCaptured <> nil then
    FCaptured.MouseMove(X, Y)
  else if Hit <> nil then
    Hit.MouseMove(X, Y);
end;

procedure TForm.BeginDrag(C: TControl; const Data: string);
var
  D: string;
  Cancel: Boolean;
begin
  D := Data;
  Cancel := False;
  if Assigned(C.FOnStartDrag) then
    C.FOnStartDrag(C, D, Cancel);
  FDragFrom := nil;
  if Cancel then
    Exit;
  FDragging := True;
  FDragFrom := C;
  FDragData := D;
  FDragTarget := nil;
  FDragAccepted := False;
  { the press is a drag now, not a click }
  if FCaptured <> nil then
    FCaptured.MouseUp(-10000, -10000, False);
  FCaptured := nil;
  NeedsRepaint := True;
end;

procedure TForm.DragMove(X, Y: Integer);
var
  C: TControl;
  Accept: Boolean;
begin
  C := HitTest(X, Y);
  while (C <> nil) and not (C.Enabled and Assigned(C.FOnDragDrop)) do
    C := C.Parent;
  Accept := C <> nil;
  if Accept and Assigned(C.FOnDragOver) then
    C.FOnDragOver(C, FDragFrom, FDragData, X, Y, Accept);
  FDragTarget := C;
  FDragAccepted := Accept;
  NeedsRepaint := True;
end;

procedure TForm.PaintDrag(C: TCanvas32);
var
  F: TPastelFont;
  S: string;
  W: Integer;
begin
  if FDragTarget <> nil then
    if FDragAccepted then
      C.StrokeRoundRect(FDragTarget.Bounds.X, FDragTarget.Bounds.Y, FDragTarget.Bounds.W, FDragTarget.Bounds.H,
        Theme.Radius, 2, Theme.Accent)
    else
      C.StrokeRoundRect(FDragTarget.Bounds.X, FDragTarget.Bounds.Y, FDragTarget.Bounds.W, FDragTarget.Bounds.H,
        Theme.Radius, 2, Theme.Danger);
  S := FDragData;
  if S = '' then
    S := '...';
  F := GetFont(Theme.FontSize);
  W := Min(F.TextWidth(S) + 16, 260);
  C.FillRoundRect(FMouseX + 12, FMouseY + 12, W, F.LineHeight + 8, Theme.Radius, Theme.Surface);
  C.StrokeRoundRect(FMouseX + 12, FMouseY + 12, W, F.LineHeight + 8, Theme.Radius, 1, Theme.Border);
  C.PushClip(RectI(FMouseX + 12, FMouseY + 12, W, F.LineHeight + 8));
  C.DrawText(F, FMouseX + 20, FMouseY + 16, S, Theme.Text);
  C.PopClip;
end;

procedure TForm.HandleMouseDown(X, Y: Integer; Button: Integer; Clicks: Integer);
var
  Hit, Target: TControl;
  P: TPopup;
begin
  HideTooltip;
  FMouseX := X;
  FMouseY := Y;
  FClickCount := Max(1, Clicks);
  FMouseButton := Button;
  Hit := HitTest(X, Y);
  { a click outside a drop-down or menu closes it (and does nothing else) }
  P := TopPopup;
  if (P <> nil) and not P.FModal and not InTree(Hit, P) then
  begin
    while (TopPopup <> nil) and not TopPopup.FModal and not InTree(Hit, TopPopup) do
      TopPopup.Close;
    NeedsRepaint := True;
    Exit;
  end;
  FHover := Hit;
  Target := Hit;
  while (Target <> nil) and not Target.Focusable do
    Target := Target.Parent;
  if Button = 3 then
  begin
    if Target <> nil then
      FocusControl(Target);
    HandleContextMenu(X, Y);
    NeedsRepaint := True;
    Exit;
  end;
  if Button <> 1 then
    Exit;
  FocusControl(Target);
  FFocusVisible := False;
  FCaptured := Hit;
  { a control that drags (it or one around it) }
  FDragFrom := Hit;
  while (FDragFrom <> nil) and (FDragFrom.FDragMode <> dmAutomatic) do
    FDragFrom := FDragFrom.Parent;
  if FDragFrom <> nil then
  begin
    FDragDownX := X;
    FDragDownY := Y;
  end;
  if (Hit <> nil) and Hit.Enabled then
    Hit.MouseDown(X, Y);
  NeedsRepaint := True;
end;

procedure TForm.HandleMouseUp(X, Y: Integer; Button: Integer);
var
  C: TControl;
begin
  if Button <> 1 then
    Exit;
  if FDragging then
  begin
    DragMove(X, Y);
    FDragging := False;
    C := FDragFrom;
    FDragFrom := nil;
    if (FDragTarget <> nil) and FDragAccepted then
      FDragTarget.FOnDragDrop(FDragTarget, C, FDragData, X, Y)
    else
      FDragTarget := nil;
    if (C <> nil) and Assigned(C.FOnEndDrag) then
      C.FOnEndDrag(C, FDragTarget, FDragData);
    FDragTarget := nil;
    NeedsRepaint := True;
    Exit;
  end;
  FDragFrom := nil;
  C := FCaptured;
  FCaptured := nil;
  if C <> nil then
    C.MouseUp(X, Y, C.Bounds.Contains(X, Y) and (HitTest(X, Y) = C));
  NeedsRepaint := True;
end;

procedure TForm.HandleMouseLeave;
begin
  if FHover <> nil then
  begin
    FHover := nil;
    NeedsRepaint := True;
  end;
end;

{ the Default (Enter) or Cancel (Escape) button in a control tree }
function FindDialogButton(C: TControl; Cancel: Boolean): TButton;
var
  I: Integer;
begin
  Result := nil;
  if not C.Visible then
    Exit;
  if (C is TButton) and C.Enabled and
     ((Cancel and TButton(C).Cancel) or (not Cancel and TButton(C).Default)) then
    Exit(TButton(C));
  for I := 0 to C.ChildCount - 1 do
  begin
    Result := FindDialogButton(C.Children[I], Cancel);
    if Result <> nil then
      Exit;
  end;
end;

procedure TForm.HandleKeyDown(Key: LongInt; Shift, Ctrl: Boolean);
var
  P: TPopup;
  Root: TControl;
  B: TButton;
begin
  HideTooltip;
  FShiftDown := Shift;
  if (FFocused <> nil) and FFocused.KeyDown(Key, Shift, Ctrl) then
    Exit;
  P := TopPopup;
  if (P <> nil) and P.FModal then Root := P else Root := Self;
  { Escape (Back on a phone) closes a drawer, a menu, a drop-down first }
  if (Key = KEY_ESCAPE) and (P <> nil) and not P.FModal then
  begin
    P.Close(mrCancel);
    Exit;
  end;
  if (Key = KEY_ESCAPE) or (Key = KEY_ENTER) or (Key = KEY_KP_ENTER) then
  begin
    B := FindDialogButton(Root, Key = KEY_ESCAPE);
    if B <> nil then
    begin
      B.Click;
      Exit;
    end;
    if (Key = KEY_ESCAPE) and (P <> nil) then
    begin
      P.Close(mrCancel);
      Exit;
    end;
  end;
  if ((Key = KEY_MENU) or (Key = KEY_APPLICATION) or ((Key = KEY_F1 + 9) and Shift)) and (FFocused <> nil) then
  begin
    HandleContextMenu(FFocused.Bounds.X + 4, FFocused.Bounds.Y + FFocused.Bounds.H - 2);
    Exit;
  end;
  if Assigned(ShortcutHook) and ShortcutHook(Self, Key, Shift, Ctrl) then
    Exit;
  if Key = KEY_TAB then
    FocusNext(Shift)
  else if ArrowKeysMoveFocus and not Ctrl then
    case Key of
      KEY_LEFT: FocusInDirection(-1, 0);
      KEY_RIGHT: FocusInDirection(1, 0);
      KEY_UP: FocusInDirection(0, -1);
      KEY_DOWN: FocusInDirection(0, 1);
    end;
end;

procedure TForm.ActivateFocused;
begin
  if FFocused = nil then
  begin
    FocusNext(False);
    Exit;
  end;
  FFocusVisible := True;
  if not FFocused.KeyDown(KEY_SPACE, False, False) then
    HandleKeyDown(KEY_ENTER, False, False);
end;

function TForm.FocusInDirection(DX, DY: Integer): Boolean;
var
  List: TFPList;
  I: Integer;
  C, Best: TControl;
  X0, Y0, CX, CY, Main, Side, Score, BestScore: Integer;
begin
  Result := False;
  List := TFPList.Create;
  try
    if (TopPopup <> nil) and TopPopup.FModal then
      CollectFocusable(TopPopup, List)
    else
      CollectFocusable(Self, List);
    if List.Count = 0 then
      Exit;
    if (FFocused = nil) or (List.IndexOf(FFocused) < 0) then
    begin
      { nothing chosen yet: the first control }
      FocusControl(TControl(List[0]));
      FFocusVisible := True;
      NeedsRepaint := True;
      Exit(True);
    end;
    X0 := FFocused.Bounds.X + FFocused.Bounds.W div 2;
    Y0 := FFocused.Bounds.Y + FFocused.Bounds.H div 2;
    Best := nil;
    BestScore := MaxInt;
    for I := 0 to List.Count - 1 do
    begin
      C := TControl(List[I]);
      if C = FFocused then
        Continue;
      CX := C.Bounds.X + C.Bounds.W div 2;
      CY := C.Bounds.Y + C.Bounds.H div 2;
      { how far it is in that direction, and how far to the side }
      if DX <> 0 then
      begin
        Main := (CX - X0) * DX;
        Side := Abs(CY - Y0);
        { it must start beyond the focused control's edge (not just overlap it) }
        if (DX > 0) and (C.Bounds.X < FFocused.Bounds.X + FFocused.Bounds.W - 4) then
          Continue;
        if (DX < 0) and (C.Bounds.X + C.Bounds.W > FFocused.Bounds.X + 4) then
          Continue;
      end
      else
      begin
        Main := (CY - Y0) * DY;
        Side := Abs(CX - X0);
        if (DY > 0) and (C.Bounds.Y < FFocused.Bounds.Y + FFocused.Bounds.H - 4) then
          Continue;
        if (DY < 0) and (C.Bounds.Y + C.Bounds.H > FFocused.Bounds.Y + 4) then
          Continue;
      end;
      if Main <= 0 then
        Continue;
      Score := Main + 2 * Side;
      if Score < BestScore then
      begin
        BestScore := Score;
        Best := C;
      end;
    end;
    if Best <> nil then
    begin
      FocusControl(Best);
      FFocusVisible := True;
      NeedsRepaint := True;     { the ring is drawn outside the controls }
      Result := True;
    end;
  finally
    List.Free;
  end;
end;

procedure TForm.SetScreenClass(AValue: TScreenClass);
begin
  if FScreenClassKnown and (FScreenClass = AValue) then
    Exit;
  FScreenClass := AValue;
  FScreenClassKnown := True;
  if Assigned(FormViewHook) then
    FormViewHook(Self, AValue);
  NeedsLayout := True;
  NeedsRepaint := True;
  if Assigned(FOnScreenClassChange) then
    FOnScreenClassChange(Self);
end;

procedure TForm.HandleTextInput(const S: string);
begin
  if FFocused <> nil then
    FFocused.TextInput(S);
end;

function TForm.CurrentCursor: TCursorKind;
begin
  if FCaptured <> nil then
    Result := FCaptured.Cursor
  else if FHover <> nil then
    Result := FHover.Cursor
  else
    Result := ckArrow;
end;

function TForm.FindControl(const AName: string): TControl;
var
  C: TComponent;
begin
  C := FindComponent(AName);
  if C is TControl then
    Result := TControl(C)
  else
    Result := nil;
end;

procedure TForm.BindControls;
begin
end;

function TForm.BindComponent(const AName: string; AClass: TComponentClass): TComponent;
begin
  Result := FindComponent(AName);
  if (Result <> nil) and not Result.InheritsFrom(AClass) then
    raise Exception.CreateFmt('"%s" is a %s in the .pform file but a %s in the code. ' +
      'Restart the app (pastel run) so the code is regenerated.', [AName, Result.ClassName, AClass.ClassName]);
end;

function TForm.BindControl(const AName: string; AClass: TControlClass): TControl;
begin
  Result := FindControl(AName);
  if (Result <> nil) and not Result.InheritsFrom(AClass) then
    raise Exception.CreateFmt('"%s" is a %s in the .pform file but a %s in the code. ' +
      'Restart the app (pastel run) so the code is regenerated.',
      [AName, Result.ClassName, AClass.ClassName]);
end;

initialization
  ControlClasses := TStringList.Create;
  ControlClasses.Sorted := True;
  ControlClasses.CaseSensitive := False;
  LightTheme;
  Timers := TFPList.Create;
  NonVisualClasses := TStringList.Create;
  NonVisualClasses.Sorted := True;
  NonVisualClasses.CaseSensitive := False;
  RegisterNonVisual(TTimer);
  RegisterNonVisual(TAction);
  RegisterControl(TPanel);
  RegisterControl(TColumn);
  RegisterControl(TRow);
  RegisterControl(TFlow);
  RegisterControl(TCard);
  RegisterControl(TSpacer);
  RegisterControl(TLabel);
  RegisterControl(TButton);
  RegisterControl(TEdit);
  RegisterControl(TMemo);

finalization
  FreeAndNil(StyleDefs);
  ControlClasses.Free;
  NonVisualClasses.Free;
  FreeAndNil(Timers);
  while (LaterCalls <> nil) and (LaterCalls.Count > 0) do
  begin
    TObject(LaterCalls[0]).Free;
    LaterCalls.Delete(0);
  end;
  FreeAndNil(LaterCalls);
  FreeAndNil(Releases);

end.
