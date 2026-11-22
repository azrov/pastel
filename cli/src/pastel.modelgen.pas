{ Pastel - "pastel new model": a table, its migration, a unit to use it and tests.

    pastel new model Customer name:string! email:string age:integer active:boolean

  makes database/migrations/00N_create_customers.sql, src/models/customers.pas
  (TCustomer, one row; TCustomers, the table) and tests/customers_test.pas.
  Part of the Pastel project, MIT License. }
unit Pastel.ModelGen;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ Field specs: name:type, ! after the type for a required field. Types:
  string, text, integer, bigint, number, money, boolean, date, datetime. }
function CreateModel(const Root, Name: string; const Specs: array of string): Boolean;
{ Customer -> customers, Category -> categories, Box -> boxes }
function TableNameOf(const Name: string): string;

implementation

uses
  Classes, Pastel.Console, Pastel.Files;

type
  TModelField = record
    Name, Prop, Kind: string;
    Required: Boolean;
  end;

function Snake(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if (S[I] in ['A'..'Z']) and (I > 1) and not (S[I - 1] in ['A'..'Z', '_']) then
      Result := Result + '_';
    Result := Result + LowerCase(S[I]);
  end;
end;

{ first_name -> FirstName }
function Pascal(const S: string): string;
var
  I: Integer;
  Up: Boolean;
begin
  Result := '';
  Up := True;
  for I := 1 to Length(S) do
    if S[I] = '_' then
      Up := True
    else if Up then
    begin
      Result := Result + UpCase(S[I]);
      Up := False;
    end
    else
      Result := Result + S[I];
end;

function TableNameOf(const Name: string): string;
var
  S: string;
begin
  S := Snake(Name);
  if (Length(S) > 1) and (S[Length(S)] = 'y') and not (S[Length(S) - 1] in ['a', 'e', 'i', 'o', 'u']) then
    Result := Copy(S, 1, Length(S) - 1) + 'ies'
  else if (S <> '') and ((S[Length(S)] in ['s', 'x', 'z']) or (Copy(S, Length(S) - 1, 2) = 'ch') or
    (Copy(S, Length(S) - 1, 2) = 'sh')) then
    Result := S + 'es'
  else
    Result := S + 's';
end;

function SqlType(const F: TModelField): string;
begin
  case F.Kind of
    'string': Result := 'varchar(200) not null default ''''';
    'text': Result := 'text';
    'integer': Result := 'integer not null default 0';
    'bigint': Result := 'bigint not null default 0';
    'number': Result := 'double precision not null default 0';
    'money': Result := 'decimal(14,2) not null default 0';
    'boolean': Result := 'integer not null default 0';
    'date': Result := 'varchar(10) not null default ''''';
    'datetime': Result := 'varchar(19) not null default ''''';
  end;
end;

function PasType(const F: TModelField): string;
begin
  case F.Kind of
    'integer': Result := 'Integer';
    'bigint': Result := 'Int64';
    'number': Result := 'Double';
    'money': Result := 'Currency';
    'boolean': Result := 'Boolean';
  else
    Result := 'string';
  end;
end;

function FromJsonLine(const F: TModelField): string;
begin
  case F.Kind of
    'integer': Result := Format('  F%s := JInt(Data, ''%s'');', [F.Prop, F.Name]);
    'bigint': Result := Format('  F%s := JInt(Data, ''%s'');', [F.Prop, F.Name]);
    'number': Result := Format('  F%s := JFloat(Data, ''%s'');', [F.Prop, F.Name]);
    'money': Result := Format('  F%s := JFloat(Data, ''%s'');', [F.Prop, F.Name]);
    'boolean': Result := Format('  F%s := JBool(Data, ''%s'');', [F.Prop, F.Name]);
  else
    Result := Format('  F%s := JStr(Data, ''%s'');', [F.Prop, F.Name]);
  end;
end;

function SampleValue(const F: TModelField; Second: Boolean): string;
begin
  case F.Kind of
    'integer', 'bigint': if Second then Result := '7' else Result := '3';
    'number': if Second then Result := '2.5' else Result := '1.5';
    'money': if Second then Result := '20.50' else Result := '10.25';
    'boolean': if Second then Result := 'False' else Result := 'True';
    'date': if Second then Result := '''2026-11-04''' else Result := '''2026-11-03''';
    'datetime': if Second then Result := '''2026-11-04 10:00:00''' else Result := '''2026-11-03 09:30:00''';
  else
    if Second then Result := '''Second ' + F.Name + '''' else Result := '''First ' + F.Name + '''';
  end;
end;

function CreateModel(const Root, Name: string; const Specs: array of string): Boolean;
const
  Kinds = 'string text integer bigint number money boolean date datetime';
var
  Fields: array of TModelField;
  F: TModelField;
  Spec, Table, ClassName, UnitName, Cols, Marks, Sets, Args, MigDir, MigFile, S: string;
  P, Next, N: Integer;
  L, T: TStringList;
  M: string;
begin
  Result := False;
  if (Name = '') or not (Name[1] in ['A'..'Z', 'a'..'z']) then
  begin
    Fail(Format('"%s" is not a name for a model (like Customer or InvoiceLine)', [Name]));
    Exit;
  end;
  Fields := nil;
  for Spec in Specs do
  begin
    P := Pos(':', Spec);
    F := Default(TModelField);
    if P = 0 then
    begin
      F.Name := Snake(Spec);
      F.Kind := 'string';
    end
    else
    begin
      F.Name := Snake(Copy(Spec, 1, P - 1));
      F.Kind := LowerCase(Copy(Spec, P + 1, MaxInt));
    end;
    if (F.Kind <> '') and (F.Kind[Length(F.Kind)] = '!') then
    begin
      F.Required := True;
      SetLength(F.Kind, Length(F.Kind) - 1);
    end;
    if (F.Name = '') or (F.Name = 'id') then
    begin
      Fail(Format('"%s": every model has an id; give the other fields', [Spec]));
      Exit;
    end;
    if Pos(' ' + F.Kind + ' ', ' ' + Kinds + ' ') = 0 then
    begin
      Fail(Format('"%s": unknown type "%s" (%s)', [Spec, F.Kind, Kinds]));
      Exit;
    end;
    F.Prop := Pascal(F.Name);
    Fields := Concat(Fields, [F]);
  end;
  if Length(Fields) = 0 then
  begin
    Fail('give the fields: pastel new model ' + Name + ' name:string! email:string age:integer');
    Exit;
  end;
  Table := TableNameOf(Name);
  ClassName := Pascal(Snake(Name));
  UnitName := Pascal(Table);
  if FileExists(JoinPath([Root, 'src', 'models', Table + '.pas'])) then
  begin
    Fail(Format('src/models/%s.pas exists already', [Table]));
    Exit;
  end;

  { the migration }
  MigDir := JoinPath([Root, 'database', 'migrations']);
  EnsureDir(MigDir);
  Next := 1;
  for S in ListFiles(MigDir, '*.sql') do
    if TryStrToInt(Copy(ExtractFileName(S), 1, Pos('_', ExtractFileName(S)) - 1), N) and (N >= Next) then
      Next := N + 1;
  MigFile := JoinPath([MigDir, Format('%.3d_create_%s.sql', [Next, Table])]);
  M := '-- The table of ' + ClassName + ' (src/models/' + Table + '.pas). Made by "pastel new model".' + LineEnding +
    '-- Runs once, with "pastel migrate" or Db.Migrate; later changes go into new migrations.' + LineEnding +
    'create table ' + Table + ' (' + LineEnding + '  id {{id}}';
  for F in Fields do
    M := M + ',' + LineEnding + '  ' + F.Name + ' ' + SqlType(F);
  M := M + LineEnding + ');' + LineEnding;
  WriteText(MigFile, M);

  { the unit }
  Cols := '';
  Marks := '';
  Sets := '';
  Args := '';
  for F in Fields do
  begin
    if Cols <> '' then
    begin
      Cols := Cols + ', ';
      Marks := Marks + ', ';
      Sets := Sets + ', ';
      Args := Args + ', ';
    end;
    Cols := Cols + F.Name;
    Marks := Marks + '?';
    Sets := Sets + F.Name + ' = ?';
    Args := Args + 'C.' + F.Prop;
  end;
  L := TStringList.Create;
  try
    L.Add('{ ' + UnitName + ': the table ' + Table + ', and T' + ClassName + ', one row of it.');
    L.Add('  Made by "pastel new model"; change it as you need (the checks in Check).');
    L.Add('');
    L.Add('    ' + UnitName + ' := T' + UnitName + '.Create(Db);');
    L.Add('    Item := T' + ClassName + '.Create;');
    L.Add('    Item.' + Fields[0].Prop + ' := ' + SampleValue(Fields[0], False) + ';');
    L.Add('    ' + UnitName + '.Save(Item);                // checked; Item.Id is set');
    L.Add('    Item := ' + UnitName + '.Find(Id);          // nil when there is none');
    L.Add('    Rows := ' + UnitName + '.All;               // JSON rows, for a TListView: List.LoadJson(Rows)');
    L.Add('}');
    L.Add('unit ' + UnitName + ';');
    L.Add('');
    L.Add('{$mode objfpc}{$H+}');
    L.Add('');
    L.Add('interface');
    L.Add('');
    L.Add('uses');
    L.Add('  SysUtils, fpjson, Pastel.Db;');
    L.Add('');
    L.Add('type');
    L.Add('  E' + ClassName + 'Invalid = class(Exception);');
    L.Add('');
    L.Add('  { One row of ' + Table + '. The published properties work with TDataBinding.LoadObject/SaveObject. }');
    L.Add('  T' + ClassName + ' = class');
    L.Add('  private');
    L.Add('    FId: Int64;');
    for F in Fields do
      L.Add('    F' + F.Prop + ': ' + PasType(F) + ';');
    L.Add('  public');
    L.Add('    { Raises E' + ClassName + 'Invalid with a message when a value is wrong. }');
    L.Add('    procedure Check;');
    L.Add('    procedure FromJson(Data: TJSONObject);');
    L.Add('    { A new JSON object with the values; the caller frees it. }');
    L.Add('    function ToJson: TJSONObject;');
    L.Add('  published');
    L.Add('    { 0 until it is saved }');
    L.Add('    property Id: Int64 read FId write FId;');
    for F in Fields do
      L.Add('    property ' + F.Prop + ': ' + PasType(F) + ' read F' + F.Prop + ' write F' + F.Prop + ';');
    L.Add('  end;');
    L.Add('');
    L.Add('  { The table ' + Table + '. }');
    L.Add('  T' + UnitName + ' = class');
    L.Add('  private');
    L.Add('    FDb: TDatabase;');
    L.Add('  public');
    L.Add('    constructor Create(ADb: TDatabase);');
    L.Add('    { The row with this id; nil when there is none. The caller frees it. }');
    L.Add('    function Find(Id: Int64): T' + ClassName + ';');
    L.Add('    { The rows as JSON objects (Where: ''age > ?'', OrderBy: ''' + Fields[0].Name + '''); the caller frees it. }');
    L.Add('    function All(const Where: string; const Params: array of const; const OrderBy: string = ''id''): TJSONArray;');
    L.Add('    function All: TJSONArray;');
    L.Add('    { Checks and stores it: a new row when Id is 0 (Id is set then). Returns the id. }');
    L.Add('    function Save(Item: T' + ClassName + '): Int64;');
    L.Add('    procedure Delete(Id: Int64);');
    L.Add('    function Count: Integer;');
    L.Add('  end;');
    L.Add('');
    L.Add('implementation');
    L.Add('');
    L.Add('uses');
    L.Add('  Pastel.Json;');
    L.Add('');
    L.Add('procedure T' + ClassName + '.Check;');
    L.Add('begin');
    N := 0;
    for F in Fields do
      if F.Required then
      begin
        Inc(N);
        if PasType(F) = 'string' then
        begin
          L.Add('  if Trim(F' + F.Prop + ') = '''' then');
          L.Add('    raise E' + ClassName + 'Invalid.Create(''' + F.Name + ' is required'');');
        end
        else if PasType(F) <> 'Boolean' then
        begin
          L.Add('  if F' + F.Prop + ' = 0 then');
          L.Add('    raise E' + ClassName + 'Invalid.Create(''' + F.Name + ' is required'');');
        end;
      end;
    if N = 0 then
      L.Add('  { what must be true, for example: if Trim(FName) = '''' then raise E' + ClassName +
        'Invalid.Create(''name is required''); }');
    L.Add('end;');
    L.Add('');
    L.Add('procedure T' + ClassName + '.FromJson(Data: TJSONObject);');
    L.Add('begin');
    L.Add('  FId := JInt(Data, ''id'');');
    for F in Fields do
      L.Add(FromJsonLine(F));
    L.Add('end;');
    L.Add('');
    L.Add('function T' + ClassName + '.ToJson: TJSONObject;');
    L.Add('begin');
    S := '  Result := JObject([''id'', FId';
    for F in Fields do
      S := S + ', ''' + F.Name + ''', F' + F.Prop;
    L.Add(S + ']);');
    L.Add('end;');
    L.Add('');
    L.Add('constructor T' + UnitName + '.Create(ADb: TDatabase);');
    L.Add('begin');
    L.Add('  inherited Create;');
    L.Add('  FDb := ADb;');
    L.Add('end;');
    L.Add('');
    L.Add('function T' + UnitName + '.Find(Id: Int64): T' + ClassName + ';');
    L.Add('var');
    L.Add('  Row: TJSONObject;');
    L.Add('begin');
    L.Add('  Result := nil;');
    L.Add('  Row := FDb.QueryOne(''select * from ' + Table + ' where id = ?'', [Id]);');
    L.Add('  if Row = nil then');
    L.Add('    Exit;');
    L.Add('  try');
    L.Add('    Result := T' + ClassName + '.Create;');
    L.Add('    Result.FromJson(Row);');
    L.Add('  finally');
    L.Add('    Row.Free;');
    L.Add('  end;');
    L.Add('end;');
    L.Add('');
    L.Add('function T' + UnitName + '.All(const Where: string; const Params: array of const; const OrderBy: string): TJSONArray;');
    L.Add('var');
    L.Add('  SQL: string;');
    L.Add('begin');
    L.Add('  SQL := ''select * from ' + Table + ''';');
    L.Add('  if Where <> '''' then');
    L.Add('    SQL := SQL + '' where '' + Where;');
    L.Add('  Result := FDb.Query(SQL + '' order by '' + OrderBy, Params);');
    L.Add('end;');
    L.Add('');
    L.Add('function T' + UnitName + '.All: TJSONArray;');
    L.Add('begin');
    L.Add('  Result := All('''', [], ''id'');');
    L.Add('end;');
    L.Add('');
    L.Add('function T' + UnitName + '.Save(Item: T' + ClassName + '): Int64;');
    L.Add('begin');
    L.Add('  Item.Check;');
    L.Add('  if Item.Id = 0 then');
    L.Add('    Item.Id := FDb.Insert(''insert into ' + Table + ' (' + Cols + ') values (' + Marks + ')'',');
    L.Add('      [' + StringReplace(Args, 'C.', 'Item.', [rfReplaceAll]) + '])');
    L.Add('  else');
    L.Add('    FDb.Exec(''update ' + Table + ' set ' + Sets + ' where id = ?'',');
    L.Add('      [' + StringReplace(Args, 'C.', 'Item.', [rfReplaceAll]) + ', Item.Id]);');
    L.Add('  Result := Item.Id;');
    L.Add('end;');
    L.Add('');
    L.Add('procedure T' + UnitName + '.Delete(Id: Int64);');
    L.Add('begin');
    L.Add('  FDb.Exec(''delete from ' + Table + ' where id = ?'', [Id]);');
    L.Add('end;');
    L.Add('');
    L.Add('function T' + UnitName + '.Count: Integer;');
    L.Add('begin');
    L.Add('  Result := FDb.QueryInt(''select count(*) from ' + Table + ''', []);');
    L.Add('end;');
    L.Add('');
    L.Add('end.');
    EnsureDir(JoinPath([Root, 'src', 'models']));
    WriteText(JoinPath([Root, 'src', 'models', Table + '.pas']), L.Text);
  finally
    L.Free;
  end;

  { the tests: a database of their own, the migrations, save, find, list }
  T := TStringList.Create;
  try
    T.Add('{ Tests for src/models/' + Table + '.pas: a SQLite database of their own. Run them with: pastel test }');
    T.Add('unit ' + UnitName + '_Test;');
    T.Add('');
    T.Add('{$mode objfpc}{$H+}');
    T.Add('');
    T.Add('interface');
    T.Add('');
    T.Add('uses');
    T.Add('  SysUtils, fpjson, Pastel.Testing, Pastel.Db, Pastel.Files, ' + UnitName + ';');
    T.Add('');
    T.Add('type');
    T.Add('  T' + UnitName + 'Tests = class(TTestSuite)');
    T.Add('  private');
    T.Add('    Dir: string;');
    T.Add('    Db: TDatabase;');
    T.Add('    Table: T' + UnitName + ';');
    T.Add('  public');
    T.Add('    procedure SetUp; override;');
    T.Add('    procedure TearDown; override;');
    T.Add('  published');
    T.Add('    procedure SavesAndFinds;');
    T.Add('    procedure ChangesAndDeletes;');
    T.Add('  end;');
    T.Add('');
    T.Add('implementation');
    T.Add('');
    T.Add('procedure T' + UnitName + 'Tests.SetUp;');
    T.Add('begin');
    T.Add('  Dir := MakeTempDir;');
    T.Add('  Db := TDatabase.Open(''sqlite:'' + JoinPath([Dir, ''test.db'']));');
    T.Add('  Db.Migrate(''database/migrations'');');
    T.Add('  Table := T' + UnitName + '.Create(Db);');
    T.Add('end;');
    T.Add('');
    T.Add('procedure T' + UnitName + 'Tests.TearDown;');
    T.Add('begin');
    T.Add('  Table.Free;');
    T.Add('  Db.Free;');
    T.Add('  DeleteDir(Dir);');
    T.Add('end;');
    T.Add('');
    T.Add('procedure T' + UnitName + 'Tests.SavesAndFinds;');
    T.Add('var');
    T.Add('  Item, Found: T' + ClassName + ';');
    T.Add('  Rows: TJSONArray;');
    T.Add('begin');
    T.Add('  Item := T' + ClassName + '.Create;');
    T.Add('  try');
    for F in Fields do
      T.Add('    Item.' + F.Prop + ' := ' + SampleValue(F, False) + ';');
    T.Add('    AssertTrue(Table.Save(Item) > 0, ''a new id'');');
    T.Add('    Found := Table.Find(Item.Id);');
    T.Add('    try');
    T.Add('      AssertNotNil(Found);');
    for F in Fields do
      if PasType(F) = 'string' then
        T.Add('      AssertEquals(Item.' + F.Prop + ', Found.' + F.Prop + ');')
      else if PasType(F) = 'Boolean' then
        T.Add('      AssertEquals(Item.' + F.Prop + ', Found.' + F.Prop + ');')
      else if (PasType(F) = 'Double') or (PasType(F) = 'Currency') then
        T.Add('      AssertEquals(Double(Item.' + F.Prop + '), Double(Found.' + F.Prop + '), 0.001);')
      else
        T.Add('      AssertEquals(Int64(Item.' + F.Prop + '), Int64(Found.' + F.Prop + '));');
    T.Add('    finally');
    T.Add('      Found.Free;');
    T.Add('    end;');
    T.Add('    Rows := Table.All;');
    T.Add('    try');
    T.Add('      AssertEquals(1, Rows.Count);');
    T.Add('    finally');
    T.Add('      Rows.Free;');
    T.Add('    end;');
    T.Add('  finally');
    T.Add('    Item.Free;');
    T.Add('  end;');
    T.Add('end;');
    T.Add('');
    T.Add('procedure T' + UnitName + 'Tests.ChangesAndDeletes;');
    T.Add('var');
    T.Add('  Item, Found: T' + ClassName + ';');
    T.Add('begin');
    T.Add('  Item := T' + ClassName + '.Create;');
    T.Add('  try');
    for F in Fields do
      T.Add('    Item.' + F.Prop + ' := ' + SampleValue(F, False) + ';');
    T.Add('    Table.Save(Item);');
    T.Add('    Item.' + Fields[0].Prop + ' := ' + SampleValue(Fields[0], True) + ';');
    T.Add('    Table.Save(Item);');
    T.Add('    AssertEquals(1, Table.Count, ''changed, not added'');');
    T.Add('    Found := Table.Find(Item.Id);');
    T.Add('    try');
    if PasType(Fields[0]) = 'string' then
      T.Add('      AssertEquals(' + SampleValue(Fields[0], True) + ', Found.' + Fields[0].Prop + ');')
    else
      T.Add('      AssertNotNil(Found);');
    T.Add('    finally');
    T.Add('      Found.Free;');
    T.Add('    end;');
    T.Add('    Table.Delete(Item.Id);');
    T.Add('    AssertEquals(0, Table.Count);');
    T.Add('  finally');
    T.Add('    Item.Free;');
    T.Add('  end;');
    T.Add('end;');
    T.Add('');
    T.Add('initialization');
    T.Add('  RegisterTests(T' + UnitName + 'Tests);');
    T.Add('');
    T.Add('end.');
    EnsureDir(JoinPath([Root, 'tests']));
    WriteText(JoinPath([Root, 'tests', Table + '_test.pas']), T.Text);
  finally
    T.Free;
  end;
  Status('Created', RelativePath(MigFile, GetCurrentDir));
  Status('Created', RelativePath(JoinPath([Root, 'src', 'models', Table + '.pas']), GetCurrentDir));
  Status('Created', RelativePath(JoinPath([Root, 'tests', Table + '_test.pas']), GetCurrentDir));
  Hint(Format('pastel migrate makes the table; uses %s; in the code. pastel test runs its tests', [UnitName]));
  Result := True;
end;

end.
