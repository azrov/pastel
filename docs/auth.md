# Users and login: Pastel.Auth

A server with users, passwords and roles, and apps that log in to it.

## The server

```pascal
uses
  Pastel.Auth;

Users := TUserStore.Create(Db);
Users.CreateTables;                                   // users and refresh_tokens
if Users.Count = 0 then
  Users.Add('admin@shop.com', Config.Require('auth.first_password'), 'Admin', 'admin');

AddAuthRoutes(Web, Users, Config.Require('auth.secret'));   // at least 32 characters: openssl rand -base64 32
Web.RequireJwt('/api/shop', Config.Require('auth.secret'));  // these routes need a login
```

| Route | |
|---|---|
| `POST /api/auth/login` | `{"email", "password"}` → `{"token", "refresh_token", "expires_in", "user"}`; 401 when wrong; at most 10 tries a minute from one address |
| `POST /api/auth/refresh` | `{"refresh_token"}` → new tokens; a refresh token works once |
| `POST /api/auth/logout` | `{"refresh_token"}` → the refresh token is removed |
| `GET /api/auth/me` | The user of the token |

In a handler, the token's claims say who asks: `Req.Claim('sub')` (the user's id), `email`, `name`, `role`.

```pascal
procedure TShop.DeleteCustomer(Req: TWebRequest; Res: TWebResponse);
begin
  RequireRole(Req, ['admin', 'manager']);     // 403 for the others
  ...
end;
```

Managing users: `Add(Email, Password, Name, Role)`, `Check(Email, Password)`, `Find(Id)`, `FindByEmail`, `List`, `SetPassword` (also logs the user out everywhere), `SetRole`, `SetActive(Id, False)`.

**How it is kept safe:** passwords are stored as PBKDF2-SHA256 hashes with a salt (210,000 rounds); a wrong e-mail takes as long as a wrong password, so answers do not tell which e-mails exist; the token (a JWT) is valid for 15 minutes, the refresh token for 30 days, stored only as a hash, and replaced at every use. Put the server behind HTTPS ([deploy.md](deploy.md)).

## The app

```pascal
uses
  Pastel.Auth, Pastel.Dialogs;

Client := TAuthClient.Create(SettingsForm.ServerUrl);
Email := SettingsForm.LastEmail;
while LoginDialog(_('Salon'), Email, Password, Client.Error) do
  if Client.Login(Email, Password) then
    Break;
if not Client.LoggedIn then
  Application.Terminate;

R := Client.Get('/api/shop/customers');       // with the token; renewed when it ran out
Customers.LoadJson(TJSONArray(R.Json));
```

`LoginDialog` asks for the e-mail and the password, and shows the last problem (`Client.Error`: a wrong password, no network, too many tries) in the app's language. `Client.User` is the user (`name`, `role`) — show or hide what their role may do.

To stay logged in between starts, keep `Client.RefreshToken` (in the user's settings) and next time call `Client.ResumeWith(Saved)`; it is `False` when the user must log in again. `Client.Logout` ends it on the server too.

| | |
|---|---|
| `Login(Email, Password)`, `Logout`, `LoggedIn`, `ResumeWith(RefreshToken)` | |
| `Get(Path)`, `PostJson(Path, Json)`, `Delete(Path)` | Requests with the token |
| `User`, `Error`, `RefreshToken`, `Http` | |
