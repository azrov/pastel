{ Tests of Pastel.Serial with a pair of pseudo terminals (socat), on Linux. }
unit serial_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Serial;

type
  TSerialTests = class(TTestSuite)
  published
    procedure LinesBothWays;
    procedure NoSuchPort;
  end;

implementation

uses
  Process, Pastel.Process, Pastel.Files;

procedure TSerialTests.LinesBothWays;
var
  P: TProcess;
  Dir: string;
  A, B: TSerialPort;
  Until_: QWord;
begin
  {$IFNDEF LINUX}
  Exit;
  {$ENDIF}
  if Which('socat') = '' then
  begin
    Skip('socat is not installed');
    Exit;
  end;
  Dir := MakeTempDir('pastel-serial');
  P := TProcess.Create(nil);
  A := TSerialPort.Create;
  B := TSerialPort.Create;
  try
    P.Executable := Which('socat');
    P.Parameters.AddStrings(['pty,raw,echo=0,link=' + Dir + 'a', 'pty,raw,echo=0,link=' + Dir + 'b']);
    P.Execute;
    Until_ := GetTickCount64 + 3000;
    while not (FileExists(Dir + 'a') and FileExists(Dir + 'b')) and (GetTickCount64 < Until_) do
      Sleep(20);
    A.Open(Dir + 'a', 115200);
    B.Open(Dir + 'b', 115200);
    AssertTrue(A.IsOpen);
    A.WriteText('W'#13#10);
    AssertEquals('W', B.ReadLine(2000), 'a line, without its #13');
    B.WriteText('  12.450 kg'#13#10'next');
    AssertEquals('  12.450 kg', A.ReadLine(2000));
    AssertEquals('', A.ReadLine(200), 'no line end yet');
    A.WriteText('x');
    AssertEquals('x', B.Read(10, 2000));
    AssertEquals('', B.Read(10, 100), 'nothing more');
  finally
    A.Free;
    B.Free;
    P.Terminate(0);
    P.WaitOnExit;
    P.Free;
    try
      DeleteDir(Dir);
    except
      { socat's links go a moment later }
    end;
  end;
end;

procedure TSerialTests.NoSuchPort;
var
  A: TSerialPort;
begin
  A := TSerialPort.Create;
  try
    try
      {$IFDEF WINDOWS}
      A.Open('COM250');
      {$ELSE}
      A.Open('/dev/no-such-port');
      {$ENDIF}
      Fail('a port that is not there');
    except
      on E: ESerialError do
        AssertTrue(Pos('cannot be opened', E.Message) > 0, E.Message);
    end;
    AssertFalse(A.IsOpen);
    try
      A.Open('/dev/null', 12345);
      Fail('a speed no port uses');
    except
      on E: ESerialError do ;
    end;
  finally
    A.Free;
  end;
end;

initialization
  RegisterTests(TSerialTests);

end.
