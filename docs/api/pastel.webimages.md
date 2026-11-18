# Pastel.WebImages

Pictures from the web: posters, logos, avatars.

    B := WebImage('https://example.com/poster.jpg');   // nil while it comes
    if B <> nil then C.DrawBitmap(B, X, Y, W, H);

  Four threads fetch them (what is asked last, first: what is on the screen
  now); the window paints again when one comes. They are kept in memory (the
  ones used least go: MaxWebImages) and in a cache folder, made smaller on the
  way (WebImageMaxSide), so a list of thousands of posters stays light. A
  bitmap given by WebImage is for drawing at once: do not keep it.
  TImage.Url and TTileView use it. Part of the Pastel project, MIT License.

`uses Pastel.WebImages;` · source: [framework/src/pastel.webimages.pas](../../framework/src/pastel.webimages.pas)

## Routines

### WebImage

```pascal
function WebImage(const Url: string): TBitmap32
```

The picture, or nil while it comes (or when it failed: WebImageFailed). Main thread only.

### WebImageFailed

```pascal
function WebImageFailed(const Url: string): Boolean
```

### ClearWebImages

```pascal
procedure ClearWebImages
```

Forgets the pictures in memory (not the cache folder).

### WebImageCacheDir

```pascal
function WebImageCacheDir: string
```

The cache folder (default: the user's cache folder / the program's name / images).

## Constants and variables

| | |
|---|---|
| `var MaxWebImages: Integer` |  |
| `var WebImageMaxSide: Integer` | pictures are made smaller than this on the longer side (pixels) |
| `var WebImageUserAgent: string` |  |
| `var WebImageCache: string` | '' : the default cache folder; set it to change the place |
