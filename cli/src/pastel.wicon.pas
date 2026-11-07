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
