# Pastel.Charts

Charts: bars, lines, pies and donuts, drawn by Pastel (the same on
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

`uses Pastel.Charts;` · source: [framework/src/pastel.charts.pas](../../framework/src/pastel.charts.pas)

## Types

### TChartKind

```pascal
type TChartKind = (ckBar, ckLine, ckPie, ckDonut)
```

- `ckBar`
- `ckLine`
- `ckPie`
- `ckDonut`
### TChart

```pascal
type TChart = class(TControl)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Clear` |  |
| `procedure SetLabels(const ALabels: array of string)` |  |
| `function AddSeries(const AName: string; const AValues: array of Double; AColor: TColor32 = 0): Integer` | A series of values, one for each label; its index. Color 0: the next of the chart's colors. |
| `procedure LoadJson(Rows: TJSONArray; const LabelField: string; const ValueFields: array of string)` | Rows of a database or a service: LabelField the labels, each of ValueFields a series. |
| `function SeriesCount: Integer` |  |
| `function SeriesName(Index: Integer): string` |  |
| `property Kind: TChartKind` |  |
| `property Title: string` |  |
| `property Labels: TStrings` | The labels: one a bar group, a point, a slice. |
| `property Data: TStrings` | The series as 'Name=1,2,3' lines (the decimal point a dot). |
| `property ShowLegend: Boolean` |  |
| `property ShowValues: Boolean` | The numbers on the bars, points and slices. |
| `property Stacked: Boolean` | Bars of the series on each other instead of side by side. |
| `property ValueFormat: string` | How numbers look: Format's ('%.1f', '%.0n'); '' writes them short (1,234.5). |
| `property OnItemClick: TChartClickEvent` |  |

## Other types

| | |
|---|---|
| `type TChartClickEvent = procedure(Sender: TObject; SeriesIndex: Integer; ItemIndex: Integer)` | A point (a bar, a slice) was clicked: which series, which label. |

