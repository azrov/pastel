{ salon-api - the server of the salon system.

    pastel run               then: curl localhost:8080/api/customers
    pastel test

  The data and its checks: SalonStore (examples/salon-core), shared with
  the desktop app. The routes: src/controllers/saloncontroller.pas. }
program salon_api;

{$mode objfpc}{$H+}

uses
  SysUtils, Pastel.Service, Pastel.Web, Pastel.Config, Pastel.Db, Pastel.Log, AppInfo,
  SalonStore, SalonController;

type
  TSalonApi = class(TWebService)
  private
    FStore: TSalonStore;
    FController: TSalonController;
  protected
    procedure Configure(C: TConfig); override;
    procedure Started; override;
    procedure Stopping; override;
    procedure Routes(Web: TWebServer); override;
  public
    destructor Destroy; override;
  end;

procedure TSalonApi.Configure(C: TConfig);
begin
  inherited Configure(C);
  C.SetDefault('database.url', 'sqlite:data/salon.db');
end;

procedure TSalonApi.Started;
var
  Db: TDatabase;
begin
  Db := TDatabase.Open(Config.Require('database.url'));
  Log.Info('database %s', [Db.SafeUrl]);
  FStore := TSalonStore.Create(Db, True);
  FStore.CreateTables;
  FController := TSalonController.Create(FStore);
  inherited Started;                  { starts the web server; it calls Routes }
end;

procedure TSalonApi.Routes(Web: TWebServer);
var
  Keys: TStringArray;
begin
  Web.RateLimit('/api', 600, 60);
  { with [api] keys = ["..."], every shop computer needs one of them (X-API-Key) }
  Keys := Config.GetList('api.keys');
  if Length(Keys) > 0 then
    Web.RequireApiKey('/api', Keys);
  FController.Routes(Web);
  Web.Health('/health', AppVersion);
end;

procedure TSalonApi.Stopping;
begin
  inherited Stopping;                 { stops the web server first }
  FreeAndNil(FController);
  FreeAndNil(FStore);
end;

destructor TSalonApi.Destroy;
begin
  inherited Destroy;
  FController.Free;
  FStore.Free;
end;

var
  Api: TSalonApi;
begin
  Api := TSalonApi.Create(AppName, AppVersion);
  try
    ExitCode := Api.Run;
  finally
    Api.Free;
  end;
end.
