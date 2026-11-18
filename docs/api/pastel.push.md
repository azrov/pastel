# Pastel.Push

Push messages: a server sends, the phone shows (Firebase Cloud Messaging).

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

`uses Pastel.Push;` · source: [framework/src/pastel.push.pas](../../framework/src/pastel.push.pas)

## Types

### TPushMessage

```pascal
type TPushMessage = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |

### TPushNotifications

```pascal
type TPushNotifications = class(TComponent)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure RequestToken` | Asks for the device's address for push messages: OnToken (again when it changes). |
| `procedure Subscribe(const Topic: string)` | Messages sent to a topic (/topics/offers) come too. |
| `procedure Unsubscribe(const Topic: string)` |  |
| `property Token: string` | The last token that came. |
| `property OnToken: TPushTokenEvent` |  |
| `property OnMessage: TPushMessageEvent` |  |
| `property OnError: TPushErrorEvent` |  |

## Other types

| | |
|---|---|
| `type TPushTokenEvent = procedure(Sender: TObject; Token: string)` |  |
| `type TPushMessageEvent = procedure(Sender: TObject; Msg: TPushMessage)` |  |
| `type TPushErrorEvent = procedure(Sender: TObject; Error: string)` |  |

## Routines

### PushTestMessage

```pascal
procedure PushTestMessage(const Title: string; const Body: string; const Data: array of string; Opened: Boolean = False)
```

A message as if a push message came (tests, computers).

