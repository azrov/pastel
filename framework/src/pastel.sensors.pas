{ Pastel - the phone's senses: motion, compass, light, steps; and NFC tags.

    object Motion: TSensor
      Kind = skAccelerometer
      OnReading = MotionReading
    end
    ...
    Motion.Active := True;

    procedure THomeForm.MotionReading(Sender: TObject; const R: TSensorReading);
    begin
      if Abs(R.X) > 15 then Shaken;            // m/s²: a shake
    end;

    object Tags: TNfcReader
      OnTag = TagRead                           // the tag's id and its text (an NDEF record)
    end

    object Ble: TBluetoothLE
      OnDeviceFound = BleFound                  // Ble.Scan; Ble.Connect(Address); Ble.Subscribe(...)
    end

  Readings come about ten times a second (Interval). Android only: on computers
  Available is False and Active stays False. NFC needs [package.android]
  permissions = ["nfc"], Bluetooth ["bluetooth"] (and ["location"] before Android 12).
  Part of the Pastel project, MIT License. }
unit Pastel.Sensors;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI;

type
  { accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT),
    light (lux), proximity (cm), step counter (steps since the phone started),
    rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa) }
  TSensorKind = (skAccelerometer, skGyroscope, skMagnetometer, skLight, skProximity, skStepCounter, skRotation,
    skPressure);

  TSensorReading = record
    X, Y, Z: Single;
    Values: array of Single;
  end;

  TSensorEvent = procedure(Sender: TObject; const R: TSensorReading) of object;

  TSensor = class(TComponent)
  private
    FKind: TSensorKind;
    FActive: Boolean;
    FTimer: TTimer;
    FLast: string;
    FReading: TSensorReading;
    FOnReading: TSensorEvent;
    procedure SetActive(AValue: Boolean);
    procedure SetKind(AValue: TSensorKind);
    function GetInterval: Integer;
    procedure SetInterval(AValue: Integer);
    procedure Tick(Sender: TObject);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { the device has this sensor }
    function Available: Boolean;
    { the last reading }
    property Reading: TSensorReading read FReading;
    { skRotation: the compass, 0..360 degrees, 0 = north }
    function Heading: Single;
  published
    property Kind: TSensorKind read FKind write SetKind default skAccelerometer;
    property Active: Boolean read FActive write SetActive default False;
    property Interval: Integer read GetInterval write SetInterval default 100;
    property OnReading: TSensorEvent read FOnReading write FOnReading;
  end;

  { Internal: a component that gets the phone's events (NFC, Bluetooth). }
  TSenseReceiver = class(TComponent)
  protected
    procedure SenseLine(const P: TStringArray); virtual; abstract;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  TNfcTagEvent = procedure(Sender: TObject; const Id, Text: string) of object;
  TNfcErrorEvent = procedure(Sender: TObject; const Error: string) of object;

  { Reads NFC tags held to the phone while Active (and the app is on the screen). }
  TNfcReader = class(TSenseReceiver)
  private
    FActive, FStarted: Boolean;
    FOnTag: TNfcTagEvent;
    FOnError: TNfcErrorEvent;
    procedure SetActive(AValue: Boolean);
  protected
    procedure Loaded; override;
    procedure SenseLine(const P: TStringArray); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Active: Boolean read FActive write SetActive default True;
    { Id: the tag's id in hex; Text: its NDEF records' text (several: separated by #31) }
    property OnTag: TNfcTagEvent read FOnTag write FOnTag;
    property OnError: TNfcErrorEvent read FOnError write FOnError;
  end;

  TBleDeviceEvent = procedure(Sender: TObject; const Address, Name: string; Rssi: Integer) of object;
  TBleAddressEvent = procedure(Sender: TObject; const Address: string) of object;
  { Characteristics: 'service-uuid/characteristic-uuid' }
  TBleServicesEvent = procedure(Sender: TObject; const Address: string; const Characteristics: TStringArray) of object;
  TBleValueEvent = procedure(Sender: TObject; const Address, Characteristic: string; const Value: RawByteString) of object;
  TBleErrorEvent = procedure(Sender: TObject; const Address, Error: string) of object;

  { Bluetooth Low Energy devices: heart-rate belts, scales, sensors, beacons, printers.
    Android 12 and newer ask for dpBluetooth first (RequestPermissions); older
    ones need dpLocation for scanning. Addresses: 'AA:BB:CC:DD:EE:FF'. }
  TBluetoothLE = class(TSenseReceiver)
  private
    FOnDeviceFound: TBleDeviceEvent;
    FOnScanDone: TNotifyEvent;
    FOnConnected, FOnDisconnected: TBleAddressEvent;
    FOnServices: TBleServicesEvent;
    FOnValue: TBleValueEvent;
    FOnError: TBleErrorEvent;
    procedure Failed(const Address, Error: string);
    procedure Gatt(const Address, Service, Characteristic, Op, Value: string);
  protected
    procedure SenseLine(const P: TStringArray); override;
  public
    procedure Scan(Seconds: Integer = 10);
    procedure StopScan;
    procedure Connect(const Address: string);
    procedure Disconnect(const Address: string);
    { OnValue with it }
    procedure Read(const Address, Service, Characteristic: string);
    procedure Write(const Address, Service, Characteristic: string; const Value: RawByteString);
    { OnValue on every change }
    procedure Subscribe(const Address, Service, Characteristic: string; Enable: Boolean = True);
  published
    property OnDeviceFound: TBleDeviceEvent read FOnDeviceFound write FOnDeviceFound;
    property OnScanDone: TNotifyEvent read FOnScanDone write FOnScanDone;
    property OnConnected: TBleAddressEvent read FOnConnected write FOnConnected;
    property OnDisconnected: TBleAddressEvent read FOnDisconnected write FOnDisconnected;
    property OnServices: TBleServicesEvent read FOnServices write FOnServices;
    property OnValue: TBleValueEvent read FOnValue write FOnValue;
    property OnError: TBleErrorEvent read FOnError write FOnError;
  end;

{ Internal: a line of the phone's events, as if it came (tests). }
procedure DeliverSenseLine(const Line: string);

implementation

uses
  Math, Pastel.Env{$IFDEF ANDROID}, Pastel.Android{$ENDIF};

{$IFDEF ANDROID}
const
  { Android's Sensor.TYPE_... }
  AndroidTypes: array[TSensorKind] of Integer = (1, 4, 2, 5, 8, 19, 11, 6);
{$ENDIF}

{ ---- TSensor ---- }

constructor TSensor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 100;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := False;
end;

destructor TSensor.Destroy;
begin
  Active := False;
  inherited Destroy;
end;

procedure TSensor.Loaded;
begin
  inherited Loaded;
  if FActive then
  begin
    FActive := False;
    Active := True;
  end;
end;

function TSensor.Available: Boolean;
begin
  {$IFDEF ANDROID}
  Result := AndroidCallString('startSensor', '(I)Ljava/lang/String;', [AndroidTypes[FKind]]) <> '';
  if Result and not FActive then
    AndroidCall('stopSensor', '(I)V', [AndroidTypes[FKind]]);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TSensor.SetKind(AValue: TSensorKind);
var
  Was: Boolean;
begin
  Was := FActive;
  Active := False;
  FKind := AValue;
  Active := Was;
end;

procedure TSensor.SetActive(AValue: Boolean);
begin
  if csLoading in ComponentState then
  begin
    FActive := AValue;
    Exit;
  end;
  if AValue = FActive then
    Exit;
  {$IFDEF ANDROID}
  if AValue then
    AValue := AndroidCallString('startSensor', '(I)Ljava/lang/String;', [AndroidTypes[FKind]]) <> ''
  else
    AndroidCall('stopSensor', '(I)V', [AndroidTypes[FKind]]);
  {$ELSE}
  AValue := False;
  {$ENDIF}
  FActive := AValue;
  FLast := '';
  FTimer.Enabled := AValue;
end;

function TSensor.GetInterval: Integer;
begin
  Result := FTimer.Interval;
end;

procedure TSensor.SetInterval(AValue: Integer);
begin
  FTimer.Interval := Max(20, AValue);
end;

procedure TSensor.Tick(Sender: TObject);
var
  S: string;
  P: TStringArray;
  I: Integer;
begin
  {$IFDEF ANDROID}
  S := AndroidCallString('readSensor', '(I)Ljava/lang/String;', [AndroidTypes[FKind]]);
  {$ELSE}
  S := '';
  {$ENDIF}
  if (S = '') or (S = FLast) then
    Exit;
  FLast := S;
  P := S.Split([#9]);
  SetLength(FReading.Values, Length(P));
  for I := 0 to High(P) do
    FReading.Values[I] := StrToFloatDef(P[I], 0, InvariantFormat);
  FReading.X := 0; FReading.Y := 0; FReading.Z := 0;
  if Length(P) > 0 then FReading.X := FReading.Values[0];
  if Length(P) > 1 then FReading.Y := FReading.Values[1];
  if Length(P) > 2 then FReading.Z := FReading.Values[2];
  if Assigned(FOnReading) then
    FOnReading(Self, FReading);
end;

function TSensor.Heading: Single;
var
  X, Y, Z, W: Double;
begin
  X := FReading.X; Y := FReading.Y; Z := FReading.Z;
  if Length(FReading.Values) > 3 then
    W := FReading.Values[3]
  else
    W := Sqrt(Max(0, 1 - X * X - Y * Y - Z * Z));
  { the rotation matrix's azimuth (SensorManager.getOrientation) }
  Result := RadToDeg(ArcTan2(2 * (X * Y - W * Z), 1 - 2 * (X * X + Z * Z)));
  Result := -Result;
  if Result < 0 then
    Result := Result + 360;
end;

{ ---- the phone's events, to the receivers ---- }

type
  TPoller = class
    procedure Tick(Sender: TObject);
  end;

var
  Receivers: TFPList;
  PollTimer: TTimer;
  Poller: TPoller;

procedure DeliverSenseLine(const Line: string);
var
  P: TStringArray;
  I: Integer;
begin
  P := Line.Split([#9]);
  if Length(P) = 0 then
    Exit;
  for I := Receivers.Count - 1 downto 0 do
    if I < Receivers.Count then
      TSenseReceiver(Receivers[I]).SenseLine(P);
end;

procedure TPoller.Tick(Sender: TObject);
var
  S, Line: string;
begin
  {$IFDEF ANDROID}
  S := AndroidCallString('senseTake', '()Ljava/lang/String;', []);
  {$ELSE}
  S := '';
  {$ENDIF}
  for Line in S.Split([#10]) do
    if Line <> '' then
      DeliverSenseLine(Line);
end;

constructor TSenseReceiver.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Receivers.Add(Self);
  if PollTimer = nil then
  begin
    Poller := TPoller.Create;
    PollTimer := TTimer.Create(nil);
    PollTimer.Interval := 150;
    PollTimer.OnTimer := @Poller.Tick;
    {$IFDEF ANDROID}
    PollTimer.Enabled := True;
    {$ELSE}
    PollTimer.Enabled := False;
    {$ENDIF}
  end;
end;

destructor TSenseReceiver.Destroy;
begin
  Receivers.Remove(Self);
  inherited Destroy;
end;

{ ---- TNfcReader ---- }

constructor TNfcReader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := True;
  if not (csLoading in ComponentState) and (AOwner = nil) then
    SetActive(True);
end;

destructor TNfcReader.Destroy;
begin
  if FStarted then
    SetActive(False);
  inherited Destroy;
end;

procedure TNfcReader.Loaded;
begin
  inherited Loaded;
  if FActive then
  begin
    FActive := False;
    SetActive(True);
  end;
end;

procedure TNfcReader.SetActive(AValue: Boolean);
{$IFDEF ANDROID}
var
  Err: string;
{$ENDIF}
begin
  if csLoading in ComponentState then
  begin
    FActive := AValue;
    Exit;
  end;
  if AValue and FStarted then
    Exit;
  FActive := AValue;
  {$IFDEF ANDROID}
  if AValue then
  begin
    Err := AndroidCallString('startNfc', '()Ljava/lang/String;', []);
    if Err <> '' then
    begin
      FActive := False;
      if Assigned(FOnError) then
        FOnError(Self, Err);
      Exit;
    end;
  end
  else
    AndroidCall('stopNfc', '()V', []);
  FStarted := AValue;
  {$ELSE}
  FStarted := False;
  if AValue and Assigned(FOnError) and not (csDesigning in ComponentState) then
    FOnError(Self, 'NFC is there on phones');
  {$ENDIF}
end;

procedure TNfcReader.SenseLine(const P: TStringArray);
begin
  if (Length(P) >= 2) and (P[0] = 'nfc') and FActive and Assigned(FOnTag) then
    if Length(P) > 2 then
      FOnTag(Self, P[1], P[2])
    else
      FOnTag(Self, P[1], '');
end;

{ ---- TBluetoothLE ---- }

function ToHex(const S: RawByteString): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + IntToHex(Ord(S[I]), 2);
end;

function FromHex(const S: string): RawByteString;
var
  I: Integer;
begin
  SetLength(Result, Length(S) div 2);
  for I := 1 to Length(S) div 2 do
    Result[I] := Chr(StrToIntDef('$' + Copy(S, I * 2 - 1, 2), 0));
end;

procedure TBluetoothLE.Failed(const Address, Error: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, Address, Error);
end;

procedure TBluetoothLE.Scan(Seconds: Integer);
var
  Err: string;
begin
  {$IFDEF ANDROID}
  Err := AndroidCallString('bleScan', '(I)Ljava/lang/String;', [Seconds]);
  {$ELSE}
  if Seconds = 0 then ;
  Err := 'Bluetooth LE is there on phones';
  {$ENDIF}
  if Err <> '' then
    Failed('', Err);
end;

procedure TBluetoothLE.StopScan;
begin
  {$IFDEF ANDROID}
  AndroidCall('bleStopScan', '()V', []);
  {$ENDIF}
end;

procedure TBluetoothLE.Connect(const Address: string);
var
  Err: string;
begin
  {$IFDEF ANDROID}
  Err := AndroidCallString('bleConnect', '(Ljava/lang/String;)Ljava/lang/String;', [UpperCase(Address)]);
  {$ELSE}
  Err := 'Bluetooth LE is there on phones';
  {$ENDIF}
  if Err <> '' then
    Failed(Address, Err);
end;

procedure TBluetoothLE.Disconnect(const Address: string);
begin
  {$IFDEF ANDROID}
  AndroidCall('bleDisconnect', '(Ljava/lang/String;)V', [UpperCase(Address)]);
  {$ELSE}
  if Address = '' then ;
  {$ENDIF}
end;

procedure TBluetoothLE.Gatt(const Address, Service, Characteristic, Op, Value: string);
var
  Err: string;
begin
  {$IFDEF ANDROID}
  Err := AndroidCallString('bleGatt',
    '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
    [UpperCase(Address), LowerCase(Service), LowerCase(Characteristic), Op, Value]);
  {$ELSE}
  if (Service = '') and (Characteristic = '') and (Op = '') and (Value = '') then ;
  Err := 'Bluetooth LE is there on phones';
  {$ENDIF}
  if Err <> '' then
    Failed(Address, Err);
end;

procedure TBluetoothLE.Read(const Address, Service, Characteristic: string);
begin
  Gatt(Address, Service, Characteristic, 'read', '');
end;

procedure TBluetoothLE.Write(const Address, Service, Characteristic: string; const Value: RawByteString);
begin
  Gatt(Address, Service, Characteristic, 'write', ToHex(Value));
end;

procedure TBluetoothLE.Subscribe(const Address, Service, Characteristic: string; Enable: Boolean);
begin
  Gatt(Address, Service, Characteristic, 'notify', IntToStr(Ord(Enable)));
end;

procedure TBluetoothLE.SenseLine(const P: TStringArray);
var
  K: string;
  function At(I: Integer): string;
  begin
    if I < Length(P) then Result := P[I] else Result := '';
  end;
begin
  K := P[0];
  if K = 'ble-found' then
  begin
    if Assigned(FOnDeviceFound) then
      FOnDeviceFound(Self, At(1), At(2), StrToIntDef(At(3), 0));
  end
  else if K = 'ble-scan-done' then
  begin
    if Assigned(FOnScanDone) then
      FOnScanDone(Self);
  end
  else if K = 'ble-connected' then
  begin
    if Assigned(FOnConnected) then
      FOnConnected(Self, At(1));
  end
  else if K = 'ble-disconnected' then
  begin
    if Assigned(FOnDisconnected) then
      FOnDisconnected(Self, At(1));
  end
  else if K = 'ble-services' then
  begin
    if Assigned(FOnServices) then
      FOnServices(Self, At(1), At(2).Split([',']));
  end
  else if (K = 'ble-read') or (K = 'ble-changed') then
  begin
    if (K = 'ble-read') and (At(4) <> '') and (At(4) <> '0') then
      Failed(At(1), 'the characteristic was not read (' + At(4) + ')')
    else if Assigned(FOnValue) then
      FOnValue(Self, At(1), At(2), FromHex(At(3)));
  end
  else if K = 'ble-written' then
  begin
    if (At(4) <> '') and (At(4) <> '0') then
      Failed(At(1), 'the characteristic was not written (' + At(4) + ')');
  end
  else if K = 'ble-error' then
    Failed(At(1), At(2));
end;

initialization
  Receivers := TFPList.Create;
  RegisterNonVisual(TSensor);
  RegisterNonVisual(TNfcReader);
  RegisterNonVisual(TBluetoothLE);

finalization
  PollTimer.Free;
  Poller.Free;
  Receivers.Free;
end.
