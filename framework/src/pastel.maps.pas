{ Pastel - a map in a form: TMapView.

    Map.SetCenter(41.0082, 28.9784, 13);                  // Istanbul
    Map.AddMarker(41.0086, 28.9802, 'Salon', $FFE53935);
    Map.AddRoute([GeoPoint(41.00, 28.97), GeoPoint(41.01, 28.98)]);
    procedure THomeForm.MapMarkerClick(Sender: TObject; Marker: TMapMarker);

  Drawn by Pastel itself from map tiles (256 x 256 pictures of the Web
  Mercator projection), the same on phones and computers: a finger or the
  mouse moves it, a double tap, the wheel and the + - buttons zoom. TileUrl
  takes any tile server (z, x, y in braces; default OpenStreetMap's, whose rules ask
  for its attribution - shown - and no heavy use: a busy app uses a tile
  service of its own or a paid one). Tiles are kept in memory and in a cache
  folder, fetched on a thread of their own.
  Part of the Pastel project, MIT License. }
unit Pastel.Maps;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  TGeoPoint = record
    Lat, Lon: Double;
  end;
  TGeoPoints = array of TGeoPoint;

  TMapMarker = class
  public
    Lat, Lon: Double;
    Title: string;
    Color: TColor32;
    { the app's own: an id, an index }
    Data: PtrInt;
  end;

  TMarkerEvent = procedure(Sender: TObject; Marker: TMapMarker) of object;
  TMapPointEvent = procedure(Sender: TObject; Lat, Lon: Double) of object;

  TMapView = class(TControl)
  private
    FLat, FLon: Double;
    FZoom, FMinZoom, FMaxZoom: Integer;
    FTileUrl, FAttribution: string;
    FMarkers: TFPList;
    FRoutes: array of record
      Points: TGeoPoints;
      Color: TColor32;
      Width: Single;
    end;
    FSelected: TMapMarker;
    FShowZoomButtons: Boolean;
    FOnMarkerClick: TMarkerEvent;
    FOnMapClick: TMapPointEvent;
    FOnMove: TNotifyEvent;
    FDownX, FDownY, FLastX, FLastY: Integer;
    FMoved, FDown: Boolean;
    FPinch: Single;
    FTimer: TTimer;
    procedure SetLat(AValue: Double);
    procedure SetLon(AValue: Double);
    procedure SetZoom(AValue: Integer);
    procedure SetTileUrl(const AValue: string);
    function GetMarker(Index: Integer): TMapMarker;
    function GetMarkerCount: Integer;
    procedure Tick(Sender: TObject);
    { the center in world pixels at the zoom }
    procedure CenterPixels(out CX, CY: Double);
    procedure SetCenterPixels(CX, CY: Double);
    function MarkerAt(X, Y: Integer): TMapMarker;
    function ZoomButton(X, Y: Integer): Integer;
    procedure ZoomAt(Delta, X, Y: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    function Gesture(const G: TGestureInfo): Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    function Focusable: Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { A finger moves the map, not the page around it. }
    function DragsAt(X, Y: Integer): Boolean; override;
    procedure SetCenter(ALat, ALon: Double; AZoom: Integer = -1);
    procedure ZoomIn;
    procedure ZoomOut;
    function AddMarker(ALat, ALon: Double; const ATitle: string = ''; AColor: TColor32 = 0): TMapMarker;
    procedure RemoveMarker(M: TMapMarker);
    procedure ClearMarkers;
    { A line through the points (a route, a track); its index. }
    function AddRoute(const Points: array of TGeoPoint; AColor: TColor32 = 0; AWidth: Single = 4): Integer;
    procedure ClearRoutes;
    { Center and zoom so that every marker (and route) is seen. }
    procedure FitAll;
    { The place under a point of the control (X, Y in the form's units). }
    function PlaceAt(X, Y: Integer): TGeoPoint;
    { Where a place is drawn (the form's units). }
    function PointOf(ALat, ALon: Double): TPoint;
    property MarkerCount: Integer read GetMarkerCount;
    property Markers[Index: Integer]: TMapMarker read GetMarker;
    { The marker last tapped (its title is shown), or nil. }
    property Selected: TMapMarker read FSelected write FSelected;
  published
    property Latitude: Double read FLat write SetLat;
    property Longitude: Double read FLon write SetLon;
    { 1 (the world) to 19 (a house). }
    property Zoom: Integer read FZoom write SetZoom default 13;
    property MinZoom: Integer read FMinZoom write FMinZoom default 1;
    property MaxZoom: Integer read FMaxZoom write FMaxZoom default 19;
    { The tile server: z, x, y (and s: a, b or c) in braces, like OpenStreetMap's. }
    property TileUrl: string read FTileUrl write SetTileUrl;
    { Shown at the bottom right, as the tile server's rules ask. }
    property Attribution: string read FAttribution write FAttribution;
    property ShowZoomButtons: Boolean read FShowZoomButtons write FShowZoomButtons default True;
    property OnMarkerClick: TMarkerEvent read FOnMarkerClick write FOnMarkerClick;
    { A tap on the map itself (not a marker): the place. }
    property OnMapClick: TMapPointEvent read FOnMapClick write FOnMapClick;
    { Moved or zoomed (by the user or the code). }
    property OnMove: TNotifyEvent read FOnMove write FOnMove;
  end;

function GeoPoint(ALat, ALon: Double): TGeoPoint;
{ Web Mercator: world pixels at a zoom (256 * 2^Zoom across) and back. }
procedure GeoToPixels(Lat, Lon: Double; Zoom: Integer; out X, Y: Double);
procedure PixelsToGeo(X, Y: Double; Zoom: Integer; out Lat, Lon: Double);
{ The address of a tile from a TileUrl. }
function TileAddress(const Template: string; Z, X, Y: Integer): string;
{ Where tiles are kept between runs ('': in memory only). }
var
  MapTileCacheDir: string = '';

implementation

uses
  Math, SyncObjs, Pastel.Http, Pastel.Files;

const
  TileSize = 256;
  MaxLat = 85.05112878;
  DefaultTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  DefaultAttribution = '© OpenStreetMap contributors';
  MemoryTiles = 300;

function GeoPoint(ALat, ALon: Double): TGeoPoint;
begin
  Result.Lat := ALat;
  Result.Lon := ALon;
end;

procedure GeoToPixels(Lat, Lon: Double; Zoom: Integer; out X, Y: Double);
var
  N, S: Double;
begin
  N := TileSize * Power(2, Zoom);
  Lat := EnsureRange(Lat, -MaxLat, MaxLat);
  S := Sin(DegToRad(Lat));
  X := (Lon + 180) / 360 * N;
  Y := (0.5 - Ln((1 + S) / (1 - S)) / (4 * Pi)) * N;
end;

procedure PixelsToGeo(X, Y: Double; Zoom: Integer; out Lat, Lon: Double);
var
  N: Double;
begin
  N := TileSize * Power(2, Zoom);
  Lon := X / N * 360 - 180;
  Lat := RadToDeg(ArcTan(SinH(Pi * (1 - 2 * Y / N))));
end;

function TileAddress(const Template: string; Z, X, Y: Integer): string;
begin
  Result := StringReplace(Template, '{z}', IntToStr(Z), [rfReplaceAll]);
  Result := StringReplace(Result, '{x}', IntToStr(X), [rfReplaceAll]);
  Result := StringReplace(Result, '{y}', IntToStr(Y), [rfReplaceAll]);
  Result := StringReplace(Result, '{s}', Chr(Ord('a') + (X + Y) mod 3), [rfReplaceAll]);
end;

{ ---- tiles: in memory, in the cache folder, fetched on a thread ---- }

type
  TTileLoader = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  Lock: TCriticalSection;
  Tiles: TStringList;          { address -> TBitmap32 (nil: failed) }
  Wanted: TStringList;         { addresses to fetch, newest last }
  Loader: TTileLoader;
  Arrived: Integer;            { tiles that came since the maps looked }
  UserAgent: string;

function CacheFile(const Url: string): string;
var
  I: Integer;
  S: string;
begin
  if MapTileCacheDir = '' then
    Exit('');
  S := Url;
  I := Pos('://', S);
  if I > 0 then
    Delete(S, 1, I + 2);
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_']) then
      S[I] := '_';
  Result := IncludeTrailingPathDelimiter(MapTileCacheDir) + S;
end;

procedure TTileLoader.Execute;
var
  Url, F: string;
  B: TBitmap32;
  Http: THttpClient;
  R: THttpResponse;
  M: TMemoryStream;
begin
  Http := THttpClient.Create;
  try
    Http.UserAgent := UserAgent;
    Http.Timeout := 15000;
    while not Terminated do
    begin
      Url := '';
      Lock.Enter;
      try
        if Wanted.Count > 0 then
        begin
          { the newest first: what is on the screen now }
          Url := Wanted[Wanted.Count - 1];
          Wanted.Delete(Wanted.Count - 1);
        end;
      finally
        Lock.Leave;
      end;
      if Url = '' then
      begin
        Sleep(30);
        Continue;
      end;
      B := TBitmap32.Create;
      M := TMemoryStream.Create;
      try
        try
          F := CacheFile(Url);
          if (F <> '') and FileExists(F) then
            M.LoadFromFile(F)
          else
          begin
            R := Http.Get(Url);
            if R.Status <> 200 then
              raise Exception.CreateFmt('%d', [R.Status]);
            if R.Body <> '' then
              M.WriteBuffer(R.Body[1], Length(R.Body));
            if F <> '' then
            try
              ForceDirectories(ExtractFileDir(F));
              M.SaveToFile(F);
            except
              { the cache is only a help }
            end;
          end;
          M.Position := 0;
          B.LoadFromStream(M);
        except
          FreeAndNil(B);
        end;
      finally
        M.Free;
      end;
      Lock.Enter;
      try
        if Tiles.IndexOf(Url) < 0 then
          Tiles.AddObject(Url, B)
        else
          B.Free;
        { the oldest go when there are too many }
        while Tiles.Count > MemoryTiles do
        begin
          Tiles.Objects[0].Free;
          Tiles.Delete(0);
        end;
        Inc(Arrived);
      finally
        Lock.Leave;
      end;
    end;
  finally
    Http.Free;
  end;
end;

{ the tile when it is there; else asked for. Found: False while it comes. }
function GetTile(const Url: string; Ask: Boolean; out Found: Boolean): TBitmap32;
var
  I: Integer;
begin
  Result := nil;
  Lock.Enter;
  try
    I := Tiles.IndexOf(Url);
    Found := I >= 0;
    if Found then
    begin
      Result := TBitmap32(Tiles.Objects[I]);
      { used: the newest }
      Tiles.Move(I, Tiles.Count - 1);
    end
    else if Ask then
    begin
      I := Wanted.IndexOf(Url);
      if I >= 0 then
        Wanted.Delete(I);
      Wanted.Add(Url);
      if Wanted.Count > 64 then
        Wanted.Delete(0);
      if Loader = nil then
      begin
        IsMultiThread := True;
        Loader := TTileLoader.Create(False);
      end;
    end;
  finally
    Lock.Leave;
  end;
end;

{ ---- TMapView ---- }

constructor TMapView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMarkers := TFPList.Create;
  FZoom := 13;
  FMinZoom := 1;
  FMaxZoom := 19;
  FTileUrl := DefaultTiles;
  FAttribution := DefaultAttribution;
  FShowZoomButtons := True;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 100;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;
end;

destructor TMapView.Destroy;
begin
  ClearMarkers;
  FMarkers.Free;
  inherited Destroy;
end;

procedure TMapView.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := Min(AvailWidth, 400);
  H := 300;
end;

function TMapView.Focusable: Boolean;
begin
  Result := True;
end;

function TMapView.DragsAt(X, Y: Integer): Boolean;
begin
  Result := True;
end;

procedure TMapView.Tick(Sender: TObject);
var
  N: Integer;
begin
  Lock.Enter;
  try
    N := Arrived;
    Arrived := 0;
  finally
    Lock.Leave;
  end;
  if N > 0 then
    Invalidate;
end;

procedure TMapView.SetLat(AValue: Double);
begin
  FLat := EnsureRange(AValue, -MaxLat, MaxLat);
  Invalidate;
end;

procedure TMapView.SetLon(AValue: Double);
begin
  { -180..180, around the world }
  FLon := AValue - 360 * Floor((AValue + 180) / 360);
  Invalidate;
end;

procedure TMapView.SetZoom(AValue: Integer);
begin
  AValue := EnsureRange(AValue, Max(0, FMinZoom), Min(22, FMaxZoom));
  if AValue = FZoom then
    Exit;
  FZoom := AValue;
  Invalidate;
  if Assigned(FOnMove) and not (csLoading in ComponentState) then
    FOnMove(Self);
end;

procedure TMapView.SetTileUrl(const AValue: string);
begin
  if AValue = '' then
    FTileUrl := DefaultTiles
  else
    FTileUrl := AValue;
  Invalidate;
end;

procedure TMapView.SetCenter(ALat, ALon: Double; AZoom: Integer);
begin
  SetLat(ALat);
  SetLon(ALon);
  if AZoom >= 0 then
    FZoom := EnsureRange(AZoom, Max(0, FMinZoom), Min(22, FMaxZoom));
  Invalidate;
  if Assigned(FOnMove) then
    FOnMove(Self);
end;

procedure TMapView.CenterPixels(out CX, CY: Double);
begin
  GeoToPixels(FLat, FLon, FZoom, CX, CY);
end;

procedure TMapView.SetCenterPixels(CX, CY: Double);
var
  ALat, ALon: Double;
begin
  PixelsToGeo(CX, CY, FZoom, ALat, ALon);
  SetLat(ALat);
  SetLon(ALon);
end;

function TMapView.PlaceAt(X, Y: Integer): TGeoPoint;
var
  CX, CY: Double;
begin
  CenterPixels(CX, CY);
  PixelsToGeo(CX + X - (Bounds.X + Bounds.W / 2), CY + Y - (Bounds.Y + Bounds.H / 2), FZoom, Result.Lat, Result.Lon);
  Result.Lon := Result.Lon - 360 * Floor((Result.Lon + 180) / 360);
end;

function TMapView.PointOf(ALat, ALon: Double): TPoint;
var
  CX, CY, PX, PY, N: Double;
begin
  CenterPixels(CX, CY);
  GeoToPixels(ALat, ALon, FZoom, PX, PY);
  { the nearer copy of the world (a marker across 180°) }
  N := TileSize * Power(2, FZoom);
  if PX - CX > N / 2 then
    PX := PX - N
  else if CX - PX > N / 2 then
    PX := PX + N;
  Result.X := Round(Bounds.X + Bounds.W / 2 + PX - CX);
  Result.Y := Round(Bounds.Y + Bounds.H / 2 + PY - CY);
end;

procedure TMapView.ZoomIn;
begin
  Zoom := FZoom + 1;
end;

procedure TMapView.ZoomOut;
begin
  Zoom := FZoom - 1;
end;

{ zooms keeping the place under X, Y where it is }
procedure TMapView.ZoomAt(Delta, X, Y: Integer);
var
  P: TGeoPoint;
  CX, CY, PX, PY: Double;
  Z: Integer;
begin
  Z := EnsureRange(FZoom + Delta, Max(0, FMinZoom), Min(22, FMaxZoom));
  if Z = FZoom then
    Exit;
  P := PlaceAt(X, Y);
  FZoom := Z;
  GeoToPixels(P.Lat, P.Lon, FZoom, PX, PY);
  CX := PX - (X - (Bounds.X + Bounds.W / 2));
  CY := PY - (Y - (Bounds.Y + Bounds.H / 2));
  SetCenterPixels(CX, CY);
  if Assigned(FOnMove) then
    FOnMove(Self);
end;

function TMapView.AddMarker(ALat, ALon: Double; const ATitle: string; AColor: TColor32): TMapMarker;
begin
  Result := TMapMarker.Create;
  Result.Lat := ALat;
  Result.Lon := ALon;
  Result.Title := ATitle;
  if AColor = 0 then
    Result.Color := Theme.Accent
  else
    Result.Color := AColor;
  FMarkers.Add(Result);
  Invalidate;
end;

procedure TMapView.RemoveMarker(M: TMapMarker);
begin
  if FMarkers.Remove(M) >= 0 then
  begin
    if FSelected = M then
      FSelected := nil;
    M.Free;
    Invalidate;
  end;
end;

procedure TMapView.ClearMarkers;
var
  I: Integer;
begin
  for I := 0 to FMarkers.Count - 1 do
    TMapMarker(FMarkers[I]).Free;
  FMarkers.Clear;
  FSelected := nil;
  Invalidate;
end;

function TMapView.GetMarker(Index: Integer): TMapMarker;
begin
  Result := TMapMarker(FMarkers[Index]);
end;

function TMapView.GetMarkerCount: Integer;
begin
  Result := FMarkers.Count;
end;

function TMapView.AddRoute(const Points: array of TGeoPoint; AColor: TColor32; AWidth: Single): Integer;
var
  I: Integer;
begin
  Result := Length(FRoutes);
  SetLength(FRoutes, Result + 1);
  SetLength(FRoutes[Result].Points, Length(Points));
  for I := 0 to High(Points) do
    FRoutes[Result].Points[I] := Points[I];
  if AColor = 0 then
    FRoutes[Result].Color := Theme.Accent
  else
    FRoutes[Result].Color := AColor;
  FRoutes[Result].Width := AWidth;
  Invalidate;
end;

procedure TMapView.ClearRoutes;
begin
  FRoutes := nil;
  Invalidate;
end;

procedure TMapView.FitAll;
var
  MinLat, MaxLat_, MinLon, MaxLon: Double;
  Any: Boolean;
  I, J, Z: Integer;
  X1, Y1, X2, Y2: Double;

  procedure Take(ALat, ALon: Double);
  begin
    if not Any then
    begin
      MinLat := ALat; MaxLat_ := ALat; MinLon := ALon; MaxLon := ALon;
      Any := True;
    end
    else
    begin
      MinLat := Min(MinLat, ALat); MaxLat_ := Max(MaxLat_, ALat);
      MinLon := Min(MinLon, ALon); MaxLon := Max(MaxLon, ALon);
    end;
  end;

begin
  Any := False;
  MinLat := 0; MaxLat_ := 0; MinLon := 0; MaxLon := 0;
  for I := 0 to FMarkers.Count - 1 do
    Take(Markers[I].Lat, Markers[I].Lon);
  for I := 0 to High(FRoutes) do
    for J := 0 to High(FRoutes[I].Points) do
      Take(FRoutes[I].Points[J].Lat, FRoutes[I].Points[J].Lon);
  if not Any then
    Exit;
  { the closest zoom with everything inside, a margin around }
  Z := Min(FMaxZoom, 17);
  while Z > FMinZoom do
  begin
    GeoToPixels(MaxLat_, MinLon, Z, X1, Y1);
    GeoToPixels(MinLat, MaxLon, Z, X2, Y2);
    if (X2 - X1 <= Max(1, Bounds.W - 64)) and (Y2 - Y1 <= Max(1, Bounds.H - 64)) then
      Break;
    Dec(Z);
  end;
  SetCenter((MinLat + MaxLat_) / 2, (MinLon + MaxLon) / 2, Z);
end;

function TMapView.MarkerAt(X, Y: Integer): TMapMarker;
var
  I: Integer;
  P: TPoint;
begin
  Result := nil;
  { the top one: drawn last }
  for I := FMarkers.Count - 1 downto 0 do
  begin
    P := PointOf(Markers[I].Lat, Markers[I].Lon);
    if (Abs(X - P.X) <= 14) and (Y <= P.Y + 4) and (Y >= P.Y - 34) then
      Exit(Markers[I]);
  end;
end;

{ +1, -1 or 0: the zoom buttons at the top right }
function TMapView.ZoomButton(X, Y: Integer): Integer;
var
  BX: Integer;
begin
  Result := 0;
  if not FShowZoomButtons then
    Exit;
  BX := Bounds.X + Bounds.W - 44;
  if (X >= BX) and (X < BX + 36) then
    if (Y >= Bounds.Y + 8) and (Y < Bounds.Y + 44) then
      Result := 1
    else if (Y >= Bounds.Y + 46) and (Y < Bounds.Y + 82) then
      Result := -1;
end;

procedure TMapView.MouseDown(X, Y: Integer);
var
  F: TForm;
  B: Integer;
begin
  FDownX := X;
  FDownY := Y;
  FLastX := X;
  FLastY := Y;
  FMoved := False;
  FDown := True;
  B := ZoomButton(X, Y);
  if B <> 0 then
  begin
    FDown := False;
    ZoomAt(B, Bounds.X + Bounds.W div 2, Bounds.Y + Bounds.H div 2);
    Exit;
  end;
  F := ParentForm;
  if (F <> nil) and (F.ClickCount = 2) then
  begin
    FDown := False;
    ZoomAt(1, X, Y);
  end;
end;

procedure TMapView.MouseMove(X, Y: Integer);
var
  CX, CY: Double;
begin
  if not FDown then
    Exit;
  if not FMoved and (Abs(X - FDownX) + Abs(Y - FDownY) < 6) then
    Exit;
  FMoved := True;
  CenterPixels(CX, CY);
  SetCenterPixels(CX - (X - FLastX), CY - (Y - FLastY));
  FLastX := X;
  FLastY := Y;
end;

procedure TMapView.MouseUp(X, Y: Integer; Inside: Boolean);
var
  M: TMapMarker;
  P: TGeoPoint;
begin
  if not FDown then
    Exit;
  FDown := False;
  if FMoved then
  begin
    if Assigned(FOnMove) then
      FOnMove(Self);
    Exit;
  end;
  if not Inside then
    Exit;
  M := MarkerAt(X, Y);
  if M <> nil then
  begin
    FSelected := M;
    Invalidate;
    if Assigned(FOnMarkerClick) then
      FOnMarkerClick(Self, M);
    Exit;
  end;
  if FSelected <> nil then
  begin
    FSelected := nil;
    Invalidate;
  end;
  if Assigned(FOnMapClick) then
  begin
    P := PlaceAt(X, Y);
    FOnMapClick(Self, P.Lat, P.Lon);
  end;
end;

function TMapView.MouseWheel(DX, DY: Integer): Boolean;
var
  F: TForm;
begin
  Result := True;
  F := ParentForm;
  if DY > 0 then
    if F <> nil then ZoomAt(1, F.MouseX, F.MouseY) else ZoomIn
  else if DY < 0 then
    if F <> nil then ZoomAt(-1, F.MouseX, F.MouseY) else ZoomOut;
end;

function TMapView.Gesture(const G: TGestureInfo): Boolean;
begin
  Result := True;
  if G.State = gsBegin then
    FPinch := 1;
  FDown := False;
  FPinch := FPinch * G.Scale;
  { whole zoom steps: about 1.6 times apart (fingers twice as far: one step) }
  while FPinch >= 1.6 do
  begin
    ZoomAt(1, G.X, G.Y);
    FPinch := FPinch / 2;
  end;
  while FPinch <= 0.625 do
  begin
    ZoomAt(-1, G.X, G.Y);
    FPinch := FPinch * 2;
  end;
end;

function TMapView.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  CX, CY: Double;
begin
  Result := True;
  CenterPixels(CX, CY);
  case Key of
    KEY_LEFT: SetCenterPixels(CX - 64, CY);
    KEY_RIGHT: SetCenterPixels(CX + 64, CY);
    KEY_UP: SetCenterPixels(CX, CY - 64);
    KEY_DOWN: SetCenterPixels(CX, CY + 64);
    KEY_PAGEUP: ZoomIn;
    KEY_PAGEDOWN: ZoomOut;
  else
    if (Key = Ord('+')) or (Key = Ord('=')) then
      ZoomIn
    else if Key = Ord('-') then
      ZoomOut
    else
      Result := False;
  end;
end;

procedure TMapView.Paint(C: TCanvas32);
var
  CX, CY, OX, OY: Double;
  N, TX, TY, TX0, TX1, TY0, TY1, WX, SX, SY, I, J, Z, Up: Integer;
  B: TBitmap32;
  Found, Drawn: Boolean;
  P, Q: TPoint;
  M: TMapMarker;
  F, Small: TPastelFont;
  W, BX, BY: Integer;
  Back: TColor32;
begin
  if Theme.Dark then
    Back := $FF2B2B30
  else
    Back := $FFE8E6E1;
  C.PushClip(Bounds);
  try
    C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Back);
    CenterPixels(CX, CY);
    OX := CX - Bounds.W / 2;
    OY := CY - Bounds.H / 2;
    N := 1 shl FZoom;
    TX0 := Floor(OX / TileSize);
    TX1 := Floor((OX + Bounds.W) / TileSize);
    TY0 := Max(0, Floor(OY / TileSize));
    TY1 := Min(N - 1, Floor((OY + Bounds.H) / TileSize));
    for TY := TY0 to TY1 do
      for TX := TX0 to TX1 do
      begin
        WX := ((TX mod N) + N) mod N;
        SX := Round(Bounds.X + TX * TileSize - OX);
        SY := Round(Bounds.Y + TY * TileSize - OY);
        B := GetTile(TileAddress(FTileUrl, FZoom, WX, TY), True, Found);
        if B <> nil then
        begin
          C.DrawBitmap(B, SX, SY, TileSize, TileSize, True);
          Continue;
        end;
        { while it comes: the same place from a tile of a smaller zoom, larger }
        Drawn := False;
        for Up := 1 to Min(4, FZoom) do
        begin
          Z := FZoom - Up;
          B := GetTile(TileAddress(FTileUrl, Z, WX shr Up, TY shr Up), False, Found);
          if B <> nil then
          begin
            C.PushClip(RectI(SX, SY, TileSize, TileSize));
            try
              I := TileSize shl Up;
              C.DrawBitmap(B, SX - (WX and ((1 shl Up) - 1)) * TileSize, SY - (TY and ((1 shl Up) - 1)) * TileSize,
                I, I, True);
            finally
              C.PopClip;
            end;
            Drawn := True;
            Break;
          end;
        end;
        if not Drawn then
          C.StrokeRoundRect(SX, SY, TileSize, TileSize, 0, 1, Theme.Border);
      end;
    { routes }
    for I := 0 to High(FRoutes) do
      for J := 1 to High(FRoutes[I].Points) do
      begin
        P := PointOf(FRoutes[I].Points[J - 1].Lat, FRoutes[I].Points[J - 1].Lon);
        Q := PointOf(FRoutes[I].Points[J].Lat, FRoutes[I].Points[J].Lon);
        C.DrawLine(P.X, P.Y, Q.X, Q.Y, FRoutes[I].Width, FRoutes[I].Color);
      end;
    { markers: a pin, its point at the place }
    F := GetFont(Theme.FontSize);
    for I := 0 to FMarkers.Count - 1 do
    begin
      M := Markers[I];
      P := PointOf(M.Lat, M.Lon);
      if (P.X < Bounds.X - 20) or (P.X > Bounds.X + Bounds.W + 20) or (P.Y < Bounds.Y - 10) or
         (P.Y > Bounds.Y + Bounds.H + 40) then
        Continue;
      C.DrawLine(P.X, P.Y - 14, P.X, P.Y, 3, $FF555555);
      C.FillCircle(P.X, P.Y - 20, 10, $FFFFFFFF);
      C.FillCircle(P.X, P.Y - 20, 8, M.Color);
      if (M = FSelected) and (M.Title <> '') then
      begin
        W := F.TextWidth(M.Title) + 16;
        BX := P.X - W div 2;
        BY := P.Y - 36 - F.LineHeight - 8;
        C.FillRoundRect(BX, BY, W, F.LineHeight + 8, 6, Theme.Surface);
        C.StrokeRoundRect(BX, BY, W, F.LineHeight + 8, 6, 1, Theme.Border);
        C.DrawText(F, BX + 8, BY + 4, M.Title, Theme.Text);
      end;
    end;
    { + and - }
    if FShowZoomButtons then
    begin
      BX := Bounds.X + Bounds.W - 44;
      for I := 0 to 1 do
      begin
        BY := Bounds.Y + 8 + I * 38;
        C.FillRoundRect(BX, BY, 36, 36, 6, Theme.Surface);
        C.StrokeRoundRect(BX, BY, 36, 36, 6, 1, Theme.Border);
        C.DrawLine(BX + 11, BY + 18, BX + 25, BY + 18, 2, Theme.Text);
        if I = 0 then
          C.DrawLine(BX + 18, BY + 11, BX + 18, BY + 25, 2, Theme.Text);
      end;
    end;
    { the tile server's attribution }
    if FAttribution <> '' then
    begin
      Small := GetFont(Max(9, Theme.FontSize - 3));
      W := Small.TextWidth(FAttribution) + 8;
      C.FillRect(Bounds.X + Bounds.W - W, Bounds.Y + Bounds.H - Small.LineHeight - 2, W, Small.LineHeight + 2, $C0FFFFFF);
      C.DrawText(Small, Bounds.X + Bounds.W - W + 4, Bounds.Y + Bounds.H - Small.LineHeight - 1, FAttribution, $FF333333);
    end;
  finally
    C.PopClip;
  end;
end;

procedure FreeTiles;
var
  I: Integer;
begin
  if Loader <> nil then
  begin
    Loader.Terminate;
    Loader.WaitFor;
    Loader.Free;
  end;
  for I := 0 to Tiles.Count - 1 do
    Tiles.Objects[I].Free;
  Tiles.Free;
  Wanted.Free;
end;

function DefaultCacheDir: string;
begin
  {$IFDEF WINDOWS}
  Result := GetEnvironmentVariable('LOCALAPPDATA');
  {$ELSE}
  Result := GetEnvironmentVariable('XDG_CACHE_HOME');
  if Result = '' then
    Result := JoinPath([HomeDir, '.cache']);
  {$ENDIF}
  if Result <> '' then
    Result := JoinPath([Result, 'pastel-tiles']);
end;

initialization
  Lock := TCriticalSection.Create;
  Tiles := TStringList.Create;
  Wanted := TStringList.Create;
  MapTileCacheDir := DefaultCacheDir;
  UserAgent := 'Pastel map (' + ChangeFileExt(ExtractFileName(ParamStr(0)), '') + ')';
  RegisterControl(TMapView);

finalization
  FreeTiles;
  Lock.Free;
end.
