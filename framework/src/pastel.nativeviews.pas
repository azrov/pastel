{ Pastel - the phone's own views in a form: web pages, video, and sound.

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
  Part of the Pastel project, MIT License. }
unit Pastel.NativeViews;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI, Pastel.Device;

type
  TWebUrlEvent = procedure(Sender: TObject; const Url: string) of object;
  TWebTextEvent = procedure(Sender: TObject; const Text: string) of object;
  { The answer of EvaluateJavaScript, as JSON ('"text"', '42', 'null'). }
  TJavaScriptResultEvent = procedure(Sender: TObject; const Json: string) of object;
  TMediaErrorEvent = procedure(Sender: TObject; const Message: string) of object;

  { A control with one of the phone's views over it (Android); on computers it paints itself. }
  TNativeView = class(TControl)
  private
    FId: Integer;
    FTimer: TTimer;
    FPlaced: string;
    procedure Tick(Sender: TObject);
  protected
    { the phone's view's kind: 'web', 'video', 'camera', 'player', 'audio' }
    FKind: string;
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    { The phone's view: made on first use. }
    function ViewId: Integer;
    procedure Run(const Op, Arg: string);
    function State: TStringArray;
    { Where it is shown now: the control, the part a scrolling parent leaves; False: not on the screen. }
    function OnScreen(out R, Seen: TRectI): Boolean;
    procedure Place;
    procedure ViewEvent(const Parts: TStringArray); virtual;
    procedure PaintOnComputer(C: TCanvas32); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  { A web page in the form: Android's WebView; on computers a box that opens it in the browser. }
  TWebBrowser = class(TNativeView)
  private
    FUrl, FHtml, FBaseUrl, FTitle: string;
    FOnLoad, FOnLoading: TWebUrlEvent;
    FOnError, FOnMessage: TWebTextEvent;
    FCalls: array of record
      Tag: Integer;
      Done: TJavaScriptResultEvent;
    end;
    FNextTag: Integer;
    procedure SetUrl(const AValue: string);
  protected
    procedure ViewEvent(const Parts: TStringArray); override;
    procedure PaintOnComputer(C: TCanvas32); override;
    function Cursor: TCursorKind; override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Loaded; override;
    procedure Navigate(const AUrl: string);
    { A page from text; BaseUrl: where its relative links and pictures point. }
    procedure LoadHtml(const Html: string; const BaseUrl: string = '');
    procedure GoBack;
    procedure GoForward;
    procedure Reload;
    procedure Stop;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    { Runs JavaScript in the page; Done gets its value as JSON (Android). }
    procedure EvaluateJavaScript(const Script: string; Done: TJavaScriptResultEvent = nil);
    { The page's title (after OnLoad). }
    function Title: string;
  published
    { Setting it opens the page. }
    property Url: string read FUrl write SetUrl;
    { A page started loading (also a link the user tapped). }
    property OnLoading: TWebUrlEvent read FOnLoading write FOnLoading;
    { A page is there. }
    property OnLoad: TWebUrlEvent read FOnLoad write FOnLoad;
    property OnError: TWebTextEvent read FOnError write FOnError;
    { The page's JavaScript called pastel.post(text). }
    property OnMessage: TWebTextEvent read FOnMessage write FOnMessage;
  end;

  { What TMediaPlayer and TVideoView share: a sound or a video, played. }
  TMediaCore = class
  private
    FOwner: TObject;
    FId: Integer;
    FUrl: string;
    FVolume: Single;
    FLoop, FPlaying, FPrepared: Boolean;
    FDuration: Integer;
    FOnPrepared, FOnCompleted: TNotifyEvent;
    FOnError: TMediaErrorEvent;
    { computers: the player program }
    FProcess: TObject;
    FStartPos: Integer;
    FStartedAt: QWord;
    FIdFor: function: Integer of object;
    procedure ComputerStart;
    procedure ComputerStop;
  public
    constructor Create(AOwner: TObject);
    destructor Destroy; override;
    procedure Open(const AUrl: string);
    procedure Play;
    procedure Pause;
    procedure Stop;
    function Position: Integer;
    procedure SetPosition(Ms: Integer);
    procedure SetVolume(V: Single);
    procedure SetLoop(V: Boolean);
    function Playing: Boolean;
    procedure Event(const Parts: TStringArray);
    procedure Check;
  end;

  { Sound (music, a recording, a stream) without a view. }
  TMediaPlayer = class(TComponent)
  private
    FCore: TMediaCore;
    FTimer: TTimer;
    FId: Integer;
    function GetUrl: string;
    procedure SetUrl(const AValue: string);
    function GetVolume: Single;
    procedure SetVolume(AValue: Single);
    function GetLoop: Boolean;
    procedure SetLoop(AValue: Boolean);
    function GetPosition: Integer;
    procedure SetPosition(AValue: Integer);
    function GetOnPrepared: TNotifyEvent;
    procedure SetOnPrepared(AValue: TNotifyEvent);
    function GetOnCompleted: TNotifyEvent;
    procedure SetOnCompleted(AValue: TNotifyEvent);
    function GetOnError: TMediaErrorEvent;
    procedure SetOnError(AValue: TMediaErrorEvent);
    function MakeId: Integer;
    procedure Tick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Play;
    procedure Pause;
    procedure Stop;
    function Playing: Boolean;
    { Milliseconds; 0 until OnPrepared (or not known on computers). }
    function Duration: Integer;
    property Position: Integer read GetPosition write SetPosition;
  published
    { A file (an absolute path) or an http(s) address. }
    property Url: string read GetUrl write SetUrl;
    { 0 to 1. }
    property Volume: Single read GetVolume write SetVolume;
    property Loop: Boolean read GetLoop write SetLoop default False;
    property OnPrepared: TNotifyEvent read GetOnPrepared write SetOnPrepared;
    property OnCompleted: TNotifyEvent read GetOnCompleted write SetOnCompleted;
    property OnError: TMediaErrorEvent read GetOnError write SetOnError;
  end;

  { A video in the form: Android's VideoView; on computers the video app plays it. }
  TVideoView = class(TNativeView)
  private
    FCore: TMediaCore;
    function GetUrl: string;
    procedure SetUrl(const AValue: string);
    function GetVolume: Single;
    procedure SetVolume(AValue: Single);
    function GetLoop: Boolean;
    procedure SetLoop(AValue: Boolean);
    function GetPosition: Integer;
    procedure SetPosition(AValue: Integer);
    function GetOnPrepared: TNotifyEvent;
    procedure SetOnPrepared(AValue: TNotifyEvent);
    function GetOnCompleted: TNotifyEvent;
    procedure SetOnCompleted(AValue: TNotifyEvent);
    function GetOnError: TMediaErrorEvent;
    procedure SetOnError(AValue: TMediaErrorEvent);
  protected
    procedure ViewEvent(const Parts: TStringArray); override;
    procedure PaintOnComputer(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Play;
    procedure Pause;
    procedure Stop;
    function Playing: Boolean;
    function Duration: Integer;
    property Position: Integer read GetPosition write SetPosition;
  published
    property Url: string read GetUrl write SetUrl;
    property Volume: Single read GetVolume write SetVolume;
    property Loop: Boolean read GetLoop write SetLoop default False;
    property OnPrepared: TNotifyEvent read GetOnPrepared write SetOnPrepared;
    property OnCompleted: TNotifyEvent read GetOnCompleted write SetOnCompleted;
    property OnError: TMediaErrorEvent read GetOnError write SetOnError;
  end;

  TCameraPhotoEvent = procedure(Sender: TObject; const FileName: string) of object;

  { The camera's picture in the form (Android's Camera2): a scanner, a photo
    without leaving the app. Asks for the camera's permission on Start. }
  TCameraView = class(TNativeView)
  private
    FFront, FTorch, FActive: Boolean;
    FOnPhoto: TCameraPhotoEvent;
    FOnError: TMediaErrorEvent;
    FOnStarted: TNotifyEvent;
    procedure SetFront(AValue: Boolean);
    procedure SetTorch(AValue: Boolean);
    procedure Permitted(Sender: TObject; Granted, Blocked: TDevicePermissions);
  protected
    procedure ViewEvent(const Parts: TStringArray); override;
    procedure PaintOnComputer(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start;
    procedure Stop;
    { A JPEG into FileName (default: a new file in the app's folder); OnPhoto when it is there. }
    procedure TakePhoto(const FileName: string = '');
    property Active: Boolean read FActive;
  published
    { The camera on the screen's side (a selfie) instead of the back one. }
    property Front: Boolean read FFront write SetFront default False;
    { The flash's light on. }
    property Torch: Boolean read FTorch write SetTorch default False;
    property OnStarted: TNotifyEvent read FOnStarted write FOnStarted;
    property OnPhoto: TCameraPhotoEvent read FOnPhoto write FOnPhoto;
    property OnError: TMediaErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  Math, Process, StrUtils, Pastel.Files, Pastel.Env{$IFDEF ANDROID}, Pastel.Android{$ENDIF}{$IFNDEF ANDROID}, Pastel.Process{$ENDIF};

{ ---- the phone's side ---- }

function NewView(const Kind: string): Integer;
begin
  {$IFDEF ANDROID}
  Result := AndroidNewRequest;
  if not AndroidCall('viewCreate', '(ILjava/lang/String;)V', [Result, Kind]) then
    Result := -1;
  {$ELSE}
  Result := -1;
  if Kind = '' then ;
  {$ENDIF}
end;

procedure ViewRun(Id: Integer; const Op, Arg: string);
begin
  {$IFDEF ANDROID}
  if Id >= 0 then
    AndroidCall('viewRun', '(ILjava/lang/String;Ljava/lang/String;)V', [Id, Op, Arg]);
  {$ELSE}
  if (Id = 0) and (Op = '') and (Arg = '') then ;
  {$ENDIF}
end;

function ViewState(Id: Integer): TStringArray;
begin
  Result := nil;
  {$IFDEF ANDROID}
  if Id >= 0 then
    Result := AndroidCallString('viewState', '(I)Ljava/lang/String;', [Id]).Split([#9]);
  {$ELSE}
  if Id = 0 then ;
  {$ENDIF}
end;

procedure ViewDestroy(Id: Integer);
begin
  {$IFDEF ANDROID}
  if Id >= 0 then
    AndroidCall('viewDestroy', '(I)V', [Id]);
  {$ELSE}
  if Id = 0 then ;
  {$ENDIF}
end;

{ the events that came for the view: "kind"#9"data"... }
function TakeEvent(Id: Integer; out Parts: TStringArray): Boolean;
{$IFDEF ANDROID}
var
  Ok: Boolean;
  Text: string;
{$ENDIF}
begin
  Parts := nil;
  Result := False;
  {$IFDEF ANDROID}
  if (Id >= 0) and AndroidTakeResult(Id, Ok, Text) then
  begin
    Parts := Text.Split([#9]);
    Result := Length(Parts) > 0;
  end;
  {$ELSE}
  if Id = 0 then ;
  {$ENDIF}
end;

function Part(const Parts: TStringArray; I: Integer): string;
begin
  if I < Length(Parts) then
    Result := Parts[I]
  else
    Result := '';
end;

{ ---- TNativeView ---- }

constructor TNativeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FId := -1;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.OnTimer := @Tick;
  {$IFDEF ANDROID}
  FTimer.Enabled := True;
  {$ELSE}
  FTimer.Enabled := False;
  {$ENDIF}
end;

destructor TNativeView.Destroy;
begin
  ViewDestroy(FId);
  FId := -1;
  inherited Destroy;
end;

procedure TNativeView.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := Min(AvailWidth, 320);
  H := 240;
end;

function TNativeView.ViewId: Integer;
begin
  if FId < 0 then
    FId := NewView(FKind);
  Result := FId;
end;

procedure TNativeView.Run(const Op, Arg: string);
begin
  ViewRun(ViewId, Op, Arg);
end;

function TNativeView.State: TStringArray;
begin
  Result := ViewState(FId);
end;

function TNativeView.OnScreen(out R, Seen: TRectI): Boolean;
var
  P: TControl;
  Pop: TPopup;
  O: TRectI;
  I: Integer;
begin
  Result := False;
  R := Bounds;
  Seen := Bounds;
  if (MainForm = nil) or not Assigned(WindowPixelRect) then
    Exit;
  P := Self;
  while True do
  begin
    if not P.Visible then
      Exit;
    if P <> Self then
      Seen := Seen.Intersect(P.Bounds);
    if P.Parent = nil then
      Break;
    P := P.Parent;
  end;
  { on the form, or in the popup (a dialog) on top; popups above it: a dialog
    (the window dimmed) or a drawer hides it, a menu or a drop-down only when over it }
  if P <> MainForm then
    if not ((P is TPopup) and TPopup(P).Shown) then
      Exit;
  for I := MainForm.PopupCount - 1 downto 0 do
  begin
    Pop := MainForm.PopupAt(I);
    if Pop = P then
      Break;
    if Pop.Modal or (Pop.Side <> psAnchor) then
      Exit;
    O := Pop.Bounds.Intersect(Seen);
    if (O.W > 0) and (O.H > 0) then
      Exit;
  end;

  Result := (Seen.W > 0) and (Seen.H > 0) and (R.W > 0) and (R.H > 0);
end;

procedure TNativeView.Place;
var
  R, Seen, PR, PS: TRectI;
  Shown: Boolean;
  Key: string;
begin
  if FId < 0 then
    Exit;
  Shown := OnScreen(R, Seen);
  if Shown then
  begin
    PR := WindowPixelRect(R);
    PS := WindowPixelRect(Seen);
    Key := Format('%d,%d,%d,%d,%d,%d,%d,%d', [PR.X, PR.Y, PR.W, PR.H, PS.X, PS.Y, PS.W, PS.H]);
  end
  else
  begin
    PR := RectI(0, 0, 0, 0);
    PS := PR;
    Key := 'hidden';
  end;
  if Key = FPlaced then
    Exit;
  FPlaced := Key;
  {$IFDEF ANDROID}
  AndroidCall('viewBounds', '(IIIIIIIIIZ)V', [FId, PR.X, PR.Y, PR.W, PR.H, PS.X, PS.Y, PS.W, PS.H, Shown]);
  {$ENDIF}
end;

procedure TNativeView.Tick(Sender: TObject);
var
  Parts: TStringArray;
begin
  Place;
  while TakeEvent(FId, Parts) do
    ViewEvent(Parts);
end;

procedure TNativeView.ViewEvent(const Parts: TStringArray);
begin
end;

procedure TNativeView.Paint(C: TCanvas32);
begin
  {$IFDEF ANDROID}
  { the phone's view is over it; this shows while it comes }
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Surface);
  ViewId;
  Place;
  {$ELSE}
  PaintOnComputer(C);
  {$ENDIF}
end;

procedure TNativeView.PaintOnComputer(C: TCanvas32);
begin
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface);
end;

{ ---- TWebBrowser ---- }

constructor TWebBrowser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := 'web';
end;

procedure TWebBrowser.Loaded;
begin
  inherited Loaded;
  if FUrl <> '' then
    Run('url', FUrl);
end;

procedure TWebBrowser.SetUrl(const AValue: string);
begin
  Navigate(AValue);
end;

procedure TWebBrowser.Navigate(const AUrl: string);
begin
  FUrl := AUrl;
  FHtml := '';
  if (AUrl <> '') and not (csLoading in ComponentState) then
    Run('url', AUrl);
  Invalidate;
end;

procedure TWebBrowser.LoadHtml(const Html: string; const BaseUrl: string);
begin
  FHtml := Html;
  FBaseUrl := BaseUrl;
  FUrl := '';
  Run('html', BaseUrl + #10 + Html);
  Invalidate;
end;

procedure TWebBrowser.GoBack;
begin
  Run('back', '');
end;

procedure TWebBrowser.GoForward;
begin
  Run('forward', '');
end;

procedure TWebBrowser.Reload;
begin
  Run('reload', '');
end;

procedure TWebBrowser.Stop;
begin
  Run('stop', '');
end;

function TWebBrowser.CanGoBack: Boolean;
begin
  Result := Part(State, 2) = '1';
end;

function TWebBrowser.CanGoForward: Boolean;
begin
  Result := Part(State, 3) = '1';
end;

function TWebBrowser.Title: string;
var
  S: TStringArray;
begin
  S := State;
  if Length(S) > 1 then
    FTitle := S[1];
  Result := FTitle;
end;

procedure TWebBrowser.EvaluateJavaScript(const Script: string; Done: TJavaScriptResultEvent);
begin
  Inc(FNextTag);
  if Assigned(Done) then
  begin
    SetLength(FCalls, Length(FCalls) + 1);
    FCalls[High(FCalls)].Tag := FNextTag;
    FCalls[High(FCalls)].Done := Done;
  end;
  {$IFDEF ANDROID}
  Run('js', IntToStr(FNextTag) + #10 + Script);
  {$ELSE}
  { computers: no page to run it in }
  if Assigned(Done) then
  begin
    SetLength(FCalls, Length(FCalls) - 1);
    Done(Self, 'null');
  end;
  {$ENDIF}
end;

procedure TWebBrowser.ViewEvent(const Parts: TStringArray);
var
  K: string;
  I, JsTag: Integer;
  Done: TJavaScriptResultEvent;
begin
  K := Parts[0];
  if K = 'loading' then
  begin
    FUrl := Part(Parts, 1);
    if Assigned(FOnLoading) then
      FOnLoading(Self, FUrl);
  end
  else if K = 'loaded' then
  begin
    FUrl := Part(Parts, 1);
    FTitle := Part(Parts, 2);
    if Assigned(FOnLoad) then
      FOnLoad(Self, FUrl);
  end
  else if K = 'error' then
  begin
    if Assigned(FOnError) then
      FOnError(Self, Part(Parts, 1));
  end
  else if K = 'message' then
  begin
    if Assigned(FOnMessage) then
      FOnMessage(Self, Part(Parts, 1));
  end
  else if K = 'js' then
  begin
    JsTag := StrToIntDef(Part(Parts, 1), -1);
    for I := 0 to High(FCalls) do
      if FCalls[I].Tag = JsTag then
      begin
        Done := FCalls[I].Done;
        Delete(FCalls, I, 1);
        Done(Self, Part(Parts, 2));
        Break;
      end;
  end;
end;

procedure TWebBrowser.PaintOnComputer(C: TCanvas32);
var
  F, B: TPastelFont;
  S: string;
begin
  inherited PaintOnComputer(C);
  C.PushClip(Bounds);
  try
    F := GetFont(Theme.FontSize);
    B := GetFont(Theme.FontSize, True);
    if FUrl <> '' then
      S := FUrl
    else if FHtml <> '' then
      S := 'a page'
    else
      S := 'no page yet';
    C.DrawText(B, Bounds.X + 12, Bounds.Y + 12, 'Web page', Theme.Text);
    C.DrawText(F, Bounds.X + 12, Bounds.Y + 12 + B.LineHeight + 4, S, Theme.TextMuted);
    if (FUrl <> '') or (FHtml <> '') then
      C.DrawText(F, Bounds.X + 12, Bounds.Y + 12 + B.LineHeight + 8 + F.LineHeight, 'Click to open it in the browser',
        Theme.Accent);
  finally
    C.PopClip;
  end;
end;

function TWebBrowser.Cursor: TCursorKind;
begin
  if (FUrl <> '') or (FHtml <> '') then
    Result := ckHand
  else
    Result := inherited Cursor;
end;

procedure TWebBrowser.MouseUp(X, Y: Integer; Inside: Boolean);
var
  F: string;
begin
  inherited MouseUp(X, Y, Inside);
  {$IFNDEF ANDROID}
  if not Inside then
    Exit;
  if FUrl <> '' then
    OpenUrl(FUrl)
  else if FHtml <> '' then
  begin
    F := IncludeTrailingPathDelimiter(GetTempDir) + 'pastel-page-' + IntToStr(GetProcessID) + '.html';
    WriteText(F, FHtml);
    OpenUrl(F);
  end;
  {$ELSE}
  F := '';
  if F = '' then ;
  {$ENDIF}
end;

{ ---- TMediaCore ---- }

constructor TMediaCore.Create(AOwner: TObject);
begin
  FOwner := AOwner;
  FId := -1;
  FVolume := 1;
end;

destructor TMediaCore.Destroy;
begin
  ComputerStop;
  inherited Destroy;
end;

procedure TMediaCore.Open(const AUrl: string);
begin
  ComputerStop;
  FUrl := AUrl;
  FPrepared := False;
  FPlaying := False;
  FDuration := 0;
  FStartPos := 0;
  {$IFDEF ANDROID}
  if (AUrl <> '') and Assigned(FIdFor) then
  begin
    ViewRun(FIdFor(), 'loop', IntToStr(Ord(FLoop)));
    ViewRun(FIdFor(), 'volume', FloatToStr(FVolume, InvariantFormat));
    ViewRun(FIdFor(), 'open', AUrl);
  end;
  {$ENDIF}
end;

procedure TMediaCore.Play;
begin
  if FUrl = '' then
    Exit;
  {$IFDEF ANDROID}
  if Assigned(FIdFor) then
    ViewRun(FIdFor(), 'play', '');
  FPlaying := True;
  {$ELSE}
  if not FPlaying then
    ComputerStart;
  {$ENDIF}
end;

procedure TMediaCore.Pause;
begin
  {$IFDEF ANDROID}
  ViewRun(FId, 'pause', '');
  FPlaying := False;
  {$ELSE}
  if FPlaying then
  begin
    FStartPos := Position;
    ComputerStop;
  end;
  {$ENDIF}
end;

procedure TMediaCore.Stop;
begin
  {$IFDEF ANDROID}
  ViewRun(FId, 'stop', '');
  FPlaying := False;
  {$ELSE}
  ComputerStop;
  FStartPos := 0;
  {$ENDIF}
end;

function TMediaCore.Position: Integer;
begin
  {$IFDEF ANDROID}
  Result := StrToIntDef(Part(ViewState(FId), 0), 0);
  {$ELSE}
  Result := FStartPos;
  if FPlaying then
    Result := FStartPos + Integer(GetTickCount64 - FStartedAt);
  {$ENDIF}
end;

procedure TMediaCore.SetPosition(Ms: Integer);
begin
  Ms := Max(0, Ms);
  {$IFDEF ANDROID}
  ViewRun(FId, 'seek', IntToStr(Ms));
  {$ELSE}
  if FPlaying then
  begin
    ComputerStop;
    FStartPos := Ms;
    ComputerStart;
  end
  else
    FStartPos := Ms;
  {$ENDIF}
end;

procedure TMediaCore.SetVolume(V: Single);
begin
  FVolume := EnsureRange(V, 0, 1);
  ViewRun(FId, 'volume', FloatToStr(FVolume, InvariantFormat));
end;

procedure TMediaCore.SetLoop(V: Boolean);
begin
  FLoop := V;
  ViewRun(FId, 'loop', IntToStr(Ord(V)));
end;

function TMediaCore.Playing: Boolean;
begin
  {$IFDEF ANDROID}
  if FId >= 0 then
    FPlaying := Part(ViewState(FId), 2) = '1';
  {$ENDIF}
  Result := FPlaying;
end;

procedure TMediaCore.Event(const Parts: TStringArray);
var
  K: string;
begin
  K := Parts[0];
  if K = 'prepared' then
  begin
    FPrepared := True;
    FDuration := StrToIntDef(Part(Parts, 1), 0);
    if Assigned(FOnPrepared) then
      FOnPrepared(FOwner);
  end
  else if K = 'completed' then
  begin
    FPlaying := False;
    if Assigned(FOnCompleted) then
      FOnCompleted(FOwner);
  end
  else if K = 'error' then
  begin
    FPlaying := False;
    if Assigned(FOnError) then
      FOnError(FOwner, Part(Parts, 1));
  end;
end;

{ computers: a player program }

function PlayerCommand(const Url: string; StartMs: Integer; Volume: Single; out Exe: string): TStringArray;
var
  S: string;
begin
  Result := nil;
  S := FloatToStrF(StartMs / 1000, ffFixed, 12, 1, InvariantFormat);
  {$IFDEF WINDOWS}
  Exe := 'powershell.exe';
  Result := ['-NoProfile', '-NonInteractive', '-Command',
    Format('$p = New-Object -ComObject WMPlayer.OCX; $p.settings.volume = %d; $p.URL = ''%s''; ' +
      '$p.controls.currentPosition = %s; $p.controls.play(); Start-Sleep -Milliseconds 800; ' +
      'while ($p.playState -ne 1 -and $p.playState -ne 8 -and $p.playState -ne 10) { Start-Sleep -Milliseconds 200 }',
      [Round(Volume * 100), StringReplace(Url, '''', '''''', [rfReplaceAll]), S])];
  {$ELSE}
  {$IFNDEF ANDROID}
  Exe := Which('mpv');
  if Exe <> '' then
    Exit(['--no-video', '--really-quiet', '--start=' + S, '--volume=' + IntToStr(Round(Volume * 100)), Url]);
  Exe := Which('ffplay');
  if Exe <> '' then
    Exit(['-nodisp', '-autoexit', '-loglevel', 'quiet', '-ss', S, '-volume', IntToStr(Round(Volume * 100)), Url]);
  Exe := Which('cvlc');
  if Exe <> '' then
    Exit(['--play-and-exit', '--quiet', '--start-time=' + S, Url]);
  Exe := Which('afplay');
  if Exe <> '' then
    Exit(['-v', FloatToStrF(Volume, ffFixed, 4, 2, InvariantFormat), Url]);
  {$ENDIF}
  Exe := '';
  {$ENDIF}
end;

procedure TMediaCore.ComputerStart;
var
  Exe, A: string;
  Args: TStringArray;
  P: TProcess;
begin
  Args := PlayerCommand(FUrl, FStartPos, FVolume, Exe);
  if Exe = '' then
  begin
    if Assigned(FOnError) then
      FOnError(FOwner, 'no player for sound here: install mpv, ffplay (FFmpeg) or VLC');
    Exit;
  end;
  P := TProcess.Create(nil);
  P.Executable := Exe;
  for A in Args do
    P.Parameters.Add(A);
  P.Options := [poNoConsole];
  try
    P.Execute;
  except
    on E: Exception do
    begin
      P.Free;
      if Assigned(FOnError) then
        FOnError(FOwner, E.Message);
      Exit;
    end;
  end;
  FProcess := P;
  FPlaying := True;
  FStartedAt := GetTickCount64;
  if not FPrepared then
  begin
    FPrepared := True;
    if Assigned(FOnPrepared) then
      FOnPrepared(FOwner);
  end;
end;

procedure TMediaCore.ComputerStop;
begin
  if FProcess <> nil then
  begin
    if TProcess(FProcess).Running then
      TProcess(FProcess).Terminate(0);
    FreeAndNil(FProcess);
  end;
  FPlaying := False;
end;

{ computers: the program ended by itself - the end of the sound }
procedure TMediaCore.Check;
begin
  if (FProcess = nil) or TProcess(FProcess).Running then
    Exit;
  FreeAndNil(FProcess);
  FPlaying := False;
  FStartPos := 0;
  if FLoop then
    ComputerStart
  else if Assigned(FOnCompleted) then
    FOnCompleted(FOwner);
end;

{ ---- TMediaPlayer ---- }

constructor TMediaPlayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FId := -1;
  FCore := TMediaCore.Create(Self);
  FCore.FIdFor := @MakeId;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 100;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;
end;

destructor TMediaPlayer.Destroy;
begin
  ViewDestroy(FId);
  FCore.Free;
  inherited Destroy;
end;

function TMediaPlayer.MakeId: Integer;
begin
  if FId < 0 then
  begin
    FId := NewView('audio');
    FCore.FId := FId;
  end;
  Result := FId;
end;

procedure TMediaPlayer.Tick(Sender: TObject);
var
  Parts: TStringArray;
begin
  while TakeEvent(FId, Parts) do
    FCore.Event(Parts);
  FCore.Check;
end;

function TMediaPlayer.GetUrl: string;
begin
  Result := FCore.FUrl;
end;

procedure TMediaPlayer.SetUrl(const AValue: string);
begin
  if csLoading in ComponentState then
    FCore.FUrl := AValue
  else
    FCore.Open(AValue);
end;

function TMediaPlayer.GetVolume: Single;
begin
  Result := FCore.FVolume;
end;

procedure TMediaPlayer.SetVolume(AValue: Single);
begin
  FCore.SetVolume(AValue);
end;

function TMediaPlayer.GetLoop: Boolean;
begin
  Result := FCore.FLoop;
end;

procedure TMediaPlayer.SetLoop(AValue: Boolean);
begin
  FCore.SetLoop(AValue);
end;

function TMediaPlayer.GetPosition: Integer;
begin
  Result := FCore.Position;
end;

procedure TMediaPlayer.SetPosition(AValue: Integer);
begin
  FCore.SetPosition(AValue);
end;

function TMediaPlayer.GetOnPrepared: TNotifyEvent;
begin
  Result := FCore.FOnPrepared;
end;

procedure TMediaPlayer.SetOnPrepared(AValue: TNotifyEvent);
begin
  FCore.FOnPrepared := AValue;
end;

function TMediaPlayer.GetOnCompleted: TNotifyEvent;
begin
  Result := FCore.FOnCompleted;
end;

procedure TMediaPlayer.SetOnCompleted(AValue: TNotifyEvent);
begin
  FCore.FOnCompleted := AValue;
end;

function TMediaPlayer.GetOnError: TMediaErrorEvent;
begin
  Result := FCore.FOnError;
end;

procedure TMediaPlayer.SetOnError(AValue: TMediaErrorEvent);
begin
  FCore.FOnError := AValue;
end;

procedure TMediaPlayer.Play;
begin
  {$IFDEF ANDROID}
  if (FId < 0) and (FCore.FUrl <> '') then
    FCore.Open(FCore.FUrl);
  {$ENDIF}
  FCore.Play;
end;

procedure TMediaPlayer.Pause;
begin
  FCore.Pause;
end;

procedure TMediaPlayer.Stop;
begin
  FCore.Stop;
end;

function TMediaPlayer.Playing: Boolean;
begin
  Result := FCore.Playing;
end;

function TMediaPlayer.Duration: Integer;
begin
  Result := FCore.FDuration;
end;

{ ---- TVideoView ---- }

constructor TVideoView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := 'video';
  FCore := TMediaCore.Create(Self);
  FCore.FIdFor := @ViewId;
end;

destructor TVideoView.Destroy;
begin
  FCore.Free;
  inherited Destroy;
end;

procedure TVideoView.ViewEvent(const Parts: TStringArray);
begin
  FCore.FId := FId;
  FCore.Event(Parts);
end;

procedure TVideoView.PaintOnComputer(C: TCanvas32);
var
  F: TPastelFont;
  S: string;
begin
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, $FF000000);
  F := GetFont(Theme.FontSize);
  if FCore.FUrl = '' then
    S := 'no video'
  else
    S := ExtractFileName(FCore.FUrl);
  C.PushClip(Bounds);
  try
    C.DrawText(F, Bounds.X + (Bounds.W - F.TextWidth(S)) div 2, Bounds.Y + (Bounds.H - F.LineHeight) div 2, S,
      $FFDDDDDD);
  finally
    C.PopClip;
  end;
end;

function TVideoView.GetUrl: string;
begin
  Result := FCore.FUrl;
end;

procedure TVideoView.SetUrl(const AValue: string);
begin
  if csLoading in ComponentState then
    FCore.FUrl := AValue
  else
  begin
    FCore.FId := ViewId;
    FCore.Open(AValue);
  end;
  Invalidate;
end;

function TVideoView.GetVolume: Single;
begin
  Result := FCore.FVolume;
end;

procedure TVideoView.SetVolume(AValue: Single);
begin
  FCore.SetVolume(AValue);
end;

function TVideoView.GetLoop: Boolean;
begin
  Result := FCore.FLoop;
end;

procedure TVideoView.SetLoop(AValue: Boolean);
begin
  FCore.SetLoop(AValue);
end;

function TVideoView.GetPosition: Integer;
begin
  Result := FCore.Position;
end;

procedure TVideoView.SetPosition(AValue: Integer);
begin
  FCore.SetPosition(AValue);
end;

function TVideoView.GetOnPrepared: TNotifyEvent;
begin
  Result := FCore.FOnPrepared;
end;

procedure TVideoView.SetOnPrepared(AValue: TNotifyEvent);
begin
  FCore.FOnPrepared := AValue;
end;

function TVideoView.GetOnCompleted: TNotifyEvent;
begin
  Result := FCore.FOnCompleted;
end;

procedure TVideoView.SetOnCompleted(AValue: TNotifyEvent);
begin
  FCore.FOnCompleted := AValue;
end;

function TVideoView.GetOnError: TMediaErrorEvent;
begin
  Result := FCore.FOnError;
end;

procedure TVideoView.SetOnError(AValue: TMediaErrorEvent);
begin
  FCore.FOnError := AValue;
end;

procedure TVideoView.Play;
begin
  {$IFDEF ANDROID}
  FCore.FId := ViewId;
  if not FCore.FPrepared and (FCore.FUrl <> '') then
    FCore.Open(FCore.FUrl);
  FCore.Play;
  {$ELSE}
  { computers: the video app }
  if FCore.FUrl <> '' then
    OpenUrl(FCore.FUrl);
  {$ENDIF}
end;

procedure TVideoView.Pause;
begin
  FCore.Pause;
end;

procedure TVideoView.Stop;
begin
  FCore.Stop;
end;

function TVideoView.Playing: Boolean;
begin
  Result := FCore.Playing;
end;

function TVideoView.Duration: Integer;
begin
  Result := FCore.FDuration;
end;

{ ---- TCameraView ---- }

constructor TCameraView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := 'camera';
end;

procedure TCameraView.SetFront(AValue: Boolean);
begin
  if FFront = AValue then
    Exit;
  FFront := AValue;
  if FActive then
    Run('start', StrUtils.IfThen(FFront, 'front', 'back'));
end;

procedure TCameraView.SetTorch(AValue: Boolean);
begin
  FTorch := AValue;
  if FId >= 0 then
    Run('torch', IntToStr(Ord(AValue)));
end;

procedure TCameraView.Start;
begin
  RequestPermissions([dpCamera], @Permitted);
end;

procedure TCameraView.Permitted(Sender: TObject; Granted, Blocked: TDevicePermissions);
begin
  if not (dpCamera in Granted) then
  begin
    if Assigned(FOnError) then
      FOnError(Self, 'no permission for the camera');
    Exit;
  end;
  {$IFDEF ANDROID}
  FActive := True;
  Run('start', StrUtils.IfThen(FFront, 'front', 'back'));
  if FTorch then
    Run('torch', '1');
  {$ELSE}
  if Assigned(FOnError) then
    FOnError(Self, 'the camera''s picture in a form is there on phones (on computers: TakePhoto of Pastel.Device)');
  {$ENDIF}
end;

procedure TCameraView.Stop;
begin
  FActive := False;
  if FId >= 0 then
    Run('stop', '');
end;

procedure TCameraView.TakePhoto(const FileName: string);
var
  F: string;
begin
  F := FileName;
  if F = '' then
    F := JoinPath([HomeDir, 'photo-' + FormatDateTime('yyyymmdd-hhnnsszzz', Now) + '.jpg']);
  if not FActive then
  begin
    if Assigned(FOnError) then
      FOnError(Self, 'the camera is not on (Start)');
    Exit;
  end;
  Run('photo', F);
end;

procedure TCameraView.ViewEvent(const Parts: TStringArray);
begin
  if Parts[0] = 'started' then
  begin
    if Assigned(FOnStarted) then
      FOnStarted(Self);
  end
  else if Parts[0] = 'photo' then
  begin
    if Assigned(FOnPhoto) then
      FOnPhoto(Self, Part(Parts, 1));
  end
  else if Parts[0] = 'error' then
    if Assigned(FOnError) then
      FOnError(Self, Part(Parts, 1));
end;

procedure TCameraView.PaintOnComputer(C: TCanvas32);
var
  F: TPastelFont;
  S: string;
begin
  C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, $FF202020);
  F := GetFont(Theme.FontSize);
  S := 'Camera';
  C.DrawText(F, Bounds.X + (Bounds.W - F.TextWidth(S)) div 2, Bounds.Y + (Bounds.H - F.LineHeight) div 2, S, $FFAAAAAA);
end;

initialization
  RegisterControl(TCameraView);
  RegisterControl(TWebBrowser);
  RegisterControl(TVideoView);
  RegisterNonVisual(TMediaPlayer);
end.
