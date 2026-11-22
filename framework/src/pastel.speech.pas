{ Pastel - the app speaks, and listens.

    Speak('Your order is ready');                 // the system's voice
    Speak('Siparişiniz hazır', 'tr');
    StopSpeaking;
    Listen(@Heard, 'tr');                         // phones: speech to text

    procedure THomeForm.Heard(Sender: TObject; Ok: Boolean; const Text: string);
    begin
      if Ok then SearchEdit.Text := Text;
    end;

  Android: its TextToSpeech and the speech recognizer (its own small window,
  [package.android] permissions = ["microphone"] not needed for it).
  Computers: spd-say or espeak (Linux), the Windows voice (SAPI), say (macOS);
  Listen is not there (OnDone with False).
  Part of the Pastel project, MIT License. }
unit Pastel.Speech;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TListenDoneEvent = procedure(Sender: TObject; Ok: Boolean; const Text: string) of object;

{ Says Text (after what is being said); Language: 'tr', 'en-US'... ('' the system's). }
procedure Speak(const Text: string; const Language: string = '');
procedure StopSpeaking;
function IsSpeaking: Boolean;
{ Listens to the user once and gives what was said. }
procedure Listen(OnDone: TListenDoneEvent; const Language: string = '');

implementation

uses
  Process, Pastel.UI{$IFDEF ANDROID}, Pastel.Android{$ENDIF}{$IFNDEF ANDROID}, Pastel.Process{$ENDIF};

{$IFNDEF ANDROID}
var
  Speaker: TProcess = nil;
{$ENDIF}

procedure Speak(const Text: string; const Language: string);
{$IFNDEF ANDROID}
var
  Exe: string;
{$ENDIF}
begin
  if Text = '' then
    Exit;
  {$IFDEF ANDROID}
  AndroidCall('speak', '(Ljava/lang/String;Ljava/lang/String;)V', [Text, Language]);
  {$ELSE}
  StopSpeaking;
  Speaker := TProcess.Create(nil);
  Speaker.Options := [poNoConsole];
  {$IFDEF WINDOWS}
  Speaker.Executable := 'powershell.exe';
  Speaker.Parameters.AddStrings(['-NoProfile', '-NonInteractive', '-Command',
    'Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; ' +
    '$s.Speak([Console]::In.ReadToEnd())']);
  Speaker.Options := Speaker.Options + [poUsePipes];
  {$ELSE}
  {$IFDEF DARWIN}
  Speaker.Executable := '/usr/bin/say';
  Speaker.Parameters.Add(Text);
  {$ELSE}
  Exe := Which('spd-say');
  if Exe <> '' then
  begin
    Speaker.Executable := Exe;
    Speaker.Parameters.Add('--wait');
    if Language <> '' then
      Speaker.Parameters.AddStrings(['-l', Copy(Language, 1, 2)]);
    Speaker.Parameters.Add(Text);
  end
  else
  begin
    Exe := Which('espeak-ng');
    if Exe = '' then
      Exe := Which('espeak');
    if Exe = '' then
    begin
      FreeAndNil(Speaker);
      raise Exception.Create('no voice here: install speech-dispatcher (spd-say) or espeak-ng');
    end;
    Speaker.Executable := Exe;
    if Language <> '' then
      Speaker.Parameters.AddStrings(['-v', Copy(Language, 1, 2)]);
    Speaker.Parameters.Add(Text);
  end;
  {$ENDIF}
  {$ENDIF}
  Speaker.Execute;
  {$IFDEF WINDOWS}
  Speaker.Input.Write(Text[1], Length(Text));
  Speaker.CloseInput;
  {$ENDIF}
  {$ENDIF}
end;

procedure StopSpeaking;
begin
  {$IFDEF ANDROID}
  AndroidCall('stopSpeaking', '()V', []);
  {$ELSE}
  if Speaker <> nil then
  begin
    if Speaker.Running then
      Speaker.Terminate(0);
    FreeAndNil(Speaker);
  end;
  {$ENDIF}
end;

function IsSpeaking: Boolean;
begin
  {$IFDEF ANDROID}
  Result := AndroidCallString('speaking', '()Ljava/lang/String;', []) <> '';
  {$ELSE}
  Result := (Speaker <> nil) and Speaker.Running;
  {$ENDIF}
end;

type
  TListening = class(TComponent)
  public
    Code: Integer;
    Done: TListenDoneEvent;
    Timer: TTimer;
    procedure Tick(Sender: TObject);
  end;

procedure TListening.Tick(Sender: TObject);
var
  Ok: Boolean;
  Text: string;
begin
  Ok := False;
  Text := 'speech to text is there on phones';
  {$IFDEF ANDROID}
  if not AndroidTakeResult(Code, Ok, Text) then
    Exit;
  {$ENDIF}
  Timer.Enabled := False;
  if Assigned(Done) then
    if Ok then
      Done(nil, True, Text)
    else
      Done(nil, False, '');
  ReleaseLater(Self);
end;

procedure Listen(OnDone: TListenDoneEvent; const Language: string);
var
  L: TListening;
begin
  L := TListening.Create(nil);
  L.Done := OnDone;
  L.Timer := TTimer.Create(L);
  L.Timer.Interval := 100;
  L.Timer.OnTimer := @L.Tick;
  {$IFDEF ANDROID}
  L.Code := AndroidNewRequest;
  AndroidCall('listen', '(ILjava/lang/String;)V', [L.Code, Language]);
  {$ELSE}
  if Language = '' then ;
  {$ENDIF}
  L.Timer.Enabled := True;
end;

finalization
  {$IFNDEF ANDROID}
  StopSpeaking;
  {$ENDIF}
end.
