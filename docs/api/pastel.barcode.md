# Pastel.Barcode

QR codes and barcodes: made (drawn) by Pastel, for screens, labels and reports.

    object Code: TBarcode
      Kind = bkQR
      Text = 'https://pastel.dev/order/1042'
    end

    Q := QrEncode('WIFI:S:Salon;T:WPA;P:secret;;');      // the modules, Q.Size x Q.Size
    SaveBarcodePng('label.png', '8690000000001', bkEAN13, 4);
    B := BarcodeBitmap('ORD-1042', bkCode128, 3);        // TBitmap32, for a report or a TImage

  QR codes (ISO/IEC 18004: every version, the four error correction levels, the
  best mask), Code 128 (letters and digits; digits in pairs, shorter) and EAN-13
  (the check digit added or checked).

`uses Pastel.Barcode;` · source: [framework/src/pastel.barcode.pas](../../framework/src/pastel.barcode.pas)

**Contents:** [TBarcodeKind](#tbarcodekind) · [TQrLevel](#tqrlevel) · [TQrCode](#tqrcode) · [EBarcodeError](#ebarcodeerror) · [TBarcode](#tbarcode) · [QrEncode](#qrencode) · [Code128Widths](#code128widths) · [Ean13Widths](#ean13widths) · [BarcodeBitmap](#barcodebitmap) · [SaveBarcodePng](#savebarcodepng)

## Types

### TBarcodeKind

```pascal
type TBarcodeKind = (bkQR, bkCode128, bkEAN13)
```

- `bkQR`
- `bkCode128`
- `bkEAN13`
### TQrLevel

```pascal
type TQrLevel = (qlLow, qlMedium, qlQuartile, qlHigh)
```

how much of a QR code may be damaged and still read: 7, 15, 25, 30 %

- `qlLow` how much of a QR code may be damaged and still read: 7, 15, 25, 30 %
- `qlMedium` how much of a QR code may be damaged and still read: 7, 15, 25, 30 %
- `qlQuartile` how much of a QR code may be damaged and still read: 7, 15, 25, 30 %
- `qlHigh` how much of a QR code may be damaged and still read: 7, 15, 25, 30 %
### TQrCode

```pascal
type TQrCode = record
```

| | |
|---|---|
| `Size: Integer` |  |
| `Version: Integer` |  |
| `Modules: array of Boolean` | Size * Size, row by row; True: dark |
| `function Dark(X: Integer; Y: Integer): Boolean` |  |

### EBarcodeError

```pascal
type EBarcodeError = class(Exception)
```

### TBarcode

```pascal
type TBarcode = class(TControl)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Error: string` | '' or why the text cannot be this kind of code |
| `property Text: string` |  |
| `property Kind: TBarcodeKind` |  |
| `property Level: TQrLevel` |  |
| `property Color: TColor32` |  |
| `property BackColor: TColor32` |  |
| `property ShowText: Boolean` | the digits under a barcode |

## Routines

### QrEncode

```pascal
function QrEncode(const Text: string; Level: TQrLevel = qlMedium): TQrCode
```

The text as UTF-8 bytes, in the smallest version that holds it.

### Code128Widths

```pascal
function Code128Widths(const Text: string): TBytes
```

Bars and spaces as widths in modules (starting with a bar), and the text shown under them.

### Ean13Widths

```pascal
function Ean13Widths(const Digits: string; out Shown: string): TBytes
```

### BarcodeBitmap

```pascal
function BarcodeBitmap(const Text: string; Kind: TBarcodeKind; Scale: Integer = 4; Level: TQrLevel = qlMedium): TBitmap32
```

The code as a picture: Scale pixels a module, a quiet zone around.

### SaveBarcodePng

```pascal
procedure SaveBarcodePng(const FileName: string; const Text: string; Kind: TBarcodeKind; Scale: Integer = 4; Level: TQrLevel = qlMedium)
```

