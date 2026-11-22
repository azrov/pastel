{ Pastel - hot reload on a phone: "pastel run --target android" serves the
  project's .pform files on a port of this computer, and "adb reverse" makes
  that port the phone's own (127.0.0.1:7865 on the phone). A debug build of
  the app asks for its form there a few times a second and rebuilds the form
  when the text changed, keeping what the user typed, like on a computer.
  Part of the Pastel project, MIT License. }
unit Pastel.FormServer;

{$mode objfpc}{$H+}

interface

const
  FormServerPort = 7865;

{ Serves Root's src/**/*.pform as /forms/<name>.pform until the program ends;
  False when the port is taken. }
function StartFormServer(const Root: string): Boolean;

implementation

uses
  Classes, SysUtils, fphttpserver, httpdefs;

type
  TFormServer = class(TThread)
  private
    FServer: TFPHttpServer;
    FRoot: string;
    procedure Request(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure Execute; override;
  public
    Failed: Boolean;
    constructor Create(const ARoot: string);
  end;

var
  Server: TFormServer = nil;

{ a .pform file of the project by its name (Home.pform), '' when there is none }
function FindForm(const Dir, Name: string): string;
var
  SR: TSearchRec;
begin
  Result := '';
  if FileExists(Dir + Name) then
    Exit(Dir + Name);
  if FindFirst(Dir + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) then
      begin
        Result := FindForm(Dir + SR.Name + PathDelim, Name);
        if Result <> '' then
          Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

constructor TFormServer.Create(const ARoot: string);
begin
  FRoot := IncludeTrailingPathDelimiter(ARoot);
  FreeOnTerminate := False;
  inherited Create(True);
end;

procedure TFormServer.Request(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  Name, F: string;
  L: TStringList;
begin
  Name := ExtractFileName(StringReplace(ARequest.URI, '/', PathDelim, [rfReplaceAll]));
  if Pos('?', Name) > 0 then
    Name := Copy(Name, 1, Pos('?', Name) - 1);
  F := '';
  if (Copy(ARequest.URI, 1, 7) = '/forms/') and SameText(ExtractFileExt(Name), '.pform') then
    F := FindForm(FRoot + 'src' + PathDelim, Name);
  if F = '' then
  begin
    AResponse.Code := 404;
    AResponse.Content := 'no such form';
    Exit;
  end;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(F);
    except
      AResponse.Code := 503;     { being written by the editor: asked again soon }
      Exit;
    end;
    AResponse.Code := 200;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := L.Text;
  finally
    L.Free;
  end;
end;

procedure TFormServer.Execute;
begin
  FServer := TFPHttpServer.Create(nil);
  try
    FServer.Port := FormServerPort;
    FServer.Threaded := False;
    FServer.OnRequest := @Request;
    try
      FServer.Active := True;      { serves until the program ends }
    except
      Failed := True;
    end;
  finally
    FreeAndNil(FServer);
  end;
end;

function StartFormServer(const Root: string): Boolean;
begin
  if Server <> nil then
    Exit(True);
  Server := TFormServer.Create(Root);
  Server.Start;
  Sleep(150);
  Result := not Server.Failed;
end;

end.
