{ Pastel - icons: small line drawings for buttons, drawn at any size and in
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

  Part of the Pastel project, MIT License. }
unit Pastel.Icons;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics;

{ Draws the icon Name in the square X, Y, Size; False when there is no such icon. }
function DrawIcon(C: TCanvas32; const Name: string; X, Y, Size: Integer; Color: TColor32): Boolean;
{ An icon with this name exists. }
function HasIcon(const Name: string): Boolean;
{ Adds (or replaces) an icon, drawn with the commands above. }
procedure RegisterIcon(const Name, Drawing: string);
{ The names of all icons, sorted. }
function IconNames: TStringArray;

implementation

uses
  Math;

var
  Icons: TStringList = nil;

procedure RegisterIcon(const Name, Drawing: string);
begin
  Icons.Values[LowerCase(Name)] := Drawing;
end;

function HasIcon(const Name: string): Boolean;
begin
  Result := (Name <> '') and (Icons.IndexOfName(LowerCase(Name)) >= 0);
end;

function IconNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Icons.Count);
  for I := 0 to Icons.Count - 1 do
    Result[I] := Icons.Names[I];
end;

function DrawIcon(C: TCanvas32; const Name: string; X, Y, Size: Integer; Color: TColor32): Boolean;
var
  Parts, Words: TStringArray;
  Part: string;
  K: Single;
  Thick: Single;
  I, N: Integer;
  Nums: array of Single;

  function PX(V: Single): Single;
  begin
    Result := X + V * K;
  end;

  function PY(V: Single): Single;
  begin
    Result := Y + V * K;
  end;

  procedure Arc(CX, CY, R, A1, A2: Single);
  var
    J, Steps: Integer;
    T0, T1: Single;
  begin
    Steps := Max(6, Round(Abs(A2 - A1) / 15));
    for J := 0 to Steps - 1 do
    begin
      T0 := DegToRad(A1 + (A2 - A1) * J / Steps);
      T1 := DegToRad(A1 + (A2 - A1) * (J + 1) / Steps);
      C.DrawLine(PX(CX + R * Cos(T0)), PY(CY + R * Sin(T0)), PX(CX + R * Cos(T1)), PY(CY + R * Sin(T1)), Thick, Color);
    end;
  end;

begin
  I := Icons.IndexOfName(LowerCase(Name));
  if (Name = '') or (I < 0) then
    Exit(False);
  Result := True;
  K := Size / 24;
  Thick := Max(1.2, Size / 13);
  Parts := Icons.ValueFromIndex[I].Split([';']);
  for Part in Parts do
  begin
    Words := Trim(Part).Split([' '], TStringSplitOptions.ExcludeEmpty);
    if Length(Words) < 2 then
      Continue;
    SetLength(Nums, Length(Words) - 1);
    for N := 1 to High(Words) do
      Nums[N - 1] := StrToFloatDef(Words[N], 0, DefaultFormatSettings);
    case Words[0] of
      'l':
        for N := 0 to Length(Nums) div 2 - 2 do
          C.DrawLine(PX(Nums[N * 2]), PY(Nums[N * 2 + 1]), PX(Nums[N * 2 + 2]), PY(Nums[N * 2 + 3]), Thick, Color);
      'o':
        if Length(Nums) >= 3 then
          Arc(Nums[0], Nums[1], Nums[2], 0, 360);
      'f':
        if Length(Nums) >= 3 then
          C.FillCircle(PX(Nums[0]), PY(Nums[1]), Nums[2] * K, Color);
      'a':
        if Length(Nums) >= 5 then
          Arc(Nums[0], Nums[1], Nums[2], Nums[3], Nums[4]);
    end;
  end;
end;

procedure AddBuiltIn;
begin
  RegisterIcon('add', 'l 12 5 12 19; l 5 12 19 12');
  RegisterIcon('remove', 'l 5 12 19 12');
  RegisterIcon('close', 'l 6 6 18 18; l 18 6 6 18');
  RegisterIcon('check', 'l 5 12.5 10 17.5 19 7');
  RegisterIcon('file', 'l 14 3 6 3 6 21 18 21 18 7 14 3 14 7 18 7');
  RegisterIcon('folder', 'l 3 6 9 6 11 8 21 8 21 19 3 19 3 6');
  RegisterIcon('save', 'l 4 3 16 3 21 8 21 21 3 21 3 3 4 3; l 7 3 7 8 15 8 15 3; l 7 21 7 14 17 14 17 21');
  RegisterIcon('edit', 'l 4 20 4 16 15 5 19 9 8 20 4 20; l 12.5 7.5 16.5 11.5');
  RegisterIcon('delete', 'l 4 6 20 6; l 9 6 9 3.5 15 3.5 15 6; l 6 6 7 21 17 21 18 6; l 10 10 10 17; l 14 10 14 17');
  RegisterIcon('search', 'o 10.5 10.5 6.5; l 15.5 15.5 20.5 20.5');
  RegisterIcon('refresh', 'a 12 12 7.5 30 300; l 15.75 5.5 19.5 9; l 19.5 4 19.5 9 14.5 9');
  RegisterIcon('print', 'l 7 9 7 3 17 3 17 9; l 7 17 3 17 3 9 21 9 21 17 17 17; l 7 14 17 14 17 21 7 21 7 14');
  RegisterIcon('settings', 'o 12 12 3; o 12 12 7.5; l 12 2 12 4.5; l 12 19.5 12 22; l 2 12 4.5 12; l 19.5 12 22 12; l 4.9 4.9 6.7 6.7; l 17.3 17.3 19.1 19.1; l 4.9 19.1 6.7 17.3; l 17.3 6.7 19.1 4.9');
  RegisterIcon('user', 'o 12 8 4; a 12 21 7.5 180 360');
  RegisterIcon('users', 'o 9 8 3.5; a 9 20 6 180 360; o 17 9 2.5; a 17 19 4.5 210 360');
  RegisterIcon('calendar', 'l 3 5 21 5 21 21 3 21 3 5; l 3 10 21 10; l 8 3 8 7; l 16 3 16 7');
  RegisterIcon('clock', 'o 12 12 9; l 12 7 12 12 15.5 14');
  RegisterIcon('home', 'l 3 11 12 3 21 11; l 5.5 9 5.5 21 18.5 21 18.5 9; l 10 21 10 15 14 15 14 21');
  RegisterIcon('left', 'l 15 5 8 12 15 19');
  RegisterIcon('right', 'l 9 5 16 12 9 19');
  RegisterIcon('up', 'l 5 15 12 8 19 15');
  RegisterIcon('down', 'l 5 9 12 16 19 9');
  RegisterIcon('info', 'o 12 12 9; l 12 11 12 17; f 12 7.5 1.2');
  RegisterIcon('warning', 'l 12 3 22 20 2 20 12 3; l 12 9.5 12 14; f 12 17 1.2');
  RegisterIcon('help', 'o 12 12 9; a 12 9.5 3 180 405; l 14.1 11.6 12 13.5 12 14.5; f 12 17.5 1.2');
  RegisterIcon('copy', 'l 9 8 20 8 20 21 9 21 9 8; l 6 16 4 16 4 3 15 3 15 5');
  RegisterIcon('menu', 'l 4 6 20 6; l 4 12 20 12; l 4 18 20 18');
  RegisterIcon('mail', 'l 3 5 21 5 21 19 3 19 3 5; l 3 6 12 13 21 6');
  RegisterIcon('play', 'l 7 4 19 12 7 20 7 4');
  RegisterIcon('stop', 'l 6 6 18 6 18 18 6 18 6 6');
  RegisterIcon('download', 'l 12 3 12 15; l 7 10 12 15 17 10; l 4 20 20 20');
  RegisterIcon('upload', 'l 12 16 12 4; l 7 9 12 4 17 9; l 4 20 20 20');
  RegisterIcon('star', 'l 12 3 14.6 9 21 9.5 16.2 13.8 17.6 20.5 12 17 6.4 20.5 7.8 13.8 3 9.5 9.4 9 12 3');
  RegisterIcon('lock', 'l 5 11 19 11 19 21 5 21 5 11; l 8 11 8 7; a 12 7 4 180 360; l 16 7 16 11');
  RegisterIcon('link', 'l 10 14 14 10; a 7.5 16.5 3.5 45 225; a 16.5 7.5 3.5 225 405; l 5 14 8 11; l 10 19 13 16; l 11 8 14 5; l 16 13 19 10');
  RegisterIcon('chart', 'l 3 3 3 21 21 21; l 7 17 7 12; l 12 17 12 7; l 17 17 17 10');
  RegisterIcon('money', 'l 2 6 22 6 22 18 2 18 2 6; o 12 12 3; f 6 12 0.9; f 18 12 0.9');
  RegisterIcon('sync', 'a 12 12 7.5 200 340; l 19.5 6 19.5 10 15.5 10; a 12 12 7.5 20 160; l 4.5 18 4.5 14 8.5 14');
end;

initialization
  Icons := TStringList.Create;
  Icons.Sorted := True;
  Icons.Duplicates := dupIgnore;
  AddBuiltIn;

finalization
  Icons.Free;

end.
