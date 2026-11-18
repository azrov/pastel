# Pastel.Assets

The files of a project's assets/ folder, inside the program.

    Logo.FileName := 'logo.png';            // TImage finds assets by name
    S := OpenAsset('data/cities.json');     // any file, as a stream
    try ... finally S.Free; end;

  "pastel build" compiles every file below assets/ into the program (in
  release builds; debug builds read them from the folder, so changes show
  without a rebuild). Names use / and are relative to assets/.
  Conventions: assets/icon.png is the window icon; assets/font.ttf and
  assets/font-bold.ttf replace the system font.

`uses Pastel.Assets;` · source: [framework/src/pastel.assets.pas](../../framework/src/pastel.assets.pas)

**Contents:** [EAssetNotFound](#eassetnotfound) · [RegisterAsset](#registerasset) · [RegisterAssetFile](#registerassetfile) · [AssetExists](#assetexists) · [OpenAsset](#openasset) · [AssetBytes](#assetbytes) · [AssetText](#assettext) · [AssetNames](#assetnames)

## Types

### EAssetNotFound

```pascal
type EAssetNotFound = class(Exception)
```

## Routines

### RegisterAsset

```pascal
procedure RegisterAsset(const Name: string; Data: Pointer; Size: Integer)
```

Called by the code "pastel build" generates.

### RegisterAssetFile

```pascal
procedure RegisterAssetFile(const Name: string; const FileName: string)
```

### AssetExists

```pascal
function AssetExists(const Name: string): Boolean
```

### OpenAsset

```pascal
function OpenAsset(const Name: string): TStream
```

The asset as a stream; the caller frees it. EAssetNotFound when there is none.

### AssetBytes

```pascal
function AssetBytes(const Name: string): TBytes
```

The asset's bytes.

### AssetText

```pascal
function AssetText(const Name: string): string
```

### AssetNames

```pascal
function AssetNames: TStringArray
```

The names of all assets ('logo.png', 'data/cities.json').

