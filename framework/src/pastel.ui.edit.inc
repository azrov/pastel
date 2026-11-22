{ Pastel.UI: TCustomEdit, the text editing shared by TEdit and TMemo.
  Included by pastel.ui.pas. }

const
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

function TCustomEdit.WantsKeyboard: Boolean;
begin
  Result := True;
end;

function TCustomEdit.KeyboardKind: TKeyboardType;
begin
  Result := FKeyboardType;
  if Result = ktDefault then
    Result := ktText;
end;

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
  FCompletions.Free;
  inherited Destroy;
end;

{ ---- syntax highlighting ---- }

function SyntaxColor(Kind: TSyntaxKind): TColor32;
begin
  if Theme.Dark then
    case Kind of
      skKeyword: Result := RGB($C7, $92, $EA);
      skString: Result := RGB($A5, $D6, $86);
      skNumber: Result := RGB($F7, $8C, $6C);
      skComment: Result := RGB($80, $8A, $98);
      skName: Result := RGB($82, $AA, $FF);
      skSymbol: Result := RGB($89, $DD, $FF);
      skError: Result := RGB($FF, $6B, $6B);
    else
      Result := Theme.Text;
    end
  else
    case Kind of
      skKeyword: Result := RGB($7C, $3A, $ED);
      skString: Result := RGB($15, $80, $3D);
      skNumber: Result := RGB($C2, $41, $0C);
      skComment: Result := RGB($6B, $72, $80);
      skName: Result := RGB($1D, $4E, $D8);
      skSymbol: Result := RGB($0E, $74, $90);
      skError: Result := RGB($DC, $26, $26);
    else
      Result := Theme.Text;
    end;
end;

procedure TCustomEdit.SetOnHighlight(AValue: THighlightEvent);
begin
  FOnHighlight := AValue;
  RehighlightText;
end;

procedure TCustomEdit.RehighlightText;
begin
  FHighlighted := False;
  Invalidate;
end;

procedure TCustomEdit.Highlight;
var
  Spans: TSyntaxSpans;
  I, J, Last: Integer;
begin
  if FHighlighted and (FHighlightFor = FText) then
    Exit;
  FHighlightFor := FText;
  FHighlighted := True;
  SetLength(FKinds, Length(FText));
  for I := 0 to High(FKinds) do
    FKinds[I] := skText;
  Spans := nil;
  FOnHighlight(Self, FText, Spans);
  for I := 0 to High(Spans) do
  begin
    Last := Min(Length(FText), Spans[I].Start + Spans[I].Len - 1);
    for J := Max(1, Spans[I].Start) to Last do
      FKinds[J - 1] := Spans[I].Kind;
  end;
end;

{ one visual line in runs of one color each }
procedure TCustomEdit.DrawLine(C: TCanvas32; F: TPastelFont; X, Y: Integer; const S: string; LineStart: Integer);
var
  A, B, N: Integer;
  K: TSyntaxKind;
begin
  if not Enabled then
  begin
    C.DrawText(F, X, Y, DisplayText(S), Theme.Disabled);
    Exit;
  end;
  if not Assigned(FOnHighlight) or FPassword or (S = '') then
  begin
    C.DrawText(F, X, Y, DisplayText(S), Theme.Text);
    Exit;
  end;
  Highlight;
  N := Length(S);
  A := 1;
  while A <= N do
  begin
    if LineStart + A - 2 <= High(FKinds) then
      K := FKinds[LineStart + A - 2]
    else
      K := skText;
    B := A + 1;
    while (B <= N) and (LineStart + B - 2 <= High(FKinds)) and (FKinds[LineStart + B - 2] = K) do
      Inc(B);
    { a letter's bytes stay together }
    while (B <= N) and ((Ord(S[B]) and $C0) = $80) do
      Inc(B);
    if Trim(Copy(S, A, B - A)) <> '' then
      C.DrawText(F, X + F.TextWidth(Copy(S, 1, A - 1)), Y, Copy(S, A, B - A), SyntaxColor(K));
    A := B;
  end;
end;

{ ---- completions ---- }

type
  { the list of words below the caret; picking one with the mouse gives the
    focus back to the edit }
  TCompletionList = class(TControl)
  private
    FEdit: TCustomEdit;
    FWords: TStringList;
    FChosen, FFirstRow: Integer;
    function RowHeight: Integer;
    function VisibleRows: Integer;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
    function Focusable: Boolean; override;
    procedure MouseDown(X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer); override;
    function MouseWheel(DX, DY: Integer): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure MoveBy(N: Integer);
  end;

constructor TCompletionList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWords := TStringList.Create;
end;

destructor TCompletionList.Destroy;
begin
  FWords.Free;
  inherited Destroy;
end;

function TCompletionList.RowHeight: Integer;
begin
  Result := GetFont(Theme.FontSize, False).LineHeight + 6;
end;

function TCompletionList.VisibleRows: Integer;
begin
  Result := Max(1, Min(FWords.Count, 8));
end;

procedure TCompletionList.Measure(AvailWidth: Integer; out W, H: Integer);
var
  I: Integer;
  F: TPastelFont;
begin
  F := GetFont(Theme.FontSize, False);
  W := 120;
  for I := 0 to FWords.Count - 1 do
    W := Max(W, F.TextWidth(FWords[I]) + 24);
  W := Min(W, Max(120, AvailWidth));
  H := VisibleRows * RowHeight;
end;

procedure TCompletionList.Paint(C: TCanvas32);
var
  I, Y, RH: Integer;
  F: TPastelFont;
begin
  F := GetFont(Theme.FontSize, False);
  RH := RowHeight;
  C.PushClip(Bounds);
  for I := FFirstRow to Min(FWords.Count - 1, FFirstRow + VisibleRows - 1) do
  begin
    Y := Bounds.Y + (I - FFirstRow) * RH;
    if I = FChosen then
      C.FillRoundRect(Bounds.X, Y, Bounds.W, RH, 4, Theme.Selection);
    C.DrawText(F, Bounds.X + 8, Y + 3, FWords[I], Theme.Text);
  end;
  C.PopClip;
end;

function TCompletionList.Focusable: Boolean;
begin
  Result := True;
end;

procedure TCompletionList.MouseDown(X, Y: Integer);
var
  I: Integer;
  E: TCustomEdit;
  F: TForm;
begin
  I := FFirstRow + (Y - Bounds.Y) div RowHeight;
  E := FEdit;
  F := E.ParentForm;
  if (I >= 0) and (I < FWords.Count) then
    E.Complete(FWords[I])
  else
    E.HideCompletions;
  if F <> nil then
    F.FocusControl(E);
end;

procedure TCompletionList.MouseMove(X, Y: Integer);
var
  I: Integer;
begin
  I := FFirstRow + (Y - Bounds.Y) div RowHeight;
  if (I >= 0) and (I < FWords.Count) and (I <> FChosen) then
  begin
    FChosen := I;
    Invalidate;
  end;
end;

function TCompletionList.MouseWheel(DX, DY: Integer): Boolean;
begin
  if DY > 0 then FFirstRow := Max(0, FFirstRow - 1)
  else if DY < 0 then FFirstRow := Max(0, Min(FWords.Count - VisibleRows, FFirstRow + 1));
  Invalidate;
  Result := True;
end;

procedure TCompletionList.MoveBy(N: Integer);
begin
  if FWords.Count = 0 then
    Exit;
  FChosen := (FChosen + N + FWords.Count) mod FWords.Count;
  if FChosen < FFirstRow then
    FFirstRow := FChosen;
  if FChosen >= FFirstRow + VisibleRows then
    FFirstRow := FChosen - VisibleRows + 1;
  Invalidate;
end;

function IsWordByte(C: Char): Boolean; inline;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', #128..#255];
end;

function TCustomEdit.GetCompletions: TStrings;
begin
  if FCompletions = nil then
  begin
    FCompletions := TStringList.Create;
    FCompletions.CaseSensitive := False;
  end;
  Result := FCompletions;
end;

procedure TCustomEdit.SetCompletions(AValue: TStrings);
begin
  GetCompletions.Assign(AValue);
end;

{ the word before the caret, with its dots ('orders.cu'); WordStart: where the
  part after the last dot begins }
function TCustomEdit.CompletionWord(out WordStart: Integer): string;
var
  P: Integer;
begin
  P := FCaret;
  while (P > 1) and IsWordByte(FText[P - 1]) do
    Dec(P);
  WordStart := P;
  while (P > 1) and ((FText[P - 1] = '.') or IsWordByte(FText[P - 1])) do
    Dec(P);
  Result := Copy(FText, P, FCaret - P);
end;

function TCustomEdit.CompletionsShown: Boolean;
begin
  Result := (FCompletePopup <> nil) and FCompletePopup.Shown;
end;

procedure TCustomEdit.HideCompletions;
begin
  if CompletionsShown then
    FCompletePopup.Close;
end;

procedure TCustomEdit.ShowCompletions;
begin
  UpdateCompletion(True);
end;

procedure TCustomEdit.UpdateCompletion(Asked: Boolean);
var
  Word, Part: string;
  All: TStringList;
  L: TCompletionList;
  F: TForm;
  I, Y, LH: Integer;
  R: TRectI;
begin
  if (FCompletions = nil) and not Assigned(FOnCompletions) then
    Exit;
  F := ParentForm;
  if (F = nil) or FReadOnly or FPassword or (GetSelLength > 0) then
  begin
    HideCompletions;
    Exit;
  end;
  Word := CompletionWord(FCompleteStart);
  Part := Copy(FText, FCompleteStart, FCaret - FCompleteStart);
  if (Part = '') and not Asked and ((Word = '') or (Word[Length(Word)] <> '.')) then
  begin
    HideCompletions;
    Exit;
  end;
  All := TStringList.Create;
  try
    if FCompletions <> nil then
      All.AddStrings(FCompletions);
    if Assigned(FOnCompletions) then
      FOnCompletions(Self, Word, All);
    if FCompletePopup = nil then
    begin
      FCompletePopup := TPopup.Create(Self);
      FCompletePopup.Padding := 4;
      L := TCompletionList.Create(FCompletePopup);
      L.FEdit := Self;
      L.Parent := FCompletePopup;
      FCompleteList := L;
    end;
    L := TCompletionList(FCompleteList);
    L.FWords.Clear;
    for I := 0 to All.Count - 1 do
      if (All[I] <> '') and SameText(Copy(All[I], 1, Length(Part)), Part) and
         (L.FWords.IndexOf(All[I]) < 0) then
        L.FWords.Add(All[I]);
  finally
    All.Free;
  end;
  { nothing to offer, or only what is typed already }
  if (L.FWords.Count = 0) or ((L.FWords.Count = 1) and (L.FWords[0] = Part) and not Asked) then
  begin
    HideCompletions;
    Exit;
  end;
  L.FChosen := 0;
  L.FFirstRow := 0;
  { first the ones with the very letters typed }
  for I := 0 to L.FWords.Count - 1 do
    if Copy(L.FWords[I], 1, Length(Part)) = Part then
    begin
      L.FChosen := I;
      Break;
    end;
  L.MoveBy(0);
  EnsureLines;
  LH := Font.LineHeight;
  R := InnerRect;
  I := LineOf(FCaret);
  if FMultiLine then Y := R.Y + I * LH - FScrollY else Y := R.Y + (R.H - LH) div 2;
  FCompletePopup.Width := 0;
  FCompletePopup.Popup(F, RectI(R.X + XOf(FCompleteStart) - FScrollX - 4, Y, 1, LH));
  L.Invalidate;
end;

procedure TCustomEdit.Complete(const Word: string);
var
  P: Integer;
begin
  HideCompletions;
  CompletionWord(P);
  FAnchor := P;
  ReplaceSelection(Word, False);
end;

procedure TCustomEdit.FocusLost;
var
  F: TForm;
begin
  inherited FocusLost;
  F := ParentForm;
  if (F = nil) or (F.Focused <> FCompleteList) or (FCompleteList = nil) then
    HideCompletions;
end;

function TCustomEdit.Font: TPastelFont;
var
  L: TStyleLook;
begin
  L := Look;
  if (L <> nil) and (L.FontSize > 0) then
    Result := GetFont(L.FontSize, L.Bold = 1)
  else
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

function TCustomEdit.NormalizeText(const S: string): string;
begin
  Result := S;
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
  V := NormalizeText(CleanText(StringReplace(AValue, #13#10, #10, [rfReplaceAll])));
  if FText = V then
    Exit;
  FText := V;
  FCaret := Length(FText) + 1;
  FAnchor := FCaret;
  FUndo := nil;
  FRedo := nil;
  { the size does not depend on the text; a memo lays out its lines again }
  if FMultiLine then Changed else Invalidate;
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
  if FError <> '' then
    Error := '';         { the user changes it: the problem may be gone }
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TCustomEdit.SetError(const AValue: string);
begin
  if FError = AValue then
    Exit;
  { the tooltip shows the problem, and the control's own hint again after }
  if FError = '' then
    FHintBefore := Hint;
  FError := AValue;
  if AValue = '' then
    Hint := FHintBefore
  else
    Hint := AValue;
  Invalidate;
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
var
  L: TStyleLook;
begin
  L := Look;
  if (L <> nil) and (L.PaddingX >= 0) then
    Result := L.PaddingX
  else if FMultiLine then
    Result := MemoPadding
  else
    Result := UIStyle.FieldPadX;
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
    H := FieldHeight(Font.LineHeight);
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
  PaintField(C, Bounds, IsFocused, IsHovered, Enabled, not FReadOnly, FError <> '', Look);
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
    DrawLine(C, F, R.X - FScrollX, Y, S, LineStart);
    { the word the phone's keyboard is still composing: underlined, as on the phone's own edits }
    if (FComposeStart > 0) and (FComposeText = FText) and (FComposeStart <= LineEnd) and (FComposeEnd > LineStart) then
    begin
      X1 := F.TextWidth(DisplayText(Copy(S, 1, Max(FComposeStart, LineStart) - LineStart)));
      X2 := F.TextWidth(DisplayText(Copy(S, 1, Min(FComposeEnd, LineEnd) - LineStart)));
      if X2 > X1 then
        C.FillRect(R.X + X1 - FScrollX, Y + LH - 2, X2 - X1, 1, Theme.Text);
    end;
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
  if (FCompletions <> nil) or Assigned(FOnCompletions) then
    if (S <> '') and (IsWordByte(S[Length(S)]) or (S[Length(S)] = '.')) then
      UpdateCompletion(False)
    else
      HideCompletions;
end;

function IsUtf8Tail(const S: string; I: Integer): Boolean; inline;
begin
  Result := (I >= 1) and (I <= Length(S)) and ((Ord(S[I]) and $C0) = $80);
end;

procedure TCustomEdit.ImeChange(const AText: string; ASelStart, ASelEnd, AComposeStart, AComposeEnd: Integer);
var
  P, S, N: Integer;
  Mid: string;

  { a byte position (0-based) on a letter's start }
  function OnLetter(const T: string; B: Integer): Integer;
  begin
    Result := EnsureRange(B, 0, Length(T));
    while (Result > 0) and IsUtf8Tail(T, Result + 1) do
      Dec(Result);
  end;

begin
  FComposeStart := 0;
  if AText <> FText then
  begin
    { what changed: the text between the parts both have at the start and the end }
    N := Min(Length(FText), Length(AText));
    P := 0;
    while (P < N) and (FText[P + 1] = AText[P + 1]) do
      Inc(P);
    while (P > 0) and (IsUtf8Tail(FText, P + 1) or IsUtf8Tail(AText, P + 1)) do
      Dec(P);
    S := 0;
    while (S < Length(FText) - P) and (S < Length(AText) - P) and
      (FText[Length(FText) - S] = AText[Length(AText) - S]) do
      Inc(S);
    while (S > 0) and (IsUtf8Tail(FText, Length(FText) - S + 1) or IsUtf8Tail(AText, Length(AText) - S + 1)) do
      Dec(S);
    Mid := Copy(AText, P + 1, Length(AText) - P - S);
    { that part of our text is selected and typed over, as a user would }
    FAnchor := P + 1;
    FCaret := Length(FText) - S + 1;
    if Mid <> '' then
      TextInput(Mid)
    else if FCaret > FAnchor then
      KeyDown(KEY_BACKSPACE, False, False);
  end;
  if AText = FText then
  begin
    FAnchor := OnLetter(FText, ASelStart) + 1;
    FCaret := OnLetter(FText, ASelEnd) + 1;
    if (AComposeStart >= 0) and (AComposeEnd > AComposeStart) then
    begin
      FComposeStart := OnLetter(FText, AComposeStart) + 1;
      FComposeEnd := OnLetter(FText, AComposeEnd) + 1;
      FComposeText := FText;
    end;
  end;
  FDesiredX := -1;
  CaretVisible := True;
  FScrollToCaret := True;
  Invalidate;
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
  if CompletionsShown then
    case Key of
      KEY_UP: begin TCompletionList(FCompleteList).MoveBy(-1); Exit; end;
      KEY_DOWN: begin TCompletionList(FCompleteList).MoveBy(1); Exit; end;
      KEY_PAGEUP: begin TCompletionList(FCompleteList).MoveBy(-7); Exit; end;
      KEY_PAGEDOWN: begin TCompletionList(FCompleteList).MoveBy(7); Exit; end;
      KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
        if not Ctrl and not Shift then
        begin
          with TCompletionList(FCompleteList) do
            Complete(FWords[FChosen]);
          Exit;
        end;
      KEY_ESCAPE:
        begin
          HideCompletions;
          Exit;
        end;
      KEY_BACKSPACE: ;
    else
      HideCompletions;
    end;
  if (Key = KEY_SPACE) and Ctrl and ((FCompletions <> nil) or Assigned(FOnCompletions)) then
  begin
    ShowCompletions;
    Exit;
  end;
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
  if (Key = KEY_BACKSPACE) and CompletionsShown then
    UpdateCompletion(False);
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
