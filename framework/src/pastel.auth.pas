(* Pastel - users, passwords and roles for a server, and login for its apps.

  The server:

    Users := TUserStore.Create(Db);
    Users.CreateTables;
    if Users.Count = 0 then
      Users.Add('admin@shop.com', 'change-me-now', 'Admin', 'admin');
    AddAuthRoutes(Web, Users, Secret);       // POST /api/auth/login, /refresh, /logout; GET /api/auth/me
    Web.RequireJwt('/api/shop', Secret);     // these routes need a login
    ...
    procedure TShop.DeleteCustomer(Req: TWebRequest; Res: TWebResponse);
    begin
      RequireRole(Req, 'admin');             // 403 for the others
      ...

  The app (desktop, console):

    Client := TAuthClient.Create('https://shop.example.com');
    if not Client.Login('ayse@shop.com', Password) then ShowMessage(Client.Error);
    R := Client.Get('/api/shop/customers');  // with the token; a new one when it ran out

  Passwords are stored as PBKDF2 hashes (Pastel.Crypto). A login gives a
  token (a JWT, for 15 minutes) and a refresh token (for 30 days, kept in
  the database as a hash, replaced at every refresh, removed by logout).
  Part of the Pastel project, MIT License. *)
unit Pastel.Auth;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Db, Pastel.Web, Pastel.Http;

type
  EAuthError = class(Exception);

  TUserStore = class
  private
    FDb: TDatabase;
  public
    constructor Create(ADb: TDatabase);
    { users and refresh_tokens, when they are missing }
    procedure CreateTables;
    { A new user; EAuthError when the e-mail is taken or the password too short (8). }
    function Add(const Email, Password, Name: string; const Role: string = 'user'): Int64;
    { The user (id, email, name, role, active) with this e-mail and password; nil otherwise. }
    function Check(const Email, Password: string): TJSONObject;
    function Find(Id: Int64): TJSONObject;
    function FindByEmail(const Email: string): TJSONObject;
    { Every user, without the password hashes. }
    function List: TJSONArray;
    procedure SetPassword(Id: Int64; const Password: string);
    procedure SetRole(Id: Int64; const Role: string);
    { A user who may not log in any more (their tokens run out too). }
    procedure SetActive(Id: Int64; Active: Boolean);
    function Count: Integer;
    { ---- refresh tokens (used by the routes) ---- }
    function NewRefreshToken(UserId: Int64; Days: Integer = 30): string;
    { The user of a refresh token that is valid; it is used up. 0 when not valid. }
    function UseRefreshToken(const Token: string): Int64;
    procedure RevokeRefreshToken(const Token: string);
    property Db: TDatabase read FDb;
  end;

{ POST Prefix/login {"email","password"} -> {"token","refresh_token","expires_in","user"};
  POST Prefix/refresh {"refresh_token"} -> the same with new tokens;
  POST Prefix/logout {"refresh_token"} -> 204; GET Prefix/me -> the user (with the token).
  The token's claims: sub (the user's id), email, name, role. }
procedure AddAuthRoutes(Web: TWebServer; Users: TUserStore; const Secret: string;
  const Prefix: string = '/api/auth'; TokenMinutes: Integer = 15);
{ 403 unless the request's token has one of these roles. }
procedure RequireRole(Req: TWebRequest; const Roles: array of string);

type
  { An app's side: logs in, keeps the tokens, renews them, sends them along. }
  TAuthClient = class
  private
    FHttp: THttpClient;
    FToken, FRefresh, FError, FPrefix: string;
    FUser: TJSONObject;
    FExpires: TDateTime;
    function TakeTokens(R: THttpResponse): Boolean;
    function Renew: Boolean;
    procedure Prepare;
  public
    constructor Create(const BaseUrl: string; const Prefix: string = '/api/auth');
    destructor Destroy; override;
    { True when the e-mail and password are right; Error says why not. }
    function Login(const Email, Password: string): Boolean;
    procedure Logout;
    function LoggedIn: Boolean;
    { Requests with the token (renewed first when it runs out). }
    function Get(const Path: string): THttpResponse;
    function PostJson(const Path: string; Json: TJSONData): THttpResponse;
    function Delete(const Path: string): THttpResponse;
    { The user who is logged in (id, email, name, role); nil before Login. }
    property User: TJSONObject read FUser;
    { Why the last Login failed, for the user. }
    property Error: string read FError;
    { The refresh token: keep it (Pastel.Config, a file) to stay logged in;
      give it back with ResumeWith. }
    property RefreshToken: string read FRefresh;
    function ResumeWith(const ARefreshToken: string): Boolean;
    property Http: THttpClient read FHttp;
  end;

implementation

uses
  DateUtils, Pastel.Json, Pastel.Jwt, Pastel.Crypto, Pastel.Lang;

{ ---- TUserStore ---- }

constructor TUserStore.Create(ADb: TDatabase);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TUserStore.CreateTables;
var
  Id: string;
begin
  case FDb.Kind of
    dbPostgres: Id := 'bigserial primary key';
    dbMySQL: Id := 'bigint auto_increment primary key';
  else
    Id := 'integer primary key autoincrement';
  end;
  FDb.Exec('create table if not exists users (id ' + Id + ', email varchar(200) not null unique, ' +
    'name varchar(200) not null default '''', password_hash varchar(200) not null, ' +
    'role varchar(50) not null default ''user'', active integer not null default 1, ' +
    'created_at varchar(32) not null default '''')', []);
  FDb.Exec('create table if not exists refresh_tokens (token_hash varchar(64) primary key, ' +
    'user_id bigint not null, expires_at varchar(32) not null)', []);
end;

function NormalEmail(const Email: string): string;
begin
  Result := LowerCase(Trim(Email));
end;

function Public(Row: TJSONObject): TJSONObject;
begin
  if Row <> nil then
    Row.Delete('password_hash');
  Result := Row;
end;

function TUserStore.Add(const Email, Password, Name, Role: string): Int64;
var
  E: string;
begin
  E := NormalEmail(Email);
  if (Pos('@', E) < 2) or (Pos(' ', E) > 0) then
    raise EAuthError.CreateFmt('"%s" is not an e-mail address', [Email]);
  if Length(Password) < 8 then
    raise EAuthError.Create('a password needs at least 8 characters');
  if FDb.QueryInt('select count(*) from users where email = ?', [E]) > 0 then
    raise EAuthError.CreateFmt('there is a user with %s already', [E]);
  Result := FDb.Insert('insert into users (email, name, password_hash, role, active, created_at) values (?, ?, ?, ?, 1, ?)',
    [E, Name, HashPassword(Password), Role, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]);
end;

function TUserStore.Check(const Email, Password: string): TJSONObject;
var
  Row: TJSONObject;
begin
  Result := nil;
  Row := FDb.QueryOne('select * from users where email = ?', [NormalEmail(Email)]);
  if Row = nil then
  begin
    VerifyPassword(Password, HashPassword('x', 1000));   { about the same time: no hint whether the e-mail exists }
    Exit;
  end;
  if (JInt(Row, 'active') = 1) and VerifyPassword(Password, JStr(Row, 'password_hash')) then
    Result := Public(Row)
  else
    Row.Free;
end;

function TUserStore.Find(Id: Int64): TJSONObject;
begin
  Result := Public(FDb.QueryOne('select * from users where id = ?', [Id]));
end;

function TUserStore.FindByEmail(const Email: string): TJSONObject;
begin
  Result := Public(FDb.QueryOne('select * from users where email = ?', [NormalEmail(Email)]));
end;

function TUserStore.List: TJSONArray;
begin
  Result := FDb.Query('select id, email, name, role, active, created_at from users order by email', []);
end;

procedure TUserStore.SetPassword(Id: Int64; const Password: string);
begin
  if Length(Password) < 8 then
    raise EAuthError.Create('a password needs at least 8 characters');
  FDb.Exec('update users set password_hash = ? where id = ?', [HashPassword(Password), Id]);
  FDb.Exec('delete from refresh_tokens where user_id = ?', [Id]);    { log out everywhere }
end;

procedure TUserStore.SetRole(Id: Int64; const Role: string);
begin
  FDb.Exec('update users set role = ? where id = ?', [Role, Id]);
end;

procedure TUserStore.SetActive(Id: Int64; Active: Boolean);
begin
  FDb.Exec('update users set active = ? where id = ?', [Ord(Active), Id]);
  if not Active then
    FDb.Exec('delete from refresh_tokens where user_id = ?', [Id]);
end;

function TUserStore.Count: Integer;
begin
  Result := FDb.QueryInt('select count(*) from users', []);
end;

function Stamp(D: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', LocalTimeToUniversal(D));
end;

function TUserStore.NewRefreshToken(UserId: Int64; Days: Integer): string;
begin
  Result := RandomToken(32);
  FDb.Exec('insert into refresh_tokens (token_hash, user_id, expires_at) values (?, ?, ?)',
    [Sha256Hex(Result), UserId, Stamp(Now + Days)]);
  FDb.Exec('delete from refresh_tokens where expires_at < ?', [Stamp(Now)]);
end;

function TUserStore.UseRefreshToken(const Token: string): Int64;
var
  Row: TJSONObject;
begin
  Result := 0;
  Row := FDb.QueryOne('select user_id, expires_at from refresh_tokens where token_hash = ?', [Sha256Hex(Token)]);
  if Row = nil then
    Exit;
  try
    FDb.Exec('delete from refresh_tokens where token_hash = ?', [Sha256Hex(Token)]);   { used once }
    if JStr(Row, 'expires_at') > Stamp(Now) then
      Result := JInt(Row, 'user_id');
  finally
    Row.Free;
  end;
end;

procedure TUserStore.RevokeRefreshToken(const Token: string);
begin
  FDb.Exec('delete from refresh_tokens where token_hash = ?', [Sha256Hex(Token)]);
end;

{ ---- the routes ---- }

type
  TAuthRoutes = class
    Users: TUserStore;
    Secret: string;
    Minutes: Integer;
    function Answer(User: TJSONObject): TJSONObject;
    procedure Login(Req: TWebRequest; Res: TWebResponse);
    procedure Refresh(Req: TWebRequest; Res: TWebResponse);
    procedure Logout(Req: TWebRequest; Res: TWebResponse);
    procedure Me(Req: TWebRequest; Res: TWebResponse);
  end;

var
  AllRoutes: array of TAuthRoutes;

function TAuthRoutes.Answer(User: TJSONObject): TJSONObject;
var
  Claims: TJSONObject;
begin
  Claims := JObject(['sub', JStr(User, 'id'), 'email', JStr(User, 'email'), 'name', JStr(User, 'name'),
    'role', JStr(User, 'role')]);
  { JwtSign frees the claims }
  Result := JObject(['token', JwtSign(Claims, Secret, Minutes * 60),
    'refresh_token', Users.NewRefreshToken(JInt(User, 'id')),
    'expires_in', Minutes * 60]);
  Result.Add('user', JObject(['id', JInt(User, 'id'), 'email', JStr(User, 'email'), 'name', JStr(User, 'name'),
    'role', JStr(User, 'role')]));
end;

procedure TAuthRoutes.Login(Req: TWebRequest; Res: TWebResponse);
var
  Body, User: TJSONObject;
begin
  Body := Req.JsonObject;
  User := Users.Check(JStr(Body, 'email'), JStr(Body, 'password'));
  if User = nil then
    raise EWebError.Create(401, 'the e-mail or the password is wrong');
  try
    Res.Json(Answer(User));
  finally
    User.Free;
  end;
end;

procedure TAuthRoutes.Refresh(Req: TWebRequest; Res: TWebResponse);
var
  Id: Int64;
  User: TJSONObject;
begin
  Id := Users.UseRefreshToken(JStr(Req.JsonObject, 'refresh_token'));
  User := nil;
  if Id > 0 then
    User := Users.Find(Id);
  if (User = nil) or (JInt(User, 'active') <> 1) then
  begin
    User.Free;
    raise EWebError.Create(401, 'the refresh token is not valid; log in again');
  end;
  try
    Res.Json(Answer(User));
  finally
    User.Free;
  end;
end;

procedure TAuthRoutes.Logout(Req: TWebRequest; Res: TWebResponse);
begin
  Users.RevokeRefreshToken(JStr(Req.JsonObject, 'refresh_token'));
  Res.NoContent;
end;

procedure TAuthRoutes.Me(Req: TWebRequest; Res: TWebResponse);
var
  User: TJSONObject;
begin
  User := Users.Find(StrToInt64Def(Req.Claim('sub'), 0));
  if User = nil then
    raise EWebError.Create(404, 'no such user');
  Res.Json(User);
end;

procedure AddAuthRoutes(Web: TWebServer; Users: TUserStore; const Secret, Prefix: string; TokenMinutes: Integer);
var
  R: TAuthRoutes;
begin
  if Length(Secret) < 32 then
    raise EAuthError.Create('the secret for tokens needs at least 32 characters (openssl rand -base64 32)');
  R := TAuthRoutes.Create;
  R.Users := Users;
  R.Secret := Secret;
  R.Minutes := TokenMinutes;
  SetLength(AllRoutes, Length(AllRoutes) + 1);
  AllRoutes[High(AllRoutes)] := R;
  Web.Post(Prefix + '/login', @R.Login);
  Web.Post(Prefix + '/refresh', @R.Refresh);
  Web.Post(Prefix + '/logout', @R.Logout);
  Web.RequireJwt(Prefix + '/me', Secret);
  Web.Get(Prefix + '/me', @R.Me);
  { guessing passwords: at most 10 tries a minute from one address }
  Web.RateLimit(Prefix + '/login', 10, 60);
end;

procedure RequireRole(Req: TWebRequest; const Roles: array of string);
var
  R, Have: string;
begin
  Have := Req.Claim('role');
  for R in Roles do
    if SameText(R, Have) then
      Exit;
  raise EWebError.Create(403, 'this needs the role ' + string.Join(' or ', Roles));
end;

{ ---- TAuthClient ---- }

constructor TAuthClient.Create(const BaseUrl, Prefix: string);
begin
  inherited Create;
  FHttp := THttpClient.Create(BaseUrl);
  FPrefix := Prefix;
end;

destructor TAuthClient.Destroy;
begin
  FHttp.Free;
  FUser.Free;
  inherited Destroy;
end;

function TAuthClient.TakeTokens(R: THttpResponse): Boolean;
var
  J: TJSONData;
begin
  Result := False;
  if not R.Ok then
    Exit;
  J := R.Json;
  try
    FToken := JStr(J, 'token');
    FRefresh := JStr(J, 'refresh_token');
    FExpires := Now + (JInt(J, 'expires_in', 900) - 30) / SecsPerDay;
    FreeAndNil(FUser);
    if JFind(J, 'user') is TJSONObject then
      FUser := TJSONObject(JFind(J, 'user').Clone);
    Result := FToken <> '';
  finally
    J.Free;
  end;
end;

function TAuthClient.Login(const Email, Password: string): Boolean;
var
  R: THttpResponse;
  Body: TJSONObject;
begin
  FError := '';
  FHttp.BearerToken := '';
  Body := JObject(['email', Email, 'password', Password]);
  try
    try
      R := FHttp.PostJson(FPrefix + '/login', Body);
    except
      on E: Exception do
      begin
        FError := Format(_('The server cannot be reached: %s'), [E.Message]);
        Exit(False);
      end;
    end;
  finally
    Body.Free;
  end;
  Result := TakeTokens(R);
  if not Result then
    if R.Status = 401 then
      FError := _('The e-mail or the password is wrong.')
    else if R.Status = 429 then
      FError := _('Too many tries; wait a minute.')
    else
      FError := Format(_('The server answered %d.'), [R.Status]);
end;

function TAuthClient.Renew: Boolean;
var
  R: THttpResponse;
  Body: TJSONObject;
begin
  Result := False;
  if FRefresh = '' then
    Exit;
  FHttp.BearerToken := '';
  Body := JObject(['refresh_token', FRefresh]);
  try
    R := FHttp.PostJson(FPrefix + '/refresh', Body);
  finally
    Body.Free;
  end;
  Result := TakeTokens(R);
  if not Result then
  begin
    FToken := '';
    FRefresh := '';
  end;
end;

function TAuthClient.ResumeWith(const ARefreshToken: string): Boolean;
begin
  FRefresh := ARefreshToken;
  Result := Renew;
end;

procedure TAuthClient.Prepare;
begin
  if (FToken = '') or (Now >= FExpires) then
    if not Renew then
      raise EAuthError.Create(_('Please log in again.'));
  FHttp.BearerToken := FToken;
end;

procedure TAuthClient.Logout;
var
  Body: TJSONObject;
begin
  if FRefresh <> '' then
  begin
    Body := JObject(['refresh_token', FRefresh]);
    try
      try
        FHttp.PostJson(FPrefix + '/logout', Body);
      except
        on Exception do ;     { offline: the token runs out by itself }
      end;
    finally
      Body.Free;
    end;
  end;
  FToken := '';
  FRefresh := '';
  FreeAndNil(FUser);
end;

function TAuthClient.LoggedIn: Boolean;
begin
  Result := (FToken <> '') or (FRefresh <> '');
end;

function TAuthClient.Get(const Path: string): THttpResponse;
begin
  Prepare;
  Result := FHttp.Get(Path);
end;

function TAuthClient.PostJson(const Path: string; Json: TJSONData): THttpResponse;
begin
  Prepare;
  Result := FHttp.PostJson(Path, Json);
end;

function TAuthClient.Delete(const Path: string): THttpResponse;
begin
  Prepare;
  Result := FHttp.Delete(Path);
end;

procedure FreeRoutes;
var
  R: TAuthRoutes;
begin
  for R in AllRoutes do
    R.Free;
end;

finalization
  FreeRoutes;

end.
