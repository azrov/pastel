# WebSockets: `Pastel.WebSocket`

A WebSocket is a connection that stays open: the server can send something at any moment — a new message in a
chat, an appointment booked on another phone, a price that changed — and the app sees it at once, without asking
every few seconds.

## On the server

A `TWebSockets` holds the clients connected to one address of a [web server](web.md):

```pascal
uses Pastel.Web, Pastel.WebSocket;

type
  TApi = class(TWebService)
  private
    FChat: TWebSockets;
    procedure ChatOpen(Socket: TWebSocket);
    procedure ChatMessage(Socket: TWebSocket; const Text: string);
  protected
    procedure Routes(Web: TWebServer); override;
  end;

procedure TApi.Routes(Web: TWebServer);
begin
  FChat := TWebSockets.Create;
  FChat.OnOpen := @ChatOpen;
  FChat.OnMessage := @ChatMessage;
  Web.RequireJwt('/live', Config.Require('auth.secret'));
  Web.WebSocket('/live/rooms/:room', FChat);
end;

procedure TApi.ChatOpen(Socket: TWebSocket);
begin
  Socket.Values.Values['room'] := Socket.Params.Values['room'];
  Socket.Send('welcome, ' + Socket.Claim('name'));
end;

procedure TApi.ChatMessage(Socket: TWebSocket; const Text: string);
begin
  FChat.SendTo('room', Socket.Values.Values['room'], Socket.Claim('name') + ': ' + Text);
end;
```

- The filters of the address run first, like for a route: `RequireJwt`, `RequireApiKey`, `RateLimit`, `Use`.
  A client without a token gets `401` and no connection.
- `Socket.Params` (the route's `:room`), `Socket.Query` (`?name=...`), `Socket.Claims` / `Socket.Claim('sub')`
  (the JWT) and `Socket.Values` (what the filters set, and what the program keeps about the client) tell who it is.
- Sending: `Socket.Send(Text)`, `Socket.SendJson(Obj)`, `Socket.SendBinary(Bytes)`; to many:
  `Broadcast(Text)` (to all), `SendTo('user', '42', Text)` (to the clients whose `Values['user']` is `42`: one
  user's phone and computer, a room), `SendToId(Id, Text)`. From anywhere in the server, also from a route:
  `POST /appointments` saves and then tells the salon's other devices.
- `OnClose`: the client left (`Socket.CloseCode`: 1000 normal, 1001 going away, 1006 the network). `Socket.Close`
  ends a connection from the server.
- Each client has its own thread, like requests: what the handlers share must be protected (`TCriticalSection`).
  An error in a handler is logged; the connection stays.
- Pings every `PingInterval` seconds (30) keep connections alive through proxies and end those of phones that went
  away without a word; a message longer than `MaxMessageSize` (1 MB) closes the connection. `Stop` of the server
  ends every connection (1001).
- Web pages of other sites may not connect when `Cors` lists the allowed ones (the `Origin` must be among them).
- A plain request to the address gets `426` and a message that it is a WebSocket.

Behind nginx, the address needs `proxy_http_version 1.1;`, `proxy_set_header Upgrade $http_upgrade;` and
`proxy_set_header Connection "upgrade";` ([deploy.md](deploy.md#https-a-reverse-proxy-in-front)); Caddy passes
WebSockets by itself.

## In an app

```pascal
uses Pastel.WebSocket;

procedure THomeForm.FormCreate(Sender: TObject);
begin
  FLive := TWebSocketClient.Create;
  FLive.OnMessage := @LiveMessage;
  FLive.OnClose := @LiveClosed;
  FLive.BearerToken := Session.Token;
  FLive.Connect('wss://api.example.com/live/rooms/salon');
end;

procedure THomeForm.LiveMessage(Sender: TObject; const Text: string);
begin
  ListBox1.Items.Add(Text);         // on the app's thread: forms can be used
end;

procedure THomeForm.SendClick(Sender: TObject);
begin
  FLive.Send(MessageEdit.Text);
end;
```

`Connect` connects and does the handshake (`EWebSocketError` with the reason: the server is not there, `401`, a
certificate that is not trusted); then messages come by themselves. `OnMessage`, `OnBinary` and `OnClose` run on the
app's thread, like a button's click (`EventsOnAppThread := False`: on the reading thread, for programs without
forms). After `OnClose`, `Connect` again connects anew: a phone that lost the network does it when it is back.
`wss://` checks the server's certificate like HTTPS. On Android the phone's own TLS is used (nothing to install).
`Headers` adds lines to the handshake; `Free` closes the connection.

## In tests

The client works against a server in the same test program: start a `TWebServer` on a free port, connect a
`TWebSocketClient` with `EventsOnAppThread := False`, send, and wait for what comes back (the framework's
`websocket_test.pas` does this).
