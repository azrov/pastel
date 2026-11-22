{ Tests of TTileView (Pastel.Tiles) and web pictures (Pastel.WebImages). }
unit tiles_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Tiles, Pastel.WebImages, Pastel.Files;

type
  TTilesTests = class(TTestSuite)
  private
    FClicked: Integer;
    procedure Clicked(Sender: TObject);
  published
    procedure ThousandsAreQuick;
    procedure ArrowsMoveAndStopAtTheEdges;
    procedure AClickChooses;
    procedure PicturesComeAndAreSmaller;
  end;

implementation

type
  { the protected KeyDown: whether the view took the key }
  TTileViewAccess = class(TTileView);

procedure TTilesTests.Clicked(Sender: TObject);
begin
  FClicked := TTileView(Sender).ItemIndex;
end;

function NewView(out F: TForm; out C: TCanvas32): TTileView;
begin
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  Result := TTileView.Create(F);
  Result.Parent := F;
  Result.Grow := 1;
  F.Layout(800, 600);
  C.SetSize(800, 600);
end;

procedure TTilesTests.ThousandsAreQuick;
var
  F: TForm;
  C: TCanvas32;
  V: TTileView;
  I: Integer;
  T0: QWord;
begin
  V := NewView(F, C);
  try
    T0 := GetTickCount64;
    for I := 1 to 20000 do
      V.Add('Movie ' + IntToStr(I), '2026', '', I);
    F.Render(C);
    V.ItemIndex := 19990;
    F.Render(C);
    AssertTrue(GetTickCount64 - T0 < 1500, Format('20000 tiles in %d ms', [GetTickCount64 - T0]));
    AssertEquals(20000, V.Count);
    AssertEquals(19991, V.Tiles[19990].Tag);
    V.Style := tsList;
    F.Render(C);
    V.Clear;
    AssertEquals(0, V.Count);
    AssertEquals(-1, V.ItemIndex);
  finally
    C.Free;
    F.Free;
  end;
end;

procedure TTilesTests.ArrowsMoveAndStopAtTheEdges;
var
  F: TForm;
  C: TCanvas32;
  V: TTileView;
  I, N: Integer;
begin
  V := NewView(F, C);
  try
    V.TileWidth := 150;
    for I := 0 to 22 do
      V.Add('T' + IntToStr(I));
    F.Render(C);
    V.SetFocus;
    F.HandleKeyDown(KEY_DOWN, False, False);
    AssertEquals(0, V.ItemIndex, 'the first');
    F.HandleKeyDown(KEY_RIGHT, False, False);
    AssertEquals(1, V.ItemIndex);
    F.HandleKeyDown(KEY_DOWN, False, False);
    N := V.ItemIndex - 1;
    AssertTrue(N >= 3, Format('%d tiles in a row', [N]));
    F.HandleKeyDown(KEY_LEFT, False, False);
    F.HandleKeyDown(KEY_LEFT, False, False);
    AssertEquals(N, V.ItemIndex, 'the row''s first');
    AssertFalse(TTileViewAccess(V).KeyDown(KEY_LEFT, False, False), 'at the left edge: the key is not taken (the remote goes on)');
    V.ItemIndex := 0;
    AssertFalse(TTileViewAccess(V).KeyDown(KEY_UP, False, False), 'at the top');
    F.HandleKeyDown(KEY_END, False, False);
    AssertEquals(22, V.ItemIndex);
    AssertFalse(TTileViewAccess(V).KeyDown(KEY_DOWN, False, False), 'at the bottom');
    V.OnItemClick := @Clicked;
    FClicked := -1;
    F.HandleKeyDown(KEY_ENTER, False, False);
    AssertEquals(22, FClicked, 'Enter');
    V.Style := tsList;
    V.ItemIndex := 3;
    AssertFalse(TTileViewAccess(V).KeyDown(KEY_RIGHT, False, False), 'a list: right goes on');
    F.HandleKeyDown(KEY_DOWN, False, False);
    AssertEquals(4, V.ItemIndex);
  finally
    C.Free;
    F.Free;
  end;
end;

procedure TTilesTests.AClickChooses;
var
  F: TForm;
  C: TCanvas32;
  V: TTileView;
  I: Integer;
begin
  V := NewView(F, C);
  try
    V.Style := tsList;
    V.RowHeight := 50;
    for I := 0 to 99 do
      V.Add('Channel ' + IntToStr(I), 'Now: news');
    V.OnItemClick := @Clicked;
    F.Render(C);
    FClicked := -1;
    F.HandleMouseMove(V.Bounds.X + 100, V.Bounds.Y + 4 + 52 * 2 + 20);
    F.HandleMouseDown(V.Bounds.X + 100, V.Bounds.Y + 4 + 52 * 2 + 20);
    F.HandleMouseUp(V.Bounds.X + 100, V.Bounds.Y + 4 + 52 * 2 + 20);
    AssertEquals(2, FClicked, 'the third row');
    { a drag scrolls, it does not click }
    FClicked := -1;
    F.HandleMouseDown(V.Bounds.X + 100, V.Bounds.Y + 300);
    F.HandleMouseMove(V.Bounds.X + 100, V.Bounds.Y + 200);
    F.HandleMouseUp(V.Bounds.X + 100, V.Bounds.Y + 200);
    AssertEquals(-1, FClicked);
  finally
    C.Free;
    F.Free;
  end;
end;

procedure TTilesTests.PicturesComeAndAreSmaller;
var
  Dir, Png: string;
  B: TBitmap32;
  Big: TCanvas32;
  T0: QWord;
begin
  Dir := MakeTempDir('pastel-tiles');
  WebImageCache := Dir + 'cache';
  Png := Dir + 'poster.png';
  Big := TCanvas32.Create;
  try
    Big.SetSize(600, 900);
    Big.Clear(RGB(200, 30, 30));
    Big.SaveToPNG(Png);
  finally
    Big.Free;
  end;
  AssertTrue(WebImage(Png) = nil, 'not at once: it comes');
  T0 := GetTickCount64;
  repeat
    CheckSynchronize(10);
    B := WebImage(Png);
  until (B <> nil) or (GetTickCount64 - T0 > 5000);
  AssertFalse(WebImageFailed(Png), 'it did not fail');
  AssertTrue(B <> nil, 'it came');
  AssertEquals(240, B.Width, 'made smaller: 360 on the longer side');
  AssertEquals(360, B.Height);
  AssertEquals($FFC81E1E, B.Pixels[100]);
  AssertFalse(WebImageFailed(Png));
  { a file that is not there: failed }
  WebImage(Dir + 'none.png');
  T0 := GetTickCount64;
  repeat
    CheckSynchronize(10);
  until WebImageFailed(Dir + 'none.png') or (GetTickCount64 - T0 > 5000);
  AssertTrue(WebImageFailed(Dir + 'none.png'));
  ClearWebImages;
end;

initialization
  RegisterTests(TTilesTests);

end.
