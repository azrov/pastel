{ Tests for Pastel.Sync and Pastel.SyncWeb: two computers and a server. }
unit Sync_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Log, Pastel.Testing, Pastel.Db, Pastel.Sync, Pastel.SyncWeb, Pastel.Web, Pastel.Json, Pastel.Files;

type
  TSyncTests = class(TTestSuite)
  private
    Dir: string;
    A, B, Server: TSyncStore;
    function NewStore(const Name: string; IsServer: Boolean): TSyncStore;
    procedure Check(const Table: string; Data: TJSONObject);
    procedure SaveNameless;
    procedure AddBookkeeping;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ColumnsAreRead;
    procedure SavesWithIdAndStamp;
    procedure ChecksBeforeSaving;
    procedure ARecordTravels;
    procedure TheNewerChangeWins;
    procedure DeletionsTravel;
    procedure TheSameChangesTwiceChangeNothing;
    procedure OverHttp;
  end;

implementation

function TSyncTests.NewStore(const Name: string; IsServer: Boolean): TSyncStore;
begin
  Result := TSyncStore.Create(TDatabase.Open('sqlite:' + JoinPath([Dir, Name + '.db'])), True);
  Result.IsServer := IsServer;
  Result.OnCheck := @Check;
  Result.AddTable('customers', 'name varchar(200) not null, phone varchar(50) not null default '''', ' +
    'visits integer not null default 0');
  Result.CreateTables;
end;

procedure TSyncTests.Check(const Table: string; Data: TJSONObject);
begin
  if Trim(JStr(Data, 'name')) = '' then
    raise ESyncInvalid.Create('a customer needs a name');
end;

procedure TSyncTests.SetUp;
begin
  Dir := MakeTempDir;
  A := NewStore('a', False);
  B := NewStore('b', False);
  Server := NewStore('server', True);
end;

procedure TSyncTests.TearDown;
begin
  A.Free;
  B.Free;
  Server.Free;
  DeleteDir(Dir);
end;

{ a client's sync without HTTP }
procedure Sync(Client, Server: TSyncStore; var Since: string);
var
  Mine, Req, Answer: TJSONObject;
begin
  Mine := Client.Changes('', True);
  Req := TJSONObject.Create;
  try
    Req.Strings['since'] := Since;
    Req.Add('changes', Mine.Clone);
    Answer := AnswerSync(Server, Req);
    try
      Client.Apply(Answer.Objects['changes']);
      Client.MarkSent(Mine);
      Since := Answer.Strings['now'];
    finally
      Answer.Free;
    end;
  finally
    Req.Free;
    Mine.Free;
  end;
end;

procedure TSyncTests.ColumnsAreRead;
begin
  AssertEquals('name,phone,visits', string.Join(',', A.Fields('customers')));
  AssertEquals('customers', string.Join(',', A.Tables));
  AssertRaises(ESyncInvalid, @AddBookkeeping, 'updated_at is made by the store');
end;

procedure TSyncTests.AddBookkeeping;
begin
  A.AddTable('x', 'updated_at text');
end;

procedure TSyncTests.SavesWithIdAndStamp;
var
  Id: string;
  R: TJSONObject;
begin
  Id := A.Save('customers', JObject(['name', 'Ayşe']));
  AssertEquals(16, Length(Id));
  R := A.Get('customers', Id);
  try
    AssertEquals('', JStr(R, 'phone'), 'the column''s default');
    AssertEquals(1, JInt(R, 'dirty'), 'to be sent');
    AssertStartsWith(FormatDateTime('yyyy', Now), JStr(R, 'updated_at'));
  finally
    R.Free;
  end;
  A.Save('customers', JObject(['id', Id, 'phone', '0532']));
  R := A.Get('customers', Id);
  try
    AssertEquals('Ayşe', JStr(R, 'name'), 'values not given keep theirs');
    AssertEquals('0532', JStr(R, 'phone'));
  finally
    R.Free;
  end;
  AssertEquals(1, A.Count('customers'));
  AssertEquals(1, A.Pending);
end;

procedure TSyncTests.SaveNameless;
begin
  A.Save('customers', JObject(['phone', '1']));
end;

procedure TSyncTests.ChecksBeforeSaving;
begin
  AssertRaises(ESyncInvalid, @SaveNameless);
  AssertEquals(0, A.Count('customers'));
end;

procedure TSyncTests.ARecordTravels;
var
  SA, SB: string;
  Id: string;
  R: TJSONObject;
begin
  SA := '';
  SB := '';
  Id := A.Save('customers', JObject(['name', 'Ayşe']));
  Sync(A, Server, SA);
  AssertEquals(0, A.Pending, 'sent');
  Sync(B, Server, SB);
  R := B.Get('customers', Id);
  try
    AssertNotNil(R, 'the other computer has it');
    AssertEquals(0, JInt(R, 'dirty'), 'it came from the server: nothing to send back');
  finally
    R.Free;
  end;
  { the server's own records go to the clients too }
  Id := Server.Save('customers', JObject(['name', 'From the office']));
  Sync(A, Server, SA);
  R := A.Get('customers', Id);
  try
    AssertNotNil(R);
  finally
    R.Free;
  end;
end;

procedure TSyncTests.TheNewerChangeWins;
var
  SA, SB, Id: string;
  R: TJSONObject;
begin
  SA := '';
  SB := '';
  Id := A.Save('customers', JObject(['name', 'Ayşe']));
  Sync(A, Server, SA);
  Sync(B, Server, SB);
  A.Save('customers', JObject(['id', Id, 'phone', 'old']));
  Sleep(5);
  B.Save('customers', JObject(['id', Id, 'phone', 'new']));
  Sync(B, Server, SB);
  Sync(A, Server, SA);        { A's change is older: the server keeps B's, and A gets it }
  R := A.Get('customers', Id);
  try
    AssertEquals('new', JStr(R, 'phone'));
  finally
    R.Free;
  end;
end;

procedure TSyncTests.DeletionsTravel;
var
  SA, SB, Id: string;
begin
  SA := '';
  SB := '';
  Id := A.Save('customers', JObject(['name', 'Ayşe']));
  Sync(A, Server, SA);
  Sync(B, Server, SB);
  AssertEquals(1, B.Count('customers'));
  A.Delete('customers', Id);
  Sync(A, Server, SA);
  Sync(B, Server, SB);
  AssertEquals(0, B.Count('customers'));
  AssertNil(B.Get('customers', Id));
end;

procedure TSyncTests.TheSameChangesTwiceChangeNothing;
var
  Mine: TJSONObject;
begin
  A.Save('customers', JObject(['name', 'Ayşe']));
  Mine := A.Changes('', True);
  try
    AssertEquals(1, Server.Apply(Mine));
    AssertEquals(0, Server.Apply(Mine), 'the same version again');
  finally
    Mine.Free;
  end;
end;

procedure TSyncTests.OverHttp;
var
  Web: TWebServer;
  Port: Integer;
  Since, Id: string;
  R: TSyncResult;
  C: TJSONObject;
begin
  Port := 21000 + Random(20000);
  Web := TWebServer.Create(Port, '127.0.0.1');
  Log.Console := False;
  try
    AddSyncRoute(Web, Server);
    Web.Start;
    Id := A.Save('customers', JObject(['name', 'Ayşe']));
    Since := '';
    R := SyncWithServer(A, Format('http://127.0.0.1:%d', [Port]), '', Since);
    AssertEquals(1, R.Sent);
    AssertTrue(Since <> '', 'the server''s time is kept');
    C := Server.Get('customers', Id);
    try
      AssertNotNil(C, 'the server has it');
    finally
      C.Free;
    end;
    R := SyncWithServer(B, Format('http://127.0.0.1:%d', [Port]), '', Since);
    AssertEquals(0, R.Sent);
  finally
    Web.Free;
    Log.Console := True;
  end;
end;

initialization
  RegisterTests(TSyncTests);

end.
