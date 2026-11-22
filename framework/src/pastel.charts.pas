{ Pastel - charts: bars, lines, pies and donuts, drawn by Pastel (the same on
  every platform), with a legend, the values on hover, and a click event.

  In a .pform, with data of its own (the designer shows it as it is):
    object Sales: TChart
      Kind = ckBar
      Title = 'Sales'
      Labels = ('Jan', 'Feb', 'Mar')
      Data = ('2025=12,15,9', '2026=14,18,16')
    end

  From code (a database, a service):
    Sales.Clear;
    Sales.SetLabels(['Jan', 'Feb', 'Mar']);
    Sales.AddSeries('2026', [14, 18, 16]);
    Sales.LoadJson(Rows, 'month', ['income', 'costs']);     // one series a field

  Bars and lines show every series; pies and donuts the first one, a slice a label.
  Part of the Pastel project, MIT License. }
unit Pastel.Charts;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.Graphics, Pastel.UI;

type
  TChartKind = (ckBar, ckLine, ckPie, ckDonut);

  { A point (a bar, a slice) was clicked: which series, which label. }
  TChartClickEvent = procedure(Sender: TObject; SeriesIndex, ItemIndex: Integer) of object;

  TChart = class(TControl)
  private
    FKind: TChartKind;
    FTitle, FValueFormat: string;
    FLabels, FData: TStringList;
    FNames: TStringList;
    FValues: array of array of Double;
    FColors: array of TColor32;
    FShowLegend, FShowValues, FStacked: Boolean;
    FMouseX, FMouseY: Integer;
    FOnItemClick: TChartClickEvent;
    FPlot: TRectI;
    FPieCX, FPieCY, FPieR: Single;
    FSample: Boolean;
    procedure DataChanged(Sender: TObject);
    procedure SetKind(AValue: TChartKind);
    procedure SetTitle(const AValue: string);
    procedure SetLabelList(AValue: TStrings);
    procedure SetData(AValue: TStrings);
    function GetLabels: TStrings;
    function GetData: TStrings;
    procedure SetShowLegend(AValue: Boolean);
    procedure SetShowValues(AValue: Boolean);
    procedure SetStacked(AValue: Boolean);
    procedure SetValueFormat(const AValue: string);
    function ItemCount: Integer;
    function Value(S, I: Integer): Double;
    function ColorOf(Index: Integer): TColor32;
    function FormatValue(V: Double): string;
    procedure ValueRange(out Lo, Hi: Double);
    procedure PaintAxes(C: TCanvas32; Lo, Hi, Step: Double);
    procedure PaintBars(C: TCanvas32; Lo, Hi: Double);
    procedure PaintLines(C: TCanvas32; Lo, Hi: Double);
    procedure PaintPie(C: TCanvas32);
    procedure PaintLegend(C: TCanvas32; const R: TRectI);
    procedure PaintTip(C: TCanvas32; const Lines: array of string; X, Y: Integer);
    function LegendHeight(W: Integer): Integer;
    function HotItem: Integer;
    function HotSlice: Integer;
    function YOf(V, Lo, Hi: Double): Integer;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseDown(X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Clear;
    procedure SetLabels(const ALabels: array of string);
    { A series of values, one for each label; its index. Color 0: the next of the chart's colors. }
    function AddSeries(const AName: string; const AValues: array of Double; AColor: TColor32 = 0): Integer;
    { Rows of a database or a service: LabelField the labels, each of ValueFields a series. }
    procedure LoadJson(Rows: TJSONArray; const LabelField: string; const ValueFields: array of string);
    function SeriesCount: Integer;
    function SeriesName(Index: Integer): string;
  published
    property Kind: TChartKind read FKind write SetKind default ckBar;
    property Title: string read FTitle write SetTitle;
    { The labels: one a bar group, a point, a slice. }
    property Labels: TStrings read GetLabels write SetLabelList;
    { The series as 'Name=1,2,3' lines (the decimal point a dot). }
    property Data: TStrings read GetData write SetData;
    property ShowLegend: Boolean read FShowLegend write SetShowLegend default True;
    { The numbers on the bars, points and slices. }
    property ShowValues: Boolean read FShowValues write SetShowValues default False;
    { Bars of the series on each other instead of side by side. }
    property Stacked: Boolean read FStacked write SetStacked default False;
    { How numbers look: Format's ('%.1f', '%.0n'); '' writes them short (1,234.5). }
    property ValueFormat: string read FValueFormat write SetValueFormat;
    property OnItemClick: TChartClickEvent read FOnItemClick write FOnItemClick;
  end;

implementation

uses
  Math;

var
  Dot: TFormatSettings;

{ the chart's colors after the theme's accent: told apart also by people who see colors differently }
function PaletteColor(I: Integer): TColor32;
const
  P: array[0..6] of array[0..2] of Byte = (($10, $B9, $81), ($F5, $9E, $0B), ($EF, $44, $44), ($0E, $A5, $E9),
    ($A8, $55, $F7), ($EC, $48, $99), ($64, $74, $8B));
begin
  if I mod 8 = 0 then
    Result := Theme.Accent
  else
    Result := RGB(P[I mod 8 - 1][0], P[I mod 8 - 1][1], P[I mod 8 - 1][2]);
end;

{ a step for about N lines on the axis: 1, 2 or 5 times a power of ten }
function NiceStep(Range: Double; N: Integer): Double;
var
  Raw, Mag, F: Double;
begin
  if Range <= 0 then
    Exit(1);
  Raw := Range / N;
  Mag := Power(10, Floor(Log10(Raw)));
  F := Raw / Mag;
  if F <= 1 then
    Result := Mag
  else if F <= 2 then
    Result := 2 * Mag
  else if F <= 5 then
    Result := 5 * Mag
  else
    Result := 10 * Mag;
end;

constructor TChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLabels := TStringList.Create;
  FLabels.OnChange := @DataChanged;
  FData := TStringList.Create;
  FData.OnChange := @DataChanged;
  FNames := TStringList.Create;
  FShowLegend := True;
  FMouseX := -1;
end;

destructor TChart.Destroy;
begin
  FLabels.OnChange := nil;
  FData.OnChange := nil;
  FLabels.Free;
  FData.Free;
  FNames.Free;
  inherited Destroy;
end;

{ the series from the Data lines }
procedure TChart.DataChanged(Sender: TObject);
var
  I, J: Integer;
  Parts: TStringArray;
  Line, SName, Vals: string;
begin
  FNames.Clear;
  SetLength(FValues, FData.Count);
  for I := 0 to FData.Count - 1 do
  begin
    Line := FData[I];
    if Pos('=', Line) > 0 then
    begin
      SName := Trim(Copy(Line, 1, Pos('=', Line) - 1));
      Vals := Copy(Line, Pos('=', Line) + 1, MaxInt);
    end
    else
    begin
      SName := Format('Series %d', [I + 1]);
      Vals := Line;
    end;
    FNames.Add(SName);
    Parts := Vals.Split([',', ';']);
    SetLength(FValues[I], Length(Parts));
    for J := 0 to High(Parts) do
      FValues[I][J] := StrToFloatDef(Trim(Parts[J]), 0, Dot);
  end;
  if Length(FColors) < FData.Count then
    SetLength(FColors, FData.Count);
  Changed;
end;

procedure TChart.Clear;
begin
  FLabels.Clear;
  FData.Clear;
  FColors := nil;
end;

procedure TChart.SetLabels(const ALabels: array of string);
var
  S: string;
begin
  FLabels.BeginUpdate;
  try
    FLabels.Clear;
    for S in ALabels do
      FLabels.Add(S);
  finally
    FLabels.EndUpdate;
  end;
end;

function TChart.AddSeries(const AName: string; const AValues: array of Double; AColor: TColor32): Integer;
var
  Line: string;
  I: Integer;
begin
  Line := AName + '=';
  for I := 0 to High(AValues) do
  begin
    if I > 0 then
      Line := Line + ',';
    Line := Line + FloatToStr(AValues[I], Dot);
  end;
  Result := FData.Count;
  SetLength(FColors, Result + 1);
  FColors[Result] := AColor;
  FData.Add(Line);
end;

procedure TChart.LoadJson(Rows: TJSONArray; const LabelField: string; const ValueFields: array of string);
var
  I, F: Integer;
  O: TJSONObject;
  Values: array of Double;
  D: TJSONData;
begin
  Clear;
  if Rows = nil then
    Exit;
  FLabels.BeginUpdate;
  try
    for I := 0 to Rows.Count - 1 do
      if Rows[I] is TJSONObject then
        FLabels.Add(TJSONObject(Rows[I]).Get(LabelField, ''));
  finally
    FLabels.EndUpdate;
  end;
  for F := 0 to High(ValueFields) do
  begin
    Values := nil;
    SetLength(Values, Rows.Count);
    for I := 0 to Rows.Count - 1 do
    begin
      Values[I] := 0;
      if Rows[I] is TJSONObject then
      begin
        O := TJSONObject(Rows[I]);
        D := O.Find(ValueFields[F]);
        if (D <> nil) and (D.JSONType = jtNumber) then
          Values[I] := D.AsFloat
        else if (D <> nil) and (D.JSONType = jtString) then
          Values[I] := StrToFloatDef(D.AsString, 0, Dot);
      end;
    end;
    AddSeries(ValueFields[F], Values);
  end;
end;

function TChart.SeriesCount: Integer;
begin
  Result := Length(FValues);
end;

function TChart.SeriesName(Index: Integer): string;
begin
  Result := FNames[Index];
end;

function TChart.ItemCount: Integer;
var
  S: Integer;
begin
  Result := FLabels.Count;
  for S := 0 to High(FValues) do
    Result := Max(Result, Length(FValues[S]));
end;

function TChart.Value(S, I: Integer): Double;
begin
  if (S <= High(FValues)) and (I <= High(FValues[S])) then
    Result := FValues[S][I]
  else
    Result := 0;
end;

function TChart.ColorOf(Index: Integer): TColor32;
begin
  if (Index <= High(FColors)) and (FColors[Index] <> 0) and not (FKind in [ckPie, ckDonut]) then
    Result := FColors[Index]
  else
    Result := PaletteColor(Index);
end;

function TChart.FormatValue(V: Double): string;
begin
  if FValueFormat <> '' then
    Result := Format(FValueFormat, [V])
  else if Abs(V) >= 1E6 then
    Result := FormatFloat('#,##0.#', V / 1E6) + 'M'
  else if Abs(V) >= 1E4 then
    Result := FormatFloat('#,##0.#', V / 1E3) + 'k'
  else
    Result := FormatFloat('#,##0.##', V);
end;

procedure TChart.ValueRange(out Lo, Hi: Double);
var
  S, I: Integer;
  Sum, Neg: Double;
begin
  Lo := 0;
  Hi := 0;
  for I := 0 to ItemCount - 1 do
    if FStacked and (FKind = ckBar) then
    begin
      Sum := 0;
      Neg := 0;
      for S := 0 to High(FValues) do
        if Value(S, I) >= 0 then
          Sum := Sum + Value(S, I)
        else
          Neg := Neg + Value(S, I);
      Hi := Max(Hi, Sum);
      Lo := Min(Lo, Neg);
    end
    else
      for S := 0 to High(FValues) do
      begin
        Hi := Max(Hi, Value(S, I));
        Lo := Min(Lo, Value(S, I));
      end;
  if Hi = Lo then
    Hi := Lo + 1;
end;

function TChart.YOf(V, Lo, Hi: Double): Integer;
begin
  Result := FPlot.Y + FPlot.H - Round((V - Lo) / (Hi - Lo) * FPlot.H);
end;

procedure TChart.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 320;
  H := 220;
end;

function TChart.LegendHeight(W: Integer): Integer;
var
  F: TPastelFont;
  I, X, N: Integer;
  T: string;
begin
  Result := 0;
  if not FShowLegend then
    Exit;
  F := GetFont(Theme.FontSize - 1);
  if FKind in [ckPie, ckDonut] then
    N := ItemCount
  else
    N := Length(FValues);
  if (N <= 1) and not (FKind in [ckPie, ckDonut]) then
    Exit;
  Result := F.LineHeight + 6;
  X := 0;
  for I := 0 to N - 1 do
  begin
    if FKind in [ckPie, ckDonut] then
    begin
      if I < FLabels.Count then T := FLabels[I] else T := '';
    end
    else
      T := FNames[I];
    if (X > 0) and (X + F.TextWidth(T) + 28 > W) then
    begin
      Inc(Result, F.LineHeight + 4);
      X := 0;
    end;
    Inc(X, F.TextWidth(T) + 28);
  end;
end;

procedure TChart.PaintLegend(C: TCanvas32; const R: TRectI);
var
  F: TPastelFont;
  I, X, Y, N: Integer;
  T: string;
begin
  F := GetFont(Theme.FontSize - 1);
  if FKind in [ckPie, ckDonut] then
    N := ItemCount
  else
    N := Length(FValues);
  X := R.X;
  Y := R.Y + 6;
  for I := 0 to N - 1 do
  begin
    if FKind in [ckPie, ckDonut] then
    begin
      if I < FLabels.Count then T := FLabels[I] else T := '';
    end
    else
      T := FNames[I];
    if (X > R.X) and (X + F.TextWidth(T) + 28 > R.X + R.W) then
    begin
      Inc(Y, F.LineHeight + 4);
      X := R.X;
    end;
    C.FillRoundRect(X, Y + (F.LineHeight - 10) div 2, 10, 10, 3, ColorOf(I));
    C.DrawText(F, X + 15, Y, T, Theme.TextMuted);
    Inc(X, F.TextWidth(T) + 28);
  end;
end;

procedure TChart.PaintAxes(C: TCanvas32; Lo, Hi, Step: Double);
var
  F: TPastelFont;
  V: Double;
  Y, I, Every, X, TW: Integer;
  T: string;
begin
  F := GetFont(Theme.FontSize - 2);
  V := Lo;
  while V <= Hi + Step / 1000 do
  begin
    Y := YOf(V, Lo, Hi);
    if Abs(V) < Step / 1000 then
      C.FillRect(FPlot.X, Y, FPlot.W, 1, Theme.TextMuted)
    else
      C.FillRect(FPlot.X, Y, FPlot.W, 1, WithAlpha(Theme.Border, $A0));
    T := FormatValue(V);
    C.DrawText(F, FPlot.X - 6 - F.TextWidth(T), Y - F.LineHeight div 2, T, Theme.TextMuted);
    V := V + Step;
  end;
  { the labels under the plot: every one when they fit, else every second, third... }
  if ItemCount = 0 then
    Exit;
  TW := 0;
  for I := 0 to FLabels.Count - 1 do
    TW := Max(TW, F.TextWidth(FLabels[I]) + 8);
  Every := Max(1, Ceil(TW * ItemCount / Max(1, FPlot.W)));
  for I := 0 to Min(FLabels.Count, ItemCount) - 1 do
    if I mod Every = 0 then
    begin
      if FKind = ckLine then
        X := FPlot.X + Round((I + 0.5) * FPlot.W / ItemCount)
      else
        X := FPlot.X + Round((I + 0.5) * FPlot.W / ItemCount);
      C.DrawText(F, X - F.TextWidth(FLabels[I]) div 2, FPlot.Y + FPlot.H + 4, FLabels[I], Theme.TextMuted);
    end;
end;

procedure TChart.PaintBars(C: TCanvas32; Lo, Hi: Double);
var
  I, S, N, GroupW, BarW, X, Y0, Y1, Hot: Integer;
  Pos_, Neg: Double;
  Col: TColor32;
  F: TPastelFont;
  T: string;
begin
  N := ItemCount;
  if N = 0 then
    Exit;
  F := GetFont(Theme.FontSize - 2);
  GroupW := FPlot.W div N;
  Hot := HotItem;
  if Hot >= 0 then
    C.FillRect(FPlot.X + Hot * FPlot.W div N, FPlot.Y, GroupW, FPlot.H, WithAlpha(Theme.Accent, $14));
  for I := 0 to N - 1 do
  begin
    X := FPlot.X + I * FPlot.W div N + GroupW * 15 div 100;
    if FStacked then
    begin
      BarW := Max(2, GroupW * 70 div 100);
      Pos_ := 0;
      Neg := 0;
      for S := 0 to High(FValues) do
      begin
        Col := ColorOf(S);
        if Value(S, I) >= 0 then
        begin
          Y0 := YOf(Pos_, Lo, Hi);
          Pos_ := Pos_ + Value(S, I);
          Y1 := YOf(Pos_, Lo, Hi);
        end
        else
        begin
          Y1 := YOf(Neg, Lo, Hi);
          Neg := Neg + Value(S, I);
          Y0 := YOf(Neg, Lo, Hi);
        end;
        C.FillRect(X, Min(Y0, Y1), BarW, Abs(Y0 - Y1), Col);
      end;
      if FShowValues then
      begin
        T := FormatValue(Pos_ + Neg);
        C.DrawText(F, X + (BarW - F.TextWidth(T)) div 2, YOf(Pos_, Lo, Hi) - F.LineHeight - 2, T, Theme.Text);
      end;
    end
    else
    begin
      BarW := Max(2, GroupW * 70 div 100 div Max(1, Length(FValues)));
      for S := 0 to High(FValues) do
      begin
        Y0 := YOf(0, Lo, Hi);
        Y1 := YOf(Value(S, I), Lo, Hi);
        Col := ColorOf(S);
        if Y1 < Y0 then
        begin
          { rounded at the top, square at the bottom }
          C.FillRoundRect(X + S * BarW, Y1, Max(1, BarW - 2), Y0 - Y1, Min(4, BarW div 3), Col);
          C.FillRect(X + S * BarW, Max(Y1, Y0 - 4), Max(1, BarW - 2), Min(4, Y0 - Y1), Col);
        end
        else if Y1 > Y0 then
          C.FillRect(X + S * BarW, Y0, Max(1, BarW - 2), Y1 - Y0, Col);
        if FShowValues then
        begin
          T := FormatValue(Value(S, I));
          if Y1 < Y0 then
            C.DrawText(F, X + S * BarW + (BarW - 2 - F.TextWidth(T)) div 2, Y1 - F.LineHeight - 1, T, Theme.Text)
          else
            C.DrawText(F, X + S * BarW + (BarW - 2 - F.TextWidth(T)) div 2, Y1 + 1, T, Theme.Text);
        end;
      end;
    end;
  end;
  { the zero line again, over the bars' bottoms }
  C.FillRect(FPlot.X, YOf(0, Lo, Hi), FPlot.W, 1, Theme.TextMuted);
end;

procedure TChart.PaintLines(C: TCanvas32; Lo, Hi: Double);
var
  I, S, N, X0, Y0, X1, Y1, Hot: Integer;
  Col: TColor32;
  F: TPastelFont;
  T: string;
begin
  N := ItemCount;
  if N = 0 then
    Exit;
  F := GetFont(Theme.FontSize - 2);
  Y0 := 0;
  Hot := HotItem;
  if Hot >= 0 then
  begin
    X0 := FPlot.X + Round((Hot + 0.5) * FPlot.W / N);
    C.FillRect(X0, FPlot.Y, 1, FPlot.H, WithAlpha(Theme.TextMuted, $80));
  end;
  for S := 0 to High(FValues) do
  begin
    Col := ColorOf(S);
    for I := 0 to N - 1 do
    begin
      X1 := FPlot.X + Round((I + 0.5) * FPlot.W / N);
      Y1 := YOf(Value(S, I), Lo, Hi);
      if I > 0 then
        C.DrawLine(X0, Y0, X1, Y1, 2.5, Col);
      X0 := X1;
      Y0 := Y1;
    end;
    for I := 0 to N - 1 do
    begin
      X1 := FPlot.X + Round((I + 0.5) * FPlot.W / N);
      Y1 := YOf(Value(S, I), Lo, Hi);
      if (I = Hot) or (N <= 24) then
      begin
        C.FillCircle(X1, Y1, IfThen(I = Hot, 5, 3.5), Col);
        C.FillCircle(X1, Y1, IfThen(I = Hot, 2.5, 1.5), Theme.Surface);
      end;
      if FShowValues then
      begin
        T := FormatValue(Value(S, I));
        C.DrawText(F, X1 - F.TextWidth(T) div 2, Y1 - F.LineHeight - 4, T, Theme.Text);
      end;
    end;
  end;
end;

procedure TChart.PaintPie(C: TCanvas32);
var
  I, N, Hot: Integer;
  Total, A, Sweep, Mid, R, Inner: Double;
  F: TPastelFont;
  T: string;
begin
  N := ItemCount;
  Total := 0;
  for I := 0 to N - 1 do
    Total := Total + Max(0, Value(0, I));
  if Total <= 0 then
    Exit;
  F := GetFont(Theme.FontSize - 2);
  FPieCX := FPlot.X + FPlot.W / 2;
  FPieCY := FPlot.Y + FPlot.H / 2;
  FPieR := Min(FPlot.W, FPlot.H) / 2 - 6;
  if FKind = ckDonut then
    Inner := FPieR * 0.58
  else
    Inner := 0;
  Hot := HotSlice;
  A := 0;
  for I := 0 to N - 1 do
  begin
    Sweep := Max(0, Value(0, I)) / Total * 2 * Pi;
    R := FPieR;
    if I = Hot then
      R := FPieR + 5;
    C.FillPie(FPieCX, FPieCY, R, Inner, A, Sweep, ColorOf(I));
    { a thin line between slices }
    if N > 1 then
      C.DrawLine(FPieCX + Inner * Sin(A), FPieCY - Inner * Cos(A), FPieCX + (FPieR + 6) * Sin(A),
        FPieCY - (FPieR + 6) * Cos(A), 1.5, Theme.Surface);
    if FShowValues and (Sweep > 0.25) then
    begin
      Mid := A + Sweep / 2;
      T := FormatFloat('0', Max(0, Value(0, I)) / Total * 100) + '%';
      C.DrawText(F, Round(FPieCX + (Inner + FPieR) / 2 * Sin(Mid)) - F.TextWidth(T) div 2,
        Round(FPieCY - (Inner + FPieR) / 2 * Cos(Mid)) - F.LineHeight div 2, T, RGB($FF, $FF, $FF));
    end;
    A := A + Sweep;
  end;
  if (FKind = ckDonut) and (FNames.Count > 0) then
  begin
    F := GetFont(Theme.FontSize + 2, True);
    T := FormatValue(Total);
    C.DrawText(F, Round(FPieCX) - F.TextWidth(T) div 2, Round(FPieCY) - F.LineHeight div 2, T, Theme.Text);
  end;
end;

{ the label under the mouse (bars, lines), -1 when none }
function TChart.HotItem: Integer;
begin
  Result := -1;
  if not IsHovered or (ItemCount = 0) or FSample then
    Exit;
  if (FMouseX >= FPlot.X) and (FMouseX < FPlot.X + FPlot.W) and (FMouseY >= FPlot.Y) and (FMouseY < FPlot.Y + FPlot.H) then
    Result := EnsureRange((FMouseX - FPlot.X) * ItemCount div Max(1, FPlot.W), 0, ItemCount - 1);
end;

{ the slice under the mouse, -1 when none }
function TChart.HotSlice: Integer;
var
  DX, DY, D, A, Acc, Total: Double;
  I: Integer;
begin
  Result := -1;
  if not IsHovered or (FPieR <= 0) or FSample then
    Exit;
  DX := FMouseX - FPieCX;
  DY := FMouseY - FPieCY;
  D := Sqrt(DX * DX + DY * DY);
  if (D > FPieR + 5) or ((FKind = ckDonut) and (D < FPieR * 0.58)) then
    Exit;
  A := ArcTan2(DX, -DY);
  if A < 0 then
    A := A + 2 * Pi;
  Total := 0;
  for I := 0 to ItemCount - 1 do
    Total := Total + Max(0, Value(0, I));
  if Total <= 0 then
    Exit;
  Acc := 0;
  for I := 0 to ItemCount - 1 do
  begin
    Acc := Acc + Max(0, Value(0, I)) / Total * 2 * Pi;
    if A < Acc then
      Exit(I);
  end;
end;

procedure TChart.PaintTip(C: TCanvas32; const Lines: array of string; X, Y: Integer);
var
  F: TPastelFont;
  I, W, H: Integer;
begin
  F := GetFont(Theme.FontSize - 1);
  W := 0;
  for I := 0 to High(Lines) do
    W := Max(W, F.TextWidth(Lines[I]));
  W := W + 20;
  H := Length(Lines) * F.LineHeight + 12;
  X := X + 12;
  Y := Y - H - 8;
  if X + W > Bounds.X + Bounds.W then
    X := X - W - 24;
  X := Max(Bounds.X, X);
  Y := Max(Bounds.Y, Y);
  C.FillRoundRect(X, Y, W, H, 6, Theme.TooltipBack);
  for I := 0 to High(Lines) do
    C.DrawText(F, X + 10, Y + 6 + I * F.LineHeight, Lines[I], Theme.TooltipText);
end;

procedure TChart.Paint(C: TCanvas32);
var
  F: TPastelFont;
  TopY, LegendH, LeftW, I, S: Integer;
  Lo, Hi, Step: Double;
  Tip: array of string;
  Lbl: string;
begin
  { the designer shows an example while the chart has no data }
  FSample := (Length(FValues) = 0) and (csDesigning in ComponentState);
  if FSample then
  begin
    FData.OnChange := nil;
    FLabels.OnChange := nil;
    FLabels.CommaText := 'Jan,Feb,Mar,Apr,May';
    FData.Text := 'A=12,15,9,14,18' + LineEnding + 'B=8,11,12,10,13';
    DataChanged(nil);
  end;
  try
    C.PushClip(Bounds);
    TopY := Bounds.Y;
    if FTitle <> '' then
    begin
      F := GetFont(Theme.FontSize + 1, True);
      C.DrawText(F, Bounds.X, TopY, FTitle, Theme.Text);
      Inc(TopY, F.LineHeight + 8);
    end;
    LegendH := LegendHeight(Bounds.W);
    F := GetFont(Theme.FontSize - 2);
    if FKind in [ckPie, ckDonut] then
    begin
      FPlot := RectI(Bounds.X, TopY, Bounds.W, Max(0, Bounds.Y + Bounds.H - LegendH - TopY));
      PaintPie(C);
      I := HotSlice;
      if I >= 0 then
      begin
        if I < FLabels.Count then Lbl := FLabels[I] else Lbl := '';
        PaintTip(C, [Lbl, FormatValue(Value(0, I))], FMouseX, FMouseY);
      end;
    end
    else
    begin
      ValueRange(Lo, Hi);
      FPlot.H := Max(20, Bounds.Y + Bounds.H - LegendH - TopY - F.LineHeight - 8);
      Step := NiceStep(Hi - Lo, Max(2, FPlot.H div 40));
      Lo := Floor(Lo / Step) * Step;
      Hi := Ceil(Hi / Step) * Step;
      if Hi <= Lo then
        Hi := Lo + Step;
      LeftW := Max(F.TextWidth(FormatValue(Hi)), F.TextWidth(FormatValue(Lo))) + 10;
      FPlot := RectI(Bounds.X + LeftW, TopY + F.LineHeight div 2, Max(10, Bounds.W - LeftW - 4),
        Max(20, Bounds.Y + Bounds.H - LegendH - TopY - F.LineHeight - 8 - F.LineHeight div 2));
      PaintAxes(C, Lo, Hi, Step);
      if FKind = ckLine then
        PaintLines(C, Lo, Hi)
      else
        PaintBars(C, Lo, Hi);
      I := HotItem;
      if I >= 0 then
      begin
        Tip := nil;
        if I < FLabels.Count then
          Tip := Concat(Tip, [FLabels[I]]);
        for S := 0 to High(FValues) do
          Tip := Concat(Tip, [FNames[S] + ': ' + FormatValue(Value(S, I))]);
        PaintTip(C, Tip, FMouseX, FMouseY);
      end;
    end;
    if LegendH > 0 then
      PaintLegend(C, RectI(Bounds.X, Bounds.Y + Bounds.H - LegendH, Bounds.W, LegendH));
    C.PopClip;
  finally
    if FSample then
    begin
      FData.Clear;
      FLabels.Clear;
      FData.OnChange := @DataChanged;
      FLabels.OnChange := @DataChanged;
      DataChanged(nil);
    end;
  end;
end;

procedure TChart.MouseMove(X, Y: Integer);
begin
  FMouseX := X;
  FMouseY := Y;
  Invalidate;
end;

procedure TChart.MouseDown(X, Y: Integer);
var
  I, S: Integer;
begin
  FMouseX := X;
  FMouseY := Y;
  if not Assigned(FOnItemClick) then
    Exit;
  if FKind in [ckPie, ckDonut] then
  begin
    I := HotSlice;
    if I >= 0 then
      FOnItemClick(Self, 0, I);
    Exit;
  end;
  I := HotItem;
  if I < 0 then
    Exit;
  { the series: by the bar under the mouse (side by side), else the first }
  S := 0;
  if (FKind = ckBar) and not FStacked and (Length(FValues) > 1) then
    S := EnsureRange((X - (FPlot.X + I * FPlot.W div ItemCount + (FPlot.W div ItemCount) * 15 div 100)) div
      Max(1, (FPlot.W div ItemCount) * 70 div 100 div Length(FValues)), 0, High(FValues));
  FOnItemClick(Self, S, I);
end;

procedure TChart.SetKind(AValue: TChartKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  Changed;
end;

procedure TChart.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  Changed;
end;

procedure TChart.SetLabelList(AValue: TStrings);
begin
  FLabels.Assign(AValue);
end;

procedure TChart.SetData(AValue: TStrings);
begin
  FData.Assign(AValue);
end;

function TChart.GetLabels: TStrings;
begin
  Result := FLabels;
end;

function TChart.GetData: TStrings;
begin
  Result := FData;
end;

procedure TChart.SetShowLegend(AValue: Boolean);
begin
  FShowLegend := AValue;
  Changed;
end;

procedure TChart.SetShowValues(AValue: Boolean);
begin
  FShowValues := AValue;
  Changed;
end;

procedure TChart.SetStacked(AValue: Boolean);
begin
  FStacked := AValue;
  Changed;
end;

procedure TChart.SetValueFormat(const AValue: string);
begin
  FValueFormat := AValue;
  Changed;
end;

initialization
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  Dot.ThousandSeparator := #0;
  RegisterControl(TChart);

end.
