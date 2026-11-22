{ Tests of TVideoPlayer (Pastel.VideoPlayer) with libmpv: a video made by ffmpeg. }
unit videoplayer_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.VideoPlayer, Pastel.Process, Pastel.Files, Pastel.Env;

type
  TVideoPlayerTests = class(TTestSuite)
  private
    FStates: string;
    procedure StateChanged(Sender: TObject);
  public
    procedure SetUp; override;
  published
    procedure Clock;
    procedure PlaysSeeksPausesAndHasTracks;
    procedure ABadAddressIsAnError;
    procedure StartsInEveryLanguage;
  end;

implementation

function setlocale(Category: LongInt; Locale: PChar): PChar; cdecl; external 'c';

const
  Names: array[TPlayerState] of string = ('idle', 'loading', 'playing', 'paused', 'ended', 'error');

procedure TVideoPlayerTests.StateChanged(Sender: TObject);
begin
  FStates := FStates + Names[TVideoPlayer(Sender).State] + ' ';
end;

procedure TVideoPlayerTests.SetUp;
begin
  { no sound card here: no sound }
  SetEnv('PASTEL_VIDEO_AO', 'null');
end;

procedure TVideoPlayerTests.Clock;
begin
  AssertEquals('0:07', PlayerClock(7.9));
  AssertEquals('12:05', PlayerClock(725));
  AssertEquals('1:02:03', PlayerClock(3723));
end;

var
  Canvas: TCanvas32 = nil;

{ waits until Done (the player told it) or Ms; paints as the app does (mpv
  goes on when its frames are drawn) }
function WaitFor(P: TVideoPlayer; Ms: Integer; Done: TPlayerState): Boolean;
var
  T0: QWord;
begin
  T0 := GetTickCount64;
  repeat
    P.Update;
    CheckSynchronize(5);
    if (Canvas <> nil) and (P.ParentForm <> nil) then
      P.ParentForm.Render(Canvas);
    if P.State = Done then
      Exit(True);
  until GetTickCount64 - T0 > QWord(Ms);
  Result := False;
end;

function MakeVideo(out FileName: string): Boolean;
var
  Dir: string;
  R: TRunResult;
begin
  Dir := MakeTempDir('pastel-video');
  FileName := Dir + 'clip.mkv';
  WriteText(Dir + 'sub.srt', '1'#10'00:00:00,000 --> 00:00:06,000'#10'Merhaba'#10);
  R := Run('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:duration=8',
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=8', '-f', 'lavfi', '-i', 'sine=frequency=880:duration=8',
    '-i', Dir + 'sub.srt', '-map', '0:v', '-map', '1:a', '-map', '2:a', '-map', '3:s',
    '-c:v', 'libx264', '-preset', 'ultrafast', '-c:a', 'aac', '-c:s', 'srt',
    '-metadata:s:a:0', 'language=tur', '-metadata:s:a:1', 'language=eng', '-metadata:s:a:1', 'title=English',
    '-metadata:s:s:0', 'language=tur', FileName]);
  Result := R.Ok and FileExists(FileName);
end;

procedure TVideoPlayerTests.PlaysSeeksPausesAndHasTracks;
var
  F: TForm;
  P: TVideoPlayer;
  C: TCanvas32;
  Video: string;
  T: TPlayerTrack;
  Audio, Subs, X, Y, Bright: Integer;
  Px: TColor32;
  T0: QWord;
begin
  if not VideoPlayerAvailable then
    Skip(VideoPlayerProblem);
  if Which('ffmpeg') = '' then
    Skip('no ffmpeg to make a video');
  AssertTrue(MakeVideo(Video), 'ffmpeg made the video');
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    P := TVideoPlayer.Create(F);
    P.Parent := F;
    P.Grow := 1;
    P.OnStateChange := @StateChanged;
    F.Layout(400, 300);
    C.SetSize(400, 300);
    Canvas := C;
    P.Play(Video);
    AssertTrue(WaitFor(P, 8000, psPlaying), 'playing: ' + FStates + P.Error);
    AssertEquals('mpv', P.Engine);
    AssertTrue(Pos('loading playing', FStates) = 1, FStates);
    { the picture: testsrc's colors, not black }
    WaitFor(P, 600, psError);
    F.Render(C);
    Bright := 0;
    for Y := 0 to 29 do
      for X := 0 to 39 do
      begin
        Px := C.GetPixel(P.Bounds.X + X * P.Bounds.W div 40, P.Bounds.Y + Y * P.Bounds.H div 30);
        if ((Px shr 16) and $FF) + ((Px shr 8) and $FF) + (Px and $FF) > 150 then
          Inc(Bright);
      end;
    AssertTrue(Bright > 300, Format('the video is drawn (%d bright points)', [Bright]));
    AssertEquals(320, P.VideoWidth);
    AssertTrue(Abs(P.Duration - 8) < 0.5, Format('duration %.2f', [P.Duration]));
    { on a busy machine the first frames come slower }
    T0 := GetTickCount64;
    while (P.Position <= 0.2) and (GetTickCount64 - T0 < 4000) do
      WaitFor(P, 50, psError);
    AssertTrue(P.Position > 0.2, Format('it moves: %.2f', [P.Position]));
    AssertFalse(P.Live);
    { tracks: two sounds, one subtitle }
    Audio := 0;
    Subs := 0;
    for T in P.Tracks do
      if T.Kind = 'audio' then Inc(Audio) else Inc(Subs);
    AssertEquals(2, Audio, 'audio tracks');
    AssertEquals(1, Subs, 'subtitles');
    AssertEquals('eng - English', P.Tracks[1].Caption);
    P.SelectTrack('audio', P.Tracks[1].Id);
    T0 := GetTickCount64;
    while not P.Tracks[1].Selected and (GetTickCount64 - T0 < 3000) do
      WaitFor(P, 50, psError);
    AssertTrue(P.Tracks[1].Selected, 'the second sound');
    P.SelectTrack('sub', -1);
    { seek and pause }
    P.Seek(5);
    WaitFor(P, 3000, psPlaying);
    WaitFor(P, 400, psError);
    AssertTrue(P.Position >= 4.9, Format('after the seek: %.2f', [P.Position]));
    P.Pause;
    AssertTrue(P.State = psPaused);
    P.Seek(7.5);
    P.Play;
    AssertTrue(WaitFor(P, 5000, psEnded), 'ended: ' + FStates);
    P.ShowInfo('Kanal 1', 'Şimdi: Haberler');
    AssertTrue(P.InfoShown);
    F.Render(C);
  { freed while at its end }

  finally
    Canvas := nil;
    C.Free;
    F.Free;
  end;
end;

{ a computer in Turkish (LC_NUMERIC tr_TR): libmpv still starts }
procedure TVideoPlayerTests.StartsInEveryLanguage;
var
  F: TForm;
  P: TVideoPlayer;
begin
  if not VideoPlayerAvailable then
    Skip(VideoPlayerProblem);
  if setlocale(1, 'tr_TR.UTF-8') = nil then
    if setlocale(1, 'de_DE.UTF-8') = nil then
      Skip('no comma language installed here (locale-gen tr_TR.UTF-8)');
  F := TForm.Create(nil);
  try
    P := TVideoPlayer.Create(F);
    P.Parent := F;
    P.Play('/no/such/video.mp4');
    WaitFor(P, 5000, psError);
    AssertEquals('mpv', P.Engine, 'libmpv started: ' + P.Error);
  finally
    F.Free;
    setlocale(1, 'C');
  end;
end;

procedure TVideoPlayerTests.ABadAddressIsAnError;
var
  F: TForm;
  P: TVideoPlayer;
begin
  if not VideoPlayerAvailable then
    Skip(VideoPlayerProblem);
  F := TForm.Create(nil);
  try
    P := TVideoPlayer.Create(F);
    P.Parent := F;
    P.Play('/no/such/video.mp4');
    AssertTrue(WaitFor(P, 5000, psError), 'an error');
    AssertTrue(P.Error <> '', 'with a message');
    P.Stop;
    AssertTrue(P.State = psIdle, 'stopped');
  finally
    F.Free;
  end;
end;

initialization
  RegisterTests(TVideoPlayerTests);

end.
