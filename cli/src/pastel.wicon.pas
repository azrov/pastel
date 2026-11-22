{ Pastel - the icon of a Windows program, from assets/icon.png.

  Writes a .res file with the icon in 256, 48, 32 and 16 pixels (PNG
  inside, which Windows reads since Vista); the program links it with
  $R and Explorer, the taskbar and shortcuts show it.
  Part of the Pastel project, MIT License. }
unit Pastel.WIcon;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ '' when it worked, else what went wrong. }
function WriteIconRes(const PngFile, ResFile: string): string;
{ The picture as a Size x Size PNG (Linux menus). }
function WriteSizedPng(const PngFile, OutFile: string; Size: Integer): string;
{ Pastel's icon for apps without assets/icon.png: a rounded square in pastel colors, 512 x 512. }
procedure WriteDefaultIcon(const OutFile: string);
{ Android TV's banner (320 x 180): the icon in the middle of a dark band. }
function WriteTvBanner(const PngFile, OutFile: string): string;
{ Android's adaptive icon (8 and newer): the front layer, Size x Size. The
  phone shows the middle 72/108 in its shape (circle, squircle...): an icon with
  a background of its own is drawn a little larger (84/108), so its rounded
  corners stay outside; one without (a picture on transparent) inside the
  circle every shape keeps (66/108). }
function WriteAdaptiveForeground(const PngFile, OutFile: string; Size: Integer; HasBack: Boolean): string;
{ The color of the icon's own background (its edge, inside), as #RRGGBB: the
  back layer of the adaptive icon; '' when the icon has none. }
function IconBackColor(const PngFile: string): string;
{ Android's small icon in the status bar (Size x Size): white on transparent,
  the shape of the picture on the icon's background (Back, '#RRGGBB'; '' when
  the icon has none: its shape). }
function WriteStatusIcon(const PngFile, OutFile: string; Size: Integer; const Back: string): string;
{ The same icon as an .ico file (for installers). }
function WriteIco(const PngFile, IcoFile: string): string;

implementation

uses
  Math, FPImage, FPReadPNG, FPWritePNG;

const
  Sizes: array[0..3] of Integer = (256, 48, 32, 16);
  RT_ICON = 3;
  RT_GROUP_ICON = 14;

{ a smooth smaller (or larger) copy: area average when shrinking }
function Scaled(Src: TFPCustomImage; Size: Integer): TFPMemoryImage;
var
  X, Y, SX, SY, X0, X1, Y0, Y1, N: Integer;
  R, G, B, A: Int64;
  C: TFPColor;
  FX, FY: Double;
begin
  Result := TFPMemoryImage.Create(Size, Size);
  Result.UsePalette := False;
  FX := Src.Width / Size;
  FY := Src.Height / Size;
  for Y := 0 to Size - 1 do
    for X := 0 to Size - 1 do
    begin
      X0 := Trunc(X * FX);
      X1 := Math.Max(X0 + 1, Trunc((X + 1) * FX));
      Y0 := Trunc(Y * FY);
      Y1 := Math.Max(Y0 + 1, Trunc((Y + 1) * FY));
      R := 0; G := 0; B := 0; A := 0; N := 0;
      for SY := Y0 to Math.Min(Y1, Src.Height) - 1 do
        for SX := X0 to Math.Min(X1, Src.Width) - 1 do
        begin
          C := Src.Colors[SX, SY];
          { weighted by alpha, so transparent pixels do not darken edges }
          Inc(R, Int64(C.Red) * C.Alpha div 65535);
          Inc(G, Int64(C.Green) * C.Alpha div 65535);
          Inc(B, Int64(C.Blue) * C.Alpha div 65535);
          Inc(A, C.Alpha);
          Inc(N);
        end;
      if (N = 0) or (A = 0) then
        C := colTransparent
      else
      begin
        C.Red := Math.Min(65535, R * 65535 div A);
        C.Green := Math.Min(65535, G * 65535 div A);
        C.Blue := Math.Min(65535, B * 65535 div A);
        C.Alpha := A div N;
      end;
      Result.Colors[X, Y] := C;
    end;
end;

procedure WriteResource(S: TStream; AType, AName: Word; Data: TStream);
const
  Zero: array[0..3] of Byte = (0, 0, 0, 0);
begin
  S.WriteDWord(NtoLE(DWord(Data.Size)));   { data size }
  S.WriteDWord(NtoLE(DWord(32)));          { header size }
  S.WriteWord(NtoLE(Word($FFFF)));
  S.WriteWord(NtoLE(AType));
  S.WriteWord(NtoLE(Word($FFFF)));
  S.WriteWord(NtoLE(AName));
  S.WriteDWord(0);                          { data version }
  if AType = 0 then
    S.WriteDWord(0)                         { the empty first entry }
  else
  begin
    S.WriteWord(NtoLE(Word($1010)));       { moveable, discardable }
    S.WriteWord(NtoLE(Word($0409)));       { language }
  end;
  S.WriteDWord(0);                          { version }
  S.WriteDWord(0);                          { characteristics }
  Data.Position := 0;
  S.CopyFrom(Data, Data.Size);
  if Data.Size mod 4 <> 0 then
    S.WriteBuffer(Zero, 4 - Data.Size mod 4);
end;

function WriteIconRes(const PngFile, ResFile: string): string;
var
  Src, Img: TFPCustomImage;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
  Pngs: array[0..High(Sizes)] of TMemoryStream;
  Group, Empty: TMemoryStream;
  Res: TFileStream;
  I: Integer;
begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  Writer.WordSized := False;
  Group := TMemoryStream.Create;
  Empty := TMemoryStream.Create;
  for I := 0 to High(Pngs) do
    Pngs[I] := TMemoryStream.Create;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      on E: Exception do
        Exit(Format('%s is not a PNG picture (%s)', [PngFile, E.Message]));
    end;
    for I := 0 to High(Sizes) do
    begin
      Img := Scaled(Src, Sizes[I]);
      try
        Img.SaveToStream(Pngs[I], Writer);
      finally
        Img.Free;
      end;
    end;
    { the group: which sizes there are }
    Group.WriteWord(0);
    Group.WriteWord(NtoLE(Word(1)));
    Group.WriteWord(NtoLE(Word(Length(Sizes))));
    for I := 0 to High(Sizes) do
    begin
      Group.WriteByte(Sizes[I] mod 256);    { 0 means 256 }
      Group.WriteByte(Sizes[I] mod 256);
      Group.WriteByte(0);
      Group.WriteByte(0);
      Group.WriteWord(NtoLE(Word(1)));      { planes }
      Group.WriteWord(NtoLE(Word(32)));     { bits }
      Group.WriteDWord(NtoLE(DWord(Pngs[I].Size)));
      Group.WriteWord(NtoLE(Word(I + 1)));  { the RT_ICON id }
    end;
    ForceDirectories(ExtractFileDir(ResFile));
    Res := TFileStream.Create(ResFile, fmCreate);
    try
      { a .res file starts with an empty entry }
      WriteResource(Res, 0, 0, Empty);
      for I := 0 to High(Sizes) do
        WriteResource(Res, RT_ICON, I + 1, Pngs[I]);
      WriteResource(Res, RT_GROUP_ICON, 1, Group);
    finally
      Res.Free;
    end;
  finally
    for I := 0 to High(Pngs) do
      Pngs[I].Free;
    Group.Free;
    Empty.Free;
    Writer.Free;
    Reader.Free;
    Src.Free;
  end;
end;

function WriteSizedPng(const PngFile, OutFile: string; Size: Integer): string;
var
  Src, Img: TFPCustomImage;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  Writer.WordSized := False;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      on E: Exception do
        Exit(Format('%s is not a PNG picture (%s)', [PngFile, E.Message]));
    end;
    Img := Scaled(Src, Size);
    try
      ForceDirectories(ExtractFileDir(OutFile));
      Img.SaveToFile(OutFile, Writer);
    finally
      Img.Free;
    end;
  finally
    Writer.Free;
    Reader.Free;
    Src.Free;
  end;
end;

function WriteTvBanner(const PngFile, OutFile: string): string;
const
  W = 320;
  H = 180;
  IconSize = 132;
var
  Src, Icon: TFPCustomImage;
  Banner: TFPMemoryImage;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
  X, Y, OX, OY: Integer;
  Back, C: TFPColor;
  A: Double;
begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  Writer.WordSized := False;
  Banner := TFPMemoryImage.Create(W, H);
  Banner.UsePalette := False;
  Icon := nil;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      on E: Exception do
        Exit(Format('%s is not a PNG picture (%s)', [PngFile, E.Message]));
    end;
    Icon := Scaled(Src, IconSize);
    Back.Red := $1E00; Back.Green := $1B00; Back.Blue := $2E00; Back.Alpha := $FFFF;
    OX := (W - IconSize) div 2;
    OY := (H - IconSize) div 2;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        C := Back;
        if (X >= OX) and (X < OX + IconSize) and (Y >= OY) and (Y < OY + IconSize) then
        begin
          { the icon over the band, by its transparency }
          A := Icon.Colors[X - OX, Y - OY].Alpha / 65535;
          C.Red := Round(Back.Red + (Icon.Colors[X - OX, Y - OY].Red - Back.Red) * A);
          C.Green := Round(Back.Green + (Icon.Colors[X - OX, Y - OY].Green - Back.Green) * A);
          C.Blue := Round(Back.Blue + (Icon.Colors[X - OX, Y - OY].Blue - Back.Blue) * A);
        end;
        Banner.Colors[X, Y] := C;
      end;
    ForceDirectories(ExtractFileDir(OutFile));
    Banner.SaveToFile(OutFile, Writer);
  finally
    Icon.Free;
    Banner.Free;
    Writer.Free;
    Reader.Free;
    Src.Free;
  end;
end;

function WriteAdaptiveForeground(const PngFile, OutFile: string; Size: Integer; HasBack: Boolean): string;
var
  Src, Icon: TFPCustomImage;
  Img: TFPMemoryImage;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
  X, Y, Inner, O: Integer;
begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  Writer.WordSized := False;
  Img := TFPMemoryImage.Create(Size, Size);
  Img.UsePalette := False;
  Icon := nil;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      on E: Exception do
        Exit(Format('%s is not a PNG picture (%s)', [PngFile, E.Message]));
    end;
    if HasBack then
      Inner := Round(Size * 84 / 108)
    else
      Inner := Round(Size * 66 / 108);
    Icon := Scaled(Src, Inner);
    O := (Size - Inner) div 2;
    for Y := 0 to Size - 1 do
      for X := 0 to Size - 1 do
        if (X >= O) and (X < O + Inner) and (Y >= O) and (Y < O + Inner) then
          Img.Colors[X, Y] := Icon.Colors[X - O, Y - O]
        else
          Img.Colors[X, Y] := colTransparent;
    ForceDirectories(ExtractFileDir(OutFile));
    Img.SaveToFile(OutFile, Writer);
  finally
    Icon.Free;
    Img.Free;
    Writer.Free;
    Reader.Free;
    Src.Free;
  end;
end;

function WriteStatusIcon(const PngFile, OutFile: string; Size: Integer; const Back: string): string;
var
  Src, Icon: TFPCustomImage;
  Img: TFPMemoryImage;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
  X, Y, BR, BG, BB: Integer;
  C, W: TFPColor;
  D, MaxD: Double;
begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  Writer.WordSized := False;
  Img := TFPMemoryImage.Create(Size, Size);
  Img.UsePalette := False;
  Icon := nil;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      on E: Exception do
        Exit(Format('%s is not a PNG picture (%s)', [PngFile, E.Message]));
    end;
    Icon := Scaled(Src, Size);
    BR := 0; BG := 0; BB := 0;
    if Back <> '' then
    begin
      BR := StrToInt('$' + Copy(Back, 2, 2));
      BG := StrToInt('$' + Copy(Back, 4, 2));
      BB := StrToInt('$' + Copy(Back, 6, 2));
    end;
    { how far each pixel is from the background; the farthest are the picture,
      the near ones (a gradient, a shadow of the background) are left out }
    MaxD := 0;
    if Back <> '' then
      for Y := 0 to Size - 1 do
        for X := 0 to Size - 1 do
        begin
          C := Icon.Colors[X, Y];
          if C.Alpha > $8000 then
            MaxD := Math.Max(MaxD, (Abs(C.Red shr 8 - BR) + Abs(C.Green shr 8 - BG) + Abs(C.Blue shr 8 - BB)) / (3 * 255));
        end;
    W := colWhite;
    for Y := 0 to Size - 1 do
      for X := 0 to Size - 1 do
      begin
        C := Icon.Colors[X, Y];
        if (Back = '') or (MaxD <= 0) then
          D := 1
        else
        begin
          D := (Abs(C.Red shr 8 - BR) + Abs(C.Green shr 8 - BG) + Abs(C.Blue shr 8 - BB)) / (3 * 255);
          D := Math.EnsureRange((D - 0.5 * MaxD) / (0.25 * MaxD), 0, 1);
        end;
        W.Alpha := Round(C.Alpha * D);
        Img.Colors[X, Y] := W;
      end;
    ForceDirectories(ExtractFileDir(OutFile));
    Img.SaveToFile(OutFile, Writer);
  finally
    Icon.Free;
    Img.Free;
    Writer.Free;
    Reader.Free;
    Src.Free;
  end;
end;

function IconBackColor(const PngFile: string): string;
var
  Src: TFPCustomImage;
  Reader: TFPReaderPNG;
  I, N, X, Y, Inset: Integer;
  R, G, B: Int64;
  C: TFPColor;

  procedure Sample(PX, PY: Integer);
  begin
    C := Src.Colors[PX, PY];
    if C.Alpha >= $F000 then
    begin
      Inc(R, C.Red shr 8);
      Inc(G, C.Green shr 8);
      Inc(B, C.Blue shr 8);
      Inc(N);
    end;
  end;

begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      Exit;
    end;
    if (Src.Width < 8) or (Src.Height < 8) then
      Exit;
    { a ring a little inside the edge: past rounded corners, before the picture }
    Inset := Math.Max(1, Src.Width div 12);
    R := 0; G := 0; B := 0; N := 0;
    for I := 0 to 63 do
    begin
      X := Inset + (Src.Width - 2 * Inset - 1) * I div 63;
      Y := Inset + (Src.Height - 2 * Inset - 1) * I div 63;
      Sample(X, Inset);
      Sample(X, Src.Height - 1 - Inset);
      Sample(Inset, Y);
      Sample(Src.Width - 1 - Inset, Y);
    end;
    if N >= 128 then      { most of the ring: the icon has a background of its own }
      Result := Format('#%.2X%.2X%.2X', [R div N, G div N, B div N]);
  finally
    Reader.Free;
    Src.Free;
  end;
end;

procedure WriteDefaultIcon(const OutFile: string);
const
  Size = 512;
  Radius = 112;
  Sub = 4;              { 4 x 4 samples a pixel: smooth edges }
var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X, Y, SX, SY, Inside, Ring: Integer;
  PX, PY, DX, DY, T, D: Double;
  C: TFPColor;

  { the rounded square }
  function InSquare(AX, AY: Double): Boolean;
  var
    QX, QY: Double;
  begin
    QX := Math.Max(0, Math.Max(Radius - AX, AX - (Size - Radius)));
    QY := Math.Max(0, Math.Max(Radius - AY, AY - (Size - Radius)));
    Result := QX * QX + QY * QY <= Radius * Radius;
  end;

  function Mix(A, B: Word; F: Double): Word;
  begin
    Result := Round(A + (B - A) * F);
  end;

begin
  Img := TFPMemoryImage.Create(Size, Size);
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  try
    Img.UsePalette := False;
    for Y := 0 to Size - 1 do
      for X := 0 to Size - 1 do
      begin
        Inside := 0;
        Ring := 0;
        for SY := 0 to Sub - 1 do
          for SX := 0 to Sub - 1 do
          begin
            PX := X + (SX + 0.5) / Sub;
            PY := Y + (SY + 0.5) / Sub;
            if InSquare(PX, PY) then
            begin
              Inc(Inside);
              { a white ring in the middle }
              DX := PX - Size / 2;
              DY := PY - Size / 2;
              D := Sqrt(DX * DX + DY * DY);
              if (D <= 150) and (D >= 92) then
                Inc(Ring);
            end;
          end;
        if Inside = 0 then
        begin
          Img.Colors[X, Y] := colTransparent;
          Continue;
        end;
        { Pastel's colors: lilac at the top left to sky blue to mint at the bottom right }
        T := (X + Y) / (2 * Size);
        if T < 0.5 then
        begin
          C.Red := Mix($8C00, $5F00, T * 2);
          C.Green := Mix($6A00, $A800, T * 2);
          C.Blue := Mix($F000, $EE00, T * 2);
        end
        else
        begin
          C.Red := Mix($5F00, $3F00, (T - 0.5) * 2);
          C.Green := Mix($A800, $C900, (T - 0.5) * 2);
          C.Blue := Mix($EE00, $A600, (T - 0.5) * 2);
        end;
        { the ring, blended by how much of the pixel it covers }
        C.Red := Mix(C.Red, $FFFF, Ring / Inside);
        C.Green := Mix(C.Green, $FFFF, Ring / Inside);
        C.Blue := Mix(C.Blue, $FFFF, Ring / Inside);
        C.Alpha := Round($FFFF * Inside / (Sub * Sub));
        Img.Colors[X, Y] := C;
      end;
    ForceDirectories(ExtractFileDir(OutFile));
    Img.SaveToFile(OutFile, Writer);
  finally
    Writer.Free;
    Img.Free;
  end;
end;

function WriteIco(const PngFile, IcoFile: string): string;
var
  Src, Img: TFPCustomImage;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
  Pngs: array[0..High(Sizes)] of TMemoryStream;
  Ico: TFileStream;
  I: Integer;
  Offset: DWord;
begin
  Result := '';
  Src := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Writer.UseAlpha := True;
  Writer.WordSized := False;
  for I := 0 to High(Pngs) do
    Pngs[I] := TMemoryStream.Create;
  try
    try
      Src.LoadFromFile(PngFile, Reader);
    except
      on E: Exception do
        Exit(Format('%s is not a PNG picture (%s)', [PngFile, E.Message]));
    end;
    for I := 0 to High(Sizes) do
    begin
      Img := Scaled(Src, Sizes[I]);
      try
        Img.SaveToStream(Pngs[I], Writer);
      finally
        Img.Free;
      end;
    end;
    ForceDirectories(ExtractFileDir(IcoFile));
    Ico := TFileStream.Create(IcoFile, fmCreate);
    try
      Ico.WriteWord(0);
      Ico.WriteWord(NtoLE(Word(1)));
      Ico.WriteWord(NtoLE(Word(Length(Sizes))));
      Offset := 6 + 16 * Length(Sizes);
      for I := 0 to High(Sizes) do
      begin
        Ico.WriteByte(Sizes[I] mod 256);
        Ico.WriteByte(Sizes[I] mod 256);
        Ico.WriteByte(0);
        Ico.WriteByte(0);
        Ico.WriteWord(NtoLE(Word(1)));
        Ico.WriteWord(NtoLE(Word(32)));
        Ico.WriteDWord(NtoLE(DWord(Pngs[I].Size)));
        Ico.WriteDWord(NtoLE(Offset));
        Inc(Offset, Pngs[I].Size);
      end;
      for I := 0 to High(Sizes) do
      begin
        Pngs[I].Position := 0;
        Ico.CopyFrom(Pngs[I], Pngs[I].Size);
      end;
    finally
      Ico.Free;
    end;
  finally
    for I := 0 to High(Pngs) do
      Pngs[I].Free;
    Writer.Free;
    Reader.Free;
    Src.Free;
  end;
end;

end.
