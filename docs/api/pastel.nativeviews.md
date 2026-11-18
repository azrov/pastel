# Pastel.NativeViews

The phone's own views in a form: web pages, video, and sound.

    Browser.Navigate('https://pastel.dev');
    Browser.LoadHtml('<h1>Hello</h1><button onclick="pastel.post(''hi'')">Hi</button>');
    Browser.EvaluateJavaScript('document.title', @TitleCame);
    Video.Url := 'https://example.com/clip.mp4'; Video.Play;
    Player.Url := '/sdcard/Music/song.mp3'; Player.Play;        // TMediaPlayer: no view

  On Android TWebBrowser and TVideoView are Android's WebView and VideoView,
  over the app's window at the place of the control (they follow it as it
  moves, scrolls, hides; a menu or dialog over the form hides them while it is
  open). A web page talks to Pascal with pastel.post(text) (OnMessage).
  TMediaPlayer is Android's MediaPlayer; with [package.android] background =
  ["media_playback"] and StartBackgroundWork it plays on when the app is closed.
  On computers TWebBrowser shows the address and opens it in the browser on a
  click; TMediaPlayer plays with mpv, ffplay or VLC (Linux), afplay (macOS) or
  Windows Media Player; TVideoView opens the video in the video app.

`uses Pastel.NativeViews;` · source: [framework/src/pastel.nativeviews.pas](../../framework/src/pastel.nativeviews.pas)

## Types

### TNativeView

```pascal
type TNativeView = class(TControl)
```

A control with one of the phone's views over it (Android); on computers it paints itself.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |

### TWebBrowser

```pascal
type TWebBrowser = class(TNativeView)
```

A web page in the form: Android's WebView; on computers a box that opens it in the browser.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure Loaded` |  |
| `procedure Navigate(const AUrl: string)` |  |
| `procedure LoadHtml(const Html: string; const BaseUrl: string = '')` | A page from text; BaseUrl: where its relative links and pictures point. |
| `procedure GoBack` |  |
| `procedure GoForward` |  |
| `procedure Reload` |  |
| `procedure Stop` |  |
| `function CanGoBack: Boolean` |  |
| `function CanGoForward: Boolean` |  |
| `procedure EvaluateJavaScript(const Script: string; Done: TJavaScriptResultEvent = nil)` | Runs JavaScript in the page; Done gets its value as JSON (Android). |
| `function Title: string` | The page's title (after OnLoad). |
| `property Url: string` | Setting it opens the page. |
| `property OnLoading: TWebUrlEvent` | A page started loading (also a link the user tapped). |
| `property OnLoad: TWebUrlEvent` | A page is there. |
| `property OnError: TWebTextEvent` |  |
| `property OnMessage: TWebTextEvent` | The page's JavaScript called pastel.post(text). |

### TMediaCore

```pascal
type TMediaCore = class
```

What TMediaPlayer and TVideoView share: a sound or a video, played.

| | |
|---|---|
| `constructor Create(AOwner: TObject)` |  |
| `destructor Destroy` |  |
| `procedure Open(const AUrl: string)` |  |
| `procedure Play` |  |
| `procedure Pause` |  |
| `procedure Stop` |  |
| `function Position: Integer` |  |
| `procedure SetPosition(Ms: Integer)` |  |
| `procedure SetVolume(V: Single)` |  |
| `procedure SetLoop(V: Boolean)` |  |
| `function Playing: Boolean` |  |
| `procedure Event(const Parts: TStringArray)` |  |
| `procedure Check` |  |

### TMediaPlayer

```pascal
type TMediaPlayer = class(TComponent)
```

Sound (music, a recording, a stream) without a view.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Play` |  |
| `procedure Pause` |  |
| `procedure Stop` |  |
| `function Playing: Boolean` |  |
| `function Duration: Integer` | Milliseconds; 0 until OnPrepared (or not known on computers). |
| `property Position: Integer` |  |
| `property Url: string` | A file (an absolute path) or an http(s) address. |
| `property Volume: Single` | 0 to 1. |
| `property Loop: Boolean` |  |
| `property OnPrepared: TNotifyEvent` |  |
| `property OnCompleted: TNotifyEvent` |  |
| `property OnError: TMediaErrorEvent` |  |

### TVideoView

```pascal
type TVideoView = class(TNativeView)
```

A video in the form: Android's VideoView; on computers the video app plays it.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Play` |  |
| `procedure Pause` |  |
| `procedure Stop` |  |
| `function Playing: Boolean` |  |
| `function Duration: Integer` |  |
| `property Position: Integer` |  |
| `property Url: string` |  |
| `property Volume: Single` |  |
| `property Loop: Boolean` |  |
| `property OnPrepared: TNotifyEvent` |  |
| `property OnCompleted: TNotifyEvent` |  |
| `property OnError: TMediaErrorEvent` |  |

### TCameraView

```pascal
type TCameraView = class(TNativeView)
```

The camera's picture in the form (Android's Camera2): a scanner, a photo
without leaving the app. Asks for the camera's permission on Start.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure Start` |  |
| `procedure Stop` |  |
| `procedure TakePhoto(const FileName: string = '')` | A JPEG into FileName (default: a new file in the app's folder); OnPhoto when it is there. |
| `property Active: Boolean` |  |
| `property Front: Boolean` | The camera on the screen's side (a selfie) instead of the back one. |
| `property Torch: Boolean` | The flash's light on. |
| `property OnStarted: TNotifyEvent` |  |
| `property OnPhoto: TCameraPhotoEvent` |  |
| `property OnError: TMediaErrorEvent` |  |

## Other types

| | |
|---|---|
| `type TWebUrlEvent = procedure(Sender: TObject; Url: string)` |  |
| `type TWebTextEvent = procedure(Sender: TObject; Text: string)` |  |
| `type TJavaScriptResultEvent = procedure(Sender: TObject; Json: string)` | The answer of EvaluateJavaScript, as JSON ('"text"', '42', 'null'). |
| `type TMediaErrorEvent = procedure(Sender: TObject; Message: string)` |  |
| `type TCameraPhotoEvent = procedure(Sender: TObject; FileName: string)` |  |

