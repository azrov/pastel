{ Tests for src/services/textstats.pas. Run them with: pastel test }
unit TextStats_Test;

{$mode objfpc}{$H+}

interface

uses
  Pastel.Testing, TextStats;

type
  TTextStatsTests = class(TTestSuite)
  published
    procedure CountsWords;
    procedure CountsLines;
  end;

implementation

procedure TTextStatsTests.CountsWords;
begin
  AssertEquals(0, WordCount(''));
  AssertEquals(0, WordCount('  '#10));
  AssertEquals(2, WordCount('Merhaba dünya'));
  AssertEquals(4, WordCount('  Hello Pastel'#10'second'#9'line '));
end;

procedure TTextStatsTests.CountsLines;
begin
  AssertEquals(1, LineCount(''));
  AssertEquals(2, LineCount('a'#10'b'));
  AssertEquals(3, LineCount('a'#10#10));
end;

initialization
  RegisterTests(TTextStatsTests);
end.
