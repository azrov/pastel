# Pastel.Auth

Users, passwords and roles for a server, and login for its apps.

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

`uses Pastel.Auth;` · source: [framework/src/pastel.auth.pas](../../framework/src/pastel.auth.pas)

## Types

### EAuthError

```pascal
type EAuthError = class(Exception)
```

### TUserStore

```pascal
type TUserStore = class
```

| | |
|---|---|
| `constructor Create(ADb: TDatabase)` |  |
| `procedure CreateTables` | users and refresh_tokens, when they are missing |
| `function Add(const Email: string; const Password: string; const Name: string; const Role: string = 'user'): Int64` | A new user; EAuthError when the e-mail is taken or the password too short (8). |
| `function Check(const Email: string; const Password: string): TJSONObject` | The user (id, email, name, role, active) with this e-mail and password; nil otherwise. |
| `function Find(Id: Int64): TJSONObject` |  |
| `function FindByEmail(const Email: string): TJSONObject` |  |
| `function List: TJSONArray` | Every user, without the password hashes. |
| `procedure SetPassword(Id: Int64; const Password: string)` |  |
| `procedure SetRole(Id: Int64; const Role: string)` |  |
| `procedure SetActive(Id: Int64; Active: Boolean)` | A user who may not log in any more (their tokens run out too). |
| `function Count: Integer` |  |
| `function NewRefreshToken(UserId: Int64; Days: Integer = 30): string` |  |
| `function UseRefreshToken(const Token: string): Int64` | The user of a refresh token that is valid; it is used up. 0 when not valid. |
| `procedure RevokeRefreshToken(const Token: string)` |  |
| `property Db: TDatabase` |  |

### TAuthClient

```pascal
type TAuthClient = class
```

An app's side: logs in, keeps the tokens, renews them, sends them along.

| | |
|---|---|
| `constructor Create(const BaseUrl: string; const Prefix: string = '/api/auth')` |  |
| `destructor Destroy` |  |
| `function Login(const Email: string; const Password: string): Boolean` | True when the e-mail and password are right; Error says why not. |
| `procedure Logout` |  |
| `function LoggedIn: Boolean` |  |
| `function Get(const Path: string): THttpResponse` | Requests with the token (renewed first when it runs out). |
| `function PostJson(const Path: string; Json: TJSONData): THttpResponse` |  |
| `function Delete(const Path: string): THttpResponse` |  |
| `property User: TJSONObject` | The user who is logged in (id, email, name, role); nil before Login. |
| `property Error: string` | Why the last Login failed, for the user. |
| `property RefreshToken: string` | The refresh token: keep it (Pastel.Config, a file) to stay logged in; give it back with ResumeWith. |
| `function ResumeWith(const ARefreshToken: string): Boolean` |  |
| `property Http: THttpClient` |  |

## Routines

### AddAuthRoutes

```pascal
procedure AddAuthRoutes(Web: TWebServer; Users: TUserStore; const Secret: string; const Prefix: string = '/api/auth'; TokenMinutes: Integer = 15)
```

POST Prefix/login {"email","password"} -> {"token","refresh_token","expires_in","user"};
POST Prefix/refresh {"refresh_token"} -> the same with new tokens;
POST Prefix/logout {"refresh_token"} -> 204; GET Prefix/me -> the user (with the token).
The token's claims: sub (the user's id), email, name, role.

### RequireRole

```pascal
procedure RequireRole(Req: TWebRequest; const Roles: array of string)
```

403 unless the request's token has one of these roles.

