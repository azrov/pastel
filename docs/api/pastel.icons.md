# Pastel.Icons

Icons: small line drawings for buttons, drawn at any size and in
  any color, so they are sharp on every screen and right in the dark theme.

    object SaveButton: TButton
      Icon = 'save'
      Text = 'Save'
    end

  The built-in ones are listed by IconNames. Your own are drawn on a 24 x 24
  grid, one command per part, the parts separated by ';':

    l x1 y1 x2 y2 ...      lines through the points
    o cx cy r              a circle
    f cx cy r              a filled circle (a dot)
    a cx cy r from to      an arc; angles in degrees, 0 = right, 90 = down

    RegisterIcon('bell', 'l 6 17 6 10; a 12 10 6 180 360; l 18 10 18 17; l 4 17 20 17; f 12 20 1.5');

`uses Pastel.Icons;` · source: [framework/src/pastel.icons.pas](../../framework/src/pastel.icons.pas)

## Routines

### DrawIcon

```pascal
function DrawIcon(C: TCanvas32; const Name: string; X: Integer; Y: Integer; Size: Integer; Color: TColor32): Boolean
```

Draws the icon Name in the square X, Y, Size; False when there is no such icon.

### HasIcon

```pascal
function HasIcon(const Name: string): Boolean
```

An icon with this name exists.

### RegisterIcon

```pascal
procedure RegisterIcon(const Name: string; const Drawing: string)
```

Adds (or replaces) an icon, drawn with the commands above.

### IconNames

```pascal
function IconNames: TStringArray
```

The names of all icons, sorted.

