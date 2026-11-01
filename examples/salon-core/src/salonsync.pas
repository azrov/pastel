{ The desktop side of synchronization: sends what changed here to the
  server, takes what changed there.

    R := SyncWithServer(Store, 'https://salon.example.com', ApiKey, LastSync);
    StatusLabel.Text := Format('%d sent, %d received', [R.Sent, R.Received]);

  The server (examples/salon-api) answers POST /api/sync. LastSync is the
  server's time of the last sync; keep it (it is updated) and give it again
  next time, so only newer changes come. Raises EHttpError when the server
  cannot be reached: nothing is lost, the changes stay marked and go next time.
  It is Pastel.Sync's SyncWithServer on the store's TSyncStore. }
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
  Pastel.Sync;

function SyncWithServer(Store: TSalonStore; const ServerUrl, ApiKey: string; var LastSync: string): TSyncResult;
var
  R: Pastel.Sync.TSyncResult;
begin
  { all of it is Pastel.Sync's }
  R := Pastel.Sync.SyncWithServer(Store.Sync, ServerUrl, ApiKey, LastSync);
  Result.Sent := R.Sent;
  Result.Received := R.Received;
end;

end.
