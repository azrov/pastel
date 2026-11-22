{ Tests of Pastel.Sensors on a computer: no sensors; events of NFC and Bluetooth as the phone sends them. }
unit sensors_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Sensors;

type
  TSensorsTests = class(TTestSuite)
  private
    FLog: string;
    procedure Found(Sender: TObject; const Address, Name: string; Rssi: Integer);
    procedure Value(Sender: TObject; const Address, Characteristic: string; const V: RawByteString);
    procedure Services(Sender: TObject; const Address: string; const Chars: TStringArray);
    procedure Tag(Sender: TObject; const Id, Text: string);
    procedure Err(Sender: TObject; const Address, Error: string);
  published
    procedure NoSensorsOnAComputer;
    procedure PhoneEvents;
  end;

implementation

procedure TSensorsTests.Found(Sender: TObject; const Address, Name: string; Rssi: Integer);
begin
  FLog := FLog + Format('found %s %s %d;', [Address, Name, Rssi]);
end;

procedure TSensorsTests.Value(Sender: TObject; const Address, Characteristic: string; const V: RawByteString);
begin
  FLog := FLog + Format('value %s %d %d;', [Characteristic, Length(V), Ord(V[2])]);
end;

procedure TSensorsTests.Services(Sender: TObject; const Address: string; const Chars: TStringArray);
begin
  FLog := FLog + Format('services %d;', [Length(Chars)]);
end;

procedure TSensorsTests.Tag(Sender: TObject; const Id, Text: string);
begin
  FLog := FLog + Format('tag %s %s;', [Id, Text]);
end;

procedure TSensorsTests.Err(Sender: TObject; const Address, Error: string);
begin
  FLog := FLog + 'error;';
end;

procedure TSensorsTests.NoSensorsOnAComputer;
var
  S: TSensor;
begin
  S := TSensor.Create(nil);
  try
    AssertFalse(S.Available);
    S.Active := True;
    AssertFalse(S.Active, 'stays off');
  finally
    S.Free;
  end;
end;

procedure TSensorsTests.PhoneEvents;
var
  B: TBluetoothLE;
  N: TNfcReader;
begin
  B := TBluetoothLE.Create(nil);
  N := TNfcReader.Create(nil);
  try
    B.OnDeviceFound := @Found;
    B.OnValue := @Value;
    B.OnServices := @Services;
    B.OnError := @Err;
    N.OnTag := @Tag;
    FLog := '';
    DeliverSenseLine('ble-found'#9'AA:BB:CC:DD:EE:FF'#9'Scale'#9'-60');
    DeliverSenseLine('ble-services'#9'AA:BB:CC:DD:EE:FF'#9'180d/2a37,180f/2a19');
    DeliverSenseLine('ble-changed'#9'AA:BB:CC:DD:EE:FF'#9'2a37'#9'0048');
    DeliverSenseLine('nfc'#9'04A2B3'#9'hello');
    AssertEquals('found AA:BB:CC:DD:EE:FF Scale -60;services 2;value 2a37 2 72;tag 04A2B3 hello;', FLog);
    FLog := '';
    B.Scan;
    AssertEquals('error;', FLog, 'computers: said so');
  finally
    N.Free;
    B.Free;
  end;
end;

initialization
  RegisterTests(TSensorsTests);

end.
