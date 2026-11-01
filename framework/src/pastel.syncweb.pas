(* Pastel - the server side of Pastel.Sync: one route that clients sync with.

    Store := TSyncStore.Create(Db);
    Store.IsServer := True;
    Store.AddTable('customers', 'name varchar(200) not null, phone varchar(50)');
    Store.CreateTables;
    AddSyncRoute(Web, Store);                 // POST /api/sync

  Protect it like any route: [api] keys in config.toml (X-API-Key), or JWT.
  Part of the Pastel project, MIT License. *)
unit Pastel.SyncWeb;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Web, Pastel.Sync;

(* POST Path: {"since": "...", "changes": {...}} -> {"now", "applied", "changes"}.
  A record with a wrong value answers 422 with the reason. *)
procedure AddSyncRoute(Web: TWebServer; Store: TSyncStore; const Path: string = '/api/sync');

implementation

uses
  fpjson, Pastel.Log;

type
  TSyncRoute = class
    Store: TSyncStore;
    procedure Handle(Req: TWebRequest; Res: TWebResponse);
  end;

var
  Routes: array of TSyncRoute;

procedure TSyncRoute.Handle(Req: TWebRequest; Res: TWebResponse);
var
  Answer: TJSONObject;
begin
  try
    Answer := AnswerSync(Store, Req.JsonObject);
  except
    on E: ESyncInvalid do
      raise EWebError.Create(422, E.Message);
  end;
  Log.Info('sync: %d record(s) taken', [Answer.Integers['applied']]);
  Res.Json(Answer);
end;

procedure AddSyncRoute(Web: TWebServer; Store: TSyncStore; const Path: string);
var
  R: TSyncRoute;
begin
  R := TSyncRoute.Create;
  R.Store := Store;
  SetLength(Routes, Length(Routes) + 1);
  Routes[High(Routes)] := R;
  Web.Post(Path, @R.Handle);
end;

procedure FreeRoutes;
var
  R: TSyncRoute;
begin
  for R in Routes do
    R.Free;
  Routes := nil;
end;

finalization
  FreeRoutes;

end.
