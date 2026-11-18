# Pastel.Maps

A map in a form: TMapView.

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

`uses Pastel.Maps;` · source: [framework/src/pastel.maps.pas](../../framework/src/pastel.maps.pas)

**Contents:** [TGeoPoint](#tgeopoint) · [TMapMarker](#tmapmarker) · [TMapView](#tmapview) · [GeoPoint](#geopoint) · [GeoToPixels](#geotopixels) · [PixelsToGeo](#pixelstogeo) · [TileAddress](#tileaddress)

## Types

### TGeoPoint

```pascal
type TGeoPoint = record
```

| | |
|---|---|
| `Lat: Double` |  |
| `Lon: Double` |  |

### TMapMarker

```pascal
type TMapMarker = class
```

### TMapView

```pascal
type TMapView = class(TControl)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `function DragsAt(X: Integer; Y: Integer): Boolean` | A finger moves the map, not the page around it. |
| `procedure SetCenter(ALat: Double; ALon: Double; AZoom: Integer = -1)` |  |
| `procedure ZoomIn` |  |
| `procedure ZoomOut` |  |
| `function AddMarker(ALat: Double; ALon: Double; const ATitle: string = ''; AColor: TColor32 = 0): TMapMarker` |  |
| `procedure RemoveMarker(M: TMapMarker)` |  |
| `procedure ClearMarkers` |  |
| `function AddRoute(const Points: array of TGeoPoint; AColor: TColor32 = 0; AWidth: Single = 4): Integer` | A line through the points (a route, a track); its index. |
| `procedure ClearRoutes` |  |
| `procedure FitAll` | Center and zoom so that every marker (and route) is seen. |
| `function PlaceAt(X: Integer; Y: Integer): TGeoPoint` | The place under a point of the control (X, Y in the form's units). |
| `function PointOf(ALat: Double; ALon: Double): TPoint` | Where a place is drawn (the form's units). |
| `property MarkerCount: Integer` |  |
| `property Markers[Index: Integer]: TMapMarker` |  |
| `property Selected: TMapMarker` | The marker last tapped (its title is shown), or nil. |
| `property Latitude: Double` |  |
| `property Longitude: Double` |  |
| `property Zoom: Integer` | 1 (the world) to 19 (a house). |
| `property MinZoom: Integer` |  |
| `property MaxZoom: Integer` |  |
| `property TileUrl: string` | The tile server: z, x, y (and s: a, b or c) in braces, like OpenStreetMap's. |
| `property Attribution: string` | Shown at the bottom right, as the tile server's rules ask. |
| `property ShowZoomButtons: Boolean` |  |
| `property OnMarkerClick: TMarkerEvent` |  |
| `property OnMapClick: TMapPointEvent` | A tap on the map itself (not a marker): the place. |
| `property OnMove: TNotifyEvent` | Moved or zoomed (by the user or the code). |

## Other types

| | |
|---|---|
| `type TGeoPoints = array of TGeoPoint` |  |
| `type TMarkerEvent = procedure(Sender: TObject; Marker: TMapMarker)` |  |
| `type TMapPointEvent = procedure(Sender: TObject; Lat: Double; Lon: Double)` |  |

## Routines

### GeoPoint

```pascal
function GeoPoint(ALat: Double; ALon: Double): TGeoPoint
```

### GeoToPixels

```pascal
procedure GeoToPixels(Lat: Double; Lon: Double; Zoom: Integer; out X: Double; out Y: Double)
```

Web Mercator: world pixels at a zoom (256 * 2^Zoom across) and back.

### PixelsToGeo

```pascal
procedure PixelsToGeo(X: Double; Y: Double; Zoom: Integer; out Lat: Double; out Lon: Double)
```

### TileAddress

```pascal
function TileAddress(const Template: string; Z: Integer; X: Integer; Y: Integer): string
```

The address of a tile from a TileUrl.

## Constants and variables

| | |
|---|---|
| `var MapTileCacheDir: string` |  |
