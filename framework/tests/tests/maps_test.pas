{ Tests of Pastel.Maps: the projection, moving and zooming, markers, tiles. }
unit maps_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Maps;

type
  TMapsTests = class(TTestSuite)
  private
    FForm: TForm;
    FMap: TMapView;
    FCanvas: TCanvas32;
    FClicked: TMapMarker;
    FPlaceLat, FPlaceLon: Double;
    FMoves: Integer;
    procedure MarkerClicked(Sender: TObject; Marker: TMapMarker);
    procedure MapClicked(Sender: TObject; Lat, Lon: Double);
    procedure Moved(Sender: TObject);
    procedure Render;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Projection;
    procedure DragMovesTheMap;
    procedure ZoomButtonsAndWheel;
    procedure MarkersAndTaps;
    procedure FitAllShowsEverything;
    procedure PinchZooms;
    procedure TilesFromTheCache;
  end;

implementation

uses
  Math, Pastel.Files;

procedure TMapsTests.SetUp;
begin
  InitFonts;
  FForm := TForm.Create(nil);
  FMap := TMapView.Create(FForm);
  FMap.Parent := FForm;
  FMap.Grow := 1;
  FMap.TileUrl := 'http://127.0.0.1:1/{z}/{x}/{y}.png';
  FMap.OnMarkerClick := @MarkerClicked;
  FMap.OnMapClick := @MapClicked;
  FMap.OnMove := @Moved;
  FCanvas := TCanvas32.Create;
  FClicked := nil;
  FMoves := 0;
end;

procedure TMapsTests.TearDown;
begin
  FForm.Free;
  FCanvas.Free;
end;

procedure TMapsTests.Render;
begin
  FForm.Layout(400, 300);
  FCanvas.SetSize(400, 300);
  FForm.Render(FCanvas);
end;

procedure TMapsTests.MarkerClicked(Sender: TObject; Marker: TMapMarker);
begin
  FClicked := Marker;
end;

procedure TMapsTests.MapClicked(Sender: TObject; Lat, Lon: Double);
begin
  FPlaceLat := Lat;
  FPlaceLon := Lon;
end;

procedure TMapsTests.Moved(Sender: TObject);
begin
  Inc(FMoves);
end;

procedure TMapsTests.Projection;
var
  X, Y, Lat, Lon: Double;
begin
  GeoToPixels(0, 0, 0, X, Y);
  AssertTrue(SameValue(X, 128, 1e-6) and SameValue(Y, 128, 1e-6), 'the middle of the world');
  GeoToPixels(41.0082, 28.9784, 13, X, Y);
  AssertEquals(4755, Floor(X / 256), 'the tile of Istanbul');
  AssertEquals(3071, Floor(Y / 256));
  PixelsToGeo(X, Y, 13, Lat, Lon);
  AssertTrue(SameValue(Lat, 41.0082, 1e-7) and SameValue(Lon, 28.9784, 1e-7), 'and back');
  AssertEquals('https://t/13/4807/3078.png', TileAddress('https://t/{z}/{x}/{y}.png', 13, 4807, 3078));
  AssertEquals('https://b.t/1/1/0', TileAddress('https://{s}.t/{z}/{x}/{y}', 1, 1, 0));
end;

procedure TMapsTests.DragMovesTheMap;
var
  Lon: Double;
  P: TPoint;
begin
  FMap.SetCenter(41, 29, 10);
  Render;
  AssertTrue(FMap.DragsAt(10, 10), 'a finger moves the map');
  Lon := FMap.Longitude;
  FMoves := 0;
  FForm.HandleMouseMove(200, 150);
  FForm.HandleMouseDown(200, 150);
  FForm.HandleMouseMove(150, 150);
  FForm.HandleMouseMove(100, 150);
  FForm.HandleMouseUp(100, 150);
  AssertTrue(FMap.Longitude > Lon, 'dragged left: the map goes east');
  AssertTrue(SameValue(FMap.Latitude, 41, 1e-6), 'not up or down');
  AssertEquals(1, FMoves, 'OnMove once, at the end');
  { a place stays under the finger }
  P := FMap.PointOf(41, 29);
  AssertEquals(100, P.X);
end;

procedure TMapsTests.ZoomButtonsAndWheel;
begin
  FMap.SetCenter(41, 29, 10);
  Render;
  { the buttons: at the map's top right }
  FForm.HandleMouseMove(FMap.Bounds.X + FMap.Bounds.W - 26, FMap.Bounds.Y + 26);
  FForm.HandleMouseDown(FMap.Bounds.X + FMap.Bounds.W - 26, FMap.Bounds.Y + 26);
  FForm.HandleMouseUp(FMap.Bounds.X + FMap.Bounds.W - 26, FMap.Bounds.Y + 26);
  AssertEquals(11, FMap.Zoom, '+');
  FForm.HandleMouseDown(FMap.Bounds.X + FMap.Bounds.W - 26, FMap.Bounds.Y + 64);
  FForm.HandleMouseUp(FMap.Bounds.X + FMap.Bounds.W - 26, FMap.Bounds.Y + 64);
  AssertEquals(10, FMap.Zoom, '-');
  FForm.HandleMouseMove(200, 150);
  FForm.HandleMouseWheel(0, 1);
  AssertEquals(11, FMap.Zoom, 'the wheel');
  FMap.Zoom := 40;
  AssertEquals(19, FMap.Zoom, 'MaxZoom');
end;

procedure TMapsTests.MarkersAndTaps;
var
  M: TMapMarker;
  P: TPoint;
begin
  FMap.SetCenter(41, 29, 12);
  M := FMap.AddMarker(41.01, 29.01, 'Salon');
  Render;
  P := FMap.PointOf(M.Lat, M.Lon);
  FForm.HandleMouseMove(P.X, P.Y - 20);
  FForm.HandleMouseDown(P.X, P.Y - 20);
  FForm.HandleMouseUp(P.X, P.Y - 20);
  AssertTrue(FClicked = M, 'the pin tapped');
  AssertTrue(FMap.Selected = M);
  FForm.HandleMouseMove(50, 250);
  FForm.HandleMouseDown(50, 250);
  FForm.HandleMouseUp(50, 250);
  AssertTrue(FMap.Selected = nil, 'a tap elsewhere');
  AssertTrue(FPlaceLat < 41, 'below the middle: south');
  AssertTrue(FPlaceLon < 29, 'left: west');
  FMap.RemoveMarker(M);
  AssertEquals(0, FMap.MarkerCount);
end;

procedure TMapsTests.PinchZooms;
var
  G: TGestureInfo;
begin
  FMap.SetCenter(41, 29, 10);
  Render;
  G.X := 200;
  G.Y := 150;
  G.Rotation := 0;
  G.State := gsBegin;
  G.Scale := 1;
  FForm.HandleGesture(G);
  G.State := gsUpdate;
  G.Scale := 1.3;
  FForm.HandleGesture(G);
  AssertEquals(10, FMap.Zoom, 'not yet a step');
  FForm.HandleGesture(G);
  AssertEquals(11, FMap.Zoom, 'fingers apart: closer');
  G.Scale := 0.5;
  FForm.HandleGesture(G);
  AssertEquals(10, FMap.Zoom, 'together: further');
end;

procedure TMapsTests.FitAllShowsEverything;
var
  P: TPoint;
begin
  FMap.AddMarker(41.0, 28.9);
  FMap.AddMarker(41.1, 29.1);
  FMap.AddRoute([GeoPoint(40.95, 29.0), GeoPoint(41.0, 29.05)]);
  Render;
  FMap.FitAll;
  P := FMap.PointOf(41.0, 28.9);
  AssertTrue((P.X >= 0) and (P.X <= 400) and (P.Y >= 0) and (P.Y <= 300));
  P := FMap.PointOf(41.1, 29.1);
  AssertTrue((P.X >= 0) and (P.X <= 400) and (P.Y >= 0) and (P.Y <= 300));
  P := FMap.PointOf(40.95, 29.0);
  AssertTrue((P.Y >= 0) and (P.Y <= 300), 'the route too');
  AssertTrue(FMap.Zoom >= 9, 'and not further out than needed');
end;

procedure TMapsTests.TilesFromTheCache;
var
  Dir, OldDir: string;
  Tile: TCanvas32;
  X, Y: Double;
  TX, TY: Integer;
  Until_: QWord;
begin
  OldDir := MapTileCacheDir;
  Dir := MakeTempDir('pastel-tiles');
  try
    MapTileCacheDir := Dir;
    FMap.SetCenter(41, 29, 9);
    GeoToPixels(41, 29, 9, X, Y);
    TX := Floor(X / 256);
    TY := Floor(Y / 256);
    { the tile under the middle, as if fetched before: all red }
    Tile := TCanvas32.Create;
    try
      Tile.SetSize(256, 256);
      Tile.Clear($FFFF0000);
      Tile.SavetoPNG(Dir + '127.0.0.1_1_9_' + IntToStr(TX) + '_' + IntToStr(TY) + '.png');
    finally
      Tile.Free;
    end;
    Render;
    Until_ := GetTickCount64 + 3000;
    while (FCanvas.GetPixel(200, 150) and $FFFFFF <> $FF0000) and (GetTickCount64 < Until_) do
    begin
      Sleep(20);
      Render;
    end;
    AssertEquals(IntToHex($FFFF0000, 8), IntToHex(FCanvas.GetPixel(200, 150), 8), 'the tile is drawn');
  finally
    MapTileCacheDir := OldDir;
    DeleteDir(Dir);
  end;
end;

initialization
  RegisterTests(TMapsTests);

end.
