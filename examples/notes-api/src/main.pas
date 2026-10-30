{ notes-api - a small web API for notes, with a web page in public/.
  An example of a Pastel web service: routes, JSON, errors, static files,
  a health check, settings, clean shutdown.
  pastel run, then open http://localhost:8080 }
program notes_api;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, Pastel.Service, Pastel.Web, Pastel.Json, Pastel.Log, Pastel.Files,
  AppInfo, Notes;

type
  TNotesService = class(TWebService)
  private
    FStore: TNoteStore;
    procedure ListNotes(Req: TWebRequest; Res: TWebResponse);
    procedure GetNote(Req: TWebRequest; Res: TWebResponse);
    procedure CreateNote(Req: TWebRequest; Res: TWebResponse);
    procedure UpdateNote(Req: TWebRequest; Res: TWebResponse);
    procedure DeleteNote(Req: TWebRequest; Res: TWebResponse);
  protected
    procedure Routes(Web: TWebServer); override;
    procedure Started; override;
  public
    destructor Destroy; override;
  end;

procedure TNotesService.Routes(Web: TWebServer);
begin
  Web.Get('/api/notes', @ListNotes);
  Web.Get('/api/notes/:id', @GetNote);
  Web.Post('/api/notes', @CreateNote);
  Web.Put('/api/notes/:id', @UpdateNote);
  Web.Delete('/api/notes/:id', @DeleteNote);
  Web.Health('/health', AppVersion);
  { the web page: public/ next to the program (a package), or in the project }
  if DirectoryExists(JoinPath([AppDir, 'public'])) then
    Web.Static('/', JoinPath([AppDir, 'public']))
  else
    Web.Static('/', 'public');
end;

procedure TNotesService.Started;
begin
  { the notes live in StateDir: ./data while developing, /var/lib/notes-api under systemd }
  FStore := TNoteStore.Create(StateDir + 'notes.json');
  Log.Info('%d note(s) in %s', [FStore.Count, StateDir]);
  inherited Started;      { starts the web server }
end;

destructor TNotesService.Destroy;
begin
  inherited Destroy;
  FStore.Free;
end;

procedure TNotesService.ListNotes(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Json(FStore.List);
end;

procedure TNotesService.GetNote(Req: TWebRequest; Res: TWebResponse);
var
  Note: TJSONObject;
begin
  Note := FStore.Find(Req.ParamInt('id'));
  if Note = nil then
    raise EWebError.Create(404, 'no note with this id');
  Res.Json(Note);
end;

procedure TNotesService.CreateNote(Req: TWebRequest; Res: TWebResponse);
var
  Body: TJSONObject;
begin
  Body := Req.JsonObject;
  try
    Res.Json(FStore.Add(JStr(Body, 'title'), JStr(Body, 'text')), 201);
  except
    on E: ENoteError do
      raise EWebError.Create(422, E.Message);
  end;
end;

procedure TNotesService.UpdateNote(Req: TWebRequest; Res: TWebResponse);
var
  Body, Note: TJSONObject;
begin
  Body := Req.JsonObject;
  try
    Note := FStore.Update(Req.ParamInt('id'), JStr(Body, 'title'), JStr(Body, 'text'));
  except
    on E: ENoteError do
      raise EWebError.Create(422, E.Message);
  end;
  if Note = nil then
    raise EWebError.Create(404, 'no note with this id');
  Res.Json(Note);
end;

procedure TNotesService.DeleteNote(Req: TWebRequest; Res: TWebResponse);
begin
  if not FStore.Remove(Req.ParamInt('id')) then
    raise EWebError.Create(404, 'no note with this id');
  Res.NoContent;
end;

var
  Service: TNotesService;
begin
  Service := TNotesService.Create(AppName, AppVersion);
  try
    ExitCode := Service.Run;
  finally
    Service.Free;
  end;
end.
