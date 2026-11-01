{ Pastel - more standard controls, like the "Additional" page of Delphi's palette:

    TGroupBox    a frame with a title around controls that belong together
    TRadioGroup  a framed list of choices: one of them is chosen (ItemIndex)
    TShape       a rectangle, rounded rectangle, ellipse or circle
    TBevel       a line or a frame that divides a form
    TPaintBox    a place to draw on yourself (OnPaint)

  Part of the Pastel project, MIT License. }
unit Pastel.Additional;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  { A frame with a title (Text) around controls that belong together. Its
    controls are placed freely (Left, Top) like in Delphi; Layout = Flow stacks them. }
  TGroupBox = class(TBox)
  private
    FText: string;
    procedure SetText(const AValue: string);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Height of the title row; free-placed controls start below it (Top >= TitleHeight). }
    function TitleHeight: Integer;
  published
    property Text: string read FText write SetText;
    property Layout default lkFree;
  end;

  { A framed list of choices; one is chosen at a time. Items = ('Cash', 'Card');
    ItemIndex is the chosen one (-1: none). Arrow keys move the choice. }
  TRadioGroup = class(TControl)
  private
    FText: string;
    FItems: TStringList;
    FItemIndex, FColumns, FHot: Integer;
    FOnChange: TNotifyEvent;
    procedure SetText(const AValue: string);
    function GetItems: TStrings;
    procedure SetItems(AValue: TStrings);
    procedure SetItemIndex(AValue: Integer);
    procedure SetColumns(AValue: Integer);
    procedure ItemsChanged(Sender: TObject);
    function ItemAt(X, Y: Integer): Integer;
    function GetValue: string;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The place of item Index (for tests and custom drawing). }
    function ItemRect(Index: Integer): TRectI;
    { The text of the chosen item, '' when none is chosen. }
    property Value: string read GetValue;
  published
    property Text: string read FText write SetText;
    property Items: TStrings read GetItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    { The items fill the columns from top to bottom. }
    property Columns: Integer read FColumns write SetColumns default 1;
    { The user chose another item. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TShapeKind = (skRectangle, skRoundRect, skEllipse, skCircle);

  { A rectangle, rounded rectangle, ellipse or circle. Color fills it (default: the
    theme's surface), BorderColor and BorderWidth outline it. }
  TShape = class(TControl)
  private
    FShape: TShapeKind;
    FColor, FBorderColor: TColor32;
    FBorderWidth, FRadius: Integer;
    procedure SetShape(AValue: TShapeKind);
    procedure SetColor(AValue: TColor32);
    procedure SetBorderColor(AValue: TColor32);
    procedure SetBorderWidth(AValue: Integer);
    procedure SetRadius(AValue: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Shape: TShapeKind read FShape write SetShape default skRectangle;
    property Color: TColor32 read FColor write SetColor default 0;
    property BorderColor: TColor32 read FBorderColor write SetBorderColor default 0;
    property BorderWidth: Integer read FBorderWidth write SetBorderWidth default 1;
    { The corners of a RoundRect. }
    property Radius: Integer read FRadius write SetRadius default 8;
  end;

  TBevelKind = (bkHorizontal, bkVertical, bkFrame);

  { A thin line across (Horizontal), down (Vertical) or a frame around its place. }
  TBevel = class(TControl)
  private
    FKind: TBevelKind;
    FColor: TColor32;
    procedure SetKind(AValue: TBevelKind);
    procedure SetColor(AValue: TColor32);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  published
    property Kind: TBevelKind read FKind write SetKind default bkHorizontal;
    { The line's color; 0: the theme's border color. }
    property Color: TColor32 read FColor write SetColor default 0;
  end;

  TPaintEvent = procedure(Sender: TObject; Canvas: TCanvas32) of object;
  TPaintMouseEvent = procedure(Sender: TObject; X, Y: Integer) of object;

  { A place to draw on yourself: OnPaint gets the canvas, clipped to the box;
    Bounds tells where the box is. Invalidate draws it again. The mouse events
    give X, Y inside the box. Without OnPaint a thin frame shows where it is. }
  TPaintBox = class(TControl)
  private
    FColor: TColor32;
    FOnPaint: TPaintEvent;
    FOnMouseDown, FOnMouseMove, FOnMouseUp: TPaintMouseEvent;
    FOnClick: TNotifyEvent;
    procedure SetColor(AValue: TColor32);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
  published
    { The background; 0: none. }
    property Color: TColor32 read FColor write SetColor default 0;
    property OnPaint: TPaintEvent read FOnPaint write FOnPaint;
    property OnMouseDown: TPaintMouseEvent read FOnMouseDown write FOnMouseDown;
    property OnMouseMove: TPaintMouseEvent read FOnMouseMove write FOnMouseMove;
    property OnMouseUp: TPaintMouseEvent read FOnMouseUp write FOnMouseUp;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

implementation

uses
  Math;

const
  RowH = 28;
  MarkSize = 18;

{ the frame of a group: a line around R with a gap for the title }
procedure PaintGroupFrame(C: TCanvas32; const R: TRectI; const Title: string; Enabled: Boolean);
var
  F: TPastelFont;
  Top, TW: Integer;
  Line, Col: TColor32;
begin
  F := GetFont(Theme.FontSize, True);
  Top := R.Y + F.LineHeight div 2;
  Line := Theme.Border;
  TW := 0;
  if Title <> '' then
    TW := F.TextWidth(Title) + 8;
  C.DrawLine(R.X + 0.5, Top + 0.5, R.X + 0.5, R.Y + R.H - 0.5, 1, Line);
  C.DrawLine(R.X + R.W - 0.5, Top + 0.5, R.X + R.W - 0.5, R.Y + R.H - 0.5, 1, Line);
  C.DrawLine(R.X + 0.5, R.Y + R.H - 0.5, R.X + R.W - 0.5, R.Y + R.H - 0.5, 1, Line);
  C.DrawLine(R.X + 0.5, Top + 0.5, R.X + 8, Top + 0.5, 1, Line);
  C.DrawLine(Min(R.X + R.W, R.X + 12 + TW), Top + 0.5, R.X + R.W - 0.5, Top + 0.5, 1, Line);
  if Title <> '' then
  begin
    if Enabled then Col := Theme.Text else Col := Theme.Disabled;
    C.PushClip(R);
    C.DrawText(F, R.X + 14, R.Y, Title, Col);
    C.PopClip;
  end;
end;

function TitleRowHeight: Integer;
begin
  Result := GetFont(Theme.FontSize, True).LineHeight + 6;
end;

{ ---- TGroupBox ---- }

constructor TGroupBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Layout := lkFree;
end;

function TGroupBox.TitleHeight: Integer;
begin
  Result := TitleRowHeight;
end;

procedure TGroupBox.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
end;

procedure TGroupBox.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  inherited Measure(AvailWidth, W, H);
  if Layout = lkFlow then
    Inc(H, TitleHeight);
  W := Max(W, 120);
  H := Max(H, TitleHeight + 24);
end;

procedure TGroupBox.Arrange(const R: TRectI);
begin
  if Layout = lkFlow then
  begin
    { the stacked controls start below the title }
    inherited Arrange(RectI(R.X, R.Y + TitleHeight, R.W, Max(0, R.H - TitleHeight)));
    SetBoundsOnly(R);
  end
  else
    inherited Arrange(R);
end;

procedure TGroupBox.Paint(C: TCanvas32);
begin
  if (Cardinal(Color) shr 24) > 0 then
    C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Color);
  PaintGroupFrame(C, Bounds, FText, Enabled);
  C.PushClip(RectI(Bounds.X - 4, Bounds.Y - 4, Bounds.W + 8, Bounds.H + 8));
  PaintChildren(C);
  C.PopClip;
end;

{ ---- TRadioGroup ---- }

constructor TRadioGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FColumns := 1;
  FHot := -1;
end;

destructor TRadioGroup.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TRadioGroup.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
end;

function TRadioGroup.GetItems: TStrings;
begin
  Result := FItems;
end;

procedure TRadioGroup.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);
end;

procedure TRadioGroup.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := -1;
  Changed;
end;

procedure TRadioGroup.SetItemIndex(AValue: Integer);
begin
  if (AValue < -1) or (AValue >= FItems.Count) then
    AValue := -1;
  if FItemIndex = AValue then Exit;
  FItemIndex := AValue;
  Invalidate;
end;

procedure TRadioGroup.SetColumns(AValue: Integer);
begin
  AValue := Max(1, AValue);
  if FColumns = AValue then Exit;
  FColumns := AValue;
  Changed;
end;

function TRadioGroup.GetValue: string;
begin
  if FItemIndex >= 0 then
    Result := FItems[FItemIndex]
  else
    Result := '';
end;

procedure TRadioGroup.Measure(AvailWidth: Integer; out W, H: Integer);
var
  F: TPastelFont;
  I, ColW, Rows: Integer;
begin
  F := GetFont(Theme.FontSize);
  ColW := 60;
  for I := 0 to FItems.Count - 1 do
    ColW := Max(ColW, MarkSize + 8 + F.TextWidth(FItems[I]) + 16);
  Rows := Max(1, (FItems.Count + FColumns - 1) div FColumns);
  W := Max(24 + FColumns * ColW, GetFont(Theme.FontSize, True).TextWidth(FText) + 40);
  H := TitleRowHeight + 4 + Rows * RowH + 8;
end;

function TRadioGroup.ItemRect(Index: Integer): TRectI;
var
  Rows, ColW, Col, Row: Integer;
begin
  Rows := Max(1, (FItems.Count + FColumns - 1) div FColumns);
  ColW := Max(1, (Bounds.W - 24) div FColumns);
  Col := Index div Rows;
  Row := Index mod Rows;
  Result := RectI(Bounds.X + 12 + Col * ColW, Bounds.Y + TitleRowHeight + 4 + Row * RowH, ColW, RowH);
end;

function TRadioGroup.ItemAt(X, Y: Integer): Integer;
var
  I: Integer;
  R: TRectI;
begin
  for I := 0 to FItems.Count - 1 do
  begin
    R := ItemRect(I);
    if (X >= R.X) and (X < R.X + R.W) and (Y >= R.Y) and (Y < R.Y + R.H) then
      Exit(I);
  end;
  Result := -1;
end;

procedure TRadioGroup.Paint(C: TCanvas32);
var
  F: TPastelFont;
  I, MX, MY: Integer;
  R: TRectI;
  Col: TColor32;
  Form: TForm;
begin
  PaintGroupFrame(C, Bounds, FText, Enabled);
  F := GetFont(Theme.FontSize);
  Form := ParentForm;
  C.PushClip(Bounds);
  for I := 0 to FItems.Count - 1 do
  begin
    R := ItemRect(I);
    MX := R.X;
    MY := R.Y + (R.H - MarkSize) div 2;
    if (I = Max(FItemIndex, 0)) and (Form <> nil) and (Form.Focused = Self) and Form.FocusVisible then
      C.FillRoundRect(MX - 3, MY - 3, MarkSize + 6, MarkSize + 6, MarkSize div 2 + 3, Theme.FocusRing);
    if I = FItemIndex then
    begin
      if Enabled then Col := Theme.Accent else Col := Theme.Disabled;
      C.FillCircle(MX + 9, MY + 9, 9, Col);
      C.FillCircle(MX + 9, MY + 9, 3.6, Theme.OnAccent);
    end
    else
    begin
      if (I = FHot) and IsHovered and Enabled then Col := Theme.BorderHover else Col := Theme.Border;
      C.FillCircle(MX + 9, MY + 9, 9, Col);
      C.FillCircle(MX + 9, MY + 9, 7.5, Theme.Surface);
    end;
    if Enabled then Col := Theme.Text else Col := Theme.Disabled;
    C.DrawText(F, MX + MarkSize + 8, R.Y + (R.H - F.LineHeight) div 2, FItems[I], Col);
  end;
  C.PopClip;
end;

function TRadioGroup.Focusable: Boolean;
begin
  Result := Enabled and (FItems.Count > 0);
end;

function TRadioGroup.Cursor: TCursorKind;
begin
  if Enabled and (FHot >= 0) then Result := ckHand else Result := ckArrow;
end;

procedure TRadioGroup.MouseMove(X, Y: Integer);
var
  I: Integer;
begin
  I := ItemAt(X, Y);
  if I <> FHot then
  begin
    FHot := I;
    Invalidate;
  end;
end;

procedure TRadioGroup.MouseUp(X, Y: Integer; Inside: Boolean);
var
  I: Integer;
begin
  if not (Inside and Enabled) then Exit;
  I := ItemAt(X, Y);
  if (I >= 0) and (I <> FItemIndex) then
  begin
    ItemIndex := I;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
end;

function TRadioGroup.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  Step: Integer;
begin
  if (Key = KEY_UP) or (Key = KEY_LEFT) then
    Step := -1
  else if (Key = KEY_DOWN) or (Key = KEY_RIGHT) then
    Step := 1
  else
    Exit(False);
  Result := True;
  if FItems.Count = 0 then Exit;
  if FItemIndex < 0 then
    ItemIndex := 0
  else
    ItemIndex := EnsureRange(FItemIndex + Step, 0, FItems.Count - 1);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

{ ---- TShape ---- }

constructor TShape.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBorderWidth := 1;
  FRadius := 8;
end;

procedure TShape.SetShape(AValue: TShapeKind);
begin
  FShape := AValue;
  Invalidate;
end;

procedure TShape.SetColor(AValue: TColor32);
begin
  FColor := AValue;
  Invalidate;
end;

procedure TShape.SetBorderColor(AValue: TColor32);
begin
  FBorderColor := AValue;
  Invalidate;
end;

procedure TShape.SetBorderWidth(AValue: Integer);
begin
  FBorderWidth := Max(0, AValue);
  Invalidate;
end;

procedure TShape.SetRadius(AValue: Integer);
begin
  FRadius := Max(0, AValue);
  Invalidate;
end;

procedure TShape.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 64;
  H := 64;
end;

procedure TShape.Paint(C: TCanvas32);
var
  Fill, Line: TColor32;
  X, Y, W, H, I, Steps: Integer;
  CX, CY, RX, RY, DY, Half, A0, A1: Double;
begin
  Fill := FColor;
  if Fill = 0 then Fill := Theme.Surface;
  Line := FBorderColor;
  if Line = 0 then Line := Theme.Border;
  X := Bounds.X;
  Y := Bounds.Y;
  W := Bounds.W;
  H := Bounds.H;
  if FShape = skCircle then
  begin
    { the biggest circle in the middle }
    X := X + (W - Min(W, H)) div 2;
    Y := Y + (H - Min(W, H)) div 2;
    W := Min(W, H);
    H := W;
  end;
  if (W <= 0) or (H <= 0) then Exit;
  case FShape of
    skRectangle, skRoundRect:
      begin
        if FShape = skRectangle then I := 0 else I := FRadius;
        if (Cardinal(Fill) shr 24) > 0 then
          C.FillRoundRect(X, Y, W, H, I, Fill);
        if FBorderWidth > 0 then
          C.StrokeRoundRect(X, Y, W, H, I, FBorderWidth, Line);
      end;
  else
    CX := X + W / 2;
    CY := Y + H / 2;
    RX := W / 2;
    RY := H / 2;
    if W = H then
    begin
      C.FillCircle(CX, CY, RX, Line);
      if (Cardinal(Fill) shr 24) > 0 then
        C.FillCircle(CX, CY, Max(0, RX - FBorderWidth), Fill);
    end
    else
    begin
      { an ellipse: filled row by row, outlined by short lines }
      if (Cardinal(Fill) shr 24) > 0 then
        for I := 0 to H - 1 do
        begin
          DY := (Y + I + 0.5 - CY) / RY;
          if Abs(DY) >= 1 then Continue;
          Half := RX * Sqrt(1 - DY * DY);
          C.FillRect(Round(CX - Half), Y + I, Max(1, Round(2 * Half)), 1, Fill);
        end;
      if FBorderWidth > 0 then
      begin
        Steps := 72;
        for I := 0 to Steps - 1 do
        begin
          A0 := 2 * Pi * I / Steps;
          A1 := 2 * Pi * (I + 1) / Steps;
          C.DrawLine(CX + (RX - FBorderWidth / 2) * Cos(A0), CY + (RY - FBorderWidth / 2) * Sin(A0),
            CX + (RX - FBorderWidth / 2) * Cos(A1), CY + (RY - FBorderWidth / 2) * Sin(A1), FBorderWidth, Line);
        end;
      end;
    end;
  end;
end;

{ ---- TBevel ---- }

procedure TBevel.SetKind(AValue: TBevelKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  Changed;
end;

procedure TBevel.SetColor(AValue: TColor32);
begin
  FColor := AValue;
  Invalidate;
end;

procedure TBevel.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  case FKind of
    bkHorizontal:
      begin
        W := 100;
        H := 9;
      end;
    bkVertical:
      begin
        W := 9;
        H := 100;
      end;
  else
    W := 100;
    H := 60;
  end;
end;

procedure TBevel.Paint(C: TCanvas32);
var
  Col: TColor32;
begin
  Col := FColor;
  if Col = 0 then Col := Theme.Border;
  case FKind of
    bkHorizontal: C.FillRect(Bounds.X, Bounds.Y + Bounds.H div 2, Bounds.W, 1, Col);
    bkVertical: C.FillRect(Bounds.X + Bounds.W div 2, Bounds.Y, 1, Bounds.H, Col);
  else
    C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, 0, 1, Col);
  end;
end;

{ ---- TPaintBox ---- }

procedure TPaintBox.SetColor(AValue: TColor32);
begin
  FColor := AValue;
  Invalidate;
end;

procedure TPaintBox.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 100;
  H := 100;
end;

procedure TPaintBox.Paint(C: TCanvas32);
begin
  C.PushClip(Bounds);
  try
    if (Cardinal(FColor) shr 24) > 0 then
      C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, FColor);
    if Assigned(FOnPaint) then
      FOnPaint(Self, C)
    else
      C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, 0, 1, Theme.Border);
  finally
    C.PopClip;
  end;
end;

procedure TPaintBox.MouseDown(X, Y: Integer);
begin
  if Assigned(FOnMouseDown) then
    FOnMouseDown(Self, X - Bounds.X, Y - Bounds.Y);
end;

procedure TPaintBox.MouseMove(X, Y: Integer);
begin
  if Assigned(FOnMouseMove) then
    FOnMouseMove(Self, X - Bounds.X, Y - Bounds.Y);
end;

procedure TPaintBox.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  if Assigned(FOnMouseUp) then
    FOnMouseUp(Self, X - Bounds.X, Y - Bounds.Y);
  if Inside and Assigned(FOnClick) then
    FOnClick(Self);
end;

initialization
  RegisterControl(TGroupBox);
  RegisterControl(TRadioGroup);
  RegisterControl(TShape);
  RegisterControl(TBevel);
  RegisterControl(TPaintBox);

end.
