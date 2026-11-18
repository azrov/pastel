# Pastel.WebSocket

WebSockets: a connection that stays open, messages both ways (chat,
  live updates, notifications from the server).

  On a server (Pastel.Web):
    Chat := TWebSockets.Create;
    Chat.OnMessage := @ChatMessage;
    Web.WebSocket('/chat', Chat);           // behind RequireJwt, RateLimit... like routes

    procedure TApi.ChatMessage(Socket: TWebSocket; const Text: string);
    begin
      Chat.Broadcast(Socket.Claim('name') + ': ' + Text);
    end;

  In an app, or a program talking to a server:
    Client := TWebSocketClient.Create;
    Client.OnMessage := @Received;          // on the app's thread, like a button's click
    Client.BearerToken := Token;
    Client.Connect('wss://api.example.com/chat');
    Client.Send('hello');

  Text messages are UTF-8 strings; binary ones TBytes (OnBinary). Pings keep
  the connection alive through proxies and find dead ones. A server's
  handlers run on the connection's own thread (one per client), like routes:
  what they share must be protected.

`uses Pastel.WebSocket;` · source: [framework/src/pastel.websocket.pas](../../framework/src/pastel.websocket.pas)

## Types

### EWebSocketError

```pascal
type EWebSocketError = class(Exception)
```

### TWebSocket

```pascal
type TWebSocket = class
```

one connection: a client of a server's TWebSockets, or TWebSocketClient

| | |
|---|---|
| `constructor Create(AConn: TNetConnection; AIsClient: Boolean)` |  |
| `destructor Destroy` |  |
| `procedure Send(const Text: string)` | a text message; EWebSocketError when the connection is gone |
| `procedure SendBinary(const Data: TBytes)` |  |
| `procedure SendJson(Data: TJSONData)` | sends Data as JSON text and frees it |
| `procedure Close(Code: Integer = 1000; const Reason: string = '')` | ends the connection (1000: normal; 1008: not allowed; 1011: an error) |
| `function Open: Boolean` |  |
| `property Id: Int64` | a number for this connection, given by the server |
| `property Path: string` | the address it connected to: /chat/42 |
| `property Params: TStringList` | the route's parameters (/rooms/:room -> Params.Values['room']) and ?query |
| `property Query: TStringList` |  |
| `property Values: TStringList` | what the program keeps about it ('user', 'room'): also what filters set in Req.Values |
| `property Claims: TJSONObject` | the JWT's claims (RequireJwt); nil without one |
| `function Claim(const Name: string): string` |  |
| `property CloseCode: Integer` | why it closed: 1000 normal, 1001 going away, 1006 the connection broke |
| `property CloseReason: string` |  |
| `procedure Prepare(const APath: string; AParams: TStrings; AQuery: TStrings; AValues: TStrings; AClaims: TJSONObject)` | internal: what the server knows of the request that opened it |

### TWebSockets

```pascal
type TWebSockets = class
```

the clients connected to one address of a server (TWebServer.WebSocket)

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure Broadcast(const Text: string; Except_: TWebSocket = nil)` | to every client (but Except_) |
| `function SendTo(const Key: string; const Value: string; const Text: string): Integer` | to the clients whose Values[Key] is Value (a user's devices, a room); how many got it |
| `function SendToId(AId: Int64; const Text: string): Boolean` | to the client with this Id; False when it is not connected |
| `function Count: Integer` |  |
| `procedure CloseAll(Code: Integer = 1001; const Reason: string = 'the server stops')` | ends every connection (the server stops) |
| `procedure Serve(Socket: TWebSocket)` | internal: TWebServer's connection thread runs the connection here until it closes |

### TWebSocketClient

```pascal
type TWebSocketClient = class(TWebSocket)
```

a connection to a WebSocket server: ws:// or wss://

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure Connect(const Url: string)` | connects and does the handshake; EWebSocketError with the reason |

### TWebSocketReader

```pascal
type TWebSocketReader = class(TThread)
```

| | |
|---|---|
| `constructor Create(AClient: TWebSocketClient)` |  |
| `procedure Execute` |  |

## Other types

| | |
|---|---|
| `type TWebSocketEvent = procedure(Socket: TWebSocket)` |  |
| `type TWebSocketMessageEvent = procedure(Socket: TWebSocket; Text: string)` |  |
| `type TWebSocketBinaryEvent = procedure(Socket: TWebSocket; Data: TBytes)` |  |
| `type TWebSocketClientEvent = procedure(Sender: TObject; Text: string)` |  |
| `type TWebSocketClientBinaryEvent = procedure(Sender: TObject; Data: TBytes)` |  |

## Routines

### WebSocketAccept

```pascal
function WebSocketAccept(const Key: string): string
```

Sec-WebSocket-Accept for a Sec-WebSocket-Key

