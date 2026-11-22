{ Tests of Pastel.Push on a computer: test messages, no token. }
unit push_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Push;

type
  TPushTests = class(TTestSuite)
  private
    FTitle, FOrder, FError: string;
    FOpened: Boolean;
    FCount: Integer;
    procedure Got(Sender: TObject; Msg: TPushMessage);
    procedure Failed(Sender: TObject; const Error: string);
  published
    procedure TestMessages;
    procedure NoTokenOnAComputer;
  end;

implementation

procedure TPushTests.Got(Sender: TObject; Msg: TPushMessage);
begin
  Inc(FCount);
  FTitle := Msg.Title;
  FOrder := Msg.Data.Values['order'];
  FOpened := Msg.Opened;
end;

procedure TPushTests.Failed(Sender: TObject; const Error: string);
begin
  FError := Error;
end;

procedure TPushTests.TestMessages;
var
  P: TPushNotifications;
begin
  P := TPushNotifications.Create(nil);
  try
    P.OnMessage := @Got;
    FCount := 0;
    PushTestMessage('Order ready', 'Table 4', ['order', '1042', 'kind', 'ready'], True);
    AssertEquals(1, FCount);
    AssertEquals('Order ready', FTitle);
    AssertEquals('1042', FOrder);
    AssertTrue(FOpened, 'opened by a tap');
  finally
    P.Free;
  end;
end;

procedure TPushTests.NoTokenOnAComputer;
var
  P: TPushNotifications;
begin
  P := TPushNotifications.Create(nil);
  try
    P.OnError := @Failed;
    FError := '';
    P.RequestToken;
    AssertTrue(Pos('phones', FError) > 0, FError);
    AssertEquals('', P.Token);
  finally
    P.Free;
  end;
end;

initialization
  RegisterTests(TPushTests);

end.
