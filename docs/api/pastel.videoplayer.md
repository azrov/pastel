# Pastel.VideoPlayer

TVideoPlayer: video and live streams in the form, on computers and phones.

    Player.UserAgent := 'MyApp/1.0';                // some servers want one
    Player.Play('http://example.com/live/42.m3u8');  // HLS, MPEG-TS, MP4, MKV...
    Player.ShowInfo('Channel 1', 'Now: News 20:00-21:00');
    Player.Seek(30, True);                           // 30 seconds on
    for T in Player.Tracks do ...                    // audio and subtitles
    Player.SelectTrack('audio', 2);

  Computers: libmpv draws the picture into the window (Linux: the libmpv2
  package; Windows: libmpv-2.dll next to the program). Android: ExoPlayer when
  the app has it ([package.android] libraries = ["androidx.media3:media3-exoplayer:1.4.1",
  "androidx.media3:media3-exoplayer-hls:1.4.1"]), else Android's MediaPlayer;
  the picture is the phone's own view over the window, with the info band and
  the spinner drawn by it.

  Keys (the player has the focus): Enter/Space pause and play, Left/Right
  10 seconds back and on (not live), M mutes; OnKeyDown sees them first (the
  arrows of a TV's remote: channels).

`uses Pastel.VideoPlayer;` · source: [framework/src/pastel.videoplayer.pas](../../framework/src/pastel.videoplayer.pas)

## Types

### TPlayerState

```pascal
type TPlayerState = (psIdle, psLoading, psPlaying, psPaused, psEnded, psError)
```

- `psIdle`
- `psLoading`
- `psPlaying`
- `psPaused`
- `psEnded`
- `psError`
### TPlayerTrack

```pascal
type TPlayerTrack = record
```

An audio track or a subtitle of the stream. Id: for SelectTrack.

| | |
|---|---|
| `Kind: string` | 'audio' or 'sub' |
| `Id: Integer` |  |
| `Language: string` |  |
| `Title: string` |  |
| `Selected: Boolean` |  |
| `function Caption: string` | 'English', 'tur - Turkish', 'Track 2' |

### TVideoPlayer

```pascal
type TVideoPlayer = class(TNativeView)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Play(const AUrl: string)` | Opens Url and plays it. |
| `procedure Play` | Goes on after Pause. |
| `procedure Pause` |  |
| `procedure TogglePause` |  |
| `procedure Stop` |  |
| `procedure Seek(Seconds: Double; Relative: Boolean = False)` | To Seconds; Relative: that many seconds on (negative: back). Not live streams. |
| `function Tracks: TPlayerTracks` |  |
| `procedure SelectTrack(const Kind: string; Id: Integer)` | Kind 'audio' or 'sub'; Id of Tracks; for 'sub' -1: none. |
| `procedure ShowInfo(const Title: string; const Line: string = ''; Seconds: Integer = 5)` | The band at the bottom: a title, a line, the progress and the time, for Seconds (0: until HideInfo). |
| `procedure HideInfo` |  |
| `function InfoShown: Boolean` |  |
| `procedure Update` | Processes what the player tells (the app's timer calls it; tests too). |
| `property Position: Double` | Seconds; Duration 0: a live stream (or not known yet). |
| `property Duration: Double` |  |
| `function Live: Boolean` |  |
| `property State: TPlayerState` |  |
| `function Playing: Boolean` |  |
| `property Error: string` | Why it could not play (State = psError). |
| `property Engine: string` | 'mpv', 'exoplayer', 'mediaplayer'; '' when none (computers without libmpv). |
| `property VideoWidth: Integer` |  |
| `property VideoHeight: Integer` |  |
| `property Url: string` |  |
| `property UserAgent: string` |  |
| `property Volume: Integer` | 0..100 |
| `property Muted: Boolean` |  |
| `property OnStateChange: TNotifyEvent` |  |
| `property OnTracksChange: TNotifyEvent` |  |
| `property OnError: TMediaErrorEvent` |  |
| `property OnTap: TNotifyEvent` | A click or a tap on the picture; two quick ones: OnDoubleTap (full screen). |
| `property OnDoubleTap: TNotifyEvent` |  |
| `property OnKeyDown: TPlayerKeyEvent` |  |

## Other types

| | |
|---|---|
| `type TPlayerTracks = array of TPlayerTrack` |  |
| `type TPlayerKeyEvent = procedure(Sender: TObject; Key: LongInt; Handled: Boolean)` |  |

## Routines

### VideoPlayerAvailable

```pascal
function VideoPlayerAvailable: Boolean
```

True when videos can be played here (computers: libmpv was found).

### VideoPlayerProblem

```pascal
function VideoPlayerProblem: string
```

Why not (which library to install).

### PlayerClock

```pascal
function PlayerClock(Seconds: Double): string
```

m:ss or h:mm:ss

