{ Pastel - minimal FreeType bindings, loaded at run time.
  Only what is needed to render anti-aliased glyphs.
  Part of the Pastel project, MIT License. }
unit Pastel.FreeType;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  dynlibs;

type
  {$if defined(cpu64) and not defined(win64)}
  FT_Long = Int64;
  FT_ULong = QWord;
  {$else}
  FT_Long = LongInt;
  FT_ULong = LongWord;
  {$endif}
  FT_Pos = FT_Long;
  FT_Fixed = FT_Long;
  FT_Error = LongInt;
  FT_UInt = LongWord;
  FT_Int = LongInt;

  FT_Generic = record
    data: Pointer;
    finalizer: Pointer;
  end;

  FT_Vector = record
    x, y: FT_Pos;
  end;

  FT_BBox = record
    xMin, yMin, xMax, yMax: FT_Pos;
  end;

  FT_Glyph_Metrics = record
    width, height: FT_Pos;
    horiBearingX, horiBearingY, horiAdvance: FT_Pos;
    vertBearingX, vertBearingY, vertAdvance: FT_Pos;
  end;

  FT_Bitmap = record
    rows: LongWord;
    width: LongWord;
    pitch: LongInt;
    buffer: PByte;
    num_grays: Word;
    pixel_mode: Byte;
    palette_mode: Byte;
    palette: Pointer;
  end;

  FT_Size_Metrics = record
    x_ppem, y_ppem: Word;
    x_scale, y_scale: FT_Fixed;
    ascender, descender, height, max_advance: FT_Pos;
  end;

  PFT_Face = ^FT_FaceRec;
  PFT_GlyphSlot = ^FT_GlyphSlotRec;
  PFT_Size = ^FT_SizeRec;
  PFT_Library = Pointer;

  FT_SizeRec = record
    face: PFT_Face;
    generic: FT_Generic;
    metrics: FT_Size_Metrics;
  end;

  FT_GlyphSlotRec = record
    library_: PFT_Library;
    face: PFT_Face;
    next: PFT_GlyphSlot;
    glyph_index: FT_UInt;
    generic: FT_Generic;
    metrics: FT_Glyph_Metrics;
    linearHoriAdvance, linearVertAdvance: FT_Fixed;
    advance: FT_Vector;
    format: LongWord;
    bitmap: FT_Bitmap;
    bitmap_left: FT_Int;
    bitmap_top: FT_Int;
  end;

  FT_FaceRec = record
    num_faces, face_index, face_flags, style_flags, num_glyphs: FT_Long;
    family_name, style_name: PChar;
    num_fixed_sizes: FT_Int;
    available_sizes: Pointer;
    num_charmaps: FT_Int;
    charmaps: Pointer;
    generic: FT_Generic;
    bbox: FT_BBox;
    units_per_EM: Word;
    ascender, descender, height: SmallInt;
    max_advance_width, max_advance_height: SmallInt;
    underline_position, underline_thickness: SmallInt;
    glyph: PFT_GlyphSlot;
    size: PFT_Size;
    charmap: Pointer;
  end;

const
  FT_LOAD_RENDER = $4;
  FT_LOAD_TARGET_LIGHT = $10000;
  FT_FACE_FLAG_KERNING = 1 shl 6;
  FT_KERNING_DEFAULT = 0;

var
  FT_Init_FreeType: function(out alibrary: PFT_Library): FT_Error; cdecl;
  FT_New_Face: function(alibrary: PFT_Library; path: PChar; index: FT_Long; out face: PFT_Face): FT_Error; cdecl;
  FT_Done_Face: function(face: PFT_Face): FT_Error; cdecl;
  FT_Set_Pixel_Sizes: function(face: PFT_Face; w, h: FT_UInt): FT_Error; cdecl;
  FT_Get_Char_Index: function(face: PFT_Face; charcode: FT_ULong): FT_UInt; cdecl;
  FT_Load_Glyph: function(face: PFT_Face; index: FT_UInt; flags: LongInt): FT_Error; cdecl;
  FT_Get_Kerning: function(face: PFT_Face; left, right, mode: FT_UInt; out kerning: FT_Vector): FT_Error; cdecl;

{ Loads FreeType. Returns '' on success, otherwise an explanation. }
function LoadFreeType: string;

implementation

var
  LibHandle: TLibHandle = NilHandle;

function LoadFreeType: string;
const
  {$IF defined(WINDOWS)}
  Names: array[0..3] of string = ('freetype.dll', 'libfreetype.dll', 'libfreetype-6.dll', 'freetype6.dll');
  {$ELSEIF defined(DARWIN)}
  Names: array[0..1] of string = ('libfreetype.6.dylib', 'libfreetype.dylib');
  {$ELSE}
  Names: array[0..1] of string = ('libfreetype.so.6', 'libfreetype.so');
  {$ENDIF}
var
  N, Missing: string;

  procedure Bind(var Proc; const Name: string);
  begin
    Pointer(Proc) := GetProcedureAddress(LibHandle, Name);
    if Pointer(Proc) = nil then
      Missing := Missing + ' ' + Name;
  end;

begin
  if LibHandle <> NilHandle then
    Exit('');
  for N in Names do
  begin
    LibHandle := LoadLibrary(N);
    if LibHandle <> NilHandle then
      Break;
  end;
  if LibHandle = NilHandle then
  begin
    {$IF defined(WINDOWS)}
    Exit('freetype.dll was not found. Put it next to the program.');
    {$ELSE}
    Exit('FreeType was not found. Install it with: sudo apt install libfreetype6');
    {$ENDIF}
  end;
  Missing := '';
  Bind(FT_Init_FreeType, 'FT_Init_FreeType');
  Bind(FT_New_Face, 'FT_New_Face');
  Bind(FT_Done_Face, 'FT_Done_Face');
  Bind(FT_Set_Pixel_Sizes, 'FT_Set_Pixel_Sizes');
  Bind(FT_Get_Char_Index, 'FT_Get_Char_Index');
  Bind(FT_Load_Glyph, 'FT_Load_Glyph');
  Bind(FT_Get_Kerning, 'FT_Get_Kerning');
  if Missing <> '' then
    Exit('the installed FreeType is incomplete (missing:' + Missing + ')');
  Result := '';
end;

end.
