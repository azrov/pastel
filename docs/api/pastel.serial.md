# Pastel.Serial

Serial ports: scales, barcode readers, cash drawers, receipt printers, Arduino boards.

    Port := TSerialPort.Create;
    Port.Open('/dev/ttyUSB0', 9600);           // Windows: 'COM3'
    Port.WriteText('W'#13);                     // ask the scale for the weight
    Weight := Port.ReadLine(2000);              // up to a line end, 2 s at most
    Port.Free;

    for Name in ListSerialPorts do ...          // the ports there now

  8 data bits, no parity, 1 stop bit unless set; no flow control unless set.
  Linux (and other Unix): termios; the user must be in the "dialout" group.
  Windows: the COM ports. Android: not here (USB needs Android's USB host API).

`uses Pastel.Serial;` · source: [framework/src/pastel.serial.pas](../../framework/src/pastel.serial.pas)

## Types

### ESerialError

```pascal
type ESerialError = class(Exception)
```

### TSerialParity

```pascal
type TSerialParity = (spNone, spOdd, spEven)
```

- `spNone`
- `spOdd`
- `spEven`
### TSerialFlow

```pascal
type TSerialFlow = (sfNone, sfHardware, sfSoftware)
```

- `sfNone`
- `sfHardware`
- `sfSoftware`
### TSerialPort

```pascal
type TSerialPort = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure Open(const AName: string; Baud: Integer = 9600)` |  |
| `procedure Close` |  |
| `procedure Write(const Data: RawByteString)` |  |
| `procedure WriteText(const S: string)` |  |
| `function Read(MaxBytes: Integer = 4096; TimeoutMs: Integer = 1000): RawByteString` | what came within TimeoutMs (at least one byte unless the time ran out); '' when nothing |
| `function ReadLine(TimeoutMs: Integer = 1000): string` | up to the line end (#10; a #13 before it is dropped); '' when none came within TimeoutMs |
| `procedure SetDTR(On: Boolean)` | the line signals: DTR (some boards restart on it), RTS |
| `procedure SetRTS(On: Boolean)` |  |
| `procedure Flush` | throws away what came and was not read |
| `property Name: string` |  |
| `property IsOpen: Boolean` |  |

## Routines

### ListSerialPorts

```pascal
function ListSerialPorts: TStringArray
```

The serial ports of the computer: '/dev/ttyUSB0', '/dev/ttyACM0'...; 'COM1', 'COM3'...

