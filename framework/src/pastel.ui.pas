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
  TButtonStyle = (bsPrimary, bsSecondary, bsDanger);
  TCursorKind = (ckArrow, ckIBeam, ckHand);

  TForm = class;

  TControl = class(TComponent)
  private
    FParent: TControl;
    FChildren: TFPList;
    FWidth, FHeight, FGrow: Integer;
    FVisible, FEnabled: Boolean;
    FBounds: TRectI;
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
    function Cursor: TCursorKind; virtual;
    procedure MouseDown(X, Y: Integer); virtual;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); virtual;
    procedure MouseMove(X, Y: Integer); virtual;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; virtual;
    procedure TextInput(const S: string); virtual;
    function IsHovered: Boolean;
    function IsPressed: Boolean;
    function IsFocused: Boolean;
    procedure Changed;          { needs layout and repaint }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate;       { needs repaint only }
    procedure SetFocus;
    function HitTest(X, Y: Integer): TControl;
    function ParentForm: TForm;
    { Preferred size including explicit Width/Height. }
    procedure GetSize(AvailWidth: Integer; out W, H: Integer);
    property Parent: TControl read FParent write SetParent;
    property Children[Index: Integer]: TControl read GetChild;
    property ChildCount: Integer read GetChildCount;
    property Bounds: TRectI read FBounds;
  published
    property Width: Integer read FWidth write SetWidth default 0;
    property Height: Integer read FHeight write SetHeight default 0;
    property Grow: Integer read FGrow write SetGrow default 0;
    property Visible: Boolean read FVisible write SetVisible default True;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
  end;

  TControlClass = class of TControl;

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

  { A white rounded panel with a border. }
  TCard = class(TBox)
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
    procedure SetText(const AValue: string);
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
  published
    property Text: string read FText write SetText;
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
    procedure SetText(const AValue: string);
    procedure SetStyle(AValue: TButtonStyle);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  public
    procedure Click; virtual;
  published
    property Text: string read FText write SetText;
    property Style: TButtonStyle read FStyle write SetStyle default bsPrimary;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  TEdit = class(TControl)
  private
    FText, FPlaceholder: string;
    FCaret: Integer;          { byte index in FText where the caret is (1-based) }
    FScroll: Integer;         { horizontal scroll in pixels }
    FOnChange, FOnSubmit: TNotifyEvent;
    procedure SetText(const AValue: string);
    procedure SetPlaceholder(const AValue: string);
    procedure InsertText(const S: string);
    procedure DoChange;
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
    function Font: TPastelFont;
    property CaretPos: Integer read FCaret;
  published
    property Text: string read FText write SetText;
    property Placeholder: string read FPlaceholder write SetPlaceholder;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSubmit: TNotifyEvent read FOnSubmit write FOnSubmit;
  end;

  { The root of a window. Owns all controls created from its .pform file. }
  TForm = class(TBox)
  private
    FTitle: string;
    FFocused, FHover, FCaptured: TControl;
    FFocusVisible: Boolean;
    FOnCreate: TNotifyEvent;
    procedure SetTitle(const AValue: string);
    procedure CollectFocusable(C: TControl; List: TFPList);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Removes every control created from the .pform (used by hot reload). }
    procedure ClearControls;
    procedure Layout(AWidth, AHeight: Integer);
    procedure Render(C: TCanvas32);
    procedure FocusControl(C: TControl);
    procedure FocusNext(Backward: Boolean);
    procedure HandleMouseMove(X, Y: Integer);
    procedure HandleMouseDown(X, Y: Integer);
    procedure HandleMouseUp(X, Y: Integer);
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
    property Focused: TControl read FFocused;
    property Hovered: TControl read FHover;
    { True when focus came from the keyboard (Tab): buttons show a focus ring. }
    property FocusVisible: Boolean read FFocusVisible;
  published
    property Title: string read FTitle write SetTitle;
    property OnCreate: TNotifyEvent read FOnCreate write FOnCreate;
  end;

  TFormClass = class of TForm;

  TTheme = record
    Background, Surface, Text, TextMuted, Placeholder: TColor32;
    Accent, AccentHover, AccentPressed, OnAccent: TColor32;
    Secondary, SecondaryHover, SecondaryPressed: TColor32;
    Danger, DangerHover, DangerPressed: TColor32;
    Border, BorderHover, FocusRing, Disabled: TColor32;
    Radius, FontSize: Integer;
  end;

var
  Theme: TTheme;
  { Set by controls when something changed; the application loop reads them. }
  NeedsLayout: Boolean = True;
  NeedsRepaint: Boolean = True;
  { Caret blink phase, toggled by the application loop. }
  CaretVisible: Boolean = True;
  { Clipboard access, provided by the platform layer. }
  ClipboardGetText: function: string = nil;
  ClipboardSetText: procedure(const S: string) = nil;

const
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

procedure RegisterControl(AClass: TControlClass);
function FindControlClass(const AName: string): TControlClass;
function ControlClassCount: Integer;
function ControlClassAt(Index: Integer): TControlClass;

implementation

uses
  Math;

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

function ControlClassCount: Integer;
begin
  Result := ControlClasses.Count;
end;

function ControlClassAt(Index: Integer): TControlClass;
begin
  Result := TControlClass(ControlClasses.Objects[Index]);
end;

procedure DefaultTheme;
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
  Theme.Radius := 8;
  Theme.FontSize := 14;
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
  NeedsRepaint := True;
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
    Result := nil;
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
      if (FAlign = aiStretch) and
         ((FRow and (Child.Height = 0)) or (not FRow and (Child.Width = 0))) then
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

procedure TBox.Paint(C: TCanvas32);
begin
  if (Cardinal(FColor) shr 24) > 0 then
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, FRadius, FColor);
  if (FBorderWidth > 0) and ((Cardinal(FBorderColor) shr 24) > 0) then
    C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, FRadius, FBorderWidth, FBorderColor);
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
  FColor := Theme.Surface;
  FBorderColor := Theme.Border;
  FBorderWidth := 1;
  FRadius := 12;
  FPadding := 20;
  FGap := 12;
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

procedure TLabel.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := Font.TextWidth(FText);
  H := Font.LineHeight;
end;

procedure TLabel.Paint(C: TCanvas32);
var
  F: TPastelFont;
  X, TW: Integer;
  Col: TColor32;
begin
  F := Font;
  TW := F.TextWidth(FText);
  case FTextAlign of
    taCenter: X := Bounds.X + (Bounds.W - TW) div 2;
    taRight: X := Bounds.X + Bounds.W - TW;
  else
    X := Bounds.X;
  end;
  Col := FColor;
  if Col = 0 then
    Col := Theme.Text;
  if not Enabled then
    Col := Theme.Disabled;
  C.PushClip(Bounds);
  C.DrawText(F, X, Bounds.Y + (Bounds.H - F.LineHeight) div 2, FText, Col);
  C.PopClip;
end;

{ ---- TButton ---- }

procedure TButton.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
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
  W := F.TextWidth(FText) + 36;
  H := F.LineHeight + 20;
end;

procedure TButton.Paint(C: TCanvas32);
var
  F: TPastelFont;
  Bg, Fg: TColor32;
begin
  F := GetFont(Theme.FontSize, True);
  case FStyle of
    bsSecondary:
      begin
        if IsPressed then Bg := Theme.SecondaryPressed
        else if IsHovered then Bg := Theme.SecondaryHover
        else Bg := Theme.Secondary;
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
  if not Enabled then
  begin
    Bg := Theme.Secondary;
    Fg := Theme.Disabled;
  end;
  if IsFocused and ParentForm.FocusVisible then
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6,
      Theme.Radius + 3, Theme.FocusRing);
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Bg);
  C.PushClip(Bounds);
  C.DrawText(F, Bounds.X + (Bounds.W - F.TextWidth(FText)) div 2,
    Bounds.Y + (Bounds.H - F.LineHeight) div 2, FText, Fg);
  C.PopClip;
end;

function TButton.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TButton.Cursor: TCursorKind;
begin
  if Enabled then Result := ckHand else Result := ckArrow;
end;

procedure TButton.MouseDown(X, Y: Integer);
begin
  Invalidate;
end;

procedure TButton.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  Invalidate;
  if Inside and Enabled then
    Click;
end;

function TButton.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := (Key = KEY_ENTER) or (Key = KEY_KP_ENTER) or (Key = KEY_SPACE);
  if Result and Enabled then
    Click;
end;

procedure TButton.Click;
begin
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

{ ---- TEdit ---- }

const
  EditPadding = 12;

constructor TEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaret := 1;
end;

function TEdit.Font: TPastelFont;
begin
  Result := GetFont(Theme.FontSize, False);
end;

procedure TEdit.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  FCaret := Length(FText) + 1;
  Changed;
  DoChange;
end;

procedure TEdit.SetPlaceholder(const AValue: string);
begin
  FPlaceholder := AValue;
  Invalidate;
end;

procedure TEdit.DoChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TEdit.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 200;
  H := Font.LineHeight + 20;
end;

procedure TEdit.Paint(C: TCanvas32);
var
  F: TPastelFont;
  TextX, TextY, CaretX, InnerW: Integer;
  Border: TColor32;
begin
  F := Font;
  InnerW := Bounds.W - 2 * EditPadding;
  { keep the caret visible }
  CaretX := F.TextWidth(Copy(FText, 1, FCaret - 1));
  if CaretX - FScroll > InnerW then
    FScroll := CaretX - InnerW;
  if CaretX - FScroll < 0 then
    FScroll := CaretX;
  if F.TextWidth(FText) - FScroll < InnerW then
    FScroll := Math.Max(0, F.TextWidth(FText) - InnerW);

  if IsFocused then
  begin
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6,
      Theme.Radius + 3, Theme.FocusRing);
    Border := Theme.Accent;
  end
  else if IsHovered then
    Border := Theme.BorderHover
  else
    Border := Theme.Border;
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);
  C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Border);

  TextX := Bounds.X + EditPadding - FScroll;
  TextY := Bounds.Y + (Bounds.H - F.LineHeight) div 2;
  C.PushClip(RectI(Bounds.X + EditPadding - 1, Bounds.Y + 1, InnerW + 2, Bounds.H - 2));
  if FText = '' then
    C.DrawText(F, Bounds.X + EditPadding, TextY, FPlaceholder, Theme.Placeholder)
  else
    C.DrawText(F, TextX, TextY, FText, Theme.Text);
  if IsFocused and CaretVisible then
    C.FillRect(TextX + CaretX, TextY, 1, F.LineHeight, Theme.Text);
  C.PopClip;
end;

function TEdit.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TEdit.Cursor: TCursorKind;
begin
  Result := ckIBeam;
end;

procedure TEdit.MouseDown(X, Y: Integer);
begin
  FCaret := Font.HitTest(FText, X - Bounds.X - EditPadding + FScroll);
  CaretVisible := True;
  Invalidate;
end;

procedure TEdit.InsertText(const S: string);
var
  Clean: string;
  I: Integer;
begin
  Clean := '';
  for I := 1 to Length(S) do
    if S[I] >= ' ' then
      Clean := Clean + S[I];
  if Clean = '' then
    Exit;
  Insert(Clean, FText, FCaret);
  Inc(FCaret, Length(Clean));
  CaretVisible := True;
  Invalidate;
  DoChange;
end;

procedure TEdit.TextInput(const S: string);
begin
  InsertText(S);
end;

function TEdit.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  P: Integer;
begin
  Result := True;
  CaretVisible := True;
  case Key of
    KEY_LEFT:
      if FCaret > 1 then
        FCaret := PrevCharStart(FText, FCaret);
    KEY_RIGHT:
      if FCaret <= Length(FText) then
      begin
        P := FCaret;
        NextCodePoint(FText, P);
        FCaret := P;
      end;
    KEY_HOME: FCaret := 1;
    KEY_END: FCaret := Length(FText) + 1;
    KEY_BACKSPACE:
      if FCaret > 1 then
      begin
        P := PrevCharStart(FText, FCaret);
        Delete(FText, P, FCaret - P);
        FCaret := P;
        DoChange;
      end;
    KEY_DELETE:
      if FCaret <= Length(FText) then
      begin
        P := FCaret;
        NextCodePoint(FText, P);
        Delete(FText, FCaret, P - FCaret);
        DoChange;
      end;
    KEY_ENTER, KEY_KP_ENTER:
      if Assigned(FOnSubmit) then
        FOnSubmit(Self);
  else
    Result := False;
    if Ctrl and (Key = Ord('v')) and Assigned(ClipboardGetText) then
    begin
      InsertText(ClipboardGetText());
      Result := True;
    end
    else if Ctrl and (Key = Ord('c')) and Assigned(ClipboardSetText) then
    begin
      ClipboardSetText(FText);
      Result := True;
    end;
  end;
  Invalidate;
end;

{ ---- TForm ---- }

constructor TForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColor := Theme.Background;
  FPadding := 24;
  FGap := 12;
  FTitle := 'Pastel';
end;

procedure TForm.SetTitle(const AValue: string);
begin
  FTitle := AValue;
  Invalidate;
end;

procedure TForm.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FFocused then FFocused := nil;
    if AComponent = FHover then FHover := nil;
    if AComponent = FCaptured then FCaptured := nil;
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
begin
  Arrange(RectI(0, 0, AWidth, AHeight));
  NeedsLayout := False;
  NeedsRepaint := True;
end;

procedure TForm.Render(C: TCanvas32);
begin
  C.Clear(FColor);
  PaintChildren(C);
  NeedsRepaint := False;
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

procedure TForm.FocusControl(C: TControl);
begin
  if (C <> nil) and not C.Focusable then
    C := nil;
  if FFocused = C then
    Exit;
  FFocused := C;
  CaretVisible := True;
  NeedsRepaint := True;
end;

procedure TForm.FocusNext(Backward: Boolean);
var
  List: TFPList;
  I: Integer;
begin
  List := TFPList.Create;
  try
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
  Hit := HitTest(X, Y);
  if Hit <> FHover then
  begin
    FHover := Hit;
    NeedsRepaint := True;
  end;
  if FCaptured <> nil then
    FCaptured.MouseMove(X, Y)
  else if Hit <> nil then
    Hit.MouseMove(X, Y);
end;

procedure TForm.HandleMouseDown(X, Y: Integer);
var
  Hit, Target: TControl;
begin
  Hit := HitTest(X, Y);
  FHover := Hit;
  Target := Hit;
  while (Target <> nil) and not Target.Focusable do
    Target := Target.Parent;
  FocusControl(Target);
  FFocusVisible := False;
  FCaptured := Hit;
  if (Hit <> nil) and Hit.Enabled then
    Hit.MouseDown(X, Y);
  NeedsRepaint := True;
end;

procedure TForm.HandleMouseUp(X, Y: Integer);
var
  C: TControl;
begin
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

procedure TForm.HandleKeyDown(Key: LongInt; Shift, Ctrl: Boolean);
begin
  if (FFocused <> nil) and FFocused.KeyDown(Key, Shift, Ctrl) then
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
  DefaultTheme;
  RegisterControl(TColumn);
  RegisterControl(TRow);
  RegisterControl(TCard);
  RegisterControl(TSpacer);
  RegisterControl(TLabel);
  RegisterControl(TButton);
  RegisterControl(TEdit);

finalization
  ControlClasses.Free;

end.
