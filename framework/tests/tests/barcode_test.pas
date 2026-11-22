{ Tests of Pastel.Barcode: sizes, check digits, pictures (PASTEL_BARCODE_OUT: the PNGs too). }
unit barcode_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.Barcode;

type
  TBarcodeTests = class(TTestSuite)
  published
    procedure QrVersions;
    procedure Ean13CheckDigit;
    procedure Code128;
    procedure Pictures;
  end;

implementation

uses
  Pastel.Env, Pastel.Files;

procedure TBarcodeTests.QrVersions;
var
  Q: TQrCode;
begin
  Q := QrEncode('HELLO', qlMedium);
  AssertEquals(1, Q.Version);
  AssertEquals(21, Q.Size);
  AssertTrue(Q.Dark(0, 0) and Q.Dark(6, 6) and not Q.Dark(7, 7), 'the finder at the top left');
  AssertTrue(Q.Dark(8, Q.Size - 8), 'the dark module');
  Q := QrEncode(StringOfChar('a', 300), qlHigh);
  AssertTrue(Q.Version >= 10, 'a long text: a larger version');
  AssertEquals(Q.Version * 4 + 17, Q.Size);
  try
    QrEncode(StringOfChar('a', 3000), qlHigh);
    Fail('too long');
  except
    on E: EBarcodeError do ;
  end;
end;

procedure TBarcodeTests.Ean13CheckDigit;
var
  Shown: string;
  W: TBytes;
  I, Total: Integer;
begin
  W := Ean13Widths('400638133393', Shown);
  AssertEquals('4006381333931', Shown, 'the check digit added');
  Total := 0;
  for I := 0 to High(W) do
    Inc(Total, W[I]);
  AssertEquals(95, Total, 'an EAN-13 is 95 modules');
  Ean13Widths('4006381333931', Shown);
  try
    Ean13Widths('4006381333932', Shown);
    Fail('a wrong check digit');
  except
    on E: EBarcodeError do ;
  end;
end;

procedure TBarcodeTests.Code128;
var
  W: TBytes;
  I, Total: Integer;
begin
  W := Code128Widths('PJJ123C');
  Total := 0;
  for I := 0 to High(W) do
    Inc(Total, W[I]);
  { start, 7 symbols, check, stop (13): 11 modules each }
  AssertEquals(11 * 9 + 13, Total);
  W := Code128Widths('12345678');
  Total := 0;
  for I := 0 to High(W) do
    Inc(Total, W[I]);
  AssertEquals(11 * 6 + 13, Total, 'digits in pairs (set C)');
end;

procedure TBarcodeTests.Pictures;
var
  Dir: string;
  B: TBitmap32;
begin
  B := BarcodeBitmap('https://pastel.dev', bkQR, 4);
  try
    AssertEquals(B.Width, B.Height);
    AssertEquals(IntToHex($FFFFFFFF, 8), IntToHex(B.Pixels[0], 8), 'the quiet zone');
  finally
    B.Free;
  end;
  Dir := GetEnv('PASTEL_BARCODE_OUT');
  if Dir = '' then
    Exit;
  SaveBarcodePng(JoinPath([Dir, 'qr.png']), 'https://pastel.dev/order/1042?ğ=1', bkQR, 6);
  SaveBarcodePng(JoinPath([Dir, 'qr-long.png']), StringOfChar('x', 500), bkQR, 4, qlQuartile);
  SaveBarcodePng(JoinPath([Dir, 'ean.png']), '400638133393', bkEAN13, 4);
  SaveBarcodePng(JoinPath([Dir, 'code128.png']), 'ORD-104212345678', bkCode128, 4);
end;

initialization
  RegisterTests(TBarcodeTests);

end.
