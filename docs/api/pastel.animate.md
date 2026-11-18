# Pastel.Animate

Animations: a property goes to a new value smoothly.

    Animate(Panel, 'Height', 240);                         // 250 ms, slowing down at the end
    Animate(Card, 'Left', 0, 400, eaOutBack);              // a little past, then back
    AnimateColor(SaveButton, 'Color', $FF43A047, 300);
    Animate(Bar, 'Position', 100, 1500, eaLinear, @Loaded);
    StopAnimations(Panel);

  Any published number property (Integer, Single, Double: Width, Height, Left,
  Top, Position, Value...) or color (TColor32). An animation of the same
  property replaces the one before (from where it is). A control that is freed
  takes its animations with it.

`uses Pastel.Animate;` · source: [framework/src/pastel.animate.pas](../../framework/src/pastel.animate.pas)

**Contents:** [TEasing](#teasing) · [TAnimation](#tanimation) · [Animate](#animate) · [AnimateColor](#animatecolor) · [StopAnimations](#stopanimations) · [IsAnimating](#isanimating) · [Ease](#ease) · [StepAnimations](#stepanimations)

## Types

### TEasing

```pascal
type TEasing = (eaLinear, eaInQuad, eaOutQuad, eaInOutQuad, eaOutCubic, eaInOutCubic, eaOutBack, eaOutBounce, eaOutElastic)
```

- `eaLinear`
- `eaInQuad`
- `eaOutQuad`
- `eaInOutQuad`
- `eaOutCubic`
- `eaInOutCubic`
- `eaOutBack`
- `eaOutBounce`
- `eaOutElastic`
### TAnimation

```pascal
type TAnimation = class
```

| | |
|---|---|
| `property Target: TObject` |  |
| `property PropName: string` |  |
| `property Repeating: Boolean` | again and again (StopAnimations ends it); with Reverse, there and back |
| `property Reverse: Boolean` |  |

## Routines

### Animate

```pascal
function Animate(Target: TObject; const PropName: string; ToValue: Double; DurationMs: Integer = 250; Easing: TEasing = eaOutCubic; OnDone: TNotifyEvent = nil; DelayMs: Integer = 0): TAnimation
```

Starts it; the property is set at once on every frame until DurationMs passed.

### AnimateColor

```pascal
function AnimateColor(Target: TObject; const PropName: string; ToColor: TColor32; DurationMs: Integer = 250; Easing: TEasing = eaOutCubic; OnDone: TNotifyEvent = nil): TAnimation
```

### StopAnimations

```pascal
procedure StopAnimations(Target: TObject; const PropName: string = '')
```

Ends them where they are (all of the target's when PropName is '').

### IsAnimating

```pascal
function IsAnimating(Target: TObject; const PropName: string = ''): Boolean
```

### Ease

```pascal
function Ease(E: TEasing; T: Double): Double
```

0..1 -> 0..1 (eaOutBack and eaOutElastic go a little past 1).

### StepAnimations

```pascal
procedure StepAnimations(NowMs: QWord)
```

Runs the animations up to NowMs (the timer does it; tests call it).

## Constants and variables

| | |
|---|---|
| `var AnimationsInstant: Boolean` |  |
