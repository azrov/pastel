{ Pastel - what happens when an exception is not caught.

  Pastel adds this unit to every program automatically, after SysUtils.
  Instead of Free Pascal's
    An unhandled exception occurred at $0000000000462A8E:
    EConfigError: setting "port" must be a number, got "eighty"
      $0000000000462A8E
  the program prints
    error: setting "port" must be a number, got "eighty"
  and ends with exit code 1. Debug builds also show where it happened.
  Part of the Pastel project, MIT License. }
unit Pastel.ErrorExit;

{$mode objfpc}{$H+}

interface

implementation

uses
  SysUtils;

procedure ShowError(Obj: TObject; Addr: CodePointer; FrameCount: Longint; Frame: PCodePointer);
var
  Msg: string;
  {$IFDEF PASTEL_DEBUG}
  I: Integer;
  {$ENDIF}
begin
  if Obj is Exception then
  begin
    Msg := Exception(Obj).Message;
    { the class name only where it says something the message does not }
    if (Obj is EAccessViolation) or (Obj is EInvalidPointer) or (Obj is EStackOverflow) or
       (Obj is EOutOfMemory) or (Msg = '') then
      Msg := Obj.ClassName + ': ' + Msg;
  end
  else if Obj <> nil then
    Msg := Obj.ClassName
  else
    Msg := 'unknown error';
  try
    Flush(Output);
    WriteLn(StdErr, 'error: ', Msg);
    {$IFDEF PASTEL_DEBUG}
    WriteLn(StdErr, '  at', BackTraceStrFunc(Addr));
    for I := 0 to FrameCount - 1 do
      WriteLn(StdErr, '    ', BackTraceStrFunc(Frame[I]));
    {$ENDIF}
    Flush(StdErr);
  except
  end;
  Halt(1);
end;

initialization
  ExceptProc := @ShowError;
end.
