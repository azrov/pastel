# Pastel.Sensors

The phone's senses: motion, compass, light, steps; and NFC tags.

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

`uses Pastel.Sensors;` · source: [framework/src/pastel.sensors.pas](../../framework/src/pastel.sensors.pas)

## Types

### TSensorKind

```pascal
type TSensorKind = (skAccelerometer, skGyroscope, skMagnetometer, skLight, skProximity, skStepCounter, skRotation, skPressure)
```

accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT),
light (lux), proximity (cm), step counter (steps since the phone started),
rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)

- `skAccelerometer` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skGyroscope` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skMagnetometer` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skLight` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skProximity` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skStepCounter` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skRotation` accelerometer (m/s², with gravity), gyroscope (rad/s), magnetometer (µT), light (lux), proximity (cm), step counter (steps since the phone started), rotation (a unit quaternion's x, y, z: Heading gives the compass), pressure (hPa)
- `skPressure`
### TSensorReading

```pascal
type TSensorReading = record
```

| | |
|---|---|
| `X: Single` |  |
| `Y: Single` |  |
| `Z: Single` |  |
| `Values: array of Single` |  |

### TSensor

```pascal
type TSensor = class(TComponent)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `function Available: Boolean` | the device has this sensor |
| `property Reading: TSensorReading` | the last reading |
| `function Heading: Single` | skRotation: the compass, 0..360 degrees, 0 = north |
| `property Kind: TSensorKind` |  |
| `property Active: Boolean` |  |
| `property Interval: Integer` |  |
| `property OnReading: TSensorEvent` |  |

### TNfcReader

```pascal
type TNfcReader = class(TSenseReceiver)
```

Reads NFC tags held to the phone while Active (and the app is on the screen).

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `property Active: Boolean` |  |
| `property OnTag: TNfcTagEvent` | Id: the tag's id in hex; Text: its NDEF records' text (several: separated by #31) |
| `property OnError: TNfcErrorEvent` |  |

### TBluetoothLE

```pascal
type TBluetoothLE = class(TSenseReceiver)
```

Bluetooth Low Energy devices: heart-rate belts, scales, sensors, beacons, printers.
Android 12 and newer ask for dpBluetooth first (RequestPermissions); older
ones need dpLocation for scanning. Addresses: 'AA:BB:CC:DD:EE:FF'.

| | |
|---|---|
| `procedure Scan(Seconds: Integer = 10)` |  |
| `procedure StopScan` |  |
| `procedure Connect(const Address: string)` |  |
| `procedure Disconnect(const Address: string)` |  |
| `procedure Read(const Address: string; const Service: string; const Characteristic: string)` | OnValue with it |
| `procedure Write(const Address: string; const Service: string; const Characteristic: string; const Value: RawByteString)` |  |
| `procedure Subscribe(const Address: string; const Service: string; const Characteristic: string; Enable: Boolean = True)` | OnValue on every change |
| `property OnDeviceFound: TBleDeviceEvent` |  |
| `property OnScanDone: TNotifyEvent` |  |
| `property OnConnected: TBleAddressEvent` |  |
| `property OnDisconnected: TBleAddressEvent` |  |
| `property OnServices: TBleServicesEvent` |  |
| `property OnValue: TBleValueEvent` |  |
| `property OnError: TBleErrorEvent` |  |

## Other types

| | |
|---|---|
| `type TSensorEvent = procedure(Sender: TObject; R: TSensorReading)` |  |
| `type TNfcTagEvent = procedure(Sender: TObject; Id: string; Text: string)` |  |
| `type TNfcErrorEvent = procedure(Sender: TObject; Error: string)` |  |
| `type TBleDeviceEvent = procedure(Sender: TObject; Address: string; Name: string; Rssi: Integer)` |  |
| `type TBleAddressEvent = procedure(Sender: TObject; Address: string)` |  |
| `type TBleServicesEvent = procedure(Sender: TObject; Address: string; Characteristics: TStringArray)` | Characteristics: 'service-uuid/characteristic-uuid' |
| `type TBleValueEvent = procedure(Sender: TObject; Address: string; Characteristic: string; Value: RawByteString)` |  |
| `type TBleErrorEvent = procedure(Sender: TObject; Address: string; Error: string)` |  |

