# Guide: a REST API with a database

From an empty folder to an API running on a server: tasks with a
title, a priority and a done flag. About half an hour.

## 1. The project

```sh
pastel new api tasks
cd tasks
pastel run
```

```sh
curl -s localhost:8080/api/tasks -d '{"title": "Süt al"}'
curl -s localhost:8080/api/tasks
```

The parts:

| | |
|---|---|
| `src/main.pas` | the service: opens the database, runs the migrations, adds the routes |
| `src/models/tasks.pas` | the model: every SQL statement about tasks |
| `src/controllers/taskscontroller.pas` | the controller: routes, checks, JSON answers |
| `database/migrations/` | the tables |
| `tests/tasks_test.pas` | tests of the model and the API |
| `config.toml` | settings while developing (SQLite in `data/app.db`) |

In VS Code the Pastel panel lists the routes, the jobs and the
migrations; above every route is **▶ Send**, which sends a request to the
running API and shows the answer.

## 2. A new column: a migration

```sh
pastel migrate new add_priority
```

`database/migrations/002_add_priority.sql`:

```sql
alter table tasks add column priority integer not null default 0;
```

The next `pastel run` applies it (or `pastel migrate` now; `pastel migrate
status` shows what ran). Never change a migration that ran somewhere; add
a new one.

## 3. The model

In `src/models/tasks.pas`, select the new column everywhere and add it to
`Add`:

```pascal
function TTasks.Add(const Title: string; Priority: Integer; Done: Boolean): TJSONObject;
var
  Id: Int64;
begin
  Id := FDb.Insert('insert into tasks (title, priority, done, created_at) values (?, ?, ?, ?)',
    [Title, Priority, Done, DateToISO8601(LocalTimeToUniversal(Now))]);
  Result := Find(Id);
end;
```

Values always go in as `?`, never pasted into the SQL. More:
[database.md](database.md).

## 4. The controller

Check the input with `Req.Validate`; every problem goes back at once as
422:

```pascal
procedure TTasksController.CreateTask(Req: TWebRequest; Res: TWebResponse);
var
  V: TValidator;
  Title: string;
  Priority: Int64;
begin
  V := Req.Validate;
  Title := V.Str('title', 1, 200);
  Priority := V.OptInt('priority', 0, 0, 5);
  V.Check;
  Res.Json(FTasks.Add(Title, Priority, False), 201);
end;
```

A new route, in `Routes`:

```pascal
Web.Get('/api/tasks/urgent', @UrgentTasks);
```

Errors: `raise EWebError.Create(404, 'no task with this id')`; anything
unexpected becomes 500 and goes to the log. More: [web.md](web.md).

## 5. Tests

```sh
pastel test
```

The tests get a fresh SQLite database each, with the migrations applied.
Add one for the priority:

```pascal
procedure TTasksTests.KeepsThePriority;
var
  T: TJSONObject;
begin
  Model.Add('x', 3, False).Free;
  T := Model.Find(1);
  try
    AssertEquals(3, JInt(T, 'priority'));
  finally
    T.Free;
  end;
end;
```

`pastel test --watch` runs them on every save.

## 6. Who may call it

In `config.toml`:

```toml
[api]
keys = ["a-long-random-key-from-openssl-rand"]
```

Now `/api/...` needs `X-API-Key: <key>` (Send Request in VS Code adds it
from `config.toml`). For users who log in, use JWT instead:
[web.md](web.md#who-is-calling-api-keys-and-tokens). The example key
`CHANGE-ME-...` is refused, so a server never runs with it.

## 7. Work in the background

Sending a mail when a task is done should not slow the answer down:

```pascal
FMail := TWorkerPool.Create('mail', 2, @SendDoneMail);
...
FMail.Submit(JObject(['id', Id]).AsJSON);
```

[services.md](services.md#background-work-pastelworkers).

## 8. PostgreSQL

```toml
[database]
url = "postgres://tasks:password@localhost/tasks"
```

Nothing else changes: the same migrations and SQL run on SQLite,
PostgreSQL and MySQL/MariaDB. Add `libpq5` to `[package.deb] depends`.

## 9. On a server

```sh
pastel package deb
scp dist/tasks_0.1.0_amd64.deb you@server:
ssh you@server
sudo apt install ./tasks_0.1.0_amd64.deb
sudo nano /etc/tasks/config.toml        # the real key, the database
sudo systemctl start tasks
```

Or `pastel package docker`. HTTPS with Caddy or nginx in front:
[deploy.md](deploy.md).
