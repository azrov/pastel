{ The desktop side of synchronization: sends what changed here to the
  server, takes what changed there.

    R := SyncWithServer(Store, 'https://salon.example.com', ApiKey, LastSync);
    StatusLabel.Text := Format('%d sent, %d received', [R.Sent, R.Received]);

  The server (examples/salon-api) answers POST /api/sync. LastSync is the
  server's time of the last sync; keep it (it is updated) and give it again
  next time, so only newer changes come. Raises EHttpError when the server
  cannot be reached: nothing is lost, the changes stay marked and go next time. }
unit SalonSync;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, SalonStore;

type
  TSyncResult = record
    Sent, Received: Integer;
  end;

function SyncWithServer(Store: TSalonStore; const ServerUrl, ApiKey: string; var LastSync: string): TSyncResult;

implementation

uses
  fpjson, Pastel.Http, Pastel.Json;

function CountRows(Data: TJSONObject): Integer;
var
  K: TSalonKind;
begin
  Result := 0;
  for K := Low(TSalonKind) to High(TSalonKind) do
    if Data.Find(KindTables[K]) is TJSONArray then
      Inc(Result, TJSONArray(Data.Find(KindTables[K])).Count);
end;

function SyncWithServer(Store: TSalonStore; const ServerUrl, ApiKey: string; var LastSync: string): TSyncResult;
var
  Client: THttpClient;
  Mine, Body: TJSONObject;
  Answer: TJSONData;
  R: THttpResponse;
begin
  Result.Sent := 0;
  Result.Received := 0;
  Mine := Store.Changes('', True);
  Body := TJSONObject.Create;
  Client := THttpClient.Create(ServerUrl);
  try
    Body.Strings['since'] := LastSync;
    Body.Add('changes', Mine.Clone);
    if ApiKey <> '' then
      Client.Headers := ['X-API-Key: ' + ApiKey];
    Client.Timeout := 15000;
    R := Client.PostJson('/api/sync', Body);
    R.RaiseForStatus;
    Answer := R.Json;
    try
      if not (Answer is TJSONObject) or not (TJSONObject(Answer).Find('changes') is TJSONObject) then
        raise EHttpError.Create('the server''s answer is not a sync answer');
      { theirs first: our records that changed meanwhile stay newer }
      Result.Received := Store.Apply(TJSONObject(TJSONObject(Answer).Find('changes')), False);
      Store.MarkSent(Mine);
      Result.Sent := CountRows(Mine);
      LastSync := JStr(Answer, 'now', LastSync);
    finally
      Answer.Free;
    end;
  finally
    Client.Free;
    Body.Free;
    Mine.Free;
  end;
end;

end.
