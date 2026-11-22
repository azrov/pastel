{ Pastel - TTileView: many items with pictures, as a grid of tiles (posters)
  or a list of rows (channels with their logos). Thousands of items stay quick:
  only what is on the screen is drawn, pictures come from the web as they are
  seen (Pastel.WebImages).

    Movies.Clear;
    for M in List do
      Movies.Add(M.Name, M.Year, M.PosterUrl, M.Id);
    procedure TMainForm.MoviesItemClick(Sender: TObject);
    begin
      Play(Movies.Tiles[Movies.ItemIndex].Tag);
    end;

  The arrows move between the tiles (a TV's remote too); at an edge they go on
  to the control beside it. Enter or a click: OnItemClick.
  Part of the Pastel project, MIT License. }
unit Pastel.Tiles;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Pastel.Graphics, Pastel.UI, Pastel.WebImages;

type
  TTileStyle = (tsGrid, tsList);

  TTile = record
    Title, Subtitle, ImageUrl, Badge: string;
    Tag: PtrInt;
    { the app's own text (an id, JSON...) }
    Data: string;
  end;

  TTileView = class(TControl)
  private
    FTiles: array of TTile;
    FCount: Integer;
    FStyle: TTileStyle;
    FTileWidth, FRowHeight, FGap: Integer;
    FImageRatio: Single;
    FItemIndex, FHover: Integer;
    FScrollY: Integer;
    FEmptyText: string;
    FDragY, FDragScroll: Integer;
    FDragging, FDragged: Boolean;
    FOnChange, FOnItemClick: TNotifyEvent;
    function GetTile(Index: Integer): TTile;
    procedure SetStyle(AValue: TTileStyle);
    procedure SetItemIndex(AValue: Integer);
    procedure SetTileWidth(AValue: Integer);
    function Columns: Integer;
    function CellW: Integer;
    function CellH: Integer;
    function ContentHeight: Integer;
    function TileRect(Index: Integer): TRectI;
    function IndexAt(X, Y: Integer): Integer;
    procedure ClampScroll;
    procedure PaintTile(C: TCanvas32; Index: Integer; const R: TRectI);
    procedure PaintPicture(C: TCanvas32; const T: TTile; const R: TRectI; Cover: Boolean);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Clear;
    function Add(const Title: string; const Subtitle: string = ''; const ImageUrl: string = '';
      ATag: PtrInt = 0; const AData: string = ''): Integer;
    { Changes a tile in place (a badge, the line under the title). }
    procedure SetTile(Index: Integer; const T: TTile);
    procedure MakeVisible(Index: Integer);
    function Count: Integer;
    property Tiles[Index: Integer]: TTile read GetTile;
    { the chosen tile; -1: none }
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
  published
    { tsGrid: tiles side by side (posters); tsList: one row each (a picture at the left). }
    property Style: TTileStyle read FStyle write SetStyle default tsGrid;
    { the width of a tile (grid); they grow to fill the row }
    property TileWidth: Integer read FTileWidth write SetTileWidth default 150;
    { the picture's height / width in the grid (posters 1.5; logos 0.6) }
    property ImageRatio: Single read FImageRatio write FImageRatio;
    { a row's height (list) }
    property RowHeight: Integer read FRowHeight write FRowHeight default 56;
    property Gap: Integer read FGap write FGap default 12;
    { shown when there are no tiles }
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnItemClick: TNotifyEvent read FOnItemClick write FOnItemClick;
  end;

implementation

constructor TTileView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTileWidth := 150;
  FRowHeight := 56;
  FGap := 12;
  FImageRatio := 1.5;
  FItemIndex := -1;
  FHover := -1;
end;

procedure TTileView.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := AvailWidth;
  H := 300;
end;

function TTileView.Focusable: Boolean;
begin
  Result := Enabled;
end;

procedure TTileView.Clear;
begin
  FTiles := nil;
  FCount := 0;
  FItemIndex := -1;
  FHover := -1;
  FScrollY := 0;
  Invalidate;
end;

function TTileView.Add(const Title, Subtitle, ImageUrl: string; ATag: PtrInt; const AData: string): Integer;
begin
  if FCount = Length(FTiles) then
    SetLength(FTiles, Max(64, FCount * 2));
  FTiles[FCount].Title := Title;
  FTiles[FCount].Subtitle := Subtitle;
  FTiles[FCount].ImageUrl := ImageUrl;
  FTiles[FCount].Badge := '';
  FTiles[FCount].Tag := ATag;
  FTiles[FCount].Data := AData;
  Result := FCount;
  Inc(FCount);
  Invalidate;
end;

procedure TTileView.SetTile(Index: Integer; const T: TTile);
begin
  if (Index >= 0) and (Index < FCount) then
  begin
    FTiles[Index] := T;
    Invalidate;
  end;
end;

function TTileView.Count: Integer;
begin
  Result := FCount;
end;

function TTileView.GetTile(Index: Integer): TTile;
begin
  if (Index < 0) or (Index >= FCount) then
    raise EListError.CreateFmt('no tile %d (there are %d)', [Index, FCount]);
  Result := FTiles[Index];
end;

procedure TTileView.SetStyle(AValue: TTileStyle);
begin
  FStyle := AValue;
  Invalidate;
end;

procedure TTileView.SetTileWidth(AValue: Integer);
begin
  FTileWidth := Max(40, AValue);
  Invalidate;
end;

function TTileView.Columns: Integer;
begin
  if FStyle = tsList then
    Exit(1);
  Result := Max(1, (Bounds.W - 16 + FGap) div (FTileWidth + FGap));
end;

function TTileView.CellW: Integer;
var
  N: Integer;
begin
  N := Columns;
  { room for the scroll bar at the right }
  Result := Max(1, (Bounds.W - 16 - FGap * (N - 1)) div N);
end;

{ the height of a tile with its texts }
function TTileView.CellH: Integer;
var
  F: TPastelFont;
begin
  if FStyle = tsList then
    Exit(FRowHeight);
  F := GetFont(Theme.FontSize, False);
  Result := Round(CellW * FImageRatio) + 10 + F.LineHeight * 2 + 4;
end;

function TTileView.ContentHeight: Integer;
var
  Rows: Integer;
begin
  Rows := (FCount + Columns - 1) div Columns;
  if FStyle = tsList then
    Result := Rows * (CellH + 2)
  else
    Result := Rows * (CellH + FGap);
end;

function TTileView.TileRect(Index: Integer): TRectI;
var
  Col, Row, StepY: Integer;
begin
  Col := Index mod Columns;
  Row := Index div Columns;
  if FStyle = tsList then StepY := CellH + 2 else StepY := CellH + FGap;
  Result := RectI(Bounds.X + 4 + Col * (CellW + FGap), Bounds.Y + 4 + Row * StepY - FScrollY, CellW, CellH);
end;

function TTileView.IndexAt(X, Y: Integer): Integer;
var
  I, First, Last: Integer;
  R: TRectI;
  StepY: Integer;
begin
  Result := -1;
  if FStyle = tsList then StepY := CellH + 2 else StepY := CellH + FGap;
  First := Max(0, (Y - Bounds.Y - 4 + FScrollY) div StepY - 1) * Columns;
  Last := Min(FCount - 1, First + Columns * 3);
  for I := First to Last do
  begin
    R := TileRect(I);
    if (X >= R.X) and (X < R.X + R.W) and (Y >= R.Y) and (Y < R.Y + R.H) then
      Exit(I);
  end;
end;

procedure TTileView.ClampScroll;
begin
  FScrollY := EnsureRange(FScrollY, 0, Max(0, ContentHeight + 8 - Bounds.H));
end;

procedure TTileView.MakeVisible(Index: Integer);
var
  R: TRectI;
begin
  if (Index < 0) or (Index >= FCount) or (Bounds.H <= 0) then
    Exit;
  R := TileRect(Index);
  if R.Y < Bounds.Y + 4 then
    Inc(FScrollY, R.Y - Bounds.Y - 4)
  else if R.Y + R.H > Bounds.Y + Bounds.H - 4 then
    Inc(FScrollY, R.Y + R.H - (Bounds.Y + Bounds.H - 4));
  ClampScroll;
  Invalidate;
end;

procedure TTileView.SetItemIndex(AValue: Integer);
begin
  AValue := EnsureRange(AValue, -1, FCount - 1);
  if AValue = FItemIndex then
    Exit;
  FItemIndex := AValue;
  MakeVisible(AValue);
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

{ the picture, or the title's first letters on a color of its own while it comes }
procedure TTileView.PaintPicture(C: TCanvas32; const T: TTile; const R: TRectI; Cover: Boolean);
var
  B: TBitmap32;
  Scale: Double;
  W, H, I: Integer;
  Hash: Cardinal;
  F: TPastelFont;
  Letters: string;
begin
  B := nil;
  if T.ImageUrl <> '' then
    B := WebImage(T.ImageUrl);
  if (B <> nil) and not B.Empty then
  begin
    C.FillRect(R.X, R.Y, R.W, R.H, Mix(Theme.Surface, Theme.Text, 0.06));
    if Cover then
      Scale := Max(R.W / B.Width, R.H / B.Height)
    else
      Scale := Min(R.W / B.Width, R.H / B.Height);
    W := Max(1, Round(B.Width * Scale));
    H := Max(1, Round(B.Height * Scale));
    C.PushClip(R);
    C.DrawBitmap(B, R.X + (R.W - W) div 2, R.Y + (R.H - H) div 2, W, H, True);
    C.PopClip;
    Exit;
  end;
  Hash := 0;
  for I := 1 to Length(T.Title) do
    Hash := (Hash * 31 + Ord(T.Title[I])) and $FFFFFF;
  C.FillRect(R.X, R.Y, R.W, R.H, Mix(Theme.Surface, RGB(60 + Hash mod 140, 60 + (Hash shr 8) mod 140,
    90 + (Hash shr 16) mod 140), 0.55));
  Letters := UTF8Encode(UpperCase(Copy(UTF8Decode(Trim(T.Title)), 1, 2)));
  F := GetFont(Max(12, Min(R.H div 3, 32)), True);
  C.DrawText(F, R.X + (R.W - F.TextWidth(Letters)) div 2, R.Y + (R.H - F.LineHeight) div 2, Letters,
    RGBA($FF, $FF, $FF, $E0));
end;

procedure TTileView.PaintTile(C: TCanvas32; Index: Integer; const R: TRectI);
var
  T: TTile;
  F, FB: TPastelFont;
  Pic: TRectI;
  Chosen, Hot: Boolean;
  X, BW, TextW: Integer;
begin
  T := FTiles[Index];
  F := GetFont(Theme.FontSize - 1, False);
  FB := GetFont(Theme.FontSize, True);
  Chosen := Index = FItemIndex;
  Hot := Index = FHover;
  if FStyle = tsList then
  begin
    if Chosen then
      C.FillRoundRect(R.X, R.Y, R.W, R.H, Theme.Radius, WithAlpha(Theme.Accent, IfThen(IsFocused, $38, $20)))
    else if Hot then
      C.FillRoundRect(R.X, R.Y, R.W, R.H, Theme.Radius, WithAlpha(Theme.Text, $0C));
    Pic := RectI(R.X + 8, R.Y + 6, Round((R.H - 12) * 1.6), R.H - 12);
    PaintPicture(C, T, Pic, False);
    X := Pic.X + Pic.W + 12;
    TextW := R.X + R.W - X - 8;
    if T.Badge <> '' then
    begin
      BW := F.TextWidth(T.Badge);
      C.DrawText(F, R.X + R.W - BW - 10, R.Y + (R.H - F.LineHeight) div 2, T.Badge, Theme.Accent);
      Dec(TextW, BW + 12);
    end;
    if T.Subtitle = '' then
      C.DrawText(FB, X, R.Y + (R.H - FB.LineHeight) div 2, FitText(FB, T.Title, TextW), Theme.Text)
    else
    begin
      C.DrawText(FB, X, R.Y + R.H div 2 - FB.LineHeight + 1, FitText(FB, T.Title, TextW), Theme.Text);
      C.DrawText(F, X, R.Y + R.H div 2 + 2, FitText(F, T.Subtitle, TextW), Theme.TextMuted);
    end;
    if Chosen and IsFocused then
      C.StrokeRoundRect(R.X, R.Y, R.W, R.H, Theme.Radius, 2, Theme.Accent);
    Exit;
  end;
  Pic := RectI(R.X, R.Y, R.W, Round(R.W * FImageRatio));
  C.PushClip(Pic);
  PaintPicture(C, T, Pic, FImageRatio >= 1);
  C.PopClip;
  if T.Badge <> '' then
  begin
    BW := F.TextWidth(T.Badge) + 12;
    C.FillRoundRect(Pic.X + Pic.W - BW - 6, Pic.Y + 6, BW, F.LineHeight + 4, 6, RGBA(0, 0, 0, $B0));
    C.DrawText(F, Pic.X + Pic.W - BW, Pic.Y + 8, T.Badge, RGB($FF, $FF, $FF));
  end;
  if Chosen and IsFocused then
    C.StrokeRoundRect(Pic.X - 3, Pic.Y - 3, Pic.W + 6, Pic.H + 6, Theme.Radius + 2, 3, Theme.Accent)
  else if Chosen or Hot then
    C.StrokeRoundRect(Pic.X - 2, Pic.Y - 2, Pic.W + 4, Pic.H + 4, Theme.Radius + 2, 2,
      WithAlpha(Theme.Accent, IfThen(Chosen, $C0, $60)));
  C.DrawText(FB, R.X, Pic.Y + Pic.H + 8, FitText(FB, T.Title, R.W), Theme.Text);
  if T.Subtitle <> '' then
    C.DrawText(F, R.X, Pic.Y + Pic.H + 8 + FB.LineHeight, FitText(F, T.Subtitle, R.W), Theme.TextMuted);
end;

procedure TTileView.Paint(C: TCanvas32);
var
  I, First, Last, StepY, H: Integer;
  R: TRectI;
  F: TPastelFont;
begin
  ClampScroll;
  C.PushClip(Bounds);
  if FCount = 0 then
  begin
    if FEmptyText <> '' then
    begin
      F := GetFont(Theme.FontSize, False);
      C.DrawText(F, Bounds.X + (Bounds.W - F.TextWidth(FEmptyText)) div 2, Bounds.Y + 40, FEmptyText,
        Theme.TextMuted);
    end;
    C.PopClip;
    Exit;
  end;
  if FStyle = tsList then StepY := CellH + 2 else StepY := CellH + FGap;
  First := Max(0, FScrollY div StepY) * Columns;
  Last := Min(FCount - 1, ((FScrollY + Bounds.H) div StepY + 1) * Columns + Columns - 1);
  for I := First to Last do
  begin
    R := TileRect(I);
    if (R.Y + R.H >= Bounds.Y) and (R.Y <= Bounds.Y + Bounds.H) then
      PaintTile(C, I, R);
  end;
  { a thin scroll bar }
  H := ContentHeight;
  if H > Bounds.H then
    C.FillRoundRect(Bounds.X + Bounds.W - 5, Bounds.Y + (Bounds.H - Max(24, Bounds.H * Bounds.H div H)) *
      FScrollY div Max(1, H - Bounds.H), 4, Max(24, Bounds.H * Bounds.H div H), 2, WithAlpha(Theme.TextMuted, $70));
  C.PopClip;
  { pictures that come later: paint again then (Pastel.WebImages does) }
end;

function TTileView.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  I, N, PageRows: Integer;
begin
  Result := True;
  N := Columns;
  I := FItemIndex;
  PageRows := Max(1, Bounds.H div Max(1, CellH));
  case Key of
    KEY_LEFT:
      if (FStyle = tsGrid) and (I > 0) and (I mod N > 0) then I := I - 1 else Exit(False);
    KEY_RIGHT:
      if (FStyle = tsGrid) and (I < FCount - 1) and (I mod N < N - 1) then I := I + 1 else Exit(False);
    KEY_UP:
      if I < 0 then I := 0 else if I - N >= 0 then I := I - N else Exit(False);
    KEY_DOWN:
      if I < 0 then I := 0 else if I + N < FCount then I := I + N
      else if (I div N) < ((FCount - 1) div N) then I := FCount - 1 else Exit(False);
    KEY_PAGEUP:
      I := Max(0, I - N * PageRows);
    KEY_PAGEDOWN:
      I := Min(FCount - 1, Max(0, I) + N * PageRows);
    KEY_HOME:
      I := 0;
    KEY_END:
      I := FCount - 1;
    KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
      begin
        if (FItemIndex >= 0) and Assigned(FOnItemClick) then
          FOnItemClick(Self);
        Exit(FItemIndex >= 0);
      end;
  else
    Exit(False);
  end;
  if FCount = 0 then
    Exit(False);
  ItemIndex := I;
end;

procedure TTileView.MouseDown(X, Y: Integer);
begin
  FDragging := True;
  FDragged := False;
  FDragY := Y;
  FDragScroll := FScrollY;
end;

procedure TTileView.MouseMove(X, Y: Integer);
var
  I: Integer;
begin
  if FDragging then
  begin
    { a finger (or the mouse) pulls the tiles }
    if Abs(Y - FDragY) > 8 then
      FDragged := True;
    if FDragged then
    begin
      FScrollY := FDragScroll - (Y - FDragY);
      ClampScroll;
      Invalidate;
      Exit;
    end;
  end;
  I := IndexAt(X, Y);
  if I <> FHover then
  begin
    FHover := I;
    Invalidate;
  end;
end;

procedure TTileView.MouseUp(X, Y: Integer; Inside: Boolean);
var
  I: Integer;
begin
  FDragging := False;
  if FDragged or not Inside then
    Exit;
  I := IndexAt(X, Y);
  if I < 0 then
    Exit;
  ItemIndex := I;
  if Assigned(FOnItemClick) then
    FOnItemClick(Self);
end;

function TTileView.MouseWheel(DX, DY: Integer): Boolean;
begin
  FScrollY := FScrollY - DY * Max(40, CellH div 2);
  ClampScroll;
  Invalidate;
  Result := True;
end;

initialization
  RegisterControl(TTileView);

end.
