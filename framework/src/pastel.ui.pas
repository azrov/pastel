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
  TTextAlign = (taLeft, taCenter, taRight);
  { bsFlat: no background until the mouse is on it (tool bars). }
  TButtonStyle = (bsPrimary, bsSecondary, bsDanger, bsFlat);
  TCursorKind = (ckArrow, ckIBeam, ckHand, ckSizeWE, ckSizeNS);
  TWindowState = (wsNormal, wsMaximized, wsMinimized, wsFullScreen);
  { Light, dark, or what the computer is set to. }
  TThemeMode = (tmLight, tmDark, tmSystem);
  TCloseQueryEvent = procedure(Sender: TObject; var CanClose: Boolean) of object;

  TForm = class;
  TPopup = class;

  TControl = class(TComponent)
  private
    FParent: TControl;
    FChildren: TFPList;
    FWidth, FHeight, FGrow: Integer;
    FVisible, FEnabled: Boolean;
    FBounds: TRectI;
    FHint: string;
    FPopupMenu: TControl;
    FPopupForm: TForm;        { set on the root of a popup: the form it is shown on }
    procedure SetPopupMenu(AValue: TControl);
    function GetChild(Index: Integer): TControl;
    function GetChildCount: Integer;
    procedure SetParent(AValue: TControl);
    procedure SetWidth(AValue: Integer);
    procedure SetHeight(AValue: Integer);
    procedure SetGrow(AValue: Integer);
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
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function IsHovered: Boolean;
    { A child got the focus: scrolling parents bring it into view. }
    procedure ScrollIntoView(C: TControl); virtual;
    function IsPressed: Boolean;
    function IsFocused: Boolean;
    procedure Changed;          { needs layout and repaint }
    { Sets Bounds without arranging children (scrolling containers). }
    procedure SetBoundsOnly(const R: TRectI);
  public
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
    property Parent: TControl read FParent write SetParent;
    property Children[Index: Integer]: TControl read GetChild;
    property ChildCount: Integer read GetChildCount;
    function IndexOfChild(C: TControl): Integer;
    property Bounds: TRectI read FBounds;
  published
    property Width: Integer read FWidth write SetWidth default 0;
    property Height: Integer read FHeight write SetHeight default 0;
    property Grow: Integer read FGrow write SetGrow default 0;
    property Visible: Boolean read FVisible write SetVisible default True;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    { Shown in a tooltip when the mouse rests on the control. }
    property Hint: string read FHint write FHint;
    { A TPopupMenu shown on a right click (or the menu key). }
    property PopupMenu: TControl read FPopupMenu write SetPopupMenu;
  end;

  TControlClass = class of TControl;

  { A command with a caption and a keyboard shortcut, used by menu items and
    buttons: one place for what happens, and for Enabled and Checked. }
  TAction = class(TBasicAction)
  private
    FCaption, FShortCut, FHint: string;
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
    procedure SetGap(AValue: Integer);
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
  public
    { True for TRow: children are placed left to right. }
    property Horizontal: Boolean read FRow;
  published
    property Gap: Integer read FGap write SetGap default 0;
    property Padding: Integer read FPadding write SetPadding default 0;
    property Align: TAlignItems read FAlign write SetAlign default aiStretch;
    property Justify: TJustify read FJustify write SetJustify default jsStart;
    property Color: TColor32 read FColor write SetColor default 0;
    property BorderColor: TColor32 read FBorderColor write SetBorderColor default 0;
    property BorderWidth: Integer read FBorderWidth write SetBorderWidth default 0;
    property Radius: Integer read FRadius write SetRadius default 0;
  end;

  TColumn = class(TBox);

  TRow = class(TBox)
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
    procedure SetText(const AValue: string);
    procedure SetIcon(const AValue: string);
    function IconSize: Integer;
    procedure SetStyle(AValue: TButtonStyle);
    procedure SetAction(AValue: TBasicAction);
    function GetText: string;
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

  { Text editing for TEdit and TMemo: caret, selection with mouse and
    keyboard, clipboard, undo/redo, scrolling; TMemo adds lines and wrapping. }
  TCustomEdit = class(TControl)
  private
    FText, FPlaceholder: string;
    FCaret, FAnchor: Integer;     { byte positions (1-based); the selection is between them }
    FScrollX, FScrollY: Integer;
    FDesiredX: Integer;
    FSelecting, FLastWasTyping, FScrollToCaret: Boolean;
    FUndo, FRedo: TEditStates;
    FVisual: array of TVisualLine;
    FVisualText: string;
    FVisualWidth: Integer;
    FLines: TStrings;
    FOnChange, FOnSubmit: TNotifyEvent;
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
  protected
    FMultiLine, FWordWrap, FReadOnly, FPassword: Boolean;
    FMaxLength: Integer;
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
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Font: TPastelFont;
    procedure SelectAll;
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    property CaretPos: Integer read FCaret;
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
    property Text;
    property Placeholder;
    property ReadOnly;
    property MaxLength;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default True;
    property OnChange;
  end;

  { A panel shown above the form: drop-down lists, menus, dialogs. }
  TPopup = class(TBox)
  private
    FModal, FClosed, FShown: Boolean;
    FModalResult: Integer;
    FAnchor: TRectI;
    FAnchored, FPlaceRight: Boolean;
    FSavedFocus, FActiveControl: TControl;
    FOnClose: TNotifyEvent;
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
    function ShowModal(Form: TForm): Integer;
    procedure Close(AModalResult: Integer = 0);
    property Modal: Boolean read FModal write FModal;
    property Closed: Boolean read FClosed;
    property Shown: Boolean read FShown;
    property ModalResult: Integer read FModalResult write FModalResult;
    { Gets the focus when a modal popup opens; the first focusable control when nil. }
    property ActiveControl: TControl read FActiveControl write FActiveControl;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
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
    procedure HandleMouseWheel(DX, DY: Integer);
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
    function ShowModal: Integer;
    { Setting it in a dialog form closes the dialog with that result. }
    property ModalResult: Integer read GetModalResult write SetModalResult;
    { Called by the platform layer when the user changed the window state. }
    procedure WindowStateChanged(AState: TWindowState);
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
    { Set CanClose to False to keep the window open, e.g. to ask about unsaved work. }
    property OnCloseQuery: TCloseQueryEvent read FOnCloseQuery write FOnCloseQuery;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property OnResize: TNotifyEvent read FOnResize write FOnResize;
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
  end;

var
  Theme: TTheme;
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
  { The main window's form; dialogs are shown on it. Set by Pastel.App. }
  MainForm: TForm = nil;
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
{ Runs the timers that are due; the milliseconds until the next one (-1: none). }
function ProcessTimers(NowMs: QWord): Integer;
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

implementation

uses
  Math, Pastel.Icons;

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
        Theme.AccentHover := Mix(C, Shade, 0.12);
        Theme.AccentPressed := Mix(C, Shade, 0.22);
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

function ProcessTimers(NowMs: QWord): Integer;
var
  I: Integer;
  T: TTimer;
  Due: TFPList;
begin
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

{ ---- TControl ---- }

constructor TControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChildren := TFPList.Create;
  FVisible := True;
  FEnabled := True;
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

procedure TBox.Measure(AvailWidth: Integer; out W, H: Integer);
var
  I, CW, CH, N, Inner: Integer;
  Child: TControl;
begin
  W := 0;
  H := 0;
  N := 0;
  Inner := Max(0, AvailWidth - 2 * FPadding);
  for I := 0 to ChildCount - 1 do
  begin
    Child := Children[I];
    if not Child.Visible then
      Continue;
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
  Inner := RectI(R.X + FPadding, R.Y + FPadding,
    Max(0, R.W - 2 * FPadding), Max(0, R.H - 2 * FPadding));
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

procedure TBox.Paint(C: TCanvas32);
var
  Col, Bor: TColor32;
begin
  Col := PaintColor;
  Bor := PaintBorderColor;
  if (Cardinal(Col) shr 24) > 0 then
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, FRadius, Col);
  if (FBorderWidth > 0) and ((Cardinal(Bor) shr 24) > 0) then
    C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, FRadius, FBorderWidth, Bor);
  { a little extra room so children's focus rings are not cut off }
  C.PushClip(RectI(Bounds.X - 4, Bounds.Y - 4, Bounds.W + 8, Bounds.H + 8));
  PaintChildren(C);
  C.PopClip;
end;

constructor TRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRow := True;
  FAlign := aiCenter;
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
begin
  Result := GetFont(FFontSize, FBold);
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

procedure TButton.Measure(AvailWidth: Integer; out W, H: Integer);
var
  F: TPastelFont;
begin
  F := GetFont(Theme.FontSize, True);
  W := F.TextWidth(GetText);
  if HasIcon(FIcon) then
  begin
    if GetText <> '' then
      Inc(W, 6);
    Inc(W, IconSize);
  end;
  if FStyle = bsFlat then
  begin
    if GetText = '' then
      Inc(W, 12)          { an icon alone: nearly square }
    else
      Inc(W, 20);
    H := Max(F.LineHeight, IconSize) + 12;
    Exit;
  end;
  if GetText = '' then
    Inc(W, 20)
  else
    Inc(W, 36);
  H := Max(F.LineHeight, IconSize) + 20;
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
  Bg, Fg: TColor32;
  IW, IS_, X: Integer;
  S: string;
begin
  F := GetFont(Theme.FontSize, True);
  S := GetText;
  case FStyle of
    bsSecondary:
      begin
        if IsPressed then Bg := Theme.SecondaryPressed
        else if IsHovered then Bg := Theme.SecondaryHover
        else Bg := Theme.Secondary;
        Fg := Theme.Text;
      end;
    bsFlat:
      begin
        if IsPressed then Bg := Theme.SecondaryPressed
        else if IsHovered then Bg := Theme.SecondaryHover
        else Bg := 0;
        Fg := Theme.Text;
      end;
    bsDanger:
      begin
        if IsPressed then Bg := Theme.DangerPressed
        else if IsHovered then Bg := Theme.DangerHover
        else Bg := Theme.Danger;
        Fg := Theme.OnAccent;
      end;
  else
    if IsPressed then Bg := Theme.AccentPressed
    else if IsHovered then Bg := Theme.AccentHover
    else Bg := Theme.Accent;
    Fg := Theme.OnAccent;
  end;
  if not IsEnabled then
  begin
    if FStyle <> bsFlat then
      Bg := Theme.Secondary;
    Fg := Theme.Disabled;
  end;
  if IsFocused and ParentForm.FocusVisible then
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6,
      Theme.Radius + 3, Theme.FocusRing);
  if (Bg = 0) and IsFocused and ParentForm.FocusVisible then
    Bg := Theme.Secondary;
  if Bg <> 0 then
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Bg);
  C.PushClip(Bounds);
  IW := 0;
  if HasIcon(FIcon) then
  begin
    IS_ := IconSize;
    IW := IS_;
    if S <> '' then
      Inc(IW, 6);
  end;
  X := Bounds.X + (Bounds.W - IW - F.TextWidth(S)) div 2;
  if IW > 0 then
    DrawIcon(C, FIcon, X, Bounds.Y + (Bounds.H - IS_) div 2, IS_, Fg);
  C.DrawText(F, X + IW, Bounds.Y + (Bounds.H - F.LineHeight) div 2, S, Fg);
  C.PopClip;
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
      P.Close(FModalResult);
  end;
end;

{ ---- TPopup ---- }

constructor TPopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRadius := 10;
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

procedure TPopup.Close(AModalResult: Integer);
var
  F: TForm;
begin
  if FClosed then
    Exit;
  if AModalResult <> mrNone then
    FModalResult := AModalResult;
  F := FPopupForm;
  if F <> nil then
    F.ClosePopup(Self);
  if Assigned(FOnClose) then
    FOnClose(Self);
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

destructor TForm.Destroy;
var
  I: Integer;
begin
  for I := FPopups.Count - 1 downto 0 do
  begin
    TPopup(FPopups[I]).FPopupForm := nil;
    TPopup(FPopups[I]).FClosed := True;
  end;
  FreeAndNil(FPopups);
  FreeAndNil(FTooltip);
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

procedure TForm.HandleContextMenu(X, Y: Integer);
var
  C: TControl;
begin
  C := HitTest(X, Y);
  while C <> nil do
  begin
    if C.FPopupMenu <> nil then
    begin
      if Assigned(PopupMenuHook) then
        PopupMenuHook(C.FPopupMenu, Self, X, Y);
      Exit;
    end;
    C := C.Parent;
  end;
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
  public
    TitleLabel: TLabel;
  end;

function TForm.ShowModal: Integer;
var
  Host: TFormHost;
  Header: TRow;
begin
  if (MainForm = nil) or (MainForm = Self) then
    raise Exception.Create('ShowModal shows a form above the main window: create the main form first');
  Host := TFormHost.Create(nil);
  try
    Host.Padding := 0;
    Host.Gap := 0;
    Header := TRow.Create(Host);
    Header.Padding := 16;
    Header.Parent := Host;
    Host.TitleLabel := TLabel.Create(Host);
    Host.TitleLabel.Bold := True;
    Host.TitleLabel.FontSize := 16;
    Host.TitleLabel.Text := FTitle;
    Host.TitleLabel.Parent := Header;
    Header.Visible := FTitle <> '';
    Parent := Host;
    FFocused := nil;
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
  P := ParentPopup;
  if (P <> nil) and (AValue <> mrNone) then
    P.Close(AValue);
end;

procedure TForm.Close;
var
  P: TPopup;
begin
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
  PaintChildren(C);
  for I := 0 to FPopups.Count - 1 do
  begin
    P := TPopup(FPopups[I]);
    if P.FModal then
      C.FillRect(0, 0, FWidthPx, FHeightPx, Theme.Backdrop);
    P.Paint(C);
  end;
  if (FTooltipFor <> nil) and (FTooltip <> nil) then
    FTooltip.Paint(C);
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
  I: Integer;
begin
  if not C.Visible then
    Exit;
  if C.Focusable then
    List.Add(C);
  for I := 0 to C.ChildCount - 1 do
    CollectFocusable(C.Children[I], List);
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
  if FCaptured <> nil then
    FCaptured.MouseMove(X, Y)
  else if Hit <> nil then
    Hit.MouseMove(X, Y);
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
    FocusNext(Shift);
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
  RegisterControl(TColumn);
  RegisterControl(TRow);
  RegisterControl(TCard);
  RegisterControl(TSpacer);
  RegisterControl(TLabel);
  RegisterControl(TButton);
  RegisterControl(TEdit);
  RegisterControl(TMemo);

finalization
  ControlClasses.Free;
  NonVisualClasses.Free;
  FreeAndNil(Timers);

end.
