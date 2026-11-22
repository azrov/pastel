{ Pastel - animations: a property goes to a new value smoothly.

    Animate(Panel, 'Height', 240);                         // 250 ms, slowing down at the end
    Animate(Card, 'Left', 0, 400, eaOutBack);              // a little past, then back
    AnimateColor(SaveButton, 'Color', $FF43A047, 300);
    Animate(Bar, 'Position', 100, 1500, eaLinear, @Loaded);
    StopAnimations(Panel);

  Any published number property (Integer, Single, Double: Width, Height, Left,
  Top, Position, Value...) or color (TColor32). An animation of the same
  property replaces the one before (from where it is). A control that is freed
  takes its animations with it.
  Part of the Pastel project, MIT License. }
unit Pastel.Animate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  TEasing = (eaLinear, eaInQuad, eaOutQuad, eaInOutQuad, eaOutCubic, eaInOutCubic, eaOutBack, eaOutBounce,
    eaOutElastic);

  TAnimation = class
  private
    FTarget: TObject;
    FProp: string;
    FFrom, FTo: Double;
    FFromColor, FToColor: TColor32;
    FIsColor: Boolean;
    FStart: QWord;
    FDuration: Integer;
    FEasing: TEasing;
    FOnDone: TNotifyEvent;
    FRepeat, FReverse: Boolean;
    procedure Apply(T: Double);
  public
    property Target: TObject read FTarget;
    property PropName: string read FProp;
    { again and again (StopAnimations ends it); with Reverse, there and back }
    property Repeating: Boolean read FRepeat write FRepeat;
    property Reverse: Boolean read FReverse write FReverse;
  end;

{ Starts it; the property is set at once on every frame until DurationMs passed. }
function Animate(Target: TObject; const PropName: string; ToValue: Double; DurationMs: Integer = 250;
  Easing: TEasing = eaOutCubic; OnDone: TNotifyEvent = nil; DelayMs: Integer = 0): TAnimation;
function AnimateColor(Target: TObject; const PropName: string; ToColor: TColor32; DurationMs: Integer = 250;
  Easing: TEasing = eaOutCubic; OnDone: TNotifyEvent = nil): TAnimation;
{ Ends them where they are (all of the target's when PropName is ''). }
procedure StopAnimations(Target: TObject; const PropName: string = '');
function IsAnimating(Target: TObject; const PropName: string = ''): Boolean;
{ 0..1 -> 0..1 (eaOutBack and eaOutElastic go a little past 1). }
function Ease(E: TEasing; T: Double): Double;
{ Runs the animations up to NowMs (the timer does it; tests call it). }
procedure StepAnimations(NowMs: QWord);
{ Animations in a test: every animation jumps to its end (no waiting). }
var
  AnimationsInstant: Boolean = False;

implementation

uses
  Math, TypInfo;

type
  { frees a target's animations when it goes }
  TWatcher = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TTicker = class
    procedure Tick(Sender: TObject);
  end;

var
  List: TFPList;
  Timer: TTimer;
  Ticker: TTicker;
  Watcher: TWatcher;
  Stepping: Boolean;

function Ease(E: TEasing; T: Double): Double;
const
  C1 = 1.70158;
  C3 = C1 + 1;
begin
  T := EnsureRange(T, 0, 1);
  case E of
    eaLinear: Result := T;
    eaInQuad: Result := T * T;
    eaOutQuad: Result := 1 - (1 - T) * (1 - T);
    eaInOutQuad: if T < 0.5 then Result := 2 * T * T else Result := 1 - Power(-2 * T + 2, 2) / 2;
    eaOutCubic: Result := 1 - Power(1 - T, 3);
    eaInOutCubic: if T < 0.5 then Result := 4 * T * T * T else Result := 1 - Power(-2 * T + 2, 3) / 2;
    eaOutBack: Result := 1 + C3 * Power(T - 1, 3) + C1 * Power(T - 1, 2);
    eaOutBounce:
      begin
        if T < 1 / 2.75 then
          Result := 7.5625 * T * T
        else if T < 2 / 2.75 then
        begin
          T := T - 1.5 / 2.75;
          Result := 7.5625 * T * T + 0.75;
        end
        else if T < 2.5 / 2.75 then
        begin
          T := T - 2.25 / 2.75;
          Result := 7.5625 * T * T + 0.9375;
        end
        else
        begin
          T := T - 2.625 / 2.75;
          Result := 7.5625 * T * T + 0.984375;
        end;
      end;
    eaOutElastic:
      if (T = 0) or (T = 1) then
        Result := T
      else
        Result := Power(2, -10 * T) * Sin((T * 10 - 0.75) * (2 * Pi / 3)) + 1;
  else
    Result := T;
  end;
end;

function Mix(A, B: TColor32; T: Double): TColor32;
var
  I: Integer;
  CA, CB, R: Integer;
begin
  Result := 0;
  for I := 0 to 3 do
  begin
    CA := (A shr (I * 8)) and $FF;
    CB := (B shr (I * 8)) and $FF;
    R := EnsureRange(Round(CA + (CB - CA) * T), 0, 255);
    Result := Result or (TColor32(R) shl (I * 8));
  end;
end;

procedure TAnimation.Apply(T: Double);
var
  Info: PPropInfo;
  V: Double;
begin
  Info := GetPropInfo(FTarget, FProp);
  if Info = nil then
    Exit;
  V := Ease(FEasing, T);
  if FIsColor then
    SetOrdProp(FTarget, Info, Mix(FFromColor, FToColor, V))
  else if Info^.PropType^.Kind = tkFloat then
    SetFloatProp(FTarget, Info, FFrom + (FTo - FFrom) * V)
  else
    SetOrdProp(FTarget, Info, Round(FFrom + (FTo - FFrom) * V));
  AnimationRequested := True;
  NeedsRepaint := True;
end;

procedure TWatcher.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
    for I := List.Count - 1 downto 0 do
      if TAnimation(List[I]).FTarget = AComponent then
      begin
        TAnimation(List[I]).Free;
        List.Delete(I);
      end;
end;

procedure StepAnimations(NowMs: QWord);
var
  I: Integer;
  A: TAnimation;
  T, X: Double;
  Done: TFPList;
  D: Double;
  C: TColor32;
begin
  if Stepping then
    Exit;
  Stepping := True;
  Done := TFPList.Create;
  try
    for I := List.Count - 1 downto 0 do
    begin
      A := TAnimation(List[I]);
      if NowMs < A.FStart then
        Continue;
      if AnimationsInstant or (A.FDuration <= 0) then
        T := 1
      else
        T := (NowMs - A.FStart) / A.FDuration;
      if T >= 1 then
      begin
        A.Apply(1);
        if A.FRepeat then
        begin
          A.FStart := NowMs;
          if A.FReverse then
          begin
            D := A.FFrom; A.FFrom := A.FTo; A.FTo := D;
            C := A.FFromColor; A.FFromColor := A.FToColor; A.FToColor := C;
          end
          else
            A.Apply(0);
          if AnimationsInstant then
            A.FRepeat := False;
        end
        else
        begin
          List.Delete(I);
          Done.Add(A);
        end;
      end
      else
      begin
        X := T;
        A.Apply(X);
      end;
    end;
    for I := Done.Count - 1 downto 0 do
    begin
      A := TAnimation(Done[I]);
      try
        if Assigned(A.FOnDone) then
          A.FOnDone(A.FTarget);
      finally
        A.Free;
      end;
    end;
  finally
    Done.Free;
    Stepping := False;
  end;
  Timer.Enabled := List.Count > 0;
end;

procedure TTicker.Tick(Sender: TObject);
begin
  StepAnimations(GetTickCount64);
end;

procedure Remove(Target: TObject; const PropName: string);
var
  I: Integer;
begin
  for I := List.Count - 1 downto 0 do
    if (TAnimation(List[I]).FTarget = Target) and ((PropName = '') or SameText(TAnimation(List[I]).FProp, PropName)) then
    begin
      TAnimation(List[I]).Free;
      List.Delete(I);
    end;
end;

function Start(Target: TObject; const PropName: string; DurationMs: Integer; Easing: TEasing; OnDone: TNotifyEvent;
  DelayMs: Integer): TAnimation;
var
  Info: PPropInfo;
begin
  if Target = nil then
    raise Exception.Create('Animate: no target');
  Info := GetPropInfo(Target, PropName);
  if Info = nil then
    raise Exception.CreateFmt('Animate: %s has no published property "%s"', [Target.ClassName, PropName]);
  if not (Info^.PropType^.Kind in [tkInteger, tkInt64, tkFloat]) then
    raise Exception.CreateFmt('Animate: %s.%s is not a number or a color', [Target.ClassName, PropName]);
  Remove(Target, PropName);
  Result := TAnimation.Create;
  Result.FTarget := Target;
  Result.FProp := PropName;
  Result.FDuration := DurationMs;
  Result.FEasing := Easing;
  Result.FOnDone := OnDone;
  Result.FStart := GetTickCount64 + QWord(Max(0, DelayMs));
  List.Add(Result);
  if Target is TComponent then
    TComponent(Target).FreeNotification(Watcher);
  Timer.Enabled := True;
end;

function Animate(Target: TObject; const PropName: string; ToValue: Double; DurationMs: Integer; Easing: TEasing;
  OnDone: TNotifyEvent; DelayMs: Integer): TAnimation;
var
  Info: PPropInfo;
begin
  Result := Start(Target, PropName, DurationMs, Easing, OnDone, DelayMs);
  Info := GetPropInfo(Target, PropName);
  if Info^.PropType^.Kind = tkFloat then
    Result.FFrom := GetFloatProp(Target, Info)
  else
    Result.FFrom := GetOrdProp(Target, Info);
  Result.FTo := ToValue;
  if AnimationsInstant then
    StepAnimations(GetTickCount64 + QWord(Max(0, DelayMs)));
end;

function AnimateColor(Target: TObject; const PropName: string; ToColor: TColor32; DurationMs: Integer;
  Easing: TEasing; OnDone: TNotifyEvent): TAnimation;
begin
  Result := Start(Target, PropName, DurationMs, Easing, OnDone, 0);
  Result.FIsColor := True;
  Result.FFromColor := TColor32(GetOrdProp(Target, PropName));
  Result.FToColor := ToColor;
  if AnimationsInstant then
    StepAnimations(GetTickCount64);
end;

procedure StopAnimations(Target: TObject; const PropName: string);
begin
  Remove(Target, PropName);
end;

function IsAnimating(Target: TObject; const PropName: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    if (TAnimation(List[I]).FTarget = Target) and ((PropName = '') or SameText(TAnimation(List[I]).FProp, PropName)) then
      Exit(True);
  Result := False;
end;

initialization
  List := TFPList.Create;
  Ticker := TTicker.Create;
  Watcher := TWatcher.Create(nil);
  Timer := TTimer.Create(nil);
  Timer.Interval := 15;
  Timer.OnTimer := @Ticker.Tick;
  Timer.Enabled := False;

finalization
  Timer.Free;
  while List.Count > 0 do
  begin
    TAnimation(List[0]).Free;
    List.Delete(0);
  end;
  List.Free;
  Watcher.Free;
  Ticker.Free;
end.
