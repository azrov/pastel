{ pastel-perf - measures what tests/perf.sh reports.

    pastel-perf load <port> <seconds> <threads>   requests per second against GET /health
    pastel-perf draw <frames>                     frames per second of a form with many controls
    pastel-perf hello                             does nothing (start-up time) }
program pastel_perf;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, ssockets, Pastel.Graphics, Pastel.UI, Pastel.Controls, Pastel.Grids;

type
  TLoader = class(TThread)
  public
    Port: Integer;
    Until_: QWord;
    Done, Failed: Integer;
    procedure Execute; override;
  end;

procedure TLoader.Execute;
const
  Req = 'GET /health HTTP/1.1'#13#10'Host: localhost'#13#10'Connection: close'#13#10#13#10;
var
  S: TInetSocket;
  Buf: array[0..2047] of Char;
  N, Total: Integer;
  First: string;
begin
  while GetTickCount64 < Until_ do
  begin
    try
      S := TInetSocket.Create('127.0.0.1', Port);
      try
        S.WriteBuffer(Req[1], Length(Req));
        Total := 0;
        First := '';
        repeat
          N := S.Read(Buf, SizeOf(Buf));
          if N > 0 then
          begin
            if Total = 0 then
              First := Copy(Buf, 0, N);
            Inc(Total, N);
          end;
        until N <= 0;
        if Copy(First, 1, 12) = 'HTTP/1.1 200' then
          Inc(Done)
        else
        begin
          if (Failed = 0) and (GetEnvironmentVariable('PERF_DEBUG') = '1') then
            WriteLn(StdErr, 'failed: ', Total, ' bytes: ', Copy(First, 1, 60));
          Inc(Failed);
        end;
      finally
        S.Free;
      end;
    except
      on E: Exception do
      begin
        if (Failed = 0) and (GetEnvironmentVariable('PERF_DEBUG') = '1') then
          WriteLn(StdErr, 'failed: ', E.Message);
        Inc(Failed);
      end;
    end;
  end;
end;

procedure Load(Port, Seconds, Threads: Integer);
var
  L: array of TLoader;
  I, Done, Failed: Integer;
  Started: QWord;
begin
  SetLength(L, Threads);
  Started := GetTickCount64;
  for I := 0 to Threads - 1 do
  begin
    L[I] := TLoader.Create(True);
    L[I].Port := Port;
    L[I].Until_ := Started + QWord(Seconds) * 1000;
    L[I].Start;
  end;
  Done := 0;
  Failed := 0;
  for I := 0 to Threads - 1 do
  begin
    L[I].WaitFor;
    Inc(Done, L[I].Done);
    Inc(Failed, L[I].Failed);
    L[I].Free;
  end;
  WriteLn(Format('requests_per_second %d', [Round(Done / ((GetTickCount64 - Started) / 1000))]));
  WriteLn(Format('failed %d', [Failed]));
end;

function Max(A, B: Double): Double;
begin
  if A > B then Result := A else Result := B;
end;

procedure Draw(Frames: Integer);
var
  Form: TForm;
  C: TCanvas32;
  Row: TRow;
  G: TGrid;
  I: Integer;
  T: QWord;
  E: TEdit;
begin
  InitFonts;
  Form := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    for I := 1 to 6 do
    begin
      Row := TRow.Create(Form);
      Row.Parent := Form;
      Row.Gap := 8;
      with TLabel.Create(Form) do begin Parent := Row; Text := Format('Field %d', [I]); end;
      E := TEdit.Create(Form);
      E.Parent := Row;
      E.Text := 'Some text to draw';
      E.Grow := 1;
      with TCheckBox.Create(Form) do begin Parent := Row; Text := 'Active'; Checked := Odd(I); end;
      with TButton.Create(Form) do begin Parent := Row; Text := 'Save'; end;
    end;
    G := TGrid.Create(Form);
    G.Parent := Form;
    G.Grow := 1;
    G.AddColumn('Name');
    G.AddColumn('City', 120);
    G.AddColumn('Total', 90, taRight);
    for I := 1 to 10000 do
      G.AddRow([Format('Customer %d', [I]), 'İstanbul', Format('%d,00', [I * 7])]);
    Form.Layout(1024, 768);
    C.SetSize(1024, 768);
    { everything, every frame }
    T := GetTickCount64;
    for I := 1 to Frames do
      Form.Render(C);
    WriteLn(Format('full_frames_per_second %d', [Round(Frames / Max(0.001, (GetTickCount64 - T) / 1000))]));
    { a blinking caret: only the edit }
    E.SetFocus;
    Form.Render(C);
    T := GetTickCount64;
    for I := 1 to Frames do
    begin
      E.Invalidate;
      Form.RenderArea(C, DirtyArea);
    end;
    WriteLn(Format('partial_frames_per_second %d', [Round(Frames / Max(0.001, (GetTickCount64 - T) / 1000))]));
  finally
    C.Free;
    Form.Free;
  end;
end;

begin
  if ParamCount = 0 then
  begin
    WriteLn('use: pastel-perf load <port> <seconds> <threads> | draw <frames> | hello');
    Halt(2);
  end;
  case ParamStr(1) of
    'load': Load(StrToInt(ParamStr(2)), StrToInt(ParamStr(3)), StrToInt(ParamStr(4)));
    'draw': Draw(StrToInt(ParamStr(2)));
    'hello': ;
  end;
end.
