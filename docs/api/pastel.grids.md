# Pastel.Grids

Tables and trees.

    object People: TGrid
      Editable = True
      object NameColumn: TGridColumn
        Title = 'Name'
      end
      object AgeColumn: TGridColumn
        Title = 'Age'
        Width = 80
        Alignment = Right
      end
    end

    People.AddRow(['Ayşe', '34']);
    People.LoadJson(Db.Query('select name, age from people', []));   // by Field or Title
    People.Cells[1, 0] := '35';

  Only the rows that show are drawn, so a grid handles many thousands of
  rows. A click on a title sorts by that column; with Editable, F2, Enter,
  a double click or typing edits a cell (OnCellEdit can check the value).
  TListView is a grid for choosing rows, TTreeView a tree of texts:

    object Folders: TTreeView
      Items = ('Documents', '  Letters', '  Bills', 'Pictures')
    end

`uses Pastel.Grids;` · source: [framework/src/pastel.grids.pas](../../framework/src/pastel.grids.pas)

## Types

### TGridColumn

```pascal
type TGridColumn = class(TControl)
```

One column of a TGrid. Width 0 shares the free space.

| | |
|---|---|
| `function Grid: TGrid` |  |
| `property Title: string` |  |
| `property Field: string` | The name of the value in LoadJson (a database column); the Title when empty. |
| `property Alignment: TTextAlign` |  |
| `property ReadOnly: Boolean` |  |

### TGridEditor

```pascal
type TGridEditor = class(TEdit)
```

### TGrid

```pascal
type TGrid = class(TControl)
```

A table of texts with columns.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Font: TPastelFont` |  |
| `function AddColumn(const ATitle: string; AWidth: Integer = 0; AAlignment: TTextAlign = taLeft): TGridColumn` | Adds a column from code. |
| `function AddRow(const Values: array of string): Integer` | Adds a row at the end; returns its index. |
| `procedure InsertRow(Index: Integer; const Values: array of string)` |  |
| `procedure DeleteRow(Index: Integer)` |  |
| `procedure Clear` | Removes all rows (the columns stay). |
| `procedure SortBy(ACol: Integer; Descending: Boolean = False)` | Sorts the rows by a column; numbers as numbers. Row stays on the same data. |
| `procedure LoadJson(Rows: TJSONArray)` | Fills the grid from JSON objects (Db.Query): one row per object, each column takes the value named by its Field (or Title). Without columns, one is made for every name in the first object. Frees nothing. |
| `function ToJson: TJSONArray` | The rows as JSON objects named by Field (or Title); the caller frees it. |
| `function FindRow(ACol: Integer; const Value: string): Integer` | Index of the row whose cell in ACol is Value, -1 when there is none. |
| `procedure MakeVisible(ARow: Integer; ACol: Integer = -1)` |  |
| `procedure EditCell(const Text: string = ''; Replace: Boolean = False)` | Starts editing the current cell; Text replaces the value when given. |
| `function CommitEdit: Boolean` | Ends editing: stores the value (OnCellEdit may refuse it). |
| `procedure CancelEdit` |  |
| `property Cells[ACol: Integer; ARow: Integer]: string` |  |
| `property RowValues[ARow: Integer]: TStringArray` |  |
| `property ColCount: Integer` |  |
| `property Columns[Index: Integer]: TGridColumn` |  |
| `property RowCount: Integer` |  |
| `property Editor: TGridEditor` |  |
| `property Editing: Boolean` | A cell is being edited. |
| `property SortColumn: Integer` | The column the rows are sorted by, -1 when not sorted. |
| `property SortDescending: Boolean` |  |
| `property Row: Integer` | The selected row, -1 for none. |
| `property Col: Integer` | The current column. |
| `property Editable: Boolean` |  |
| `property RowSelect: Boolean` | Whole rows are selected (True), or single cells. |
| `property Sortable: Boolean` | A click on a column title sorts. |
| `property Striped: Boolean` | Every other row slightly darker. |
| `property RowHeight: Integer` | 0: from the font. |
| `property OnChange: TNotifyEvent` | Another row or cell was selected. |
| `property OnDblClick: TNotifyEvent` | A double click or Enter on a row that is not edited. |
| `property OnCellEdit: TGridCellEvent` | A cell was edited: change Value, or set Accept to False to keep editing. |
| `property OnSort: TNotifyEvent` |  |

### TListView

```pascal
type TListView = class(TGrid)
```

A grid for choosing rows: whole rows are selected, nothing is edited.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property RowSelect` |  |

### TTreeNode

```pascal
type TTreeNode = class
```

| | |
|---|---|
| `constructor Create(ATree: TTreeView; AParent: TTreeNode; const AText: string)` |  |
| `destructor Destroy` |  |
| `function AddChild(const AText: string): TTreeNode` |  |
| `procedure Clear` |  |
| `function Level: Integer` | 0 for a top-level node. |
| `function Index: Integer` |  |
| `function HasChildren: Boolean` |  |
| `function Path: string` | 'Documents/Letters' |
| `procedure ExpandAll` | The node and all below it. |
| `property Text: string` |  |
| `property Parent: TTreeNode` |  |
| `property Count: Integer` |  |
| `property Items[AIndex: Integer]: TTreeNode` |  |
| `property Expanded: Boolean` |  |

### TTreeView

```pascal
type TTreeView = class(TControl)
```

A tree of texts that opens and closes.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `function Font: TPastelFont` |  |
| `function Add(const AText: string): TTreeNode` | Adds a top-level node. |
| `procedure Clear` |  |
| `function FindNode(const APath: string): TTreeNode` | The node at 'Documents/Letters', nil when there is none. |
| `procedure FullExpand` |  |
| `procedure FullCollapse` |  |
| `procedure MakeVisible(Node: TTreeNode)` |  |
| `procedure BeginUpdate` | Many changes at once: the rows are rebuilt at EndUpdate. |
| `procedure EndUpdate` |  |
| `property Count: Integer` |  |
| `property TopNodes[AIndex: Integer]: TTreeNode` |  |
| `property Selected: TTreeNode` |  |
| `property Items: TStrings` | The tree as lines; two spaces more for each level. |
| `property Text: string` | The path of the selected node ('Documents/Letters'). |
| `property OnChange: TNotifyEvent` |  |
| `property OnDblClick: TNotifyEvent` | A double click or Enter on a node without children. |
| `property OnExpand: TTreeNodeEvent` | A node opens: fill it now if its children are loaded lazily. |

## Other types

| | |
|---|---|
| `type TGridCellEvent = procedure(Sender: TObject; ACol: Integer; ARow: Integer; Value: string; Accept: Boolean)` |  |
| `type TTreeNodeEvent = procedure(Sender: TObject; Node: TTreeNode)` |  |

