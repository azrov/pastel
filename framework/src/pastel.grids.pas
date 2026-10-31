{ Pastel - tables and trees.

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

  Part of the Pastel project, MIT License. }
unit Pastel.Grids;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, Pastel.Graphics, Pastel.UI;

type
  TGrid = class;

  { One column of a TGrid. Width 0 shares the free space. }
  TGridColumn = class(TControl)
  private
    FTitle, FField: string;
    FAlignment: TTextAlign;
    FReadOnly: Boolean;
    procedure SetTitle(const AValue: string);
    procedure SetAlignment(AValue: TTextAlign);
  protected
    procedure Paint(C: TCanvas32); override;
  public
    function Grid: TGrid;
  published
    property Title: string read FTitle write SetTitle;
    { The name of the value in LoadJson (a database column); the Title when empty. }
    property Field: string read FField write FField;
    property Alignment: TTextAlign read FAlignment write SetAlignment default taLeft;
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
  end;

  TGridCellEvent = procedure(Sender: TObject; ACol, ARow: Integer; var Value: string;
    var Accept: Boolean) of object;

  TGridEditor = class(TEdit)
  private
    FGrid: TGrid;
  protected
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure FocusLost; override;
  end;

  { A table of texts with columns. }
  TGrid = class(TControl)
  private
    FData: array of TStringArray;
    FRowCount, FRow, FCol, FTop, FLeft, FHotRow, FRowHeight: Integer;
    FSortCol: Integer;
    FSortDesc, FEditable, FRowSelect, FSortable, FStriped, FEditing: Boolean;
    FEditor: TGridEditor;
    FResizeCol, FResizeX, FResizeW, FDragBar, FDragOffset: Integer;
    FOnChange, FOnDblClick, FOnSort: TNotifyEvent;
    FOnCellEdit: TGridCellEvent;
    function GetCell(ACol, ARow: Integer): string;
    procedure SetCell(ACol, ARow: Integer; const AValue: string);
    procedure SetRowCount(AValue: Integer);
    procedure SetRow(AValue: Integer);
    procedure SetCol(AValue: Integer);
    procedure SetRowHeight(AValue: Integer);
    function GetColCount: Integer;
    function GetColumn(Index: Integer): TGridColumn;
    function GetRowValues(ARow: Integer): TStringArray;
    function ColWidth(ACol: Integer): Integer;
    function ColX(ACol: Integer): Integer;
    function ContentWidth: Integer;
    function ContentHeight: Integer;
    function HeaderHeight: Integer;
    function DataRect: TRectI;
    function RowAt(Y: Integer): Integer;
    function ColAt(X: Integer): Integer;
    function VBarRect: TRectI;
    function HBarRect: TRectI;
    function CellRect(ACol, ARow: Integer): TRectI;
    function CanEdit(ACol: Integer): Boolean;
    procedure ClampScroll;
    procedure Select(ARow, ACol: Integer);
    procedure PlaceEditor;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Arrange(const R: TRectI); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure TextInput(const S: string); override;
  public
    constructor Create(AOwner: TComponent); override;
    function Font: TPastelFont;
    function RowHeightPx: Integer;
    { Adds a column from code. }
    function AddColumn(const ATitle: string; AWidth: Integer = 0; AAlignment: TTextAlign = taLeft): TGridColumn;
    { Adds a row at the end; returns its index. }
    function AddRow(const Values: array of string): Integer;
    procedure InsertRow(Index: Integer; const Values: array of string);
    procedure DeleteRow(Index: Integer);
    { Removes all rows (the columns stay). }
    procedure Clear;
    { Sorts the rows by a column; numbers as numbers. Row stays on the same data. }
    procedure SortBy(ACol: Integer; Descending: Boolean = False);
    { Fills the grid from JSON objects (Db.Query): one row per object, each
      column takes the value named by its Field (or Title). Without columns,
      one is made for every name in the first object. Frees nothing. }
    procedure LoadJson(Rows: TJSONArray);
    { The rows as JSON objects named by Field (or Title); the caller frees it. }
    function ToJson: TJSONArray;
    { Index of the row whose cell in ACol is Value, -1 when there is none. }
    function FindRow(ACol: Integer; const Value: string): Integer;
    procedure MakeVisible(ARow: Integer; ACol: Integer = -1);
    { Starts editing the current cell; Text replaces the value when given. }
    procedure EditCell(const Text: string = ''; Replace: Boolean = False);
    { Ends editing: stores the value (OnCellEdit may refuse it). }
    function CommitEdit: Boolean;
    procedure CancelEdit;
    property Cells[ACol, ARow: Integer]: string read GetCell write SetCell; default;
    property RowValues[ARow: Integer]: TStringArray read GetRowValues;
    property ColCount: Integer read GetColCount;
    property Columns[Index: Integer]: TGridColumn read GetColumn;
    property RowCount: Integer read FRowCount write SetRowCount;
    property Editor: TGridEditor read FEditor;
  published
    { A cell is being edited. }
    property Editing: Boolean read FEditing;
    { The column the rows are sorted by, -1 when not sorted. }
    property SortColumn: Integer read FSortCol;
    property SortDescending: Boolean read FSortDesc;
    { The selected row, -1 for none. }
    property Row: Integer read FRow write SetRow default -1;
    { The current column. }
    property Col: Integer read FCol write SetCol default 0;
    property Editable: Boolean read FEditable write FEditable default False;
    { Whole rows are selected (True), or single cells. }
    property RowSelect: Boolean read FRowSelect write FRowSelect default False;
    { A click on a column title sorts. }
    property Sortable: Boolean read FSortable write FSortable default True;
    { Every other row slightly darker. }
    property Striped: Boolean read FStriped write FStriped default True;
    { 0: from the font. }
    property RowHeight: Integer read FRowHeight write SetRowHeight default 0;
    { Another row or cell was selected. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { A double click or Enter on a row that is not edited. }
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
    { A cell was edited: change Value, or set Accept to False to keep editing. }
    property OnCellEdit: TGridCellEvent read FOnCellEdit write FOnCellEdit;
    property OnSort: TNotifyEvent read FOnSort write FOnSort;
  end;

  { A grid for choosing rows: whole rows are selected, nothing is edited. }
  TListView = class(TGrid)
  public
    constructor Create(AOwner: TComponent); override;
  published
    property RowSelect default True;
  end;

  TTreeView = class;

  TTreeNode = class
  private
    FText: string;
    FParent: TTreeNode;
    FChildren: TFPList;
    FExpanded: Boolean;
    FTree: TTreeView;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TTreeNode;
    procedure SetExpanded(AValue: Boolean);
    procedure SetText(const AValue: string);
  public
    Data: Pointer;
    Tag: PtrInt;
    constructor Create(ATree: TTreeView; AParent: TTreeNode; const AText: string);
    destructor Destroy; override;
    function AddChild(const AText: string): TTreeNode;
    procedure Clear;
    { 0 for a top-level node. }
    function Level: Integer;
    function Index: Integer;
    function HasChildren: Boolean;
    { 'Documents/Letters' }
    function Path: string;
    { The node and all below it. }
    procedure ExpandAll;
    property Text: string read FText write SetText;
    property Parent: TTreeNode read FParent;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TTreeNode read GetItem; default;
    property Expanded: Boolean read FExpanded write SetExpanded;
  end;

  TTreeNodeEvent = procedure(Sender: TObject; Node: TTreeNode) of object;

  { A tree of texts that opens and closes. }
  TTreeView = class(TControl)
  private
    FRoot: TTreeNode;
    FRows: TFPList;
    FRowsValid: Boolean;
    FSelected: TTreeNode;
    FTop, FHotIndex, FUpdating: Integer;
    FDragBar: Boolean;
    FDragOffset: Integer;
    FItems: TStringList;
    FFillingItems: Boolean;
    FOnChange, FOnDblClick: TNotifyEvent;
    FOnExpand: TTreeNodeEvent;
    procedure ItemsEdited(Sender: TObject);
    function GetItems: TStrings;
    procedure SetItems(AValue: TStrings);
    function GetText: string;
    function GetCount: Integer;
    function GetTopNode(AIndex: Integer): TTreeNode;
    procedure SetSelected(AValue: TTreeNode);
    procedure TreeChanged;
    procedure BuildRows;
    function RowCount: Integer;
    function RowNode(I: Integer): TTreeNode;
    function RowHeight: Integer;
    function InnerHeight: Integer;
    function IndexAt(Y: Integer): Integer;
    function BarRect: TRectI;
    procedure ClampTop;
    procedure SelectRow(I: Integer);
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure TextInput(const S: string); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Font: TPastelFont;
    { Adds a top-level node. }
    function Add(const AText: string): TTreeNode;
    procedure Clear;
    { The node at 'Documents/Letters', nil when there is none. }
    function FindNode(const APath: string): TTreeNode;
    procedure FullExpand;
    procedure FullCollapse;
    procedure MakeVisible(Node: TTreeNode);
    { Many changes at once: the rows are rebuilt at EndUpdate. }
    procedure BeginUpdate;
    procedure EndUpdate;
    property Count: Integer read GetCount;
    property TopNodes[AIndex: Integer]: TTreeNode read GetTopNode;
    property Selected: TTreeNode read FSelected write SetSelected;
  published
    { The tree as lines; two spaces more for each level. }
    property Items: TStrings read GetItems write SetItems;
    { The path of the selected node ('Documents/Letters'). }
    property Text: string read GetText;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { A double click or Enter on a node without children. }
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
    { A node opens: fill it now if its children are loaded lazily. }
    property OnExpand: TTreeNodeEvent read FOnExpand write FOnExpand;
  end;

implementation

uses
  StrUtils;

procedure PaintArrow(C: TCanvas32; CX, CY: Integer; Down: Boolean; Col: TColor32);
begin
  if Down then
  begin
    C.DrawLine(CX - 4, CY - 2, CX, CY + 2, 1.6, Col);
    C.DrawLine(CX, CY + 2, CX + 4, CY - 2, 1.6, Col);
  end
  else
  begin
    C.DrawLine(CX - 2, CY - 4, CX + 2, CY, 1.6, Col);
    C.DrawLine(CX + 2, CY, CX - 2, CY + 4, 1.6, Col);
  end;
end;

{ S cut to fit Width, with '…' }
function Fit(F: TPastelFont; const S: string; Width: Integer): string;
var
  I: Integer;
begin
  if F.TextWidth(S) <= Width then
    Exit(S);
  Result := S;
  while Result <> '' do
  begin
    I := PrevCharStart(Result, Length(Result) + 1);
    SetLength(Result, I - 1);
    if F.TextWidth(Result + '…') <= Width then
      Exit(Result + '…');
  end;
end;

{ 'Person 9' before 'Person 10': runs of digits compare as numbers }
function NaturalCompare(const A, B: string): Integer;
var
  I, J, SI, SJ: Integer;
  NA, NB: string;
begin
  I := 1;
  J := 1;
  while (I <= Length(A)) and (J <= Length(B)) do
  begin
    if (A[I] in ['0'..'9']) and (B[J] in ['0'..'9']) then
    begin
      SI := I;
      SJ := J;
      while (I <= Length(A)) and (A[I] in ['0'..'9']) do Inc(I);
      while (J <= Length(B)) and (B[J] in ['0'..'9']) do Inc(J);
      NA := TrimLeftSet(Copy(A, SI, I - SI), ['0']);
      NB := TrimLeftSet(Copy(B, SJ, J - SJ), ['0']);
      if Length(NA) <> Length(NB) then
        Exit(CompareValue(Length(NA), Length(NB)));
      Result := CompareStr(NA, NB);
      if Result <> 0 then
        Exit;
    end
    else
    begin
      SI := I;
      SJ := J;
      while (I <= Length(A)) and not (A[I] in ['0'..'9']) do Inc(I);
      while (J <= Length(B)) and not (B[J] in ['0'..'9']) do Inc(J);
      Result := AnsiCompareText(Copy(A, SI, I - SI), Copy(B, SJ, J - SJ));
      if Result <> 0 then
        Exit;
    end;
  end;
  Result := CompareValue(Length(A) - I, Length(B) - J);
end;

function CompareCells(const A, B: string): Integer;
var
  X, Y: Double;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if TryStrToFloat(StringReplace(Trim(A), ',', '.', []), X, FS) and
    TryStrToFloat(StringReplace(Trim(B), ',', '.', []), Y, FS) then
    Exit(CompareValue(X, Y));
  Result := NaturalCompare(A, B);
  if Result = 0 then
    Result := CompareStr(A, B);
end;

{ ---- TGridColumn ---- }

function TGridColumn.Grid: TGrid;
begin
  if Parent is TGrid then
    Result := TGrid(Parent)
  else
    Result := nil;
end;

procedure TGridColumn.SetTitle(const AValue: string);
begin
  FTitle := AValue;
  Changed;
end;

procedure TGridColumn.SetAlignment(AValue: TTextAlign);
begin
  FAlignment := AValue;
  Invalidate;
end;

procedure TGridColumn.Paint(C: TCanvas32);
begin
  { drawn by the grid }
end;

{ ---- TGridEditor ---- }

function TGridEditor.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  G: TGrid;
begin
  G := FGrid;
  case Key of
    KEY_ESCAPE:
      begin
        G.CancelEdit;
        Exit(True);
      end;
    KEY_ENTER, KEY_KP_ENTER:
      begin
        if G.CommitEdit then
          G.Select(Math.Min(G.FRowCount - 1, G.FRow + IfThen(Shift, -1, 1)), G.FCol);
        Exit(True);
      end;
    KEY_TAB:
      begin
        if G.CommitEdit then
          G.Select(G.FRow, EnsureRange(G.FCol + IfThen(Shift, -1, 1), 0, G.ColCount - 1));
        Exit(True);
      end;
    KEY_UP, KEY_DOWN:
      begin
        if G.CommitEdit then
          G.Select(EnsureRange(G.FRow + IfThen(Key = KEY_UP, -1, 1), 0, G.FRowCount - 1), G.FCol);
        Exit(True);
      end;
  end;
  Result := inherited KeyDown(Key, Shift, Ctrl);
end;

procedure TGridEditor.FocusLost;
begin
  if FGrid.FEditing then
    if not FGrid.CommitEdit then
      FGrid.CancelEdit;
end;

{ ---- TGrid ---- }

constructor TGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRow := -1;
  FHotRow := -1;
  FSortCol := -1;
  FResizeCol := -1;
  FSortable := True;
  FStriped := True;
  FEditor := TGridEditor.Create(Self);
  FEditor.FGrid := Self;
  FEditor.Visible := False;
  FEditor.Parent := Self;
end;

function TGrid.Font: TPastelFont;
begin
  Result := GetFont(Theme.FontSize);
end;

function TGrid.RowHeightPx: Integer;
begin
  if FRowHeight > 0 then
    Result := FRowHeight
  else
    Result := Font.LineHeight + 12;
end;

function TGrid.HeaderHeight: Integer;
begin
  Result := RowHeightPx + 2;
end;

function TGrid.GetColCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ChildCount - 1 do
    if Children[I] is TGridColumn then
      Inc(Result);
end;

function TGrid.GetColumn(Index: Integer): TGridColumn;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to ChildCount - 1 do
    if Children[I] is TGridColumn then
    begin
      if N = Index then
        Exit(TGridColumn(Children[I]));
      Inc(N);
    end;
  raise EListError.CreateFmt('the grid has no column %d', [Index]);
end;

function TGrid.AddColumn(const ATitle: string; AWidth: Integer; AAlignment: TTextAlign): TGridColumn;
begin
  Result := TGridColumn.Create(Self);
  Result.Title := ATitle;
  Result.Width := AWidth;
  Result.Alignment := AAlignment;
  Result.Parent := Self;
  { the editor stays last, above the columns }
  FEditor.Parent := nil;
  FEditor.Parent := Self;
end;

function TGrid.GetCell(ACol, ARow: Integer): string;
begin
  if (ARow < 0) or (ARow >= FRowCount) then
    raise EListError.CreateFmt('the grid has no row %d', [ARow]);
  if (ACol >= 0) and (ACol < Length(FData[ARow])) then
    Result := FData[ARow][ACol]
  else
    Result := '';
end;

procedure TGrid.SetCell(ACol, ARow: Integer; const AValue: string);
begin
  if (ARow < 0) or (ARow >= FRowCount) or (ACol < 0) then
    raise EListError.CreateFmt('the grid has no cell %d, %d', [ACol, ARow]);
  if ACol >= Length(FData[ARow]) then
    SetLength(FData[ARow], ACol + 1);
  FData[ARow][ACol] := AValue;
  Invalidate;
end;

function TGrid.GetRowValues(ARow: Integer): TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, ColCount);
  for I := 0 to High(Result) do
    Result[I] := Cells[I, ARow];
end;

procedure TGrid.SetRowCount(AValue: Integer);
var
  I: Integer;
begin
  AValue := Math.Max(0, AValue);
  if AValue > Length(FData) then
    SetLength(FData, Math.Max(AValue, Length(FData) * 2));
  for I := AValue to FRowCount - 1 do
    FData[I] := nil;
  FRowCount := AValue;
  if FRow >= FRowCount then
    FRow := FRowCount - 1;
  ClampScroll;
  Invalidate;
end;

function TGrid.AddRow(const Values: array of string): Integer;
begin
  InsertRow(FRowCount, Values);
  Result := FRowCount - 1;
end;

procedure TGrid.InsertRow(Index: Integer; const Values: array of string);
var
  I: Integer;
  A: TStringArray;
begin
  Index := EnsureRange(Index, 0, FRowCount);
  A := nil;
  SetLength(A, Length(Values));
  for I := 0 to High(Values) do
    A[I] := Values[I];
  RowCount := FRowCount + 1;
  for I := FRowCount - 1 downto Index + 1 do
    FData[I] := FData[I - 1];
  FData[Index] := A;
  if (FRow >= Index) and (FRow < FRowCount - 1) then
    Inc(FRow);
end;

procedure TGrid.DeleteRow(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index >= FRowCount) then
    Exit;
  if FEditing then
    CancelEdit;
  for I := Index to FRowCount - 2 do
    FData[I] := FData[I + 1];
  FData[FRowCount - 1] := nil;
  Dec(FRowCount);
  if FRow > Index then
    Dec(FRow)
  else if FRow >= FRowCount then
  begin
    FRow := FRowCount - 1;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
  ClampScroll;
  Invalidate;
end;

procedure TGrid.Clear;
begin
  if FEditing then
    CancelEdit;
  FData := nil;
  FRowCount := 0;
  FTop := 0;
  if FRow <> -1 then
  begin
    FRow := -1;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
  Invalidate;
end;

procedure TGrid.SortBy(ACol: Integer; Descending: Boolean);
var
  Idx, Tmp: array of Integer;
  NewData: array of TStringArray;
  I, NewRow: Integer;

  function Less(A, B: Integer): Boolean;
  var
    R: Integer;
    SA, SB: string;
  begin
    SA := Cells[ACol, A];
    SB := Cells[ACol, B];
    if (SA = '') <> (SB = '') then
      Exit(SB = '');                  { empty cells last, both ways }
    R := CompareCells(SA, SB);
    if Descending then
      R := -R;
    Result := (R < 0) or ((R = 0) and (A < B));    { stable }
  end;

  procedure MergeSort(L, R: Integer);
  var
    M, I, J, K: Integer;
  begin
    if R - L < 1 then
      Exit;
    M := (L + R) div 2;
    MergeSort(L, M);
    MergeSort(M + 1, R);
    I := L;
    J := M + 1;
    K := L;
    while (I <= M) and (J <= R) do
    begin
      if Less(Idx[J], Idx[I]) then
      begin
        Tmp[K] := Idx[J];
        Inc(J);
      end
      else
      begin
        Tmp[K] := Idx[I];
        Inc(I);
      end;
      Inc(K);
    end;
    while I <= M do
    begin
      Tmp[K] := Idx[I];
      Inc(I);
      Inc(K);
    end;
    while J <= R do
    begin
      Tmp[K] := Idx[J];
      Inc(J);
      Inc(K);
    end;
    for K := L to R do
      Idx[K] := Tmp[K];
  end;

begin
  if FEditing then
    CommitEdit;
  Idx := nil;
  Tmp := nil;
  NewData := nil;
  SetLength(Idx, FRowCount);
  SetLength(Tmp, FRowCount);
  for I := 0 to FRowCount - 1 do
    Idx[I] := I;
  MergeSort(0, FRowCount - 1);
  SetLength(NewData, Length(FData));
  NewRow := -1;
  for I := 0 to FRowCount - 1 do
  begin
    NewData[I] := FData[Idx[I]];
    if Idx[I] = FRow then
      NewRow := I;
  end;
  FData := NewData;
  FRow := NewRow;
  FSortCol := ACol;
  FSortDesc := Descending;
  if FRow >= 0 then
    MakeVisible(FRow);
  Invalidate;
  if Assigned(FOnSort) then
    FOnSort(Self);
end;

procedure TGrid.LoadJson(Rows: TJSONArray);
var
  I, J: Integer;
  O: TJSONObject;
  D: TJSONData;
  Names: TStringArray;
  Values: TStringArray;
begin
  Clear;
  if (ColCount = 0) and (Rows.Count > 0) and (Rows[0] is TJSONObject) then
  begin
    O := TJSONObject(Rows[0]);
    for J := 0 to O.Count - 1 do
      AddColumn(O.Names[J]).Field := O.Names[J];
  end;
  Names := nil;
  SetLength(Names, ColCount);
  for J := 0 to High(Names) do
  begin
    Names[J] := Columns[J].Field;
    if Names[J] = '' then
      Names[J] := Columns[J].Title;
  end;
  SetLength(FData, Rows.Count);
  Values := nil;
  for I := 0 to Rows.Count - 1 do
  begin
    if not (Rows[I] is TJSONObject) then
      Continue;
    O := TJSONObject(Rows[I]);
    SetLength(Values, Length(Names));
    for J := 0 to High(Names) do
    begin
      D := O.Find(Names[J]);
      if (D = nil) or (D.JSONType = jtNull) then
        Values[J] := ''
      else if D.JSONType in [jtObject, jtArray] then
        Values[J] := D.AsJSON
      else
        Values[J] := D.AsString;
    end;
    FData[FRowCount] := Copy(Values, 0, Length(Values));
    Inc(FRowCount);
  end;
  if FSortCol >= 0 then
    SortBy(FSortCol, FSortDesc);
  ClampScroll;
  Changed;
end;

function TGrid.ToJson: TJSONArray;
var
  I, J: Integer;
  O: TJSONObject;
  N: string;
begin
  Result := TJSONArray.Create;
  for I := 0 to FRowCount - 1 do
  begin
    O := TJSONObject.Create;
    for J := 0 to ColCount - 1 do
    begin
      N := Columns[J].Field;
      if N = '' then
        N := Columns[J].Title;
      O.Add(N, Cells[J, I]);
    end;
    Result.Add(O);
  end;
end;

function TGrid.FindRow(ACol: Integer; const Value: string): Integer;
begin
  for Result := 0 to FRowCount - 1 do
    if Cells[ACol, Result] = Value then
      Exit;
  Result := -1;
end;

function TGrid.ColWidth(ACol: Integer): Integer;
var
  I, Fixed, Auto, Avail: Integer;
  C: TGridColumn;
begin
  C := Columns[ACol];
  if not C.Visible then
    Exit(0);
  if C.Width > 0 then
    Exit(C.Width);
  Fixed := 0;
  Auto := 0;
  for I := 0 to ColCount - 1 do
    if Columns[I].Visible then
      if Columns[I].Width > 0 then
        Inc(Fixed, Columns[I].Width)
      else
        Inc(Auto);
  Avail := Bounds.W - 2 - Fixed;
  Result := Math.Max(80, Avail div Math.Max(1, Auto));
end;

function TGrid.ColX(ACol: Integer): Integer;
var
  I: Integer;
begin
  Result := Bounds.X + 1 - FLeft;
  for I := 0 to ACol - 1 do
    Inc(Result, ColWidth(I));
end;

function TGrid.ContentWidth: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ColCount - 1 do
    Inc(Result, ColWidth(I));
end;

function TGrid.ContentHeight: Integer;
begin
  Result := FRowCount * RowHeightPx;
end;

function TGrid.DataRect: TRectI;
begin
  Result := RectI(Bounds.X + 1, Bounds.Y + 1 + HeaderHeight, Math.Max(0, Bounds.W - 2),
    Math.Max(0, Bounds.H - 2 - HeaderHeight));
end;

procedure TGrid.ClampScroll;
var
  D: TRectI;
begin
  if Bounds.H = 0 then
    Exit;
  D := DataRect;
  FTop := EnsureRange(FTop, 0, Math.Max(0, ContentHeight - D.H));
  FLeft := EnsureRange(FLeft, 0, Math.Max(0, ContentWidth - D.W));
end;

function TGrid.RowAt(Y: Integer): Integer;
var
  D: TRectI;
begin
  D := DataRect;
  if (Y < D.Y) or (Y >= D.Y + D.H) then
    Exit(-1);
  Result := (Y - D.Y + FTop) div RowHeightPx;
  if Result >= FRowCount then
    Result := -1;
end;

function TGrid.ColAt(X: Integer): Integer;
var
  I, CX: Integer;
begin
  CX := Bounds.X + 1 - FLeft;
  for I := 0 to ColCount - 1 do
  begin
    if (X >= CX) and (X < CX + ColWidth(I)) then
      Exit(I);
    Inc(CX, ColWidth(I));
  end;
  Result := -1;
end;

function TGrid.CellRect(ACol, ARow: Integer): TRectI;
var
  D: TRectI;
begin
  D := DataRect;
  Result := RectI(ColX(ACol), D.Y + ARow * RowHeightPx - FTop, ColWidth(ACol), RowHeightPx);
end;

function TGrid.VBarRect: TRectI;
var
  D: TRectI;
  Len, Pos: Integer;
begin
  D := DataRect;
  if ContentHeight <= D.H then
    Exit(RectI(0, 0, 0, 0));
  Len := Math.Max(24, D.H * D.H div ContentHeight);
  Pos := (D.H - Len) * FTop div Math.Max(1, ContentHeight - D.H);
  Result := RectI(D.X + D.W - 8, D.Y + Pos, 6, Len);
end;

function TGrid.HBarRect: TRectI;
var
  D: TRectI;
  Len, Pos: Integer;
begin
  D := DataRect;
  if ContentWidth <= D.W then
    Exit(RectI(0, 0, 0, 0));
  Len := Math.Max(24, D.W * D.W div ContentWidth);
  Pos := (D.W - Len) * FLeft div Math.Max(1, ContentWidth - D.W);
  Result := RectI(D.X + Pos, D.Y + D.H - 8, Len, 6);
end;

procedure TGrid.MakeVisible(ARow: Integer; ACol: Integer);
var
  D: TRectI;
  Y, X, W: Integer;
begin
  if Bounds.H = 0 then
    Exit;
  D := DataRect;
  if ARow >= 0 then
  begin
    Y := ARow * RowHeightPx;
    if Y < FTop then
      FTop := Y;
    if Y + RowHeightPx > FTop + D.H then
      FTop := Y + RowHeightPx - D.H;
  end;
  if (ACol >= 0) and (ACol < ColCount) then
  begin
    X := ColX(ACol) + FLeft - D.X;
    W := ColWidth(ACol);
    if X < FLeft then
      FLeft := X;
    if X + W > FLeft + D.W then
      FLeft := X + W - D.W;
  end;
  ClampScroll;
  PlaceEditor;
  Invalidate;
end;

procedure TGrid.Select(ARow, ACol: Integer);
var
  Moved: Boolean;
begin
  ARow := EnsureRange(ARow, -1, FRowCount - 1);
  ACol := EnsureRange(ACol, 0, Math.Max(0, ColCount - 1));
  Moved := (ARow <> FRow) or (ACol <> FCol);
  FRow := ARow;
  FCol := ACol;
  MakeVisible(FRow, IfThen(FRowSelect, -1, FCol));
  Invalidate;
  if Moved and Assigned(FOnChange) and not (csLoading in ComponentState) then
    FOnChange(Self);
end;

procedure TGrid.SetRow(AValue: Integer);
begin
  if FEditing then
    CommitEdit;
  Select(AValue, FCol);
end;

procedure TGrid.SetCol(AValue: Integer);
begin
  if FEditing then
    CommitEdit;
  if ColCount = 0 then
    FCol := Math.Max(0, AValue)
  else
    Select(FRow, AValue);
end;

procedure TGrid.SetRowHeight(AValue: Integer);
begin
  FRowHeight := Math.Max(0, AValue);
  Changed;
end;

function TGrid.CanEdit(ACol: Integer): Boolean;
begin
  Result := FEditable and Enabled and (ACol >= 0) and (ACol < ColCount) and not Columns[ACol].ReadOnly;
end;

procedure TGrid.PlaceEditor;
var
  R: TRectI;
begin
  if not FEditing then
    Exit;
  R := CellRect(FCol, FRow);
  FEditor.Arrange(RectI(R.X, R.Y, R.W, R.H));
end;

procedure TGrid.EditCell(const Text: string; Replace: Boolean);
begin
  if (FRow < 0) or not CanEdit(FCol) then
    Exit;
  MakeVisible(FRow, FCol);
  FEditing := True;
  if Replace then
  begin
    FEditor.Text := '';
    FEditor.Visible := True;
    FEditor.SetFocus;
    FEditor.TextInput(Text);
  end
  else
  begin
    FEditor.Text := Cells[FCol, FRow];
    FEditor.Visible := True;
    FEditor.SetFocus;
    FEditor.SelectAll;
  end;
  PlaceEditor;
  Changed;
end;

function TGrid.CommitEdit: Boolean;
var
  Value: string;
  Accept: Boolean;
begin
  Result := True;
  if not FEditing then
    Exit;
  Value := FEditor.Text;
  Accept := True;
  if Assigned(FOnCellEdit) then
    FOnCellEdit(Self, FCol, FRow, Value, Accept);
  if not Accept then
  begin
    if not FEditor.IsFocused then
      FEditor.SetFocus;
    Exit(False);
  end;
  FEditing := False;
  Cells[FCol, FRow] := Value;
  FEditor.Visible := False;
  if FEditor.IsFocused then
    SetFocus;
  Changed;
end;

procedure TGrid.CancelEdit;
begin
  if not FEditing then
    Exit;
  FEditing := False;
  FEditor.Visible := False;
  if FEditor.IsFocused then
    SetFocus;
  Changed;
end;

procedure TGrid.Measure(AvailWidth: Integer; out W, H: Integer);
var
  I: Integer;
begin
  W := 0;
  for I := 0 to ColCount - 1 do
    if Columns[I].Visible then
      Inc(W, Math.Max(Columns[I].Width, 100));
  W := Math.Max(300, W + 2);
  H := HeaderHeight + 8 * RowHeightPx + 2;
end;

procedure TGrid.Arrange(const R: TRectI);
begin
  inherited Arrange(R);
  ClampScroll;
  PlaceEditor;
end;

procedure TGrid.Paint(C: TCanvas32);
var
  F, FB: TPastelFont;
  D, Bar: TRectI;
  I, J, First, Last, Y, X, W, RH, TX: Integer;
  Border, Fg, Bg: TColor32;
  S: string;
  GC: TGridColumn;
  Focus: Boolean;
begin
  F := Font;
  FB := GetFont(Theme.FontSize, True);
  RH := RowHeightPx;
  ClampScroll;
  Focus := IsFocused or FEditor.IsFocused;
  if IsFocused then
  begin
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6, Theme.Radius + 3, Theme.FocusRing);
    Border := Theme.Accent;
  end
  else
    Border := Theme.Border;
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);
  C.PushClip(RectI(Bounds.X + 1, Bounds.Y + 1, Bounds.W - 2, Bounds.H - 2));
  D := DataRect;
  { titles }
  C.FillRect(Bounds.X + 1, Bounds.Y + 1, Bounds.W - 2, HeaderHeight, Theme.Secondary);
  C.FillRect(Bounds.X + 1, D.Y - 1, Bounds.W - 2, 1, Theme.Border);
  X := Bounds.X + 1 - FLeft;
  for J := 0 to ColCount - 1 do
  begin
    W := ColWidth(J);
    if W = 0 then
      Continue;
    GC := Columns[J];
    S := Fit(FB, GC.Title, W - 16 - IfThen(J = FSortCol, 14, 0));
    case GC.Alignment of
      taRight: TX := X + W - 8 - FB.TextWidth(S) - IfThen(J = FSortCol, 14, 0);
      taCenter: TX := X + (W - FB.TextWidth(S)) div 2;
    else
      TX := X + 8;
    end;
    C.DrawText(FB, TX, Bounds.Y + 1 + (HeaderHeight - FB.LineHeight) div 2, S, Theme.Text);
    if J = FSortCol then
      if FSortDesc then
        PaintArrow(C, TX + FB.TextWidth(S) + 10, Bounds.Y + 1 + HeaderHeight div 2, True, Theme.TextMuted)
      else
      begin
        C.DrawLine(TX + FB.TextWidth(S) + 6, Bounds.Y + 3 + HeaderHeight div 2, TX + FB.TextWidth(S) + 10,
          Bounds.Y - 1 + HeaderHeight div 2, 1.6, Theme.TextMuted);
        C.DrawLine(TX + FB.TextWidth(S) + 10, Bounds.Y - 1 + HeaderHeight div 2, TX + FB.TextWidth(S) + 14,
          Bounds.Y + 3 + HeaderHeight div 2, 1.6, Theme.TextMuted);
      end;
    C.FillRect(X + W - 1, Bounds.Y + 1, 1, HeaderHeight, Theme.Border);
    Inc(X, W);
  end;
  { rows }
  C.PushClip(D);
  if FRowCount > 0 then
  begin
    First := FTop div RH;
    Last := Math.Min(FRowCount - 1, (FTop + D.H) div RH);
    for I := First to Last do
    begin
      Y := D.Y + I * RH - FTop;
      Bg := 0;
      if I = FRow then
        if FRowSelect and Focus then
          Bg := Theme.Accent
        else
          Bg := WithAlpha(Theme.Accent, $28)
      else if (I = FHotRow) and Enabled then
        Bg := Theme.SecondaryHover
      else if FStriped and Odd(I) then
        Bg := WithAlpha(Theme.Secondary, $A0);
      if Bg <> 0 then
        C.FillRect(D.X, Y, D.W, RH, Bg);
      X := Bounds.X + 1 - FLeft;
      for J := 0 to ColCount - 1 do
      begin
        W := ColWidth(J);
        if W = 0 then
          Continue;
        if (X + W >= D.X) and (X < D.X + D.W) then
        begin
          Fg := Theme.Text;
          if (I = FRow) and FRowSelect and Focus then
            Fg := Theme.OnAccent
          else if not Enabled then
            Fg := Theme.Disabled;
          S := Fit(F, Cells[J, I], W - 16);
          case Columns[J].Alignment of
            taRight: TX := X + W - 8 - F.TextWidth(S);
            taCenter: TX := X + (W - F.TextWidth(S)) div 2;
          else
            TX := X + 8;
          end;
          C.DrawText(F, TX, Y + (RH - F.LineHeight) div 2, S, Fg);
          if (I = FRow) and (J = FCol) and not FRowSelect and not FEditing then
            C.StrokeRoundRect(X + 1, Y + 1, W - 2, RH - 2, 3, 2, IfThen(Focus, Theme.Accent, Theme.BorderHover));
        end;
        C.FillRect(X + W - 1, Y, 1, RH, WithAlpha(Theme.Border, $80));
        Inc(X, W);
      end;
    end;
  end;
  PaintChildren(C);       { the editor }
  C.PopClip;
  Bar := VBarRect;
  if Bar.H > 0 then
    C.FillRoundRect(Bar.X, Bar.Y, Bar.W, Bar.H, 3, WithAlpha(Theme.TextMuted, $90));
  Bar := HBarRect;
  if Bar.W > 0 then
    C.FillRoundRect(Bar.X, Bar.Y, Bar.W, Bar.H, 3, WithAlpha(Theme.TextMuted, $90));
  C.PopClip;
  C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Border);
end;

function TGrid.Focusable: Boolean;
begin
  Result := Enabled;
end;

procedure TGrid.MouseDown(X, Y: Integer);
var
  Bar, D: TRectI;
  R, C, I, Edge: Integer;
  F: TForm;
begin
  if FEditing and not CommitEdit then
    Exit;
  D := DataRect;
  Bar := VBarRect;
  if (Bar.H > 0) and (X >= Bar.X - 4) and (Y >= D.Y) then
  begin
    FDragBar := 1;
    if (Y >= Bar.Y) and (Y < Bar.Y + Bar.H) then FDragOffset := Y - Bar.Y else FDragOffset := Bar.H div 2;
    MouseMove(X, Y);
    Exit;
  end;
  Bar := HBarRect;
  if (Bar.W > 0) and (Y >= Bar.Y - 4) then
  begin
    FDragBar := 2;
    if (X >= Bar.X) and (X < Bar.X + Bar.W) then FDragOffset := X - Bar.X else FDragOffset := Bar.W div 2;
    MouseMove(X, Y);
    Exit;
  end;
  if Y < D.Y then
  begin
    { a title: the edge between two resizes, elsewhere it sorts }
    Edge := Bounds.X + 1 - FLeft;
    for I := 0 to ColCount - 1 do
    begin
      Inc(Edge, ColWidth(I));
      if (ColWidth(I) > 0) and (Abs(X - Edge) <= 4) then
      begin
        FResizeCol := I;
        FResizeX := X;
        FResizeW := ColWidth(I);
        Exit;
      end;
    end;
    C := ColAt(X);
    if (C >= 0) and FSortable then
      SortBy(C, (C = FSortCol) and not FSortDesc);
    Exit;
  end;
  R := RowAt(Y);
  C := ColAt(X);
  if R < 0 then
    Exit;
  if C < 0 then
    C := FCol;
  Select(R, C);
  F := ParentForm;
  if (F <> nil) and (F.ClickCount = 2) then
    if CanEdit(FCol) and not FRowSelect then
      EditCell
    else if Assigned(FOnDblClick) then
      FOnDblClick(Self);
end;

procedure TGrid.MouseMove(X, Y: Integer);
var
  D, Bar: TRectI;
  R: Integer;
  F: TForm;
begin
  F := ParentForm;
  if (F <> nil) and (F.Captured = Self) then
  begin
    D := DataRect;
    if FResizeCol >= 0 then
    begin
      Columns[FResizeCol].Width := Math.Max(32, FResizeW + X - FResizeX);
      Exit;
    end;
    if FDragBar = 1 then
    begin
      Bar := VBarRect;
      FTop := (Y - FDragOffset - D.Y) * Math.Max(1, ContentHeight - D.H) div Math.Max(1, D.H - Bar.H);
      ClampScroll;
      PlaceEditor;
      Invalidate;
      Exit;
    end;
    if FDragBar = 2 then
    begin
      Bar := HBarRect;
      FLeft := (X - FDragOffset - D.X) * Math.Max(1, ContentWidth - D.W) div Math.Max(1, D.W - Bar.W);
      ClampScroll;
      PlaceEditor;
      Invalidate;
      Exit;
    end;
  end;
  R := RowAt(Y);
  if R <> FHotRow then
  begin
    FHotRow := R;
    Invalidate;
  end;
end;

procedure TGrid.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  FDragBar := 0;
  FResizeCol := -1;
  if not Inside and (FHotRow >= 0) then
  begin
    FHotRow := -1;
    Invalidate;
  end;
end;

function TGrid.MouseWheel(DX, DY: Integer): Boolean;
var
  D: TRectI;
  OldTop, OldLeft: Integer;
begin
  D := DataRect;
  OldTop := FTop;
  OldLeft := FLeft;
  Dec(FTop, DY * RowHeightPx * 3);
  Inc(FLeft, DX * 40);
  ClampScroll;
  Result := (FTop <> OldTop) or (FLeft <> OldLeft) or (ContentHeight > D.H);
  PlaceEditor;
  Invalidate;
end;

function TGrid.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  Page, R: Integer;
  S: string;
begin
  Result := True;
  Page := Math.Max(1, DataRect.H div RowHeightPx - 1);
  R := Math.Max(FRow, 0);
  case Key of
    KEY_UP: Select(Math.Max(0, FRow - 1), FCol);
    KEY_DOWN: Select(Math.Min(FRowCount - 1, FRow + 1), FCol);
    KEY_PAGEUP: Select(Math.Max(0, R - Page), FCol);
    KEY_PAGEDOWN: Select(Math.Min(FRowCount - 1, R + Page), FCol);
    KEY_LEFT:
      if FRowSelect then
        MouseWheel(-1, 0)
      else
        Select(R, FCol - 1);
    KEY_RIGHT:
      if FRowSelect then
        MouseWheel(1, 0)
      else
        Select(R, FCol + 1);
    KEY_HOME:
      if Ctrl or FRowSelect then Select(0, FCol) else Select(R, 0);
    KEY_END:
      if Ctrl or FRowSelect then Select(FRowCount - 1, FCol) else Select(R, ColCount - 1);
    KEY_TAB:
      if FRowSelect or (ColCount = 0) or (Shift and (FCol = 0)) or (not Shift and (FCol = ColCount - 1)) then
        Result := False
      else
        Select(R, FCol + IfThen(Shift, -1, 1));
    KEY_F1 + 1:
      EditCell;
    KEY_ENTER, KEY_KP_ENTER:
      if (FRow >= 0) and CanEdit(FCol) and not FRowSelect then
        EditCell
      else if (FRow >= 0) and Assigned(FOnDblClick) then
        FOnDblClick(Self)
      else
        Result := False;
  else
    if Ctrl and (Key = Ord('c')) and (FRow >= 0) and Assigned(ClipboardSetText) then
    begin
      if FRowSelect then
        S := string.Join(#9, RowValues[FRow])
      else
        S := Cells[FCol, FRow];
      ClipboardSetText(S);
    end
    else
      Result := False;
  end;
end;

procedure TGrid.TextInput(const S: string);
var
  I, J: Integer;
begin
  if (S = '') or (FRowCount = 0) then
    Exit;
  if (FRow >= 0) and CanEdit(FCol) and not FRowSelect then
  begin
    EditCell(S, True);
    Exit;
  end;
  { not editable: jump to the next row that starts with it }
  for J := 1 to FRowCount do
  begin
    I := (Math.Max(FRow, -1) + J) mod FRowCount;
    if AnsiStartsText(S, Cells[FCol, I]) then
    begin
      Select(I, FCol);
      Exit;
    end;
  end;
end;

{ ---- TListView ---- }

constructor TListView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRowSelect := True;
end;

{ ---- TTreeNode ---- }

constructor TTreeNode.Create(ATree: TTreeView; AParent: TTreeNode; const AText: string);
begin
  inherited Create;
  FTree := ATree;
  FParent := AParent;
  FText := AText;
  FChildren := TFPList.Create;
end;

destructor TTreeNode.Destroy;
begin
  Clear;
  FChildren.Free;
  inherited Destroy;
end;

procedure TTreeNode.Clear;
var
  I: Integer;
begin
  for I := FChildren.Count - 1 downto 0 do
  begin
    if (FTree <> nil) and (FTree.FSelected = TTreeNode(FChildren[I])) then
      FTree.FSelected := nil;
    TTreeNode(FChildren[I]).Free;
  end;
  FChildren.Clear;
  if FTree <> nil then
    FTree.TreeChanged;
end;

function TTreeNode.GetCount: Integer;
begin
  Result := FChildren.Count;
end;

function TTreeNode.GetItem(AIndex: Integer): TTreeNode;
begin
  Result := TTreeNode(FChildren[AIndex]);
end;

function TTreeNode.AddChild(const AText: string): TTreeNode;
begin
  Result := TTreeNode.Create(FTree, Self, AText);
  FChildren.Add(Result);
  if FTree <> nil then
    FTree.TreeChanged;
end;

function TTreeNode.Level: Integer;
var
  N: TTreeNode;
begin
  Result := -1;
  N := FParent;
  while N <> nil do
  begin
    Inc(Result);
    N := N.FParent;
  end;
end;

function TTreeNode.Index: Integer;
begin
  if FParent = nil then
    Result := 0
  else
    Result := FParent.FChildren.IndexOf(Self);
end;

function TTreeNode.HasChildren: Boolean;
begin
  Result := FChildren.Count > 0;
end;

function TTreeNode.Path: string;
begin
  Result := FText;
  if (FParent <> nil) and (FParent.FParent <> nil) then
    Result := FParent.Path + '/' + Result;
end;

procedure TTreeNode.SetExpanded(AValue: Boolean);
begin
  if FExpanded = AValue then
    Exit;
  FExpanded := AValue;
  if AValue and (FTree <> nil) and Assigned(FTree.FOnExpand) then
    FTree.FOnExpand(FTree, Self);
  if FTree <> nil then
    FTree.TreeChanged;
end;

procedure TTreeNode.SetText(const AValue: string);
begin
  FText := AValue;
  if FTree <> nil then
    FTree.Invalidate;
end;

procedure TTreeNode.ExpandAll;
var
  I: Integer;
begin
  if HasChildren then
    Expanded := True;
  for I := 0 to Count - 1 do
    Items[I].ExpandAll;
end;

{ ---- TTreeView ---- }

constructor TTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRoot := TTreeNode.Create(Self, nil, '');
  FRoot.FExpanded := True;
  FRows := TFPList.Create;
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsEdited;
  FHotIndex := -1;
end;

destructor TTreeView.Destroy;
begin
  FRoot.FTree := nil;
  FreeAndNil(FRoot);
  FRows.Free;
  FItems.OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

function TTreeView.Font: TPastelFont;
begin
  Result := GetFont(Theme.FontSize);
end;

procedure TTreeView.TreeChanged;
begin
  FRowsValid := False;
  if FUpdating = 0 then
    Changed;
end;

procedure TTreeView.BeginUpdate;
begin
  Inc(FUpdating);
end;

procedure TTreeView.EndUpdate;
begin
  Dec(FUpdating);
  if FUpdating = 0 then
    TreeChanged;
end;

procedure TTreeView.BuildRows;

  procedure AddNodes(N: TTreeNode);
  var
    I: Integer;
  begin
    for I := 0 to N.Count - 1 do
    begin
      FRows.Add(N.Items[I]);
      if N.Items[I].Expanded then
        AddNodes(N.Items[I]);
    end;
  end;

begin
  if FRowsValid then
    Exit;
  FRows.Clear;
  AddNodes(FRoot);
  FRowsValid := True;
end;

function TTreeView.RowCount: Integer;
begin
  BuildRows;
  Result := FRows.Count;
end;

function TTreeView.RowNode(I: Integer): TTreeNode;
begin
  BuildRows;
  if (I >= 0) and (I < FRows.Count) then
    Result := TTreeNode(FRows[I])
  else
    Result := nil;
end;

function TTreeView.Add(const AText: string): TTreeNode;
begin
  Result := FRoot.AddChild(AText);
end;

procedure TTreeView.Clear;
begin
  FSelected := nil;
  FTop := 0;
  FRoot.Clear;
end;

function TTreeView.GetCount: Integer;
begin
  Result := FRoot.Count;
end;

function TTreeView.GetTopNode(AIndex: Integer): TTreeNode;
begin
  Result := FRoot.Items[AIndex];
end;

function TTreeView.FindNode(const APath: string): TTreeNode;
var
  Parts: TStringArray;
  P: string;
  N, Found: TTreeNode;
  I: Integer;
begin
  Parts := APath.Split(['/']);
  N := FRoot;
  for P in Parts do
  begin
    Found := nil;
    for I := 0 to N.Count - 1 do
      if N.Items[I].Text = P then
      begin
        Found := N.Items[I];
        Break;
      end;
    if Found = nil then
      Exit(nil);
    N := Found;
  end;
  if N = FRoot then
    Result := nil
  else
    Result := N;
end;

procedure TTreeView.FullExpand;
begin
  BeginUpdate;
  try
    FRoot.ExpandAll;
  finally
    EndUpdate;
  end;
end;

procedure TTreeView.FullCollapse;

  procedure CollapseAll(N: TTreeNode);
  var
    I: Integer;
  begin
    for I := 0 to N.Count - 1 do
    begin
      N.Items[I].FExpanded := False;
      CollapseAll(N.Items[I]);
    end;
  end;

begin
  CollapseAll(FRoot);
  TreeChanged;
end;

function TTreeView.GetItems: TStrings;

  procedure AddNodes(N: TTreeNode; const Indent: string);
  var
    I: Integer;
  begin
    for I := 0 to N.Count - 1 do
    begin
      FItems.Add(Indent + N.Items[I].Text);
      AddNodes(N.Items[I], Indent + '  ');
    end;
  end;

begin
  FFillingItems := True;
  try
    FItems.Clear;
    AddNodes(FRoot, '');
  finally
    FFillingItems := False;
  end;
  Result := FItems;
end;

{ Items changed from outside (a .pform list, Items.Add): the tree follows }
procedure TTreeView.ItemsEdited(Sender: TObject);
var
  L: TStringList;
begin
  if FFillingItems then
    Exit;
  L := TStringList.Create;
  try
    L.Assign(FItems);
    SetItems(L);
  finally
    L.Free;
  end;
end;

procedure TTreeView.SetItems(AValue: TStrings);
var
  Stack: array of TTreeNode;
  Levels: array of Integer;
  I, Depth, Lv: Integer;
  S: string;
  N: TTreeNode;
begin
  BeginUpdate;
  try
    Clear;
    Stack := nil;
    Levels := nil;
    for I := 0 to AValue.Count - 1 do
    begin
      S := AValue[I];
      if Trim(S) = '' then
        Continue;
      Lv := 0;
      while (Lv < Length(S)) and (S[Lv + 1] = ' ') do
        Inc(Lv);
      { the parent: the last node with less indentation }
      Depth := Length(Stack);
      while (Depth > 0) and (Levels[Depth - 1] >= Lv) do
        Dec(Depth);
      if Depth = 0 then
        N := FRoot.AddChild(Trim(S))
      else
        N := Stack[Depth - 1].AddChild(Trim(S));
      SetLength(Stack, Depth + 1);
      SetLength(Levels, Depth + 1);
      Stack[Depth] := N;
      Levels[Depth] := Lv;
    end;
  finally
    EndUpdate;
  end;
end;

function TTreeView.GetText: string;
begin
  if FSelected = nil then
    Result := ''
  else
    Result := FSelected.Path;
end;

procedure TTreeView.SetSelected(AValue: TTreeNode);
var
  N: TTreeNode;
begin
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  if AValue <> nil then
  begin
    { its parents open so it shows }
    N := AValue.Parent;
    while (N <> nil) and (N <> FRoot) do
    begin
      if not N.FExpanded then
      begin
        N.FExpanded := True;
        FRowsValid := False;
      end;
      N := N.Parent;
    end;
    MakeVisible(AValue);
  end;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TTreeView.RowHeight: Integer;
begin
  Result := Font.LineHeight + 10;
end;

function TTreeView.InnerHeight: Integer;
begin
  Result := Math.Max(0, Bounds.H - 4);
end;

procedure TTreeView.ClampTop;
begin
  if Bounds.H = 0 then
    Exit;
  FTop := EnsureRange(FTop, 0, Math.Max(0, RowCount * RowHeight - InnerHeight));
end;

procedure TTreeView.MakeVisible(Node: TTreeNode);
var
  I, Y: Integer;
begin
  BuildRows;
  I := FRows.IndexOf(Node);
  if (I < 0) or (Bounds.H = 0) then
    Exit;
  Y := I * RowHeight;
  if Y < FTop then
    FTop := Y;
  if Y + RowHeight > FTop + InnerHeight then
    FTop := Y + RowHeight - InnerHeight;
  ClampTop;
  Invalidate;
end;

function TTreeView.IndexAt(Y: Integer): Integer;
begin
  Result := (Y - Bounds.Y - 2 + FTop) div RowHeight;
  if (Y < Bounds.Y + 2) or (Result < 0) or (Result >= RowCount) then
    Result := -1;
end;

function TTreeView.BarRect: TRectI;
var
  H, Content, Len, Pos: Integer;
begin
  H := InnerHeight;
  Content := RowCount * RowHeight;
  if Content <= H then
    Exit(RectI(0, 0, 0, 0));
  Len := Math.Max(24, H * H div Content);
  Pos := (H - Len) * FTop div Math.Max(1, Content - H);
  Result := RectI(Bounds.X + Bounds.W - 9, Bounds.Y + 2 + Pos, 6, Len);
end;

procedure TTreeView.SelectRow(I: Integer);
begin
  if (I >= 0) and (I < RowCount) then
    Selected := RowNode(I);
end;

procedure TTreeView.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 220;
  H := 8 * RowHeight + 4;
end;

procedure TTreeView.Paint(C: TCanvas32);
var
  F: TPastelFont;
  I, First, Last, Y, X, RH: Integer;
  N: TTreeNode;
  Fg, Bg, Border: TColor32;
  Bar: TRectI;
begin
  F := Font;
  RH := RowHeight;
  BuildRows;
  ClampTop;
  if IsFocused then
  begin
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6, Theme.Radius + 3, Theme.FocusRing);
    Border := Theme.Accent;
  end
  else
    Border := Theme.Border;
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);
  C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Border);
  C.PushClip(RectI(Bounds.X + 1, Bounds.Y + 2, Bounds.W - 2, Bounds.H - 4));
  First := FTop div RH;
  Last := Math.Min(FRows.Count - 1, (FTop + InnerHeight) div RH);
  for I := First to Last do
  begin
    N := TTreeNode(FRows[I]);
    Y := Bounds.Y + 2 + I * RH - FTop;
    X := Bounds.X + 8 + N.Level * 18;
    Fg := Theme.Text;
    Bg := 0;
    if N = FSelected then
    begin
      if IsFocused then
      begin
        Bg := Theme.Accent;
        Fg := Theme.OnAccent;
      end
      else
        Bg := Theme.SecondaryPressed;
    end
    else if (I = FHotIndex) and Enabled then
      Bg := Theme.SecondaryHover;
    if not Enabled then
      Fg := Theme.Disabled;
    if Bg <> 0 then
      C.FillRoundRect(Bounds.X + 4, Y + 1, Bounds.W - 8, RH - 2, 6, Bg);
    if N.HasChildren then
      PaintArrow(C, X + 6, Y + RH div 2, N.Expanded, IfThen(N = FSelected, Fg, Theme.TextMuted));
    C.DrawText(F, X + 18, Y + (RH - F.LineHeight) div 2, N.Text, Fg);
  end;
  C.PopClip;
  Bar := BarRect;
  if Bar.H > 0 then
    C.FillRoundRect(Bar.X, Bar.Y, Bar.W, Bar.H, 3, WithAlpha(Theme.TextMuted, $90));
end;

function TTreeView.Focusable: Boolean;
begin
  Result := Enabled;
end;

procedure TTreeView.MouseDown(X, Y: Integer);
var
  I, ArrowX: Integer;
  N: TTreeNode;
  Bar: TRectI;
  F: TForm;
begin
  Bar := BarRect;
  if (Bar.H > 0) and (X >= Bar.X - 4) then
  begin
    FDragBar := True;
    if (Y >= Bar.Y) and (Y < Bar.Y + Bar.H) then FDragOffset := Y - Bar.Y else FDragOffset := Bar.H div 2;
    MouseMove(X, Y);
    Exit;
  end;
  I := IndexAt(Y);
  N := RowNode(I);
  if N = nil then
    Exit;
  ArrowX := Bounds.X + 8 + N.Level * 18;
  if N.HasChildren and (X >= ArrowX - 4) and (X < ArrowX + 16) then
  begin
    N.Expanded := not N.Expanded;
    Exit;
  end;
  Selected := N;
  F := ParentForm;
  if (F <> nil) and (F.ClickCount = 2) then
    if N.HasChildren then
      N.Expanded := not N.Expanded
    else if Assigned(FOnDblClick) then
      FOnDblClick(Self);
end;

procedure TTreeView.MouseMove(X, Y: Integer);
var
  I, H, Len: Integer;
  F: TForm;
begin
  F := ParentForm;
  if FDragBar and (F <> nil) and (F.Captured = Self) then
  begin
    H := InnerHeight;
    Len := BarRect.H;
    FTop := (Y - FDragOffset - Bounds.Y - 2) * Math.Max(1, RowCount * RowHeight - H) div Math.Max(1, H - Len);
    ClampTop;
    Invalidate;
    Exit;
  end;
  I := IndexAt(Y);
  if I <> FHotIndex then
  begin
    FHotIndex := I;
    Invalidate;
  end;
end;

procedure TTreeView.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  FDragBar := False;
end;

function TTreeView.MouseWheel(DX, DY: Integer): Boolean;
begin
  Result := RowCount * RowHeight > InnerHeight;
  if not Result then
    Exit;
  Dec(FTop, DY * RowHeight * 3);
  ClampTop;
  Invalidate;
end;

function TTreeView.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  I, Page: Integer;
  N: TTreeNode;
begin
  Result := True;
  BuildRows;
  I := FRows.IndexOf(FSelected);
  N := FSelected;
  Page := Math.Max(1, InnerHeight div RowHeight - 1);
  case Key of
    KEY_UP: SelectRow(Math.Max(0, I - 1));
    KEY_DOWN: SelectRow(Math.Min(FRows.Count - 1, I + 1));
    KEY_PAGEUP: SelectRow(Math.Max(0, I - Page));
    KEY_PAGEDOWN: SelectRow(Math.Min(FRows.Count - 1, I + Page));
    KEY_HOME: SelectRow(0);
    KEY_END: SelectRow(FRows.Count - 1);
    KEY_RIGHT:
      if N <> nil then
        if N.HasChildren and not N.Expanded then
          N.Expanded := True
        else if N.HasChildren then
          Selected := N.Items[0];
    KEY_LEFT:
      if N <> nil then
        if N.Expanded then
          N.Expanded := False
        else if N.Parent <> FRoot then
          Selected := N.Parent;
    KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
      if N = nil then
        Result := False
      else if N.HasChildren then
        N.Expanded := not N.Expanded
      else if Assigned(FOnDblClick) and (Key <> KEY_SPACE) then
        FOnDblClick(Self);
  else
    Result := False;
  end;
end;

procedure TTreeView.TextInput(const S: string);
var
  I, J: Integer;
begin
  BuildRows;
  if (S = ' ') or (FRows.Count = 0) then
    Exit;
  I := FRows.IndexOf(FSelected);
  for J := 1 to FRows.Count do
    if AnsiStartsText(S, TTreeNode(FRows[(I + J) mod FRows.Count]).Text) then
    begin
      SelectRow((I + J) mod FRows.Count);
      Exit;
    end;
end;

initialization
  RegisterControl(TGrid);
  RegisterControl(TGridColumn);
  RegisterControl(TListView);
  RegisterControl(TTreeView);
end.
