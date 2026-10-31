{ Pastel.UI: TCustomEdit, the text editing shared by TEdit and TMemo.
  Included by pastel.ui.pas. }

const
  EditPadding = 12;
  MemoPadding = 10;

function IsWordChar(const S: string; I: Integer): Boolean;
begin
  Result := (I >= 1) and (I <= Length(S)) and
    ((S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(S[I]) >= 128));
end;

function NextCharStart(const S: string; I: Integer): Integer;
begin
  Result := I;
  if Result <= Length(S) then
    NextCodePoint(S, Result);
end;

{ ---- TMemoLines: Memo.Lines as a TStrings over the memo's text ---- }

type
  TMemoLines = class(TStrings)
  private
    FMemo: TCustomEdit;
    function Split: TStringArray;
    procedure Join(const L: TStringArray);
  protected
    function Get(Index: Integer): string; override;
    function GetCount: Integer; override;
    procedure Put(Index: Integer; const S: string); override;
  public
    constructor Create(AMemo: TCustomEdit);
    procedure Clear; override;
    procedure Delete(Index: Integer); override;
    procedure Insert(Index: Integer; const S: string); override;
  end;

constructor TMemoLines.Create(AMemo: TCustomEdit);
begin
  inherited Create;
  FMemo := AMemo;
end;

function TMemoLines.Split: TStringArray;
begin
  if FMemo.Text = '' then
    Result := nil
  else
    Result := FMemo.Text.Split([#10]);
end;

procedure TMemoLines.Join(const L: TStringArray);
begin
  FMemo.Text := string.Join(#10, L);
end;

function TMemoLines.Get(Index: Integer): string;
var
  L: TStringArray;
begin
  L := Split;
  if (Index < 0) or (Index > High(L)) then
    Error('List index (%d) out of bounds', Index);
  Result := L[Index];
end;

function TMemoLines.GetCount: Integer;
begin
  Result := Length(Split);
end;

procedure TMemoLines.Put(Index: Integer; const S: string);
var
  L: TStringArray;
begin
  L := Split;
  if (Index < 0) or (Index > High(L)) then
    Error('List index (%d) out of bounds', Index);
  L[Index] := S;
  Join(L);
end;

procedure TMemoLines.Clear;
begin
  FMemo.Text := '';
end;

procedure TMemoLines.Delete(Index: Integer);
var
  L: TStringArray;
begin
  L := Split;
  if (Index < 0) or (Index > High(L)) then
    Error('List index (%d) out of bounds', Index);
  System.Delete(L, Index, 1);
  Join(L);
end;

procedure TMemoLines.Insert(Index: Integer; const S: string);
var
  L: TStringArray;
begin
  L := Split;
  if (Index < 0) or (Index > Length(L)) then
    Error('List index (%d) out of bounds', Index);
  System.Insert(S, L, Index);
  Join(L);
end;

{ ---- TCustomEdit ---- }

constructor TCustomEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaret := 1;
  FAnchor := 1;
  FDesiredX := -1;
end;

destructor TCustomEdit.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

function TCustomEdit.Font: TPastelFont;
begin
  Result := GetFont(Theme.FontSize, False);
end;

function TCustomEdit.GetLines: TStrings;
begin
  if FLines = nil then
    FLines := TMemoLines.Create(Self);
  Result := FLines;
end;

procedure TCustomEdit.SetLines(AValue: TStrings);
begin
  if AValue = nil then
    Text := ''
  else
    Text := StringReplace(TrimRight(AValue.Text), LineEnding, #10, [rfReplaceAll]);
end;

function TCustomEdit.CleanText(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] = #13 then
      Continue
    else if (S[I] = #10) and FMultiLine then
      Result := Result + #10
    else if S[I] = #9 then
      Result := Result + ' '
    else if S[I] >= ' ' then
      Result := Result + S[I];
end;

procedure TCustomEdit.SetText(const AValue: string);
var
  V: string;
begin
  V := CleanText(StringReplace(AValue, #13#10, #10, [rfReplaceAll]));
  if FText = V then
    Exit;
  FText := V;
  FCaret := Length(FText) + 1;
  FAnchor := FCaret;
  FUndo := nil;
  FRedo := nil;
  Changed;
  DoChange;
end;

procedure TCustomEdit.SetPlaceholder(const AValue: string);
begin
  FPlaceholder := AValue;
  Invalidate;
end;

procedure TCustomEdit.SetPassword(AValue: Boolean);
begin
  FPassword := AValue;
  Invalidate;
end;

procedure TCustomEdit.SetWordWrap(AValue: Boolean);
begin
  FWordWrap := AValue;
  FVisual := nil;
  Changed;
end;

procedure TCustomEdit.DoChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TCustomEdit.DisplayText(const S: string): string;
var
  I, N: Integer;
begin
  if not FPassword then
    Exit(S);
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    NextCodePoint(S, I);
    Inc(N);
  end;
  Result := '';
  for I := 1 to N do
    Result := Result + '•';
end;

{ byte position in S -> byte position in DisplayText(S) }
function TCustomEdit.DisplayPos(const S: string; P: Integer): Integer;
var
  I, N: Integer;
begin
  if not FPassword then
    Exit(P);
  N := 0;
  I := 1;
  while (I < P) and (I <= Length(S)) do
  begin
    NextCodePoint(S, I);
    Inc(N);
  end;
  Result := N * Length('•') + 1;
end;

function TCustomEdit.SourcePos(const S: string; DP: Integer): Integer;
var
  I, N: Integer;
begin
  if not FPassword then
    Exit(DP);
  N := (DP - 1) div Length('•');
  I := 1;
  while (N > 0) and (I <= Length(S)) do
  begin
    NextCodePoint(S, I);
    Dec(N);
  end;
  Result := I;
end;

function TCustomEdit.Padding: Integer;
begin
  if FMultiLine then Result := MemoPadding else Result := EditPadding;
end;

function TCustomEdit.InnerRect: TRectI;
var
  P: Integer;
begin
  P := Padding;
  if FMultiLine then
    Result := RectI(Bounds.X + P, Bounds.Y + P, Max(1, Bounds.W - 2 * P - 6), Max(1, Bounds.H - 2 * P))
  else
    Result := RectI(Bounds.X + P, Bounds.Y, Max(1, Bounds.W - 2 * P), Bounds.H);
end;

{ The visual lines: each a byte range of FText (without the #10). }
procedure TCustomEdit.BuildLines(AWidth: Integer);
var
  F: TPastelFont;
  Start, I, LastBreak, LineStart, P, N: Integer;

  procedure Add(AStart, AEnd: Integer);
  begin
    SetLength(FVisual, N + 1);
    FVisual[N].StartPos := AStart;
    FVisual[N].EndPos := AEnd;
    Inc(N);
  end;

begin
  F := Font;
  N := 0;
  FVisual := nil;
  if not FMultiLine then
  begin
    Add(1, Length(FText) + 1);
    Exit;
  end;
  Start := 1;
  repeat
    { one paragraph: Start .. before #10 }
    P := Pos(#10, FText, Start);
    if P = 0 then
      P := Length(FText) + 1;
    if not FWordWrap or (AWidth <= 0) then
      Add(Start, P)
    else
    begin
      LineStart := Start;
      LastBreak := 0;
      I := Start;
      while I < P do
      begin
        if FText[I] = ' ' then
          LastBreak := I + 1;
        NextCodePoint(FText, I);
        if (F.TextWidth(Copy(FText, LineStart, I - LineStart)) > AWidth) and (I - LineStart > 1) then
        begin
          if (LastBreak > LineStart) and (LastBreak <= I) then
          begin
            Add(LineStart, LastBreak);
            LineStart := LastBreak;
          end
          else
          begin
            { a word longer than the line: break it }
            I := PrevCharStart(FText, I);
            Add(LineStart, I);
            LineStart := I;
          end;
          LastBreak := 0;
        end;
      end;
      Add(LineStart, P);
    end;
    Start := P + 1;
  until P > Length(FText);
  FVisualWidth := AWidth;
  FVisualText := FText;
end;

procedure TCustomEdit.EnsureLines;
begin
  if (FVisual = nil) or (FVisualText <> FText) or (FMultiLine and (FVisualWidth <> InnerRect.W)) then
    BuildLines(InnerRect.W);
end;

function TCustomEdit.LineOf(P: Integer): Integer;
var
  I: Integer;
begin
  EnsureLines;
  Result := High(FVisual);
  for I := 0 to High(FVisual) do
    if P < FVisual[I].EndPos then
      Exit(I)
    else if (P = FVisual[I].EndPos) and ((I = High(FVisual)) or (FVisual[I + 1].StartPos > P)) then
      Exit(I);
end;

function TCustomEdit.XOf(P: Integer): Integer;
var
  L: Integer;
  S: string;
begin
  L := LineOf(P);
  S := Copy(FText, FVisual[L].StartPos, P - FVisual[L].StartPos);
  Result := Font.TextWidth(DisplayText(S));
end;

function TCustomEdit.PosAt(X, Y: Integer): Integer;
var
  R: TRectI;
  L: Integer;
  S: string;
begin
  EnsureLines;
  R := InnerRect;
  if FMultiLine then
    L := EnsureRange((Y - R.Y + FScrollY) div Font.LineHeight, 0, High(FVisual))
  else
    L := 0;
  S := Copy(FText, FVisual[L].StartPos, FVisual[L].EndPos - FVisual[L].StartPos);
  Result := FVisual[L].StartPos - 1 + SourcePos(S, Font.HitTest(DisplayText(S), X - R.X + FScrollX));
end;

function TCustomEdit.SelStartPos: Integer;
begin
  Result := Min(FCaret, FAnchor);
end;

function TCustomEdit.GetSelStart: Integer;
begin
  Result := SelStartPos - 1;
end;

function TCustomEdit.GetSelLength: Integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

function TCustomEdit.GetSelText: string;
begin
  Result := Copy(FText, SelStartPos, GetSelLength);
end;

procedure TCustomEdit.SetSelStart(AValue: Integer);
begin
  FCaret := EnsureRange(AValue + 1, 1, Length(FText) + 1);
  FAnchor := FCaret;
  Invalidate;
end;

procedure TCustomEdit.SetSelLength(AValue: Integer);
begin
  FAnchor := SelStartPos;
  FCaret := EnsureRange(FAnchor + AValue, 1, Length(FText) + 1);
  Invalidate;
end;

procedure TCustomEdit.SelectAll;
begin
  FAnchor := 1;
  FCaret := Length(FText) + 1;
  Invalidate;
end;

procedure TCustomEdit.SaveUndo(Typing: Boolean);
var
  U: TEditState;
begin
  if Typing and FLastWasTyping then
    Exit;
  U.Text := FText;
  U.Caret := FCaret;
  U.Anchor := FAnchor;
  Insert(U, FUndo, Length(FUndo));
  if Length(FUndo) > 200 then
    Delete(FUndo, 0, 1);
  FRedo := nil;
  FLastWasTyping := Typing;
end;

function TCustomEdit.CanUndo: Boolean;
begin
  Result := Length(FUndo) > 0;
end;

procedure TCustomEdit.Restore(var FromStack, ToStack: TEditStates);
var
  U: TEditState;
begin
  if Length(FromStack) = 0 then
    Exit;
  U.Text := FText;
  U.Caret := FCaret;
  U.Anchor := FAnchor;
  Insert(U, ToStack, Length(ToStack));
  U := FromStack[High(FromStack)];
  SetLength(FromStack, Length(FromStack) - 1);
  FText := U.Text;
  FCaret := U.Caret;
  FAnchor := U.Anchor;
  FLastWasTyping := False;
  Changed;
  DoChange;
end;

procedure TCustomEdit.Undo;
begin
  Restore(FUndo, FRedo);
end;

procedure TCustomEdit.Redo;
begin
  Restore(FRedo, FUndo);
end;

{ replace the selection with S (as one undo step unless Typing continues one) }
procedure TCustomEdit.ReplaceSelection(const S: string; Typing: Boolean);
var
  Clean: string;
  Start: Integer;
begin
  if FReadOnly then
    Exit;
  Clean := CleanText(S);
  if (FMaxLength > 0) and (Length(FText) - GetSelLength + Length(Clean) > FMaxLength) then
    Clean := Copy(Clean, 1, Max(0, FMaxLength - (Length(FText) - GetSelLength)));
  if (Clean = '') and (GetSelLength = 0) then
    Exit;
  SaveUndo(Typing and (GetSelLength = 0) and (Clean <> ' '));
  Start := SelStartPos;
  Delete(FText, Start, GetSelLength);
  Insert(Clean, FText, Start);
  FCaret := Start + Length(Clean);
  FAnchor := FCaret;
  FDesiredX := -1;
  CaretVisible := True;
  if FMultiLine then Changed else Invalidate;
  DoChange;
end;

procedure TCustomEdit.CopyToClipboard;
begin
  if (GetSelLength > 0) and not FPassword and Assigned(ClipboardSetText) then
    ClipboardSetText(GetSelText);
end;

procedure TCustomEdit.CutToClipboard;
begin
  if FReadOnly or FPassword then
    Exit;
  CopyToClipboard;
  ReplaceSelection('', False);
end;

procedure TCustomEdit.PasteFromClipboard;
begin
  if Assigned(ClipboardGetText) then
    ReplaceSelection(ClipboardGetText(), False);
end;

procedure TCustomEdit.SetSelText(const AValue: string);
begin
  ReplaceSelection(AValue, False);
end;

procedure TCustomEdit.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := 200;
  if FMultiLine then
    H := Font.LineHeight * 5 + 2 * MemoPadding
  else
    H := Font.LineHeight + 20;
end;

procedure TCustomEdit.ScrollToCaret;
var
  R: TRectI;
  CX, LineTop, LH, TotalW: Integer;
begin
  R := InnerRect;
  EnsureLines;
  CX := XOf(FCaret);
  if FMultiLine then
  begin
    LH := Font.LineHeight;
    LineTop := LineOf(FCaret) * LH;
    if LineTop < FScrollY then
      FScrollY := LineTop;
    if LineTop + LH > FScrollY + R.H then
      FScrollY := LineTop + LH - R.H;
    FScrollY := EnsureRange(FScrollY, 0, Max(0, Length(FVisual) * LH - R.H));
    if FWordWrap then
      FScrollX := 0;
  end;
  if not FMultiLine or not FWordWrap then
  begin
    if CX - FScrollX > R.W then
      FScrollX := CX - R.W;
    if CX - FScrollX < 0 then
      FScrollX := CX;
    if not FMultiLine then
    begin
      TotalW := Font.TextWidth(DisplayText(FText));
      if TotalW - FScrollX < R.W then
        FScrollX := Max(0, TotalW - R.W);
    end;
  end;
end;

procedure TCustomEdit.Paint(C: TCanvas32);
var
  F: TPastelFont;
  R: TRectI;
  Border: TColor32;
  I, Y, LH, SA, SB, X1, X2, LineStart, LineEnd: Integer;
  S: string;
begin
  F := Font;
  LH := F.LineHeight;
  EnsureLines;
  if FScrollToCaret then
  begin
    ScrollToCaret;
    FScrollToCaret := False;
  end;
  R := InnerRect;
  if IsFocused then
  begin
    C.FillRoundRect(Bounds.X - 3, Bounds.Y - 3, Bounds.W + 6, Bounds.H + 6, Theme.Radius + 3, Theme.FocusRing);
    Border := Theme.Accent;
  end
  else if IsHovered and Enabled then
    Border := Theme.BorderHover
  else
    Border := Theme.Border;
  if Enabled and not FReadOnly then
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Surface)
  else
    C.FillRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, Theme.Secondary);
  C.StrokeRoundRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, Theme.Radius, 1, Border);
  C.PushClip(RectI(R.X - 1, Bounds.Y + 1, R.W + 2, Bounds.H - 2));
  if FText = '' then
  begin
    if FMultiLine then Y := R.Y else Y := R.Y + (R.H - LH) div 2;
    C.DrawText(F, R.X, Y, FPlaceholder, Theme.Placeholder);
  end;
  SA := SelStartPos;
  SB := Max(FCaret, FAnchor);
  for I := 0 to High(FVisual) do
  begin
    if FMultiLine then
      Y := R.Y + I * LH - FScrollY
    else
      Y := R.Y + (R.H - LH) div 2;
    if (Y + LH < Bounds.Y) or (Y > Bounds.Y + Bounds.H) then
      Continue;
    LineStart := FVisual[I].StartPos;
    LineEnd := FVisual[I].EndPos;
    S := Copy(FText, LineStart, LineEnd - LineStart);
    { selection }
    if (SB > SA) and (SA <= LineEnd) and (SB >= LineStart) then
    begin
      X1 := F.TextWidth(DisplayText(Copy(S, 1, Max(SA, LineStart) - LineStart)));
      X2 := F.TextWidth(DisplayText(Copy(S, 1, Min(SB, LineEnd) - LineStart)));
      if (SB > LineEnd) and FMultiLine and (LineEnd <= Length(FText)) and (FText[LineEnd] = #10) then
        Inc(X2, 6);       { the line break is selected too }
      if IsFocused then
        C.FillRect(R.X + X1 - FScrollX, Y, Max(1, X2 - X1), LH, WithAlpha(Theme.Accent, $50))
      else
        C.FillRect(R.X + X1 - FScrollX, Y, Max(1, X2 - X1), LH, WithAlpha(Theme.TextMuted, $38));
    end;
    if Enabled then
      C.DrawText(F, R.X - FScrollX, Y, DisplayText(S), Theme.Text)
    else
      C.DrawText(F, R.X - FScrollX, Y, DisplayText(S), Theme.Disabled);
  end;
  if IsFocused and CaretVisible and not FReadOnly then
  begin
    I := LineOf(FCaret);
    if FMultiLine then Y := R.Y + I * LH - FScrollY else Y := R.Y + (R.H - LH) div 2;
    C.FillRect(R.X + XOf(FCaret) - FScrollX, Y, 1, LH, Theme.Text);
  end;
  C.PopClip;
  { a thin scroll bar when the text is taller than the box }
  if FMultiLine and (Length(FVisual) * LH > R.H) then
  begin
    X1 := Max(20, R.H * R.H div (Length(FVisual) * LH));
    X2 := (R.H - X1) * FScrollY div Max(1, Length(FVisual) * LH - R.H);
    C.FillRoundRect(Bounds.X + Bounds.W - 7, R.Y + X2, 4, X1, 2, WithAlpha(Theme.TextMuted, $80));
  end;
end;

function TCustomEdit.Focusable: Boolean;
begin
  Result := Enabled;
end;

function TCustomEdit.Cursor: TCursorKind;
begin
  Result := ckIBeam;
end;

procedure TCustomEdit.MoveCaret(P: Integer; Extend: Boolean);
begin
  FCaret := EnsureRange(P, 1, Length(FText) + 1);
  if not Extend then
    FAnchor := FCaret;
  FLastWasTyping := False;
  CaretVisible := True;
  FScrollToCaret := True;
  Invalidate;
end;

procedure TCustomEdit.MouseDown(X, Y: Integer);
var
  P, A, B: Integer;
  F: TForm;
begin
  F := ParentForm;
  P := PosAt(X, Y);
  FDesiredX := -1;
  if (F <> nil) and (F.ClickCount >= 3) then
  begin
    { the whole line (memo) or text (edit) }
    if FMultiLine then
    begin
      A := P;
      while (A > 1) and (FText[A - 1] <> #10) do
        Dec(A);
      B := Pos(#10, FText, P);
      if B = 0 then B := Length(FText) + 1;
      FAnchor := A;
      FCaret := B;
    end
    else
      SelectAll;
  end
  else if (F <> nil) and (F.ClickCount = 2) then
  begin
    A := P;
    B := P;
    while IsWordChar(FText, A - 1) do
      Dec(A);
    while IsWordChar(FText, B) do
      Inc(B);
    FAnchor := A;
    FCaret := B;
  end
  else
    MoveCaret(P, (F <> nil) and F.ShiftDown);
  FSelecting := True;
  CaretVisible := True;
  Invalidate;
end;

procedure TCustomEdit.MouseMove(X, Y: Integer);
var
  F: TForm;
begin
  F := ParentForm;
  if FSelecting and (F <> nil) and (F.Captured = Self) then
  begin
    FCaret := PosAt(X, Y);
    FScrollToCaret := True;
    Invalidate;
  end;
end;

procedure TCustomEdit.MouseUp(X, Y: Integer; Inside: Boolean);
begin
  FSelecting := False;
end;

function TCustomEdit.MouseWheel(DX, DY: Integer): Boolean;
var
  Total: Integer;
begin
  Result := FMultiLine;
  if not Result then
    Exit;
  EnsureLines;
  Total := Length(FVisual) * Font.LineHeight - InnerRect.H;
  if Total <= 0 then
    Exit(False);
  FScrollY := EnsureRange(FScrollY - DY * Font.LineHeight * 3, 0, Total);
  Invalidate;
end;

procedure TCustomEdit.TextInput(const S: string);
begin
  ReplaceSelection(S, True);
end;

function TCustomEdit.WordLeft(P: Integer): Integer;
begin
  Result := P;
  while (Result > 1) and not IsWordChar(FText, Result - 1) do
    Dec(Result);
  while (Result > 1) and IsWordChar(FText, Result - 1) do
    Dec(Result);
end;

function TCustomEdit.WordRight(P: Integer): Integer;
begin
  Result := P;
  while (Result <= Length(FText)) and not IsWordChar(FText, Result) do
    Inc(Result);
  while (Result <= Length(FText)) and IsWordChar(FText, Result) do
    Inc(Result);
end;

function TCustomEdit.VerticalPos(P, Lines: Integer): Integer;
var
  L, X: Integer;
  S: string;
begin
  EnsureLines;
  if FDesiredX < 0 then
    FDesiredX := XOf(P);
  X := FDesiredX;
  L := LineOf(P) + Lines;
  if L < 0 then
    Exit(1);
  if L > High(FVisual) then
    Exit(Length(FText) + 1);
  S := Copy(FText, FVisual[L].StartPos, FVisual[L].EndPos - FVisual[L].StartPos);
  Result := FVisual[L].StartPos - 1 + SourcePos(S, Font.HitTest(DisplayText(S), X));
end;

function TCustomEdit.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
var
  P, L, PageLines: Integer;
  KeepX: Boolean;
begin
  Result := True;
  CaretVisible := True;
  KeepX := False;
  EnsureLines;
  PageLines := Max(1, InnerRect.H div Font.LineHeight - 1);
  case Key of
    KEY_LEFT:
      if (GetSelLength > 0) and not Shift then
        MoveCaret(SelStartPos, False)
      else if Ctrl then
        MoveCaret(WordLeft(FCaret), Shift)
      else if FCaret > 1 then
        MoveCaret(PrevCharStart(FText, FCaret), Shift);
    KEY_RIGHT:
      if (GetSelLength > 0) and not Shift then
        MoveCaret(Max(FCaret, FAnchor), False)
      else if Ctrl then
        MoveCaret(WordRight(FCaret), Shift)
      else
        MoveCaret(NextCharStart(FText, FCaret), Shift);
    KEY_UP:
      if FMultiLine then
      begin
        P := VerticalPos(FCaret, -1);
        MoveCaret(P, Shift);
        KeepX := True;
      end
      else
        Result := False;
    KEY_DOWN:
      if FMultiLine then
      begin
        P := VerticalPos(FCaret, 1);
        MoveCaret(P, Shift);
        KeepX := True;
      end
      else
        Result := False;
    KEY_PAGEUP:
      if FMultiLine then
      begin
        MoveCaret(VerticalPos(FCaret, -PageLines), Shift);
        KeepX := True;
      end
      else
        Result := False;
    KEY_PAGEDOWN:
      if FMultiLine then
      begin
        MoveCaret(VerticalPos(FCaret, PageLines), Shift);
        KeepX := True;
      end
      else
        Result := False;
    KEY_HOME:
      if Ctrl or not FMultiLine then
        MoveCaret(1, Shift)
      else
        MoveCaret(FVisual[LineOf(FCaret)].StartPos, Shift);
    KEY_END:
      if Ctrl or not FMultiLine then
        MoveCaret(Length(FText) + 1, Shift)
      else
      begin
        L := LineOf(FCaret);
        P := FVisual[L].EndPos;
        { at a wrapped line's end the caret stays before the next line's first letter }
        if (P > FVisual[L].StartPos) and (P <= Length(FText)) and (FText[P - 1] = ' ') and
           (L < High(FVisual)) and (FVisual[L + 1].StartPos = P) then
          Dec(P);
        MoveCaret(P, Shift);
      end;
    KEY_BACKSPACE:
      if FReadOnly then
        Result := True
      else if GetSelLength > 0 then
        ReplaceSelection('', False)
      else if FCaret > 1 then
      begin
        if Ctrl then FAnchor := WordLeft(FCaret) else FAnchor := PrevCharStart(FText, FCaret);
        ReplaceSelection('', False);
      end;
    KEY_DELETE:
      if FReadOnly then
        Result := True
      else if GetSelLength > 0 then
        ReplaceSelection('', False)
      else if FCaret <= Length(FText) then
      begin
        if Ctrl then FAnchor := WordRight(FCaret) else FAnchor := NextCharStart(FText, FCaret);
        ReplaceSelection('', False);
      end;
    KEY_ENTER, KEY_KP_ENTER:
      if FMultiLine and not Ctrl then
        ReplaceSelection(#10, False)
      else if Assigned(FOnSubmit) then
        FOnSubmit(Self)
      else
        Result := False;     { a dialog's default button may want it }
  else
    Result := False;
    if Ctrl then
    begin
      Result := True;
      case Key of
        Ord('a'): SelectAll;
        Ord('c'): CopyToClipboard;
        Ord('x'): CutToClipboard;
        Ord('v'): PasteFromClipboard;
        Ord('z'): if Shift then Redo else Undo;
        Ord('y'): Redo;
      else
        Result := False;
      end;
      if Result then
        FScrollToCaret := True;
    end;
  end;
  if not KeepX then
    FDesiredX := -1;
  if Result then
  begin
    FScrollToCaret := True;
    Invalidate;
  end;
end;

{ ---- TEdit, TMemo ---- }

constructor TMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMultiLine := True;
  FWordWrap := True;
end;
