{ Unit tests for Pastel.Logcat: an Android app's log by its package name. Run with: sh tests/run.sh }
program logcat_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Pastel.Logcat;

var
  Passed, Failed: Integer;

procedure Check(const Name: string; Ok: Boolean);
begin
  if Ok then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    WriteLn('FAIL: ', Name);
  end;
end;

var
  L: TLogLine;
  F: TAppLogFilter;
  P: TStringArray;
begin
  L := ParseLogLine('11-07 15:43:01.123  1234  1250 E AndroidRuntime: FATAL EXCEPTION: main');
  Check('a line: pid, level, tag, text', L.Valid and (L.Pid = '1234') and (L.Level = 'E') and (L.Tag = 'AndroidRuntime') and
    (L.Text = 'FATAL EXCEPTION: main') and (L.Time = '15:43:01'));
  L := ParseLogLine('11-07 15:43:01.123  1234  1250 I chatty  : uid=10123 expire 3 lines');
  Check('a tag with spaces after it', L.Valid and (L.Tag = 'chatty') and (L.Text = 'uid=10123 expire 3 lines'));
  Check('not a log line', not ParseLogLine('--------- beginning of crash').Valid);
  Check('the short form', ShortLogLine(ParseLogLine('11-07 15:43:01.123  1234  1250 W pastel: hello')) = '15:43:01 W pastel: hello');

  F := TAppLogFilter.Create('dev.pastel.shop');
  try
    Check('the start of the app (Android 7 and newer)', F.Keep(ParseLogLine(
      '11-07 15:43:00.000   500   520 I ActivityManager: Start proc 4321:dev.pastel.shop/u0a123 for activity {...}')));
    Check('teaches its process id', F.Pids.IndexOf('4321') >= 0);
    Check('its lines are kept', F.Keep(ParseLogLine('11-07 15:43:01.000  4321  4330 F libc    : Fatal signal 11 (SIGSEGV)')));
    Check('others are not', not F.Keep(ParseLogLine('11-07 15:43:01.000  999  999 I Other: something')));
    Check('crash reports are', F.Keep(ParseLogLine('11-07 15:43:02.000  7777  7777 F DEBUG   : backtrace:')));
    Check('its end is', F.Keep(ParseLogLine('11-07 15:43:03.000   500   520 I ActivityManager: Process dev.pastel.shop (pid 4321) has died')));
    F.Keep(ParseLogLine('11-07 15:43:00.000   500   520 I ActivityManager: Start proc dev.pastel.shop for activity dev.pastel.shop/dev.pastel.PastelActivity: pid=5555 uid=10123 gids={}'));
    Check('Android 4 and 5 say it differently', F.Pids.IndexOf('5555') >= 0);
  finally
    F.Free;
  end;

  P := PidsOf('USER     PID   PPID  VSIZE  RSS   WCHAN    PC         NAME' + LineEnding +
    'u0_a123   4321  200   1000   100   ffffffff 00000000 S dev.pastel.shop' + LineEnding +
    'u0_a123   4400  200   1000   100   ffffffff 00000000 S dev.pastel.shop:remote' + LineEnding +
    'u0_a124   4500  200   1000   100   ffffffff 00000000 S dev.pastel.shopping', 'dev.pastel.shop');
  Check('process ids from ps', (Length(P) = 2) and (P[0] = '4321') and (P[1] = '4400'));
  P := PidsOf('4321' + LineEnding, 'dev.pastel.shop');
  Check('and from pidof', (Length(P) = 1) and (P[0] = '4321'));

  WriteLn(Format('logcat: %d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
