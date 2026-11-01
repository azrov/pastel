{ TStarRating - a row of stars to give a rating (1 to 5 stars).

    object Rating: TStarRating
      Value = 4
      OnChange = RatingChange
    end

  Click a star, or use the arrow keys when it has the focus. Moving the mouse
  over it shows what a click would give. An example of a control that draws
  itself: Measure (its size), Paint (drawing), MouseDown/KeyDown (input). }
unit StarRating;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  TStarRating = class(TControl)
  private
    FValue, FMax, FHover, FStarSize: Integer;
    FReadOnly: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetValue(AValue: Integer);
    procedure SetMax(AValue: Integer);
    procedure SetStarSize(AValue: Integer);
    function StarAt(X: Integer): Integer;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function Cursor: TCursorKind; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { The number of stars given, 0 to Max. }
    property Value: Integer read FValue write SetValue default 0;
    { How many stars there are. }
    property Max: Integer read FMax write SetMax default 5;
    { The size of one star in pixels. }
    property StarSize: Integer read FStarSize write SetStarSize default 28;
    { Only shows the rating; clicks and keys change nothing. }
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    { Value changed by the user (or by code). }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

const
  StarColor = $FFF59E0B;      { amber }

constructor TStarRating.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMax := 5;
  FStarSize := 28;
  FHover := -1;
end;

procedure TStarRating.SetValue(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > FMax then AValue := FMax;
  if FValue = AValue then
    Exit;
  FValue := AValue;
  Invalidate;                  { only the look changes: paint again }
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TStarRating.SetMax(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FMax := AValue;
  if FValue > FMax then
    FValue := FMax;
  Changed;                     { the size changes: lay out and paint again }
end;

procedure TStarRating.SetStarSize(AValue: Integer);
begin
  if AValue < 8 then AValue := 8;
  FStarSize := AValue;
  Changed;
end;

procedure TStarRating.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := FMax * FStarSize;
  H := FStarSize;
end;

function TStarRating.StarAt(X: Integer): Integer;
begin
  Result := (X - Bounds.X) div FStarSize + 1;
  if (Result < 1) or (Result > FMax) then
    Result := -1;
end;

procedure TStarRating.Paint(C: TCanvas32);
var
  F: TPastelFont;
  I, Shown: Integer;
  Col: TColor32;
begin
  if IsFocused then
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6, 6, Theme.FocusRing);
  F := GetFont(FStarSize * 3 div 4);
  Shown := FValue;
  if IsHovered and (FHover > 0) and not FReadOnly and Enabled then
    Shown := FHover;
  for I := 1 to FMax do
  begin
    if I <= Shown then
      Col := StarColor
    else
      Col := Theme.Border;
    if not Enabled then
      Col := Theme.Disabled;
    C.DrawText(F, Bounds.X + (I - 1) * FStarSize + (FStarSize - F.TextWidth('★')) div 2,
      Bounds.Y + (FStarSize - F.LineHeight) div 2, '★', Col);
  end;
end;

function TStarRating.Focusable: Boolean;
begin
  Result := Enabled and not FReadOnly;
end;

function TStarRating.Cursor: TCursorKind;
begin
  if FReadOnly then Result := ckArrow else Result := ckHand;
end;

procedure TStarRating.MouseDown(X, Y: Integer);
var
  S: Integer;
begin
  S := StarAt(X);
  if FReadOnly or (S < 1) then
    Exit;
  { a click on the only given star takes it back }
  if (S = 1) and (FValue = 1) then
    Value := 0
  else
    Value := S;
end;

procedure TStarRating.MouseMove(X, Y: Integer);
var
  S: Integer;
begin
  S := StarAt(X);
  if S <> FHover then
  begin
    FHover := S;
    Invalidate;
  end;
end;

function TStarRating.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := not FReadOnly;
  if not Result then
    Exit;
  case Key of
    KEY_RIGHT, KEY_UP: Value := FValue + 1;
    KEY_LEFT, KEY_DOWN: Value := FValue - 1;
    KEY_HOME: Value := 0;
    KEY_END: Value := FMax;
  else
    Result := False;
  end;
end;

initialization
  RegisterControl(TStarRating);
end.
