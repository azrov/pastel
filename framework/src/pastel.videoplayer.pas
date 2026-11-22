{ Pastel - TVideoPlayer: video and live streams in the form, on computers and phones.

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
  Part of the Pastel project, MIT License. }
unit Pastel.VideoPlayer;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math, Pastel.Graphics, Pastel.UI, Pastel.NativeViews;

type
  TPlayerState = (psIdle, psLoading, psPlaying, psPaused, psEnded, psError);

  { An audio track or a subtitle of the stream. Id: for SelectTrack. }
  TPlayerTrack = record
    Kind: string;              { 'audio' or 'sub' }
    Id: Integer;
    Language, Title: string;
    Selected: Boolean;
    function Caption: string;  { 'English', 'tur - Turkish', 'Track 2' }
  end;
  TPlayerTracks = array of TPlayerTrack;

  TPlayerKeyEvent = procedure(Sender: TObject; Key: LongInt; var Handled: Boolean) of object;

  TVideoPlayer = class(TNativeView)
  private
    FUrl, FUserAgent, FError, FInfoTitle, FInfoLine, FEngine: string;
    FState: TPlayerState;
    FVolume: Integer;
    FMuted: Boolean;
    FPosition, FDuration: Double;
    FTracks: TPlayerTracks;
    FInfoUntil: QWord;
    FVideoW, FVideoH: Integer;
    FOnStateChange, FOnTracksChange, FOnTap, FOnDoubleTap: TNotifyEvent;
    FOnError: TMediaErrorEvent;
    FOnKeyDown: TPlayerKeyEvent;
    { computers: libmpv }
    FMpv: Pointer;
    FRenderer: TObject;           { TMpvRenderer: draws the frames on a thread of its own }
    FTick: TTimer;
    FLastPoll, FTracksDue: QWord;
    procedure SetState(S: TPlayerState);
    procedure SetVolume(AValue: Integer);
    procedure SetMuted(AValue: Boolean);
    procedure Failed(const Msg: string);
    procedure ParseTracks(const S: string);
    procedure Tick(Sender: TObject);
    procedure MpvEvents;
    procedure MpvPoll;
    procedure MpvTracks;
    procedure MpvStop;
    function MpvStart: Boolean;
    procedure PaintInfo(C: TCanvas32);
  protected
    procedure ViewEvent(const Parts: TStringArray); override;
    procedure Paint(C: TCanvas32); override;
    procedure PaintOnComputer(C: TCanvas32); override;
    function Focusable: Boolean; override;
    function KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean; override;
    procedure MouseUp(X, Y: Integer; Inside: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Opens Url and plays it. }
    procedure Play(const AUrl: string); overload;
    { Goes on after Pause. }
    procedure Play; overload;
    procedure Pause;
    procedure TogglePause;
    procedure Stop;
    { To Seconds; Relative: that many seconds on (negative: back). Not live streams. }
    procedure Seek(Seconds: Double; Relative: Boolean = False);
    function Tracks: TPlayerTracks;
    { Kind 'audio' or 'sub'; Id of Tracks; for 'sub' -1: none. }
    procedure SelectTrack(const Kind: string; Id: Integer);
    { The band at the bottom: a title, a line, the progress and the time, for
      Seconds (0: until HideInfo). }
    procedure ShowInfo(const Title: string; const Line: string = ''; Seconds: Integer = 5);
    procedure HideInfo;
    function InfoShown: Boolean;
    { Processes what the player tells (the app's timer calls it; tests too). }
    procedure Update;
    { Seconds; Duration 0: a live stream (or not known yet). }
    property Position: Double read FPosition;
    property Duration: Double read FDuration;
    function Live: Boolean;
    property State: TPlayerState read FState;
    function Playing: Boolean;
    { Why it could not play (State = psError). }
    property Error: string read FError;
    { 'mpv', 'exoplayer', 'mediaplayer'; '' when none (computers without libmpv). }
    property Engine: string read FEngine;
    property VideoWidth: Integer read FVideoW;
    property VideoHeight: Integer read FVideoH;
  published
    property Url: string read FUrl;
    property UserAgent: string read FUserAgent write FUserAgent;
    { 0..100 }
    property Volume: Integer read FVolume write SetVolume default 100;
    property Muted: Boolean read FMuted write SetMuted default False;
    property OnStateChange: TNotifyEvent read FOnStateChange write FOnStateChange;
    property OnTracksChange: TNotifyEvent read FOnTracksChange write FOnTracksChange;
    property OnError: TMediaErrorEvent read FOnError write FOnError;
    { A click or a tap on the picture; two quick ones: OnDoubleTap (full screen). }
    property OnTap: TNotifyEvent read FOnTap write FOnTap;
    property OnDoubleTap: TNotifyEvent read FOnDoubleTap write FOnDoubleTap;
    property OnKeyDown: TPlayerKeyEvent read FOnKeyDown write FOnKeyDown;
  end;

{ True when videos can be played here (computers: libmpv was found). }
function VideoPlayerAvailable: Boolean;
{ Why not (which library to install). }
function VideoPlayerProblem: string;
{ m:ss or h:mm:ss }
function PlayerClock(Seconds: Double): string;

implementation

uses
  {$IFNDEF ANDROID}dynlibs,{$ENDIF} Pastel.Icons, Pastel.Env;

function PlayerClock(Seconds: Double): string;
var
  S: Int64;
begin
  if IsNan(Seconds) or (Seconds < 0) then
    Seconds := 0;
  S := Trunc(Seconds);
  if S >= 3600 then
    Result := Format('%d:%.2d:%.2d', [S div 3600, (S div 60) mod 60, S mod 60])
  else
    Result := Format('%d:%.2d', [S div 60, S mod 60]);
end;

function TPlayerTrack.Caption: string;
begin
  if (Language <> '') and (Title <> '') then
    Result := Language + ' - ' + Title
  else if Title <> '' then
    Result := Title
  else if Language <> '' then
    Result := Language
  else
    Result := 'Track ' + IntToStr(Id);
end;

{ ---- libmpv ---- }

{$IFNDEF ANDROID}
{$packrecords c}
type
  TMpvRenderParam = record
    Kind: LongInt;
    Data: Pointer;
  end;
  TMpvEvent = record
    EventId: LongInt;
    Error: LongInt;
    ReplyUserdata: QWord;
    Data: Pointer;
  end;
  PMpvEvent = ^TMpvEvent;
  TMpvEndFile = record
    Reason: LongInt;
    Error: LongInt;
  end;
  PMpvEndFile = ^TMpvEndFile;
{$packrecords default}

const
  MPV_FORMAT_FLAG = 3;
  MPV_FORMAT_INT64 = 4;
  MPV_FORMAT_DOUBLE = 5;
  MPV_EVENT_START_FILE = 6;
  MPV_EVENT_END_FILE = 7;
  MPV_EVENT_FILE_LOADED = 8;
  MPV_EVENT_VIDEO_RECONFIG = 17;
  MPV_EVENT_PLAYBACK_RESTART = 21;
  MPV_END_FILE_REASON_EOF = 0;
  MPV_END_FILE_REASON_ERROR = 4;
  MPV_RENDER_PARAM_API_TYPE = 1;
  MPV_RENDER_PARAM_SW_SIZE = 17;
  MPV_RENDER_PARAM_SW_FORMAT = 18;
  MPV_RENDER_PARAM_SW_STRIDE = 19;
  MPV_RENDER_PARAM_SW_POINTER = 20;

var
  MpvLib: TLibHandle = NilHandle;
  MpvTried: Boolean = False;
  MpvProblem: string = '';
  mpv_create: function: Pointer; cdecl;
  mpv_initialize: function(Ctx: Pointer): LongInt; cdecl;
  mpv_terminate_destroy: procedure(Ctx: Pointer); cdecl;
  mpv_set_option_string: function(Ctx: Pointer; Name, Value: PChar): LongInt; cdecl;
  mpv_set_property_string: function(Ctx: Pointer; Name, Value: PChar): LongInt; cdecl;
  mpv_get_property: function(Ctx: Pointer; Name: PChar; Format: LongInt; Data: Pointer): LongInt; cdecl;
  mpv_get_property_string: function(Ctx: Pointer; Name: PChar): PChar; cdecl;
  mpv_free: procedure(P: Pointer); cdecl;
  mpv_command: function(Ctx: Pointer; Args: PPChar): LongInt; cdecl;
  mpv_wait_event: function(Ctx: Pointer; Timeout: Double): PMpvEvent; cdecl;
  mpv_error_string: function(Error: LongInt): PChar; cdecl;
  mpv_render_context_create: function(out Res: Pointer; Mpv: Pointer; Params: Pointer): LongInt; cdecl;
  mpv_render_context_set_update_callback: procedure(Ctx: Pointer; Callback: Pointer; Data: Pointer); cdecl;
  mpv_render_context_update: function(Ctx: Pointer): QWord; cdecl;
  mpv_render_context_render: function(Ctx: Pointer; Params: Pointer): LongInt; cdecl;
  mpv_render_context_free: procedure(Ctx: Pointer); cdecl;

{$IFDEF UNIX}
function setlocale(Category: LongInt; Locale: PChar): PChar; cdecl; external 'c';
const
  {$IFDEF DARWIN}LC_NUMERIC = 4;{$ELSE}LC_NUMERIC = 1;{$ENDIF}
{$ENDIF}

function LoadMpv: Boolean;
const
  {$IFDEF WINDOWS}
  Names: array[0..2] of string = ('libmpv-2.dll', 'mpv-2.dll', 'mpv-1.dll');
  {$ELSE}
  {$IFDEF DARWIN}
  Names: array[0..2] of string = ('libmpv.2.dylib', 'libmpv.dylib', '/opt/homebrew/lib/libmpv.dylib');
  {$ELSE}
  Names: array[0..2] of string = ('libmpv.so.2', 'libmpv.so.1', 'libmpv.so');
  {$ENDIF}
  {$ENDIF}
var
  N: string;

  function Get(const Name: string): Pointer;
  begin
    Result := GetProcedureAddress(MpvLib, Name);
    if Result = nil then
      MpvProblem := 'libmpv has no ' + Name + ' (too old: 0.33 or newer is needed)';
  end;

begin
  if MpvTried then
    Exit(MpvLib <> NilHandle);
  MpvTried := True;
  for N in Names do
    if MpvLib = NilHandle then
      MpvLib := LoadLibrary(N);
  if MpvLib = NilHandle then
  begin
    {$IFDEF WINDOWS}
    MpvProblem := 'videos need libmpv-2.dll next to the program (https://sourceforge.net/projects/mpv-player-windows/files/libmpv/)';
    {$ELSE}
    MpvProblem := 'videos need libmpv: sudo apt install libmpv2 (Fedora: mpv-libs)';
    {$ENDIF}
    Exit(False);
  end;
  Pointer(mpv_create) := Get('mpv_create');
  Pointer(mpv_initialize) := Get('mpv_initialize');
  Pointer(mpv_terminate_destroy) := Get('mpv_terminate_destroy');
  Pointer(mpv_set_option_string) := Get('mpv_set_option_string');
  Pointer(mpv_set_property_string) := Get('mpv_set_property_string');
  Pointer(mpv_get_property) := Get('mpv_get_property');
  Pointer(mpv_get_property_string) := Get('mpv_get_property_string');
  Pointer(mpv_free) := Get('mpv_free');
  Pointer(mpv_command) := Get('mpv_command');
  Pointer(mpv_wait_event) := Get('mpv_wait_event');
  Pointer(mpv_error_string) := Get('mpv_error_string');
  Pointer(mpv_render_context_create) := Get('mpv_render_context_create');
  Pointer(mpv_render_context_set_update_callback) := Get('mpv_render_context_set_update_callback');
  Pointer(mpv_render_context_update) := Get('mpv_render_context_update');
  Pointer(mpv_render_context_render) := Get('mpv_render_context_render');
  Pointer(mpv_render_context_free) := Get('mpv_render_context_free');
  if MpvProblem <> '' then
  begin
    UnloadLibrary(MpvLib);
    MpvLib := NilHandle;
    Exit(False);
  end;
  Result := True;
end;

{ libmpv wants its frames drawn by a thread that never waits for the player
  (else stopping a file waits for ever): TMpvRenderer draws them into a
  picture; the window takes the newest one when it paints. }
type
  TMpvRenderer = class(TThread)
  private
    FCtx: Pointer;
    FWake: PRTLEvent;
    FLock: TRTLCriticalSection;
    FBack, FFront: TBitmap32;
    FWantW, FWantH: Integer;
    FResized: Boolean;
    FNewFrame: LongInt;
    FFailed: string;
  protected
    procedure Execute; override;
  public
    constructor Create(ACtx: Pointer);
    destructor Destroy; override;
    procedure Wake;
    procedure SetSize(W, H: Integer);
    { the newest picture into the canvas; False: none yet }
    function DrawTo(C: TCanvas32; const R: TRectI): Boolean;
    { a new picture came since the last call }
    function TakeNew: Boolean;
    procedure Finish;
  end;

{ mpv's threads: a new frame (or something else) for the renderer }
procedure MpvUpdated(Data: Pointer); cdecl;
begin
  TMpvRenderer(Data).Wake;
end;

constructor TMpvRenderer.Create(ACtx: Pointer);
begin
  FCtx := ACtx;
  FWake := RTLEventCreate;
  InitCriticalSection(FLock);
  FBack := TBitmap32.Create;
  FFront := TBitmap32.Create;
  inherited Create(False);
end;

destructor TMpvRenderer.Destroy;
begin
  FBack.Free;
  FFront.Free;
  DoneCriticalSection(FLock);
  RTLEventDestroy(FWake);
  inherited Destroy;
end;

procedure TMpvRenderer.Wake;
begin
  RTLEventSetEvent(FWake);
end;

procedure TMpvRenderer.SetSize(W, H: Integer);
begin
  EnterCriticalSection(FLock);
  try
    if (W <> FWantW) or (H <> FWantH) then
    begin
      FWantW := W;
      FWantH := H;
      FResized := True;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
  if FResized then
    Wake;
end;

procedure TMpvRenderer.Execute;
var
  P: array[0..4] of TMpvRenderParam;
  Size: array[0..1] of LongInt;
  Stride: PtrUInt;
  W, H, I: Integer;
  Draw: Boolean;
  T: TBitmap32;
begin
  { C code (libmpv's scaling) counts on float exceptions being off: Pascal's
    are on, and one inside libmpv would end this thread with libmpv's lock held }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    while not Terminated do
    begin
      RTLEventWaitFor(FWake, 100);
      if Terminated then
        Break;
      Draw := (mpv_render_context_update(FCtx) and 1) <> 0;
      EnterCriticalSection(FLock);
      try
        W := FWantW;
        H := FWantH;
        Draw := Draw or FResized;
        FResized := False;
      finally
        LeaveCriticalSection(FLock);
      end;
      if not Draw or (W <= 0) or (H <= 0) then
        Continue;
      if (FBack.Width <> W) or (FBack.Height <> H) then
        FBack.SetSize(W, H);
      Size[0] := W;
      Size[1] := H;
      Stride := W * 4;
      P[0].Kind := MPV_RENDER_PARAM_SW_SIZE;
      P[0].Data := @Size[0];
      P[1].Kind := MPV_RENDER_PARAM_SW_FORMAT;
      P[1].Data := PChar('bgr0');
      P[2].Kind := MPV_RENDER_PARAM_SW_STRIDE;
      P[2].Data := @Stride;
      P[3].Kind := MPV_RENDER_PARAM_SW_POINTER;
      P[3].Data := @FBack.Pixels[0];
      P[4].Kind := 0;
      P[4].Data := nil;
      if mpv_render_context_render(FCtx, @P[0]) < 0 then
        Continue;
      { the fourth byte is not set: opaque }
      for I := 0 to High(FBack.Pixels) do
        FBack.Pixels[I] := FBack.Pixels[I] or $FF000000;
      EnterCriticalSection(FLock);
      try
        T := FFront;
        FFront := FBack;
        FBack := T;
      finally
        LeaveCriticalSection(FLock);
      end;
      InterLockedExchange(FNewFrame, 1);
      if Assigned(WakeMainThread) then
        WakeMainThread(nil);
    end;
  except
    on E: Exception do
    begin
      { libmpv's lock may be held: the player stops drawing, the app goes on }
      FFailed := E.Message;
    end;
  end;
end;

function TMpvRenderer.DrawTo(C: TCanvas32; const R: TRectI): Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := not FFront.Empty;
    if Result then
      C.DrawBitmap(FFront, R.X, R.Y, R.W, R.H, False);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TMpvRenderer.TakeNew: Boolean;
begin
  Result := InterLockedExchange(FNewFrame, 0) <> 0;
end;

procedure TMpvRenderer.Finish;
begin
  Terminate;
  Wake;
  WaitFor;
end;

function MpvString(Ctx: Pointer; const Name: string): string;
var
  P: PChar;
begin
  Result := '';
  P := mpv_get_property_string(Ctx, PChar(Name));
  if P <> nil then
  begin
    Result := StrPas(P);
    mpv_free(P);
  end;
end;

function MpvDouble(Ctx: Pointer; const Name: string; out V: Double): Boolean;
begin
  V := 0;
  Result := mpv_get_property(Ctx, PChar(Name), MPV_FORMAT_DOUBLE, @V) >= 0;
end;

function MpvFlag(Ctx: Pointer; const Name: string): Boolean;
var
  F: LongInt;
begin
  F := 0;
  Result := (mpv_get_property(Ctx, PChar(Name), MPV_FORMAT_FLAG, @F) >= 0) and (F <> 0);
end;

procedure MpvCommand(Ctx: Pointer; const Args: array of string);
var
  P: array of PChar;
  I: Integer;
begin
  P := nil;
  SetLength(P, Length(Args) + 1);
  for I := 0 to High(Args) do
    P[I] := PChar(Args[I]);
  P[Length(Args)] := nil;
  mpv_command(Ctx, @P[0]);
end;
{$ENDIF}

function VideoPlayerAvailable: Boolean;
begin
  {$IFDEF ANDROID}
  Result := True;
  {$ELSE}
  Result := LoadMpv;
  {$ENDIF}
end;

function VideoPlayerProblem: string;
begin
  {$IFDEF ANDROID}
  Result := '';
  {$ELSE}
  LoadMpv;
  Result := MpvProblem;
  {$ENDIF}
end;

{ ---- TVideoPlayer ---- }

constructor TVideoPlayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := 'player';
  FVolume := 100;
  FTick := TTimer.Create(Self);
  FTick.Interval := 10;
  FTick.OnTimer := @Tick;
  {$IFDEF ANDROID}
  FEngine := '';
  FTick.Interval := 250;       { the info band's time: the phone's view keeps it }
  FTick.Enabled := False;
  {$ELSE}
  FTick.Enabled := False;
  {$ENDIF}
end;

destructor TVideoPlayer.Destroy;
begin
  { the form going: its handlers are not called any more }
  FOnStateChange := nil;
  FOnTracksChange := nil;
  FOnError := nil;
  {$IFNDEF ANDROID}
  MpvStop;
  {$ENDIF}
  inherited Destroy;
end;

function TVideoPlayer.Focusable: Boolean;
begin
  Result := Enabled;
end;

procedure TVideoPlayer.SetState(S: TPlayerState);
begin
  if S = FState then
    Exit;
  FState := S;
  if S <> psError then
    FError := '';
  Invalidate;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self);
end;

procedure TVideoPlayer.Failed(const Msg: string);
begin
  FError := Msg;
  FState := psIdle;      { SetState calls OnStateChange with the message there }
  SetState(psError);
  FError := Msg;
  if Assigned(FOnError) then
    FOnError(Self, Msg);
end;

function TVideoPlayer.Live: Boolean;
begin
  Result := (FState in [psPlaying, psPaused, psLoading]) and (FDuration <= 0);
end;

function TVideoPlayer.Playing: Boolean;
begin
  Result := FState = psPlaying;
end;

function TVideoPlayer.Tracks: TPlayerTracks;
begin
  Result := FTracks;
end;

{$IFNDEF ANDROID}
function TVideoPlayer.MpvStart: Boolean;
var
  P: array[0..1] of TMpvRenderParam;
  Rc: LongInt;
  Ctx: Pointer;
  OldMask: TFPUExceptionMask;
begin
  Result := FMpv <> nil;
  if Result then
    Exit;
  if not LoadMpv then
    Exit(False);
  { libmpv refuses a language that writes numbers otherwise (tr_TR: 1,5; the
    program's language comes from cwstring): numbers in C's way, as Pastel
    writes them for files anyway }
  {$IFDEF UNIX}
  setlocale(LC_NUMERIC, 'C');
  {$ENDIF}
  { libmpv's threads start from here and take the float settings they find:
    exceptions off, as C code expects (and back on for Pascal after) }
  OldMask := GetExceptionMask;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    FMpv := mpv_create();
  finally
    SetExceptionMask(OldMask);
  end;
  if FMpv = nil then
  begin
    MpvProblem := 'libmpv could not start (mpv_create)';
    Exit(False);
  end;
  mpv_set_option_string(FMpv, 'vo', 'libmpv');
  mpv_set_option_string(FMpv, 'hwdec', 'auto-copy-safe');
  mpv_set_option_string(FMpv, 'idle', 'yes');
  mpv_set_option_string(FMpv, 'keep-open', 'yes');
  mpv_set_option_string(FMpv, 'terminal', 'no');
  mpv_set_option_string(FMpv, 'input-default-bindings', 'no');
  mpv_set_option_string(FMpv, 'osc', 'no');
  mpv_set_option_string(FMpv, 'cache', 'yes');
  mpv_set_option_string(FMpv, 'network-timeout', '20');
  mpv_set_option_string(FMpv, 'sub-auto', 'no');
  mpv_set_option_string(FMpv, 'audio-client-name', PChar(ChangeFileExt(ExtractFileName(ParamStr(0)), '')));
  { tests and machines without sound: PASTEL_VIDEO_AO=null }
  if GetEnv('PASTEL_VIDEO_AO') <> '' then
    mpv_set_option_string(FMpv, 'ao', PChar(GetEnv('PASTEL_VIDEO_AO')));
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    Rc := mpv_initialize(FMpv);
  finally
    SetExceptionMask(OldMask);
  end;
  if Rc < 0 then
  begin
    mpv_terminate_destroy(FMpv);
    FMpv := nil;
    MpvProblem := 'libmpv could not start (mpv_initialize)';
    Exit(False);
  end;
  P[0].Kind := MPV_RENDER_PARAM_API_TYPE;
  P[0].Data := PChar('sw');
  P[1].Kind := 0;
  P[1].Data := nil;
  Rc := mpv_render_context_create(Ctx, FMpv, @P[0]);
  if Rc < 0 then
  begin
    MpvProblem := 'libmpv cannot draw here: ' + StrPas(mpv_error_string(Rc));
    mpv_terminate_destroy(FMpv);
    FMpv := nil;
    Exit(False);
  end;
  IsMultiThread := True;
  FRenderer := TMpvRenderer.Create(Ctx);
  mpv_render_context_set_update_callback(Ctx, @MpvUpdated, FRenderer);
  FEngine := 'mpv';
  Result := True;
end;

procedure TVideoPlayer.MpvStop;
var
  R: TMpvRenderer;
begin
  if FMpv <> nil then
    MpvCommand(FMpv, ['stop']);
  { the renderer ends, then its context goes (it ends the video chain), then mpv }
  if FRenderer <> nil then
  begin
    R := TMpvRenderer(FRenderer);
    FRenderer := nil;
    mpv_render_context_set_update_callback(R.FCtx, nil, nil);
    R.Finish;
    mpv_render_context_free(R.FCtx);
    R.Free;
  end;
  if FMpv <> nil then
  begin
    mpv_terminate_destroy(FMpv);
    FMpv := nil;
  end;
end;

procedure TVideoPlayer.MpvTracks;
var
  N, I: Integer;
  T: TPlayerTrack;
  Kind, Base: string;
begin
  FTracks := nil;
  N := StrToIntDef(MpvString(FMpv, 'track-list/count'), 0);
  for I := 0 to N - 1 do
  begin
    Base := 'track-list/' + IntToStr(I) + '/';
    Kind := MpvString(FMpv, Base + 'type');
    if (Kind <> 'audio') and (Kind <> 'sub') then
      Continue;
    T := Default(TPlayerTrack);
    T.Kind := Kind;
    T.Id := StrToIntDef(MpvString(FMpv, Base + 'id'), 0);
    T.Language := MpvString(FMpv, Base + 'lang');
    T.Title := MpvString(FMpv, Base + 'title');
    T.Selected := MpvString(FMpv, Base + 'selected') = 'yes';
    FTracks := Concat(FTracks, [T]);
  end;
  if Assigned(FOnTracksChange) then
    FOnTracksChange(Self);
end;

procedure TVideoPlayer.MpvEvents;
var
  E: PMpvEvent;
  EF: PMpvEndFile;
  W, H: Double;
begin
  repeat
    E := mpv_wait_event(FMpv, 0);
    if (E = nil) or (E^.EventId = 0) then
      Break;
    case E^.EventId of
      MPV_EVENT_START_FILE:
        SetState(psLoading);
      MPV_EVENT_FILE_LOADED:
        begin
          MpvPoll;
          MpvTracks;
          if MpvFlag(FMpv, 'pause') then SetState(psPaused) else SetState(psPlaying);
        end;
      MPV_EVENT_PLAYBACK_RESTART:
        if MpvFlag(FMpv, 'pause') then SetState(psPaused) else SetState(psPlaying);
      MPV_EVENT_VIDEO_RECONFIG:
        if MpvDouble(FMpv, 'width', W) and MpvDouble(FMpv, 'height', H) then
        begin
          FVideoW := Round(W);
          FVideoH := Round(H);
        end;
      MPV_EVENT_END_FILE:
        begin
          EF := PMpvEndFile(E^.Data);
          if EF <> nil then
            case EF^.Reason of
              MPV_END_FILE_REASON_EOF:
                SetState(psEnded);
              MPV_END_FILE_REASON_ERROR:
                Failed('the stream cannot be played: ' + StrPas(mpv_error_string(EF^.Error)));
            end;
        end;
    end;
  until False;
end;

procedure TVideoPlayer.MpvPoll;
var
  V: Double;
  I: Int64;
begin
  if MpvDouble(FMpv, 'time-pos', V) then
    FPosition := V;
  if MpvDouble(FMpv, 'duration', V) and MpvFlag(FMpv, 'seekable') and (V > 0) then
    FDuration := V
  else
    FDuration := 0;
  I := 0;
  if mpv_get_property(FMpv, 'width', MPV_FORMAT_INT64, @I) >= 0 then
    FVideoW := I;
  if mpv_get_property(FMpv, 'height', MPV_FORMAT_INT64, @I) >= 0 then
    FVideoH := I;
  { waiting for the network }
  if FState in [psPlaying, psLoading] then
    if MpvFlag(FMpv, 'paused-for-cache') or MpvFlag(FMpv, 'seeking') then
      SetState(psLoading)
    else if FState = psLoading then
      if MpvFlag(FMpv, 'core-idle') and not MpvFlag(FMpv, 'idle-active') and MpvFlag(FMpv, 'pause') then
        SetState(psPaused)
      else if not MpvFlag(FMpv, 'core-idle') then
        SetState(psPlaying);
  { keep-open: at the end mpv waits on the last picture (no end-file) }
  if MpvFlag(FMpv, 'eof-reached') then
  begin
    if FState in [psPlaying, psPaused, psLoading] then
      SetState(psEnded);
  end
  else if (FState = psEnded) and not MpvFlag(FMpv, 'idle-active') then
    if MpvFlag(FMpv, 'pause') then SetState(psPaused) else SetState(psPlaying);
end;
{$ELSE}
function TVideoPlayer.MpvStart: Boolean;
begin
  Result := False;
end;

procedure TVideoPlayer.MpvStop;
begin
end;

procedure TVideoPlayer.MpvTracks;
begin
end;

procedure TVideoPlayer.MpvEvents;
begin
end;

procedure TVideoPlayer.MpvPoll;
begin
end;
{$ENDIF}

procedure TVideoPlayer.Update;
{$IFDEF ANDROID}
var
  S: TStringArray;
{$ENDIF}
begin
  {$IFDEF ANDROID}
  if (FInfoUntil > 0) and (GetTickCount64 > FInfoUntil) then
    FInfoUntil := 0;
  { position (ms), duration (ms; 0 live), state, engine }
  S := inherited State;
  if Length(S) >= 4 then
  begin
    FPosition := StrToInt64Def(S[0], 0) / 1000;
    FDuration := StrToInt64Def(S[1], 0) / 1000;
    FEngine := S[3];
  end;
  {$ELSE}
  if FMpv = nil then
    Exit;
  MpvEvents;
  if GetTickCount64 - FLastPoll >= 200 then
  begin
    FLastPoll := GetTickCount64;
    MpvPoll;
    if InfoShown then
      Invalidate;
  end;
  if (FInfoUntil > 0) and (GetTickCount64 > FInfoUntil) then
  begin
    FInfoUntil := 0;
    Invalidate;
  end;
  if (FTracksDue > 0) and (GetTickCount64 >= FTracksDue) then
  begin
    FTracksDue := 0;
    MpvTracks;
  end;
  if (FRenderer <> nil) and TMpvRenderer(FRenderer).TakeNew then
    Invalidate;
  if (FRenderer <> nil) and (TMpvRenderer(FRenderer).FFailed <> '') and (FState <> psError) then
    Failed('the video cannot be drawn: ' + TMpvRenderer(FRenderer).FFailed);
  {$ENDIF}
end;

procedure TVideoPlayer.Tick(Sender: TObject);
begin
  Update;
  if FState = psLoading then
    AnimationRequested := True;
end;

procedure TVideoPlayer.Play(const AUrl: string);
begin
  FUrl := AUrl;
  FTracks := nil;
  FPosition := 0;
  FDuration := 0;
  FError := '';
  FVideoW := 0;
  FVideoH := 0;
  {$IFDEF ANDROID}
  Run('open', AUrl + #10 + FUserAgent);
  Run('volume', FloatToStr(FVolume / 100, InvariantFormat));
  Run('mute', IntToStr(Ord(FMuted)));
  FState := psIdle;
  SetState(psLoading);
  FTick.Enabled := True;
  {$ELSE}
  if not MpvStart then
  begin
    Failed(MpvProblem);
    Exit;
  end;
  if FUserAgent <> '' then
    mpv_set_property_string(FMpv, 'user-agent', PChar(FUserAgent));
  mpv_set_property_string(FMpv, 'volume', PChar(IntToStr(FVolume)));
  mpv_set_property_string(FMpv, 'mute', PChar(BoolToStr(FMuted, 'yes', 'no')));
  mpv_set_property_string(FMpv, 'pause', 'no');
  MpvCommand(FMpv, ['loadfile', AUrl, 'replace']);
  FState := psIdle;
  SetState(psLoading);
  FTick.Enabled := True;
  {$ENDIF}
end;

procedure TVideoPlayer.Play;
begin
  if FState = psEnded then
  begin
    Seek(0);
  end;
  {$IFDEF ANDROID}
  Run('play', '');
  {$ELSE}
  if FMpv <> nil then
    mpv_set_property_string(FMpv, 'pause', 'no');
  {$ENDIF}
  if FState in [psPaused, psEnded] then
    SetState(psPlaying);
end;

procedure TVideoPlayer.Pause;
begin
  {$IFDEF ANDROID}
  Run('pause', '');
  {$ELSE}
  if FMpv <> nil then
    mpv_set_property_string(FMpv, 'pause', 'yes');
  {$ENDIF}
  if FState in [psPlaying, psLoading] then
    SetState(psPaused);
end;

procedure TVideoPlayer.TogglePause;
begin
  if FState in [psPaused, psEnded] then
    Play
  else
    Pause;
end;

procedure TVideoPlayer.Stop;
begin
  {$IFDEF ANDROID}
  Run('stop', '');
  {$ELSE}
  if FMpv <> nil then
    MpvCommand(FMpv, ['stop']);
  FTick.Enabled := False;
  {$ENDIF}
  FUrl := '';
  FTracks := nil;
  FPosition := 0;
  FDuration := 0;
  SetState(psIdle);
end;

procedure TVideoPlayer.Seek(Seconds: Double; Relative: Boolean);
var
  T: Double;
begin
  if Relative then
    T := FPosition + Seconds
  else
    T := Seconds;
  if FDuration > 0 then
    T := EnsureRange(T, 0, FDuration - 1);
  T := Max(0, T);
  FPosition := T;
  {$IFDEF ANDROID}
  Run('seek', IntToStr(Round(T * 1000)));
  {$ELSE}
  if FMpv <> nil then
    MpvCommand(FMpv, ['seek', FloatToStr(T, InvariantFormat), 'absolute']);
  {$ENDIF}
  Invalidate;
end;

procedure TVideoPlayer.SelectTrack(const Kind: string; Id: Integer);
{$IFNDEF ANDROID}
var
  Prop: string;
{$ENDIF}
begin
  {$IFDEF ANDROID}
  Run('track', Kind + ' ' + IntToStr(Id));
  {$ELSE}
  if FMpv = nil then
    Exit;
  if Kind = 'audio' then Prop := 'aid' else Prop := 'sid';
  if Id < 0 then
    mpv_set_property_string(FMpv, PChar(Prop), 'no')
  else
    mpv_set_property_string(FMpv, PChar(Prop), PChar(IntToStr(Id)));
  { mpv switches a moment later: the list again then }
  FTracksDue := GetTickCount64 + 150;
  {$ENDIF}
end;

procedure TVideoPlayer.SetVolume(AValue: Integer);
begin
  FVolume := EnsureRange(AValue, 0, 100);
  {$IFDEF ANDROID}
  Run('volume', FloatToStr(FVolume / 100, InvariantFormat));
  {$ELSE}
  if FMpv <> nil then
    mpv_set_property_string(FMpv, 'volume', PChar(IntToStr(FVolume)));
  {$ENDIF}
end;

procedure TVideoPlayer.SetMuted(AValue: Boolean);
begin
  FMuted := AValue;
  {$IFDEF ANDROID}
  Run('mute', IntToStr(Ord(AValue)));
  {$ELSE}
  if FMpv <> nil then
    mpv_set_property_string(FMpv, 'mute', PChar(BoolToStr(AValue, 'yes', 'no')));
  {$ENDIF}
end;

procedure TVideoPlayer.ShowInfo(const Title, Line: string; Seconds: Integer);
begin
  FInfoTitle := Title;
  FInfoLine := Line;
  if Seconds > 0 then
    FInfoUntil := GetTickCount64 + QWord(Seconds) * 1000
  else
    FInfoUntil := High(QWord);
  {$IFDEF ANDROID}
  Run('info', Title + #10 + Line + #10 + IntToStr(Seconds));
  {$ELSE}
  FTick.Enabled := True;
  {$ENDIF}
  Invalidate;
end;

procedure TVideoPlayer.HideInfo;
begin
  FInfoUntil := 0;
  {$IFDEF ANDROID}
  Run('hideinfo', '');
  {$ENDIF}
  Invalidate;
end;

function TVideoPlayer.InfoShown: Boolean;
begin
  Result := (FInfoUntil > 0) and (GetTickCount64 <= FInfoUntil);
end;

{ Android: what the phone's player tells }
procedure TVideoPlayer.ViewEvent(const Parts: TStringArray);

  function P(I: Integer): string;
  begin
    if I < Length(Parts) then Result := Parts[I] else Result := '';
  end;

begin
  if Length(Parts) = 0 then
    Exit;
  case Parts[0] of
    'state':
      case P(1) of
        'idle': SetState(psIdle);
        'loading': SetState(psLoading);
        'playing': SetState(psPlaying);
        'paused': SetState(psPaused);
        'ended': SetState(psEnded);
        'error': if FState <> psError then Failed('the stream cannot be played');
      end;
    'error':
      Failed(P(1));
    'tracks':
      ParseTracks(P(1));
    'size':
      begin
        FVideoW := StrToIntDef(P(1), 0);
        FVideoH := StrToIntDef(P(2), 0);
      end;
    'tap':
      if (GetTickCount64 - FLastPoll < 350) and Assigned(FOnDoubleTap) then
      begin
        FLastPoll := 0;
        FOnDoubleTap(Self);
      end
      else
      begin
        FLastPoll := GetTickCount64;
        if Assigned(FOnTap) then
          FOnTap(Self);
      end;
  end;
end;

procedure TVideoPlayer.ParseTracks(const S: string);
var
  Entry: string;
  F: TStringArray;
  T: TPlayerTrack;
begin
  FTracks := nil;
  if S <> '' then
    for Entry in S.Split([#1]) do
    begin
      F := Entry.Split([#2]);
      if Length(F) < 5 then
        Continue;
      T := Default(TPlayerTrack);
      T.Kind := F[0];
      T.Id := StrToIntDef(F[1], 0);
      T.Selected := F[2] = '1';
      T.Language := F[3];
      T.Title := F[4];
      FTracks := Concat(FTracks, [T]);
    end;
  if Assigned(FOnTracksChange) then
    FOnTracksChange(Self);
end;

function TVideoPlayer.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  Handled: Boolean;
begin
  Handled := False;
  if Assigned(FOnKeyDown) then
    FOnKeyDown(Self, Key, Handled);
  if Handled then
    Exit(True);
  Result := True;
  case Key of
    KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
      TogglePause;
    KEY_LEFT:
      if FDuration > 0 then Seek(-10, True) else Result := False;
    KEY_RIGHT:
      if FDuration > 0 then Seek(10, True) else Result := False;
    Ord('m'):
      Muted := not Muted;
  else
    Result := False;
  end;
end;

procedure TVideoPlayer.MouseUp(X, Y: Integer; Inside: Boolean);
var
  F: TForm;
begin
  if not Inside then
    Exit;
  F := ParentForm;
  if (F <> nil) and (F.ClickCount = 2) and Assigned(FOnDoubleTap) then
    FOnDoubleTap(Self)
  else if Assigned(FOnTap) then
    FOnTap(Self);
end;

procedure TVideoPlayer.Paint(C: TCanvas32);
begin
  {$IFDEF ANDROID}
  inherited Paint(C);
  {$ELSE}
  PaintOnComputer(C);
  {$ENDIF}
end;

procedure TVideoPlayer.PaintInfo(C: TCanvas32);
var
  F, FB: TPastelFont;
  H, Y, X, W, BarW: Integer;
  T: string;
begin
  F := GetFont(Theme.FontSize, False);
  FB := GetFont(Theme.FontSize + 4, True);
  H := 24 + FB.LineHeight + 8;
  if FInfoLine <> '' then
    Inc(H, F.LineHeight + 4);
  Inc(H, 22);
  Y := Bounds.Y + Bounds.H - H;
  C.FillRect(Bounds.X, Y, Bounds.W, H, RGBA($10, $10, $14, $C8));
  X := Bounds.X + 20;
  W := Bounds.W - 40;
  Inc(Y, 14);
  C.DrawText(FB, X, Y, FInfoTitle, RGB($FF, $FF, $FF));
  Inc(Y, FB.LineHeight + 4);
  if FInfoLine <> '' then
  begin
    C.DrawText(F, X, Y, FInfoLine, RGB($CF, $D3, $DC));
    Inc(Y, F.LineHeight + 6);
  end;
  if FDuration > 0 then
  begin
    T := PlayerClock(FPosition) + ' / ' + PlayerClock(FDuration);
    BarW := W - F.TextWidth(T) - 16;
    C.FillRoundRect(X, Y + 7, BarW, 6, 3, RGBA($FF, $FF, $FF, $40));
    C.FillRoundRect(X, Y + 7, Max(6, Round(BarW * EnsureRange(FPosition / FDuration, 0, 1))), 6, 3, Theme.Accent);
    C.DrawText(F, X + BarW + 16, Y, T, RGB($CF, $D3, $DC));
  end
  else if FState in [psPlaying, psPaused] then
    C.DrawText(F, X, Y, 'LIVE', RGB($FF, $6B, $6B));
end;

procedure TVideoPlayer.PaintOnComputer(C: TCanvas32);
{$IFNDEF ANDROID}
var
  PR: TRectI;
  F: TPastelFont;
  A: Single;
  CX, CY: Integer;
  Msg: string;
{$ENDIF}
begin
  {$IFNDEF ANDROID}
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, RGB(0, 0, 0));
  if (FRenderer <> nil) and (FState in [psPlaying, psPaused, psLoading, psEnded]) and (FVideoW > 0) then
  begin
    { the renderer draws at the control's size in pixels; the newest picture here }
    PR := C.PixelRect(Bounds);
    TMpvRenderer(FRenderer).SetSize(PR.W, PR.H);
    TMpvRenderer(FRenderer).DrawTo(C, Bounds);
  end;
  CX := Bounds.X + Bounds.W div 2;
  CY := Bounds.Y + Bounds.H div 2;
  if FState = psLoading then
  begin
    { a turning arc }
    A := (GetTickCount64 mod 1000) / 1000 * 2 * Pi;
    C.FillPie(CX, CY, 22, 17, A, 1.5 * Pi, RGBA($FF, $FF, $FF, $D0));
  end
  else if FState = psError then
  begin
    F := GetFont(Theme.FontSize, False);
    Msg := FError;
    C.DrawText(F, CX - F.TextWidth(Msg) div 2, CY - F.LineHeight div 2, Msg, RGB($FF, $8A, $8A));
  end
  else if (FState = psPaused) and not InfoShown then
  begin
    C.FillCircle(CX, CY, 30, RGBA(0, 0, 0, $90));
    C.FillRect(CX - 10, CY - 12, 7, 24, RGB($FF, $FF, $FF));
    C.FillRect(CX + 3, CY - 12, 7, 24, RGB($FF, $FF, $FF));
  end;
  if InfoShown then
    PaintInfo(C);
  {$ENDIF}
end;

initialization
  RegisterControl(TVideoPlayer);

end.
