{ Tests for Pastel.Auth: users, login, tokens, roles. }
unit Auth_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Testing, Pastel.Db, Pastel.Auth, Pastel.Web, Pastel.Http, Pastel.Json,
  Pastel.Files, Pastel.Log;

type
  TAuthTests = class(TTestSuite)
  private
    Dir: string;
    Db: TDatabase;
    Users: TUserStore;
    procedure ShortPassword;
    procedure SameEmail;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure UsersAndPasswords;
    procedure LoginTokensAndRoles;
  end;

implementation

const
  Secret = 'a-secret-for-the-tests-of-32-characters-or-more';

type
  TShop = class
    procedure Customers(Req: TWebRequest; Res: TWebResponse);
    procedure Admin(Req: TWebRequest; Res: TWebResponse);
  end;

procedure TShop.Customers(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Json(JObject(['hello', Req.Claim('name')]));
end;

procedure TShop.Admin(Req: TWebRequest; Res: TWebResponse);
begin
  RequireRole(Req, ['admin']);
  Res.Text('ok');
end;

procedure TAuthTests.SetUp;
begin
  Dir := MakeTempDir;
  Db := TDatabase.Open('sqlite:' + JoinPath([Dir, 'users.db']));
  Users := TUserStore.Create(Db);
  Users.CreateTables;
end;

procedure TAuthTests.TearDown;
begin
  Users.Free;
  Db.Free;
  DeleteDir(Dir);
end;

procedure TAuthTests.ShortPassword;
begin
  Users.Add('ali@shop.com', 'short', 'Ali');
end;

procedure TAuthTests.SameEmail;
begin
  Users.Add('AYSE@shop.com', 'another-password', 'Ayşe 2');
end;

procedure TAuthTests.UsersAndPasswords;
var
  U: TJSONObject;
  Id: Int64;
begin
  Id := Users.Add('ayse@shop.com', 'right-password', 'Ayşe', 'admin');
  AssertTrue(Id > 0);
  AssertRaises(EAuthError, @ShortPassword);
  AssertRaises(EAuthError, @SameEmail, 'e-mails are the same in any case');
  U := Users.Check(' Ayse@Shop.com ', 'right-password');
  try
    AssertNotNil(U);
    AssertEquals('admin', JStr(U, 'role'));
    AssertFalse(JHas(U, 'password_hash'), 'the hash stays in the database');
  finally
    U.Free;
  end;
  AssertNil(Users.Check('ayse@shop.com', 'wrong-password'));
  AssertNil(Users.Check('nobody@shop.com', 'right-password'));
  Users.SetActive(Id, False);
  AssertNil(Users.Check('ayse@shop.com', 'right-password'), 'not active');
  AssertEquals(1, Users.Count);
end;

procedure TAuthTests.LoginTokensAndRoles;
var
  Web: TWebServer;
  Shop: TShop;
  Port: Integer;
  C: TAuthClient;
  R: THttpResponse;
  Old: string;
begin
  Users.Add('ayse@shop.com', 'right-password', 'Ayşe', 'admin');
  Users.Add('ali@shop.com', 'other-password', 'Ali');
  Port := 21000 + Random(20000);
  Web := TWebServer.Create(Port, '127.0.0.1');
  Shop := TShop.Create;
  Log.Console := False;
  C := TAuthClient.Create(Format('http://127.0.0.1:%d', [Port]));
  try
    AddAuthRoutes(Web, Users, Secret);
    Web.RequireJwt('/api/shop', Secret);
    Web.Get('/api/shop/customers', @Shop.Customers);
    Web.Get('/api/shop/admin', @Shop.Admin);
    Web.Start;
    AssertFalse(C.Login('ayse@shop.com', 'wrong'));
    AssertEquals('The e-mail or the password is wrong.', C.Error);
    AssertTrue(C.Login('ayse@shop.com', 'right-password'), C.Error);
    AssertEquals('Ayşe', JStr(C.User, 'name'));
    R := C.Get('/api/shop/customers');
    AssertEquals(200, R.Status);
    AssertContains('"hello":"Ayşe"', R.Body);
    AssertEquals(200, C.Get('/api/shop/admin').Status, 'an admin');
    { a new token from the refresh token; the old refresh token is used up }
    Old := C.RefreshToken;
    AssertTrue(C.ResumeWith(Old));
    AssertNotEquals(Old, C.RefreshToken);
    AssertFalse(C.ResumeWith(Old), 'a refresh token works once');
    AssertTrue(C.Login('ali@shop.com', 'other-password'));
    AssertEquals(403, C.Get('/api/shop/admin').Status, 'not an admin');
    C.Logout;
    AssertFalse(C.LoggedIn);
    C.Http.BearerToken := '';
    AssertEquals(401, C.Http.Get('/api/shop/customers').Status, 'no token, no answer');
  finally
    C.Free;
    Web.Free;
    Shop.Free;
    Log.Console := True;
  end;
end;

initialization
  RegisterTests(TAuthTests);

end.
