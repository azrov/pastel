{ Tests of Pastel.CrashReport: a report kept, then sent to a server. }
unit crashreport_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.CrashReport;

type
  TCrashReportTests = class(TTestSuite)
  published
    procedure KeptThenSent;
  end;

implementation

uses
  fphttpserver, fpjson, jsonparser, Pastel.Env, Pastel.Files;

type
  TReceiver = class(TThread)
  public
    Server: TFPHttpServer;
    Got: TStringList;
    procedure Handle(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
    procedure Execute; override;
  end;

procedure TReceiver.Handle(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
begin
  Got.Add(ARequest.Content);
  AResponse.Code := 201;
  AResponse.Content := '';
end;

procedure TReceiver.Execute;
begin
  try
    Server.Active := True;
  except
  end;
end;

procedure TCrashReportTests.KeptThenSent;
var
  Dir: string;
  R: TReceiver;
  Port, I: Integer;
  J: TJSONData;
begin
  Dir := MakeTempDir('pastel-crash');
  SetEnv('PASTEL_CRASH_DIR', Dir);
  Port := 20000 + Random(20000);
  R := TReceiver.Create(True);
  R.Got := TStringList.Create;
  R.Server := TFPHttpServer.Create(nil);
  R.Server.Port := Port;
  R.Server.OnRequest := @R.Handle;
  R.Server.Threaded := True;
  try
    { nowhere to send yet: kept }
    EnableCrashReports('', '1.4.2');
    try
      raise EConvertError.Create('"abc" is not a number');
    except
      on E: Exception do
        ReportError(E, 'import');
    end;
    AssertEquals(1, Length(ListFiles(Dir, '*.json')));
    J := GetJSON(ReadText(ListFiles(Dir, '*.json')[0]));
    try
      AssertEquals('EConvertError', TJSONObject(J).Get('error', ''));
      AssertEquals('"abc" is not a number', TJSONObject(J).Get('message', ''));
      AssertEquals('1.4.2', TJSONObject(J).Get('version', ''));
      AssertEquals('import', TJSONObject(J).Get('where', ''));
      AssertTrue(TJSONObject(J).Arrays['stack'].Count > 0, 'where it happened');
    finally
      J.Free;
    end;
    R.Start;
    for I := 1 to 100 do
      if R.Server.Active then Break else Sleep(10);
    Sleep(50);
    EnableCrashReports('http://127.0.0.1:' + IntToStr(Port) + '/crashes', '1.4.2');
    { the start sends them on a thread; this sends what is left }
    SendCrashReports;
    for I := 1 to 100 do
      if Length(ListFiles(Dir, '*.json')) = 0 then Break else Sleep(20);
    AssertEquals(0, Length(ListFiles(Dir, '*.json')), 'and removed');
    AssertEquals(1, R.Got.Count, 'sent once');
    AssertTrue(Pos('EConvertError', R.Got.Text) > 0);
  finally
    EnableCrashReports('', '');
    UnsetEnv('PASTEL_CRASH_DIR');
    R.Server.Active := False;
    DeleteDir(Dir);
  end;
end;

initialization
  RegisterTests(TCrashReportTests);

end.
