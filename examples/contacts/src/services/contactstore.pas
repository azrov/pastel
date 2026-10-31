{ The contacts in a SQLite database (or any database Pastel.Db speaks). }
unit ContactStore;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Db;

type
  TContact = record
    Id: Int64;
    Name, Phone, Email, Notes: string;
  end;
  TContactArray = array of TContact;

  EContactInvalid = class(Exception);

  TContactStore = class
  private
    FDb: TDatabase;
  public
    { Url like 'sqlite:contacts.db'; creates the table when it is missing. }
    constructor Create(const Url: string);
    destructor Destroy; override;
    { The contacts whose name, phone or e-mail contain Filter, by name. }
    function List(const Filter: string = ''): TContactArray;
    function Get(Id: Int64): TContact;
    { Adds the contact (Id = 0) or updates it; returns its id. }
    function Save(const C: TContact): Int64;
    procedure Delete(Id: Int64);
    { The same as JSON objects (id, name, phone, email, notes), for a grid
      and a TDataBinding; the caller frees the result. }
    function ListJson(const Filter: string = ''): TJSONArray;
    { Saves a JSON object like those (id 0 or missing: a new contact). }
    function SaveJson(Data: TJSONObject): Int64;
    function Count: Integer;
  end;

{ The default place for the database: CONTACTS_DB, or the user's app data folder. }
function DefaultDatabaseUrl: string;
function NewContact(const Name, Phone, Email: string; const Notes: string = ''): TContact;

implementation

function DefaultDatabaseUrl: string;
var
  Dir: string;
begin
  Result := GetEnvironmentVariable('CONTACTS_DB');
  if Result <> '' then
    Exit('sqlite:' + Result);
  Dir := GetAppConfigDir(False);
  ForceDirectories(Dir);
  Result := 'sqlite:' + IncludeTrailingPathDelimiter(Dir) + 'contacts.db';
end;

function NewContact(const Name, Phone, Email, Notes: string): TContact;
begin
  Result.Id := 0;
  Result.Name := Name;
  Result.Phone := Phone;
  Result.Email := Email;
  Result.Notes := Notes;
end;

function FromJson(O: TJSONObject): TContact;
begin
  Result.Id := O.Get('id', Int64(0));
  Result.Name := O.Get('name', '');
  Result.Phone := O.Get('phone', '');
  Result.Email := O.Get('email', '');
  Result.Notes := O.Get('notes', '');
end;

constructor TContactStore.Create(const Url: string);
begin
  FDb := TDatabase.Create(Url, 1);
  FDb.Exec('create table if not exists contacts (id integer primary key autoincrement, ' +
    'name text not null, phone text not null default '''', email text not null default '''', ' +
    'notes text not null default '''')', []);
end;

destructor TContactStore.Destroy;
begin
  FDb.Free;
  inherited Destroy;
end;

function TContactStore.ListJson(const Filter: string): TJSONArray;
var
  Like: string;
begin
  Like := '%' + LowerCase(Trim(Filter)) + '%';
  Result := FDb.Query('select * from contacts where lower(name) like ? or phone like ? or lower(email) like ? ' +
    'order by lower(name), id', [Like, Like, Like]);
end;

function TContactStore.SaveJson(Data: TJSONObject): Int64;
begin
  Result := Save(FromJson(Data));
end;

function TContactStore.List(const Filter: string): TContactArray;
var
  Rows: TJSONArray;
  I: Integer;
begin
  Result := nil;
  Rows := ListJson(Filter);
  try
    SetLength(Result, Rows.Count);
    for I := 0 to Rows.Count - 1 do
      Result[I] := FromJson(Rows.Objects[I]);
  finally
    Rows.Free;
  end;
end;

function TContactStore.Get(Id: Int64): TContact;
var
  O: TJSONObject;
begin
  O := FDb.QueryOne('select * from contacts where id = ?', [Id]);
  if O = nil then
    raise EContactInvalid.CreateFmt('there is no contact %d', [Id]);
  try
    Result := FromJson(O);
  finally
    O.Free;
  end;
end;

function TContactStore.Save(const C: TContact): Int64;
begin
  if Trim(C.Name) = '' then
    raise EContactInvalid.Create('a contact needs a name');
  if (C.Email <> '') and (Pos('@', C.Email) < 2) then
    raise EContactInvalid.CreateFmt('"%s" is not an e-mail address', [C.Email]);
  if C.Id = 0 then
    Result := FDb.Insert('insert into contacts (name, phone, email, notes) values (?, ?, ?, ?)',
      [Trim(C.Name), Trim(C.Phone), Trim(C.Email), C.Notes])
  else
  begin
    FDb.Exec('update contacts set name = ?, phone = ?, email = ?, notes = ? where id = ?',
      [Trim(C.Name), Trim(C.Phone), Trim(C.Email), C.Notes, C.Id]);
    Result := C.Id;
  end;
end;

procedure TContactStore.Delete(Id: Int64);
begin
  FDb.Exec('delete from contacts where id = ?', [Id]);
end;

function TContactStore.Count: Integer;
begin
  Result := FDb.QueryInt('select count(*) from contacts', []);
end;

end.
