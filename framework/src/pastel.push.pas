{ Pastel - push messages: a server sends, the phone shows (Firebase Cloud Messaging).

    object Push: TPushNotifications
      OnToken = PushToken
      OnMessage = PushMessage
    end

    procedure THomeForm.FormCreate(Sender: TObject);
    begin
      RequestPermissions([dpNotifications], nil);   // Android 13 and newer ask
      Push.RequestToken;                            // OnToken: send it to your server
      Push.Subscribe('offers');
    end;

    procedure THomeForm.PushMessage(Sender: TObject; Msg: TPushMessage);
    begin
      if Msg.Opened then                            // the user tapped its notification
        ShowAppointment(Msg.Data.Values['appointment']);
    end;

  The app needs Firebase's library and its google-services.json:
    [package.android]
    libraries = ["com.google.firebase:firebase-messaging:24.1.0"]
    permissions = ["notifications"]
  pastel package apk then puts Pastel's push service in. A message while the app is
  on the screen comes to OnMessage; when it is not, the phone shows it as a
  notification, and a tap on it opens the app with OnMessage (Opened = True).
  Computers have no push: PushTestMessage gives OnMessage a message, for tests.
  Part of the Pastel project, MIT License. }
unit Pastel.Push;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI;

type
  TPushMessage = class
  public
    Title, Body: string;
    { the message's data: Data.Values['order'] }
    Data: TStringList;
    { True: the app was opened by a tap on its notification }
    Opened: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  TPushTokenEvent = procedure(Sender: TObject; const Token: string) of object;
  TPushMessageEvent = procedure(Sender: TObject; Msg: TPushMessage) of object;
  TPushErrorEvent = procedure(Sender: TObject; const Error: string) of object;

  TPushNotifications = class(TComponent)
  private
    FToken: string;
    FOnToken: TPushTokenEvent;
    FOnMessage: TPushMessageEvent;
    FOnError: TPushErrorEvent;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Asks for the device's address for push messages: OnToken (again when it changes). }
    procedure RequestToken;
    { Messages sent to a topic (/topics/offers) come too. }
    procedure Subscribe(const Topic: string);
    procedure Unsubscribe(const Topic: string);
    { The last token that came. }
    property Token: string read FToken;
  published
    property OnToken: TPushTokenEvent read FOnToken write FOnToken;
    property OnMessage: TPushMessageEvent read FOnMessage write FOnMessage;
    property OnError: TPushErrorEvent read FOnError write FOnError;
  end;

{ A message as if a push message came (tests, computers). }
procedure PushTestMessage(const Title, Body: string; const Data: array of string; Opened: Boolean = False);

implementation

uses
  fpjson, jsonparser{$IFDEF ANDROID}, Pastel.Android{$ENDIF};

var
  Receivers: TFPList;
  Timer: TTimer;
  Waiting: TStringList;        { lines that came before a receiver was there }

type
  TPoller = class
    procedure Tick(Sender: TObject);
  end;

var
  Poller: TPoller;

constructor TPushMessage.Create;
begin
  Data := TStringList.Create;
end;

destructor TPushMessage.Destroy;
begin
  Data.Free;
  inherited Destroy;
end;

function PushCall(const Method, Arg: string): string;
begin
  {$IFDEF ANDROID}
  Result := AndroidCallString('pushCall', '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;', [Method, Arg]);
  {$ELSE}
  if (Method = '') and (Arg = '') then ;
  Result := '!push messages are there on phones (PushTestMessage for tests)';
  {$ENDIF}
end;

procedure Deliver(const Line: string);
var
  P: TStringArray;
  I: Integer;
  R: TPushNotifications;
  M: TPushMessage;
  J: TJSONData;
  K: Integer;
begin
  P := Line.Split([#9]);
  if Length(P) = 0 then
    Exit;
  if Receivers.Count = 0 then
  begin
    Waiting.Add(Line);
    Exit;
  end;
  for I := 0 to Receivers.Count - 1 do
  begin
    R := TPushNotifications(Receivers[I]);
    if (P[0] = 'token') and (Length(P) > 1) then
    begin
      R.FToken := P[1];
      if Assigned(R.FOnToken) then
        R.FOnToken(R, P[1]);
    end
    else if P[0] = 'error' then
    begin
      if Assigned(R.FOnError) then
        R.FOnError(R, Copy(Line, 7, MaxInt));
    end
    else if P[0] = 'message' then
    begin
      M := TPushMessage.Create;
      try
        if Length(P) > 1 then M.Title := P[1];
        if Length(P) > 2 then M.Body := P[2];
        if (Length(P) > 3) and (P[3] <> '') then
        begin
          try
            J := GetJSON(P[3]);
            try
              if J is TJSONObject then
                for K := 0 to TJSONObject(J).Count - 1 do
                  M.Data.Values[TJSONObject(J).Names[K]] := TJSONObject(J).Items[K].AsString;
            finally
              J.Free;
            end;
          except
            { data that is not JSON: left out }
          end;
        end;
        M.Opened := (Length(P) > 4) and (P[4] = '1');
        if Assigned(R.FOnMessage) then
          R.FOnMessage(R, M);
      finally
        M.Free;
      end;
    end;
  end;
end;

procedure TPoller.Tick(Sender: TObject);
var
  S, Line: string;
  L: TStringList;
begin
  { what came before a receiver was there (the tap that opened the app) }
  if (Waiting.Count > 0) and (Receivers.Count > 0) then
  begin
    L := TStringList.Create;
    try
      L.Assign(Waiting);
      Waiting.Clear;
      for S in L do
        Deliver(S);
    finally
      L.Free;
    end;
  end;
  {$IFDEF ANDROID}
  S := PushCall('take', '');
  if (S = '') or (S[1] = '!') then
    Exit;
  for Line in S.Split([#10]) do
    if Line <> '' then
      Deliver(Line);
  {$ELSE}
  S := '';
  Line := S;
  if Line <> '' then ;
  {$ENDIF}
end;

procedure PushTestMessage(const Title, Body: string; const Data: array of string; Opened: Boolean);
var
  J: TJSONObject;
  I: Integer;
begin
  J := TJSONObject.Create;
  try
    I := 0;
    while I + 1 <= High(Data) do
    begin
      J.Add(Data[I], Data[I + 1]);
      Inc(I, 2);
    end;
    Deliver('message'#9 + Title + #9 + Body + #9 + J.AsJSON + #9 + IntToStr(Ord(Opened)));
  finally
    J.Free;
  end;
end;

constructor TPushNotifications.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Receivers.Add(Self);
  if Timer = nil then
  begin
    Poller := TPoller.Create;
    Timer := TTimer.Create(nil);
    Timer.Interval := 300;
    Timer.OnTimer := @Poller.Tick;
    Timer.Enabled := True;
  end;
end;

destructor TPushNotifications.Destroy;
begin
  Receivers.Remove(Self);
  inherited Destroy;
end;

procedure TPushNotifications.RequestToken;
var
  S: string;
begin
  S := PushCall('requestToken', '');
  if (S <> '') and (S[1] = '!') and Assigned(FOnError) then
    FOnError(Self, Copy(S, 2, MaxInt));
end;

procedure TPushNotifications.Subscribe(const Topic: string);
var
  S: string;
begin
  S := PushCall('subscribe', Topic);
  if (S <> '') and (S[1] = '!') and Assigned(FOnError) then
    FOnError(Self, Copy(S, 2, MaxInt));
end;

procedure TPushNotifications.Unsubscribe(const Topic: string);
begin
  PushCall('unsubscribe', Topic);
end;

initialization
  Receivers := TFPList.Create;
  Waiting := TStringList.Create;
  RegisterNonVisual(TPushNotifications);

finalization
  Timer.Free;
  Poller.Free;
  Receivers.Free;
  Waiting.Free;
end.
