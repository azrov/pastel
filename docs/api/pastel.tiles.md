# Pastel.Tiles

TTileView: many items with pictures, as a grid of tiles (posters)
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

`uses Pastel.Tiles;` · source: [framework/src/pastel.tiles.pas](../../framework/src/pastel.tiles.pas)

## Types

### TTileStyle

```pascal
type TTileStyle = (tsGrid, tsList)
```

- `tsGrid`
- `tsList`
### TTile

```pascal
type TTile = record
```

| | |
|---|---|
| `Title: string` |  |
| `Subtitle: string` |  |
| `ImageUrl: string` |  |
| `Badge: string` |  |
| `Tag: PtrInt` |  |
| `Data: string` | the app's own text (an id, JSON...) |

### TTileView

```pascal
type TTileView = class(TControl)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure Clear` |  |
| `function Add(const Title: string; const Subtitle: string = ''; const ImageUrl: string = ''; ATag: PtrInt = 0; const AData: string = ''): Integer` |  |
| `procedure SetTile(Index: Integer; const T: TTile)` | Changes a tile in place (a badge, the line under the title). |
| `procedure MakeVisible(Index: Integer)` |  |
| `function Count: Integer` |  |
| `property Tiles[Index: Integer]: TTile` |  |
| `property ItemIndex: Integer` | the chosen tile; -1: none |
| `property Style: TTileStyle` | tsGrid: tiles side by side (posters); tsList: one row each (a picture at the left). |
| `property TileWidth: Integer` | the width of a tile (grid); they grow to fill the row |
| `property ImageRatio: Single` | the picture's height / width in the grid (posters 1.5; logos 0.6) |
| `property RowHeight: Integer` | a row's height (list) |
| `property Gap: Integer` |  |
| `property EmptyText: string` | shown when there are no tiles |
| `property OnChange: TNotifyEvent` |  |
| `property OnItemClick: TNotifyEvent` |  |

