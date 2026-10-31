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

end.
