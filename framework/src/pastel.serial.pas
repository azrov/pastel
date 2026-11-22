{ Pastel - serial ports: scales, barcode readers, cash drawers, receipt printers, Arduino boards.

    Port := TSerialPort.Create;
    Port.Open('/dev/ttyUSB0', 9600);           // Windows: 'COM3'
    Port.WriteText('W'#13);                     // ask the scale for the weight
    Weight := Port.ReadLine(2000);              // up to a line end, 2 s at most
    Port.Free;

    for Name in ListSerialPorts do ...          // the ports there now

  8 data bits, no parity, 1 stop bit unless set; no flow control unless set.
  Linux (and other Unix): termios; the user must be in the "dialout" group.
  Windows: the COM ports. Android: not here (USB needs Android's USB host API).
  Part of the Pastel project, MIT License. }
unit Pastel.Serial;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  ESerialError = class(Exception);
  TSerialParity = (spNone, spOdd, spEven);
  TSerialFlow = (sfNone, sfHardware, sfSoftware);

  TSerialPort = class
  private
    FName: string;
    FHandle: PtrInt;
    FPending: RawByteString;
    function GetOpen: Boolean;
  public
    DataBits: Integer;           { 5 to 8 }
    StopBits: Integer;           { 1 or 2 }
    Parity: TSerialParity;
    Flow: TSerialFlow;
    constructor Create;
    destructor Destroy; override;
    procedure Open(const AName: string; Baud: Integer = 9600);
    procedure Close;
    procedure Write(const Data: RawByteString);
    procedure WriteText(const S: string);
    { what came within TimeoutMs (at least one byte unless the time ran out); '' when nothing }
    function Read(MaxBytes: Integer = 4096; TimeoutMs: Integer = 1000): RawByteString;
    { up to the line end (#10; a #13 before it is dropped); '' when none came within TimeoutMs }
    function ReadLine(TimeoutMs: Integer = 1000): string;
    { the line signals: DTR (some boards restart on it), RTS }
    procedure SetDTR(On: Boolean);
    procedure SetRTS(On: Boolean);
    { throws away what came and was not read }
    procedure Flush;
    property Name: string read FName;
    property IsOpen: Boolean read GetOpen;
  end;

{ The serial ports of the computer: '/dev/ttyUSB0', '/dev/ttyACM0'...; 'COM1', 'COM3'... }
function ListSerialPorts: TStringArray;

implementation

uses
  Math
  {$IFDEF UNIX}, BaseUnix, termio{$ENDIF}
  {$IFDEF WINDOWS}, Windows, Registry{$ENDIF};

constructor TSerialPort.Create;
begin
  FHandle := -1;
  DataBits := 8;
  StopBits := 1;
end;

destructor TSerialPort.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TSerialPort.GetOpen: Boolean;
begin
  Result := FHandle <> -1;
end;

procedure TSerialPort.WriteText(const S: string);
begin
  Write(S);
end;

function TSerialPort.ReadLine(TimeoutMs: Integer): string;
var
  Until_: QWord;
  I, Left: Integer;
begin
  Until_ := GetTickCount64 + QWord(Max(0, TimeoutMs));
  repeat
    I := Pos(#10, FPending);
    if I > 0 then
    begin
      Result := Copy(FPending, 1, I - 1);
      Delete(FPending, 1, I);
      if (Result <> '') and (Result[Length(Result)] = #13) then
        SetLength(Result, Length(Result) - 1);
      Exit;
    end;
    Left := Integer(Int64(Until_) - Int64(GetTickCount64));
    if Left <= 0 then
      Break;
    FPending := FPending + Read(4096, Left);
  until False;
  Result := '';
end;

{$IFDEF UNIX}

function BaudFlag(Baud: Integer): Cardinal;
begin
  case Baud of
    50: Result := B50;
    75: Result := B75;
    110: Result := B110;
    134: Result := B134;
    150: Result := B150;
    200: Result := B200;
    300: Result := B300;
    600: Result := B600;
    1200: Result := B1200;
    1800: Result := B1800;
    2400: Result := B2400;
    4800: Result := B4800;
    9600: Result := B9600;
    19200: Result := B19200;
    38400: Result := B38400;
    57600: Result := B57600;
    115200: Result := B115200;
    230400: Result := B230400;
    {$IFDEF LINUX}
    460800: Result := B460800;
    500000: Result := B500000;
    921600: Result := B921600;
    1000000: Result := B1000000;
    {$ENDIF}
  else
    raise ESerialError.CreateFmt('the speed %d is not one serial ports use (9600, 19200, 115200...)', [Baud]);
  end;
end;

procedure TSerialPort.Open(const AName: string; Baud: Integer);
var
  T: TermIOS;
  H: cint;
  Speed: Cardinal;
begin
  Close;
  Speed := BaudFlag(Baud);
  H := fpOpen(AName, O_RDWR or O_NOCTTY or O_NONBLOCK);
  if H < 0 then
    if fpGetErrno = ESysEACCES then
      raise ESerialError.CreateFmt('%s: no permission (the user must be in the "dialout" group: sudo usermod -aG dialout $USER, then log in again)', [AName])
    else
      raise ESerialError.CreateFmt('%s cannot be opened: %s', [AName, SysErrorMessage(fpGetErrno)]);
  T := Default(TermIOS);
  if TCGetAttr(H, T) <> 0 then
  begin
    fpClose(H);
    raise ESerialError.CreateFmt('%s is not a serial port', [AName]);
  end;
  CFMakeRaw(T);
  CFSetISpeed(T, Speed);
  CFSetOSpeed(T, Speed);
  T.c_cflag := T.c_cflag and not CSIZE;
  case DataBits of
    5: T.c_cflag := T.c_cflag or CS5;
    6: T.c_cflag := T.c_cflag or CS6;
    7: T.c_cflag := T.c_cflag or CS7;
  else
    T.c_cflag := T.c_cflag or CS8;
  end;
  if StopBits = 2 then
    T.c_cflag := T.c_cflag or CSTOPB
  else
    T.c_cflag := T.c_cflag and not CSTOPB;
  T.c_cflag := T.c_cflag and not (PARENB or PARODD);
  case Parity of
    spOdd: T.c_cflag := T.c_cflag or PARENB or PARODD;
    spEven: T.c_cflag := T.c_cflag or PARENB;
  end;
  T.c_cflag := T.c_cflag or CLOCAL or CREAD;
  {$IFDEF LINUX}
  if Flow = sfHardware then
    T.c_cflag := T.c_cflag or CRTSCTS
  else
    T.c_cflag := T.c_cflag and not CRTSCTS;
  {$ENDIF}
  if Flow = sfSoftware then
    T.c_iflag := T.c_iflag or IXON or IXOFF
  else
    T.c_iflag := T.c_iflag and not (IXON or IXOFF or IXANY);
  T.c_cc[VMIN] := 0;
  T.c_cc[VTIME] := 0;
  if TCSetAttr(H, TCSANOW, T) <> 0 then
  begin
    fpClose(H);
    raise ESerialError.CreateFmt('%s: the settings were not taken', [AName]);
  end;
  FHandle := H;
  FName := AName;
  FPending := '';
end;

procedure TSerialPort.Close;
begin
  if FHandle <> -1 then
    fpClose(FHandle);
  FHandle := -1;
end;

procedure TSerialPort.Write(const Data: RawByteString);
var
  Done, N: Integer;
  Fds: TFDSet;
  Tv: TTimeVal;
begin
  if FHandle = -1 then
    raise ESerialError.Create('the serial port is not open');
  Done := 0;
  while Done < Length(Data) do
  begin
    N := fpWrite(FHandle, Data[Done + 1], Length(Data) - Done);
    if N > 0 then
      Inc(Done, N)
    else if (N < 0) and (fpGetErrno <> ESysEAGAIN) then
      raise ESerialError.CreateFmt('%s: writing did not work: %s', [FName, SysErrorMessage(fpGetErrno)])
    else
    begin
      fpFD_ZERO(Fds);
      fpFD_SET(FHandle, Fds);
      Tv.tv_sec := 1;
      Tv.tv_usec := 0;
      fpSelect(FHandle + 1, nil, @Fds, nil, @Tv);
    end;
  end;
end;

function TSerialPort.Read(MaxBytes, TimeoutMs: Integer): RawByteString;
var
  Fds: TFDSet;
  Tv: TTimeVal;
  N: Integer;
begin
  Result := '';
  if FHandle = -1 then
    raise ESerialError.Create('the serial port is not open');
  if FPending <> '' then
  begin
    Result := Copy(FPending, 1, MaxBytes);
    Delete(FPending, 1, MaxBytes);
    Exit;
  end;
  fpFD_ZERO(Fds);
  fpFD_SET(FHandle, Fds);
  Tv.tv_sec := TimeoutMs div 1000;
  Tv.tv_usec := (TimeoutMs mod 1000) * 1000;
  if fpSelect(FHandle + 1, @Fds, nil, nil, @Tv) <= 0 then
    Exit;
  SetLength(Result, MaxBytes);
  N := fpRead(FHandle, Result[1], MaxBytes);
  if N <= 0 then
    Result := ''
  else
    SetLength(Result, N);
end;

procedure SetLine(H: PtrInt; Bit: cint; On: Boolean);
var
  Flags: cint;
begin
  Flags := Bit;
  if On then
    fpIOCtl(H, TIOCMBIS, @Flags)
  else
    fpIOCtl(H, TIOCMBIC, @Flags);
end;

procedure TSerialPort.SetDTR(On: Boolean);
begin
  if FHandle <> -1 then
    SetLine(FHandle, TIOCM_DTR, On);
end;

procedure TSerialPort.SetRTS(On: Boolean);
begin
  if FHandle <> -1 then
    SetLine(FHandle, TIOCM_RTS, On);
end;

procedure TSerialPort.Flush;
begin
  FPending := '';
  if FHandle <> -1 then
    TCFlush(FHandle, TCIFLUSH);
end;

function RealUart(const N: string): Boolean;
var
  L: string;
begin
  L := fpReadLink('/sys/class/tty/' + N + '/device/driver');
  Result := (L <> '') and (ExtractFileName(L) <> 'serial8250');
end;

function ListSerialPorts: TStringArray;
var
  SR: TSearchRec;
  Pat: string;
begin
  Result := nil;
  for Pat in ['/dev/ttyUSB*', '/dev/ttyACM*', '/dev/ttyAMA*', '/dev/rfcomm*', '/dev/cu.*', '/dev/ttyS*'] do
    if FindFirst(Pat, faAnyFile, SR) = 0 then
    begin
      repeat
        { /dev/ttyS0..31 are there on every PC: only those with a port behind them }
        if (Pat <> '/dev/ttyS*') or RealUart(SR.Name) then
          Result := Concat(Result, ['/dev/' + SR.Name]);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
end;

{$ENDIF}

{$IFDEF WINDOWS}

procedure TSerialPort.Open(const AName: string; Baud: Integer);
var
  H: THandle;
  D: TDCB;
  T: TCommTimeouts;
  Path: string;
begin
  Close;
  Path := AName;
  if Copy(Path, 1, 4) <> '\\.\' then
    Path := '\\.\' + Path;      { COM10 and up need it }
  H := CreateFileW(PWideChar(UnicodeString(Path)), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    raise ESerialError.CreateFmt('%s cannot be opened: %s', [AName, SysErrorMessage(GetLastError)]);
  D := Default(TDCB);
  D.DCBlength := SizeOf(D);
  GetCommState(H, D);
  D.BaudRate := Baud;
  D.ByteSize := DataBits;
  case Parity of
    spOdd: D.Parity := ODDPARITY;
    spEven: D.Parity := EVENPARITY;
  else
    D.Parity := NOPARITY;
  end;
  if StopBits = 2 then D.StopBits := TWOSTOPBITS else D.StopBits := ONESTOPBIT;
  { fBinary 1, DTR on, RTS on (or handshake), CTS out flow with hardware flow, XON/XOFF with software }
  D.Flags := 1 or (1 shl 4);
  if Flow = sfHardware then
    D.Flags := D.Flags or (1 shl 2) or (2 shl 12)
  else
    D.Flags := D.Flags or (1 shl 12);
  if Flow = sfSoftware then
    D.Flags := D.Flags or (1 shl 8) or (1 shl 9);
  if not SetCommState(H, D) then
  begin
    CloseHandle(H);
    raise ESerialError.CreateFmt('%s: the settings were not taken (%d baud)', [AName, Baud]);
  end;
  T := Default(TCommTimeouts);
  T.ReadIntervalTimeout := MAXDWORD;      { a read answers at once with what is there }
  SetCommTimeouts(H, T);
  FHandle := PtrInt(H);
  FName := AName;
  FPending := '';
end;

procedure TSerialPort.Close;
begin
  if FHandle <> -1 then
    CloseHandle(THandle(FHandle));
  FHandle := -1;
end;

procedure TSerialPort.Write(const Data: RawByteString);
var
  N: DWORD;
begin
  if FHandle = -1 then
    raise ESerialError.Create('the serial port is not open');
  if (Data <> '') and (not WriteFile(THandle(FHandle), Data[1], Length(Data), N, nil) or (N <> DWORD(Length(Data)))) then
    raise ESerialError.CreateFmt('%s: writing did not work: %s', [FName, SysErrorMessage(GetLastError)]);
end;

function TSerialPort.Read(MaxBytes, TimeoutMs: Integer): RawByteString;
var
  N: DWORD;
  Until_: QWord;
begin
  Result := '';
  if FHandle = -1 then
    raise ESerialError.Create('the serial port is not open');
  if FPending <> '' then
  begin
    Result := Copy(FPending, 1, MaxBytes);
    Delete(FPending, 1, MaxBytes);
    Exit;
  end;
  Until_ := GetTickCount64 + QWord(Max(0, TimeoutMs));
  SetLength(Result, MaxBytes);
  repeat
    N := 0;
    if not ReadFile(THandle(FHandle), Result[1], MaxBytes, N, nil) then
      raise ESerialError.CreateFmt('%s: reading did not work: %s', [FName, SysErrorMessage(GetLastError)]);
    if N > 0 then
    begin
      SetLength(Result, N);
      Exit;
    end;
    Sleep(5);
  until GetTickCount64 >= Until_;
  Result := '';
end;

procedure TSerialPort.SetDTR(On: Boolean);
begin
  if FHandle <> -1 then
    if On then EscapeCommFunction(THandle(FHandle), Windows.SETDTR) else EscapeCommFunction(THandle(FHandle), Windows.CLRDTR);
end;

procedure TSerialPort.SetRTS(On: Boolean);
begin
  if FHandle <> -1 then
    if On then EscapeCommFunction(THandle(FHandle), Windows.SETRTS) else EscapeCommFunction(THandle(FHandle), Windows.CLRRTS);
end;

procedure TSerialPort.Flush;
begin
  FPending := '';
  if FHandle <> -1 then
    PurgeComm(THandle(FHandle), PURGE_RXCLEAR);
end;

function ListSerialPorts: TStringArray;
var
  R: TRegistry;
  Names: TStringList;
  I: Integer;
begin
  Result := nil;
  R := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKeyReadOnly('HARDWARE\DEVICEMAP\SERIALCOMM') then
    begin
      R.GetValueNames(Names);
      for I := 0 to Names.Count - 1 do
        Result := Concat(Result, [R.ReadString(Names[I])]);
    end;
  finally
    Names.Free;
    R.Free;
  end;
end;

{$ENDIF}

{$IF not defined(UNIX) and not defined(WINDOWS)}
procedure TSerialPort.Open(const AName: string; Baud: Integer);
begin
  raise ESerialError.Create('serial ports are not there on this platform');
end;

procedure TSerialPort.Close;
begin
end;

procedure TSerialPort.Write(const Data: RawByteString);
begin
  raise ESerialError.Create('serial ports are not there on this platform');
end;

function TSerialPort.Read(MaxBytes, TimeoutMs: Integer): RawByteString;
begin
  Result := '';
end;

procedure TSerialPort.SetDTR(On: Boolean);
begin
end;

procedure TSerialPort.SetRTS(On: Boolean);
begin
end;

procedure TSerialPort.Flush;
begin
end;

function ListSerialPorts: TStringArray;
begin
  Result := nil;
end;
{$ENDIF}

end.
