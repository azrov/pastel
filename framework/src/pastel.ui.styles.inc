{ Pastel.UI: styles - the sizes, shapes and colors of the controls on each
  platform (Pastel, Fluent, Material) and from .pstyle files.
  Included by pastel.ui.pas. }

type
  { a style: built in or from a file; a file's starts from its base }
  TStyleDef = class
  public
    Metrics: TUIStyle;
    Base: string;                 { the built-in palette under it }
    Colors, DarkColors: TStringList;   { name=value, as in theme.toml }
    Looks, DarkLooks: TStringList;     { name -> TStyleLook }
    constructor Create;
    destructor Destroy; override;
  end;

var
  StyleDefs: TStringList = nil;   { name -> TStyleDef }
  CurrentDef: TStyleDef = nil;
  { hover and press: towards the text on the accent (Fluent, Material) or darker (Pastel) }
  StateLayers: Boolean = False;

constructor TStyleLook.Create;
begin
  inherited Create;
  Radius := -1;
  BorderWidth := -1;
  FontSize := -1;
  PaddingX := -1;
  PaddingY := -1;
  Bold := -1;
end;

procedure TStyleLook.Assign(Src: TStyleLook);
begin
  Name := Src.Name;
  Color := Src.Color;
  HoverColor := Src.HoverColor;
  PressedColor := Src.PressedColor;
  TextColor := Src.TextColor;
  BorderColor := Src.BorderColor;
  Radius := Src.Radius;
  BorderWidth := Src.BorderWidth;
  FontSize := Src.FontSize;
  PaddingX := Src.PaddingX;
  PaddingY := Src.PaddingY;
  Bold := Src.Bold;
end;

constructor TStyleDef.Create;
begin
  inherited Create;
  Colors := TStringList.Create;
  DarkColors := TStringList.Create;
  Looks := TStringList.Create;
  Looks.OwnsObjects := True;
  Looks.CaseSensitive := False;
  DarkLooks := TStringList.Create;
  DarkLooks.OwnsObjects := True;
  DarkLooks.CaseSensitive := False;
end;

destructor TStyleDef.Destroy;
begin
  Colors.Free;
  DarkColors.Free;
  Looks.Free;
  DarkLooks.Free;
  inherited Destroy;
end;

{ ---- the built-in styles ---- }

function PastelMetrics: TUIStyle;
begin
  Result := Default(TUIStyle);
  Result.Name := 'pastel';
  Result.ButtonPadX := 36;
  Result.ButtonPadY := 20;
  Result.ButtonRadius := -1;      { the theme's Radius }
  Result.ButtonBorder := 0;
  Result.ButtonBold := True;
  Result.FlatPadX := 20;
  Result.FlatPadY := 12;
  Result.FlatAccent := False;
  Result.FlatOverlay := False;
  Result.FieldPadX := 12;
  Result.FieldPadY := 20;
  Result.FieldRadius := -1;
  Result.FieldLook := flBox;
  Result.CheckSize := 18;
  Result.CheckRadius := 4;
  Result.SwitchLook := swPill;
  Result.SliderThumb := 9;
  Result.ProgressHeight := 8;
  Result.PopupRadius := 10;
  Result.DialogRadius := 10;
  Result.FocusLook := fkRing;
  Result.DefaultButtonFirst := False;
  Result.DialogFlatButtons := False;
  Result.Radius := 8;
end;

{ Windows 11: 32 pixel controls, small corners, a line at the bottom of edits }
function FluentMetrics: TUIStyle;
begin
  Result := PastelMetrics;
  Result.Name := 'fluent';
  Result.ButtonPadX := 24;
  Result.ButtonPadY := 13;
  Result.ButtonRadius := 4;
  Result.ButtonBorder := 1;
  Result.ButtonBold := False;
  Result.FlatPadX := 16;
  Result.FlatPadY := 13;
  Result.FlatOverlay := True;
  Result.FieldPadX := 11;
  Result.FieldPadY := 13;
  Result.FieldRadius := 4;
  Result.FieldLook := flUnderline;
  Result.CheckSize := 20;
  Result.CheckRadius := 4;
  Result.SwitchLook := swFluent;
  Result.SliderThumb := 10;
  Result.ProgressHeight := 4;
  Result.PopupRadius := 8;
  Result.DialogRadius := 8;
  Result.FocusLook := fkOutline;
  Result.DefaultButtonFirst := True;
  Result.Radius := 4;
end;

{ Android (Material 3): 40 pixel round-ended buttons, outlined edits, round dialogs }
function MaterialMetrics: TUIStyle;
begin
  Result := PastelMetrics;
  Result.Name := 'material';
  Result.ButtonPadX := 48;
  Result.ButtonPadY := 21;
  Result.ButtonRadius := 999;
  Result.ButtonBold := True;
  Result.FlatPadX := 24;
  Result.FlatPadY := 21;
  Result.FlatAccent := True;
  Result.FlatOverlay := True;
  Result.FieldPadX := 16;
  Result.FieldPadY := 30;
  Result.FieldRadius := 4;
  Result.FieldLook := flOutline;
  Result.CheckSize := 18;
  Result.CheckRadius := 2;
  Result.SwitchLook := swMaterial;
  Result.SliderThumb := 10;
  Result.ProgressHeight := 4;
  Result.PopupRadius := 4;
  Result.DialogRadius := 28;
  Result.FocusLook := fkOutline;
  Result.DialogFlatButtons := True;
  Result.Radius := 12;
end;

procedure FluentPalette(Dark: Boolean);
begin
  if not Dark then
  begin
    Theme.Background := RGB($F3, $F3, $F3);
    Theme.Surface := RGB($FF, $FF, $FF);
    Theme.Text := RGB($1B, $1B, $1B);
    Theme.TextMuted := RGB($5F, $5F, $5F);
    Theme.Placeholder := RGB($8A, $8A, $8A);
    Theme.Accent := RGB($00, $5F, $B8);
    Theme.AccentHover := RGB($19, $6E, $BF);
    Theme.AccentPressed := RGB($33, $7E, $C6);
    Theme.OnAccent := RGB($FF, $FF, $FF);
    Theme.Secondary := RGB($FB, $FB, $FB);
    Theme.SecondaryHover := RGB($F6, $F6, $F6);
    Theme.SecondaryPressed := RGB($F0, $F0, $F0);
    Theme.Danger := RGB($C4, $2B, $1C);
    Theme.DangerHover := RGB($CA, $40, $33);
    Theme.DangerPressed := RGB($D0, $55, $49);
    Theme.Border := RGB($E0, $E0, $E0);
    Theme.BorderHover := RGB($CC, $CC, $CC);
    Theme.Outline := RGB($86, $86, $86);
    Theme.FocusRing := RGBA($00, $5F, $B8, $40);
    Theme.Disabled := RGB($A6, $A6, $A6);
    Theme.Shadow := RGBA(0, 0, 0, $24);
    Theme.Backdrop := RGBA(0, 0, 0, $4D);
    Theme.Selection := RGBA($00, $5F, $B8, $22);
    Theme.TooltipBack := RGB($F9, $F9, $F9);
    Theme.TooltipText := RGB($1B, $1B, $1B);
  end
  else
  begin
    Theme.Background := RGB($20, $20, $20);
    Theme.Surface := RGB($2B, $2B, $2B);
    Theme.Text := RGB($FF, $FF, $FF);
    Theme.TextMuted := RGB($C5, $C5, $C5);
    Theme.Placeholder := RGB($9A, $9A, $9A);
    Theme.Accent := RGB($60, $CD, $FF);
    Theme.AccentHover := RGB($5A, $BC, $E9);
    Theme.AccentPressed := RGB($52, $A8, $D0);
    Theme.OnAccent := RGB($00, $00, $00);
    Theme.Secondary := RGB($2D, $2D, $2D);
    Theme.SecondaryHover := RGB($32, $32, $32);
    Theme.SecondaryPressed := RGB($27, $27, $27);
    Theme.Danger := RGB($FF, $99, $A4);
    Theme.DangerHover := RGB($EB, $8D, $97);
    Theme.DangerPressed := RGB($D6, $80, $8A);
    Theme.Border := RGB($3B, $3B, $3B);
    Theme.BorderHover := RGB($4A, $4A, $4A);
    Theme.Outline := RGB($9A, $9A, $9A);
    Theme.FocusRing := RGBA($60, $CD, $FF, $50);
    Theme.Disabled := RGB($5D, $5D, $5D);
    Theme.Shadow := RGBA(0, 0, 0, $66);
    Theme.Backdrop := RGBA(0, 0, 0, $80);
    Theme.Selection := RGBA($60, $CD, $FF, $30);
    Theme.TooltipBack := RGB($2C, $2C, $2C);
    Theme.TooltipText := RGB($FF, $FF, $FF);
  end;
end;

procedure MaterialPalette(Dark: Boolean);
begin
  if not Dark then
  begin
    Theme.Background := RGB($FE, $F7, $FF);
    Theme.Surface := RGB($F7, $F2, $FA);
    Theme.Text := RGB($1D, $1B, $20);
    Theme.TextMuted := RGB($49, $45, $4F);
    Theme.Placeholder := RGB($79, $74, $7E);
    Theme.Accent := RGB($67, $50, $A4);
    Theme.OnAccent := RGB($FF, $FF, $FF);
    Theme.Secondary := RGB($E8, $DE, $F8);
    Theme.Danger := RGB($B3, $26, $1E);
    Theme.Border := RGB($CA, $C4, $D0);
    Theme.BorderHover := RGB($1D, $1B, $20);
    Theme.Outline := RGB($79, $74, $7E);
    Theme.Disabled := RGB($A9, $A6, $AB);
    Theme.Shadow := RGBA(0, 0, 0, $30);
    Theme.Backdrop := RGBA(0, 0, 0, $52);
    Theme.TooltipBack := RGB($31, $30, $33);
    Theme.TooltipText := RGB($F4, $EF, $F4);
  end
  else
  begin
    Theme.Background := RGB($14, $12, $18);
    Theme.Surface := RGB($1D, $1B, $20);
    Theme.Text := RGB($E6, $E0, $E9);
    Theme.TextMuted := RGB($CA, $C4, $D0);
    Theme.Placeholder := RGB($93, $8F, $99);
    Theme.Accent := RGB($D0, $BC, $FF);
    Theme.OnAccent := RGB($38, $1E, $72);
    Theme.Secondary := RGB($4A, $44, $58);
    Theme.Danger := RGB($F2, $B8, $B5);
    Theme.Border := RGB($49, $45, $4F);
    Theme.BorderHover := RGB($E6, $E0, $E9);
    Theme.Outline := RGB($93, $8F, $99);
    Theme.Disabled := RGB($6B, $68, $70);
    Theme.Shadow := RGBA(0, 0, 0, $70);
    Theme.Backdrop := RGBA(0, 0, 0, $80);
    Theme.TooltipBack := RGB($E6, $E0, $E9);
    Theme.TooltipText := RGB($32, $2F, $35);
  end;
  { state layers: 8% (hover) and 12% (pressed) of the color on top }
  Theme.AccentHover := Mix(Theme.Accent, Theme.OnAccent, 0.08);
  Theme.AccentPressed := Mix(Theme.Accent, Theme.OnAccent, 0.12);
  Theme.SecondaryHover := Mix(Theme.Secondary, Theme.Text, 0.08);
  Theme.SecondaryPressed := Mix(Theme.Secondary, Theme.Text, 0.12);
  Theme.DangerHover := Mix(Theme.Danger, Theme.Surface, 0.08);
  Theme.DangerPressed := Mix(Theme.Danger, Theme.Surface, 0.12);
  Theme.FocusRing := WithAlpha(Theme.Accent, $40);
  Theme.Selection := WithAlpha(Theme.Accent, $24);
end;

procedure RegisterBuiltIn(const AName: string; const M: TUIStyle);
var
  D: TStyleDef;
begin
  D := TStyleDef.Create;
  D.Metrics := M;
  D.Base := AName;
  StyleDefs.AddObject(AName, D);
end;

procedure EnsureStyles;
begin
  if StyleDefs <> nil then
    Exit;
  StyleDefs := TStringList.Create;
  StyleDefs.OwnsObjects := True;
  StyleDefs.CaseSensitive := False;
  RegisterBuiltIn('pastel', PastelMetrics);
  RegisterBuiltIn('fluent', FluentMetrics);
  RegisterBuiltIn('material', MaterialMetrics);
  CurrentDef := TStyleDef(StyleDefs.Objects[0]);
  UIStyle := CurrentDef.Metrics;
end;

function FindDef(const AName: string): TStyleDef;
var
  I: Integer;
begin
  EnsureStyles;
  I := StyleDefs.IndexOf(AName);
  if I >= 0 then
    Result := TStyleDef(StyleDefs.Objects[I])
  else
    Result := nil;
end;

{ the colors of the style in use, over the Pastel ones LightTheme/DarkTheme set }
procedure ApplyStylePalette(Dark: Boolean);
var
  I: Integer;
  L: TStringList;
begin
  EnsureStyles;
  StateLayers := False;
  Theme.Outline := Theme.Border;
  if SameText(CurrentDef.Base, 'fluent') then
  begin
    FluentPalette(Dark);
    StateLayers := True;
  end
  else if SameText(CurrentDef.Base, 'material') then
  begin
    MaterialPalette(Dark);
    StateLayers := True;
  end;
  Theme.Radius := UIStyle.Radius;
  for I := 0 to CurrentDef.Colors.Count - 1 do
    SetThemeValue(CurrentDef.Colors.Names[I], CurrentDef.Colors.ValueFromIndex[I]);
  if Dark then
  begin
    L := CurrentDef.DarkColors;
    for I := 0 to L.Count - 1 do
      SetThemeValue(L.Names[I], L.ValueFromIndex[I]);
  end;
end;

function PlatformStyle: string;
begin
  {$IF defined(ANDROID)}
  Result := 'material';
  {$ELSEIF defined(WINDOWS)}
  Result := 'fluent';
  {$ELSE}
  Result := 'pastel';
  {$ENDIF}
end;

function UseStyle(const Name: string): Boolean;
var
  D: TStyleDef;
  N, Text: string;
begin
  EnsureStyles;
  N := Trim(Name);
  if (N = '') or SameText(N, 'auto') then
    N := PlatformStyle;
  D := FindDef(N);
  if (D = nil) and Assigned(StyleFileHook) then
  begin
    Text := StyleFileHook(N);
    if (Text <> '') and (LoadStyle(N, Text) = '') then
      D := FindDef(N);
  end;
  if D = nil then
    Exit(False);
  CurrentDef := D;
  UIStyle := D.Metrics;
  UseDarkTheme(Theme.Dark);
  Result := True;
end;

function StyleNames: TStringArray;
var
  I: Integer;
begin
  EnsureStyles;
  Result := nil;
  SetLength(Result, StyleDefs.Count);
  for I := 0 to StyleDefs.Count - 1 do
    Result[I] := StyleDefs[I];
end;

function FindLook(const Name: string): TStyleLook;
var
  I: Integer;
begin
  Result := nil;
  if (Name = '') or (CurrentDef = nil) then
    Exit;
  if Theme.Dark then
  begin
    I := CurrentDef.DarkLooks.IndexOf(Name);
    if I >= 0 then
      Exit(TStyleLook(CurrentDef.DarkLooks.Objects[I]));
  end;
  I := CurrentDef.Looks.IndexOf(Name);
  if I >= 0 then
    Result := TStyleLook(CurrentDef.Looks.Objects[I]);
end;

{ ---- .pstyle files ---- }

{ what Dark does not set, from Light }
procedure MergeLook(Dark, Light: TStyleLook);
begin
  if Dark.Color = 0 then Dark.Color := Light.Color;
  if Dark.HoverColor = 0 then Dark.HoverColor := Light.HoverColor;
  if Dark.PressedColor = 0 then Dark.PressedColor := Light.PressedColor;
  if Dark.TextColor = 0 then Dark.TextColor := Light.TextColor;
  if Dark.BorderColor = 0 then Dark.BorderColor := Light.BorderColor;
  if Dark.Radius < 0 then Dark.Radius := Light.Radius;
  if Dark.BorderWidth < 0 then Dark.BorderWidth := Light.BorderWidth;
  if Dark.FontSize < 0 then Dark.FontSize := Light.FontSize;
  if Dark.PaddingX < 0 then Dark.PaddingX := Light.PaddingX;
  if Dark.PaddingY < 0 then Dark.PaddingY := Light.PaddingY;
  if Dark.Bold < 0 then Dark.Bold := Light.Bold;
end;

{ would SetThemeValue take it? (the theme stays as it is) }
function IsThemeValue(const Name, Value: string): Boolean;
var
  Saved: TTheme;
begin
  Saved := Theme;
  Result := SetThemeValue(Name, Value);
  Theme := Saved;
end;

function LoadStyle(const Name, Text: string): string;
var
  Doc: TTomlDocument;
  D, B: TStyleDef;
  M: TUIStyle;
  I, J, N: Integer;
  K, Section, Key, Value, BaseName: string;
  Parts: TStringArray;
  Look: TStyleLook;

  function Bad(const Why: string): string;
  begin
    Result := Format('%s = %s: %s', [K, Value, Why]);
  end;

  function Int(Lo, Hi: Integer; out Err: string): Integer;
  begin
    Err := '';
    if not TryStrToInt(Value, Result) or (Result < Lo) or (Result > Hi) then
    begin
      Err := Bad(Format('a whole number from %d to %d', [Lo, Hi]));
      Result := 0;
    end;
  end;

  function Bool(out Err: string): Boolean;
  begin
    Err := '';
    Result := SameText(Value, 'true');
    if not Result and not SameText(Value, 'false') then
      Err := Bad('true or false');
  end;

  function SetMetric(const Sec, Key: string): string;
  var
    E: string;
  begin
    E := '';
    case Sec + '.' + Key of
      '.radius': M.Radius := Int(0, 64, E);
      'button.padding_x': M.ButtonPadX := Int(0, 200, E);
      'button.padding_y': M.ButtonPadY := Int(0, 100, E);
      'button.radius': M.ButtonRadius := Int(0, 999, E);
      'button.border': M.ButtonBorder := Int(0, 8, E);
      'button.bold': M.ButtonBold := Bool(E);
      'flat_button.padding_x': M.FlatPadX := Int(0, 200, E);
      'flat_button.padding_y': M.FlatPadY := Int(0, 100, E);
      'flat_button.accent': M.FlatAccent := Bool(E);
      'flat_button.overlay': M.FlatOverlay := Bool(E);
      'field.padding_x': M.FieldPadX := Int(0, 100, E);
      'field.padding_y': M.FieldPadY := Int(0, 100, E);
      'field.radius': M.FieldRadius := Int(0, 999, E);
      'field.look':
        case LowerCase(Value) of
          'box': M.FieldLook := flBox;
          'underline': M.FieldLook := flUnderline;
          'outline': M.FieldLook := flOutline;
        else
          E := Bad('box, underline or outline');
        end;
      'check.size': M.CheckSize := Int(10, 40, E);
      'check.radius': M.CheckRadius := Int(0, 20, E);
      'switch.look':
        case LowerCase(Value) of
          'pill', 'pastel': M.SwitchLook := swPill;
          'fluent': M.SwitchLook := swFluent;
          'material': M.SwitchLook := swMaterial;
        else
          E := Bad('pill, fluent or material');
        end;
      'slider.thumb': M.SliderThumb := Int(4, 30, E);
      'progress.height': M.ProgressHeight := Int(1, 40, E);
      'popup.radius': M.PopupRadius := Int(0, 64, E);
      'dialog.radius': M.DialogRadius := Int(0, 64, E);
      'dialog.default_first': M.DefaultButtonFirst := Bool(E);
      'dialog.flat_buttons': M.DialogFlatButtons := Bool(E);
      'focus.look':
        case LowerCase(Value) of
          'ring': M.FocusLook := fkRing;
          'outline': M.FocusLook := fkOutline;
        else
          E := Bad('ring or outline');
        end;
    else
      E := Format('"%s" is not a style value', [K]);
    end;
    Result := E;
  end;

  function SetLook(L: TStyleLook; const Key: string): string;
  var
    C: TColor32;
    E: string;
  begin
    E := '';
    case Key of
      'color', 'hover_color', 'pressed_color', 'text_color', 'border_color':
        begin
          if not TryParseColor(Value, C) then
            Exit(Bad('a color: #RRGGBB'));
          case Key of
            'color': L.Color := C;
            'hover_color': L.HoverColor := C;
            'pressed_color': L.PressedColor := C;
            'text_color': L.TextColor := C;
            'border_color': L.BorderColor := C;
          end;
        end;
      'radius': L.Radius := Int(0, 999, E);
      'border_width': L.BorderWidth := Int(0, 8, E);
      'font_size': L.FontSize := Int(8, 96, E);
      'padding_x': L.PaddingX := Int(0, 200, E);
      'padding_y': L.PaddingY := Int(0, 100, E);
      'bold': if Bool(E) then L.Bold := 1 else L.Bold := 0;
    else
      E := Format('"%s" is not a look value', [K]);
    end;
    Result := E;
  end;

  function LookIn(List: TStringList; const LName: string): TStyleLook;
  var
    Idx: Integer;
  begin
    Idx := List.IndexOf(LName);
    if Idx >= 0 then
      Exit(TStyleLook(List.Objects[Idx]));
    Result := TStyleLook.Create;
    Result.Name := LName;
    List.AddObject(LName, Result);
  end;

begin
  EnsureStyles;
  if Trim(Name) = '' then
    Exit('a style needs a name');
  if SameText(Name, 'auto') then
    Exit('"auto" is not a name for a style');
  Doc := TTomlDocument.Create;
  try
    try
      Doc.LoadFromString(Text);
    except
      on E: Exception do
        Exit(E.Message);
    end;
    BaseName := Doc.GetString('base', 'pastel');
    B := FindDef(BaseName);
    if (B = nil) or (FindDef(B.Base) = nil) then
      Exit(Format('base = %s: the base is pastel, fluent, material or a style loaded before', [BaseName]));
    if SameText(BaseName, Name) then
      Exit('a style cannot be its own base');
    D := TStyleDef.Create;
    try
      D.Base := B.Base;
      M := B.Metrics;
      D.Colors.Assign(B.Colors);
      D.DarkColors.Assign(B.DarkColors);
      for I := 0 to B.Looks.Count - 1 do
        LookIn(D.Looks, B.Looks[I]).Assign(TStyleLook(B.Looks.Objects[I]));
      for I := 0 to B.DarkLooks.Count - 1 do
        LookIn(D.DarkLooks, B.DarkLooks[I]).Assign(TStyleLook(B.DarkLooks.Objects[I]));
      for I := 0 to Doc.Values.Count - 1 do
      begin
        K := Doc.Values[I];
        Value := Trim(Doc.GetString(K));
        Parts := K.Split(['.']);
        N := Length(Parts);
        if K = 'base' then
          Continue;
        if (Parts[0] = 'colors') and (N = 2) then
          D.Colors.Values[Parts[1]] := Value
        else if (Parts[0] = 'colors') and (N = 3) and (Parts[1] = 'dark') then
          D.DarkColors.Values[Parts[2]] := Value
        else if (Parts[0] = 'look') and (N in [3, 4]) then
        begin
          if N = 3 then
            Result := SetLook(LookIn(D.Looks, Parts[1]), Parts[2])
          else if Parts[2] = 'dark' then
            Result := SetLook(LookIn(D.DarkLooks, Parts[1]), Parts[3])
          else
            Result := Format('"%s" is not a look value', [K]);
          if Result <> '' then
            Exit;
        end
        else
        begin
          if N = 1 then
          begin
            Section := '';
            Key := Parts[0];
          end
          else if N = 2 then
          begin
            Section := Parts[0];
            Key := Parts[1];
          end
          else
            Exit(Format('"%s" is not a style value', [K]));
          Result := SetMetric(Section, Key);
          if Result <> '' then
            Exit;
        end;
      end;
      { a color that is not a theme value: said now, not when the style is used }
      for I := 0 to D.Colors.Count + D.DarkColors.Count - 1 do
      begin
        if I < D.Colors.Count then
        begin
          Key := D.Colors.Names[I];
          K := 'colors.' + Key;
          Value := D.Colors.ValueFromIndex[I];
        end
        else
        begin
          Key := D.DarkColors.Names[I - D.Colors.Count];
          K := 'colors.dark.' + Key;
          Value := D.DarkColors.ValueFromIndex[I - D.Colors.Count];
        end;
        if not IsThemeValue(Key, Value) then
          Exit(Format('%s = %s is not a theme value', [K, Value]));
      end;
      { the dark look of a name: its light one with the dark values over it }
      for I := 0 to D.DarkLooks.Count - 1 do
      begin
        Look := TStyleLook(D.DarkLooks.Objects[I]);
        J := D.Looks.IndexOf(Look.Name);
        if J >= 0 then
          MergeLook(Look, TStyleLook(D.Looks.Objects[J]));
      end;
      M.Name := Name;
      D.Metrics := M;
      I := StyleDefs.IndexOf(Name);
      if I >= 0 then
      begin
        if CurrentDef = StyleDefs.Objects[I] then
          CurrentDef := D;
        StyleDefs.Objects[I].Free;
        StyleDefs.Objects[I] := D;
      end
      else
        StyleDefs.AddObject(Name, D);
      D := nil;
      Result := '';
    finally
      D.Free;
    end;
  finally
    Doc.Free;
  end;
end;

{ ---- drawing in the style ---- }

function Luminance(C: TColor32): Single;
begin
  Result := (0.2126 * ((Cardinal(C) shr 16) and $FF) + 0.7152 * ((Cardinal(C) shr 8) and $FF) +
    0.0722 * (Cardinal(C) and $FF)) / 255;
end;

function StyleRadius(R: Integer): Integer;
begin
  if R < 0 then
    Result := Theme.Radius
  else
    Result := R;
end;

procedure DrawFocus(C: TCanvas32; const R: TRectI; Radius: Single);
begin
  if UIStyle.FocusLook = fkOutline then
    C.StrokeRoundRect(R.X - 3, R.Y - 3, R.W + 6, R.H + 6, Radius + 3, 2, Theme.Text)
  else
    C.FillRoundRect(R.X - 3, R.Y - 3, R.W + 6, R.H + 6, Radius + 3, Theme.FocusRing);
end;

function FieldHeight(LineHeight: Integer): Integer;
begin
  Result := LineHeight + UIStyle.FieldPadY;
end;

procedure PaintField(C: TCanvas32; const R: TRectI; Focused, Hovered, Enabled, Editable, Error: Boolean;
  Look: TStyleLook);
var
  Bg, Border, Line: TColor32;
  Rad: Single;
  BW: Integer;
begin
  Rad := Min(StyleRadius(UIStyle.FieldRadius), Min(R.W, R.H) / 2);
  BW := 1;
  if (Look <> nil) and (Look.Radius >= 0) then
    Rad := Min(Look.Radius, Min(R.W, R.H) / 2);
  if (Look <> nil) and (Look.BorderWidth >= 0) then
    BW := Look.BorderWidth;
  if Enabled and Editable then
    Bg := Theme.Surface
  else
    Bg := Theme.Secondary;
  if (Look <> nil) and (Look.Color <> 0) then
    Bg := Look.Color;
  case UIStyle.FieldLook of
    flUnderline:
      begin
        { Fluent: a light border, the bottom line darker; the accent (2 px) when focused }
        if Hovered and Enabled and not Focused then
          Bg := Mix(Bg, Theme.Text, 0.03);
        C.FillRoundRect(R.X, R.Y, R.W, R.H, Rad, Bg);
        Border := Theme.Border;
        if (Look <> nil) and (Look.BorderColor <> 0) then
          Border := Look.BorderColor;
        if BW > 0 then
          C.StrokeRoundRect(R.X, R.Y, R.W, R.H, Rad, BW, Border);
        C.PushClip(RectI(R.X, R.Y + R.H - Round(Rad) - 1, R.W, Round(Rad) + 1));
        if Error then Line := Theme.Danger
        else if Focused then Line := Theme.Accent
        else if Enabled then Line := Theme.Outline
        else Line := Theme.Border;
        if Focused or Error then
          C.FillRect(R.X + 1, R.Y + R.H - 2, R.W - 2, 2, Line)
        else
          C.FillRect(R.X + 1, R.Y + R.H - 1, R.W - 2, 1, Line);
        C.PopClip;
      end;
    flOutline:
      begin
        { Material: the outline, thicker and in the accent when focused; no
          background of its own when it can be typed in }
        if not (Enabled and Editable) or ((Look <> nil) and (Look.Color <> 0)) then
          C.FillRoundRect(R.X, R.Y, R.W, R.H, Rad, Bg);
        if Error then Border := Theme.Danger
        else if Focused then Border := Theme.Accent
        else if Hovered and Enabled then Border := Theme.BorderHover
        else if Enabled then Border := Theme.Outline
        else Border := Theme.Disabled;
        if (Look <> nil) and (Look.BorderColor <> 0) and not Focused and not Error then
          Border := Look.BorderColor;
        if Focused or Error then
          C.StrokeRoundRect(R.X, R.Y, R.W, R.H, Rad, Math.Max(BW, 2), Border)
        else if BW > 0 then
          C.StrokeRoundRect(R.X, R.Y, R.W, R.H, Rad, BW, Border);
      end;
  else
    { Pastel: a ring around when focused, the border in the accent }
    if Focused then
    begin
      C.FillRoundRect(R.X - 3, R.Y - 3, R.W + 6, R.H + 6, Rad + 3, Theme.FocusRing);
      Border := Theme.Accent;
    end
    else if Hovered and Enabled then
      Border := Theme.BorderHover
    else
      Border := Theme.Border;
    if (Look <> nil) and (Look.BorderColor <> 0) and not Focused then
      Border := Look.BorderColor;
    if Error then
      Border := Theme.Danger;
    C.FillRoundRect(R.X, R.Y, R.W, R.H, Rad, Bg);
    if BW > 0 then
      C.StrokeRoundRect(R.X, R.Y, R.W, R.H, Rad, BW, Border);
  end;
end;
