# Pastel.Speech

The app speaks, and listens.

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

`uses Pastel.Speech;` · source: [framework/src/pastel.speech.pas](../../framework/src/pastel.speech.pas)

## Other types

| | |
|---|---|
| `type TListenDoneEvent = procedure(Sender: TObject; Ok: Boolean; Text: string)` |  |

## Routines

### Speak

```pascal
procedure Speak(const Text: string; const Language: string = '')
```

Says Text (after what is being said); Language: 'tr', 'en-US'... ('' the system's).

### StopSpeaking

```pascal
procedure StopSpeaking
```

### IsSpeaking

```pascal
function IsSpeaking: Boolean
```

### Listen

```pascal
procedure Listen(OnDone: TListenDoneEvent; const Language: string = '')
```

Listens to the user once and gives what was said.

