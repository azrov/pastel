{ Tests for src/services/duplicates.pas. Run them with: pastel test }
unit Duplicates_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.Files, Duplicates;

type
  TDuplicatesTests = class(TTestSuite)
  private
    Dir: string;
    procedure BadSize;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ReadsSizes;
    procedure RejectsNonsenseSizes;
    procedure OnlySameSizeFilesAreCandidates;
    procedure FindsFilesWithEqualContent;
    procedure BiggestWasteFirst;
    procedure IgnoresSmallFiles;
  end;

implementation

procedure TDuplicatesTests.SetUp;
begin
  Dir := MakeTempDir('dupfinder-test');
  WriteText(Dir + 'a.txt', 'hello');
  WriteText(JoinPath([Dir, 'sub', 'b.txt']), 'hello');
  WriteText(Dir + 'c.txt', 'hellp');           { same size, other content }
  WriteText(Dir + 'd.txt', 'unique size');
  WriteText(Dir + 'big1.bin', StringOfChar('x', 1000));
  WriteText(Dir + 'big2.bin', StringOfChar('x', 1000));
  WriteText(Dir + 'big3.bin', StringOfChar('x', 1000));
  WriteText(Dir + 'empty1.txt', '');
  WriteText(Dir + 'empty2.txt', '');
end;

procedure TDuplicatesTests.TearDown;
begin
  DeleteDir(Dir);
end;

procedure TDuplicatesTests.ReadsSizes;
begin
  AssertEquals(500, ParseSize('500'));
  AssertEquals(1024, ParseSize('1k'));
  AssertEquals(2621440, ParseSize('2.5M'));
  AssertEquals(10485760, ParseSize('10MB'));
  AssertEquals(Int64(1073741824), ParseSize('1G'));
end;

procedure TDuplicatesTests.BadSize;
begin
  ParseSize('lots');
end;

procedure TDuplicatesTests.RejectsNonsenseSizes;
begin
  AssertRaises(EConvertError, @BadSize);
end;

procedure TDuplicatesTests.OnlySameSizeFilesAreCandidates;
var
  C: TStringArray;
begin
  C := SameSizeFiles(ListFiles(Dir, '*', True), 1);
  { a, b, c (5 bytes) and the three big ones; not d, not the empty files }
  AssertEquals(6, Length(C));
end;

procedure TDuplicatesTests.FindsFilesWithEqualContent;
var
  G: TDupGroups;
begin
  G := FindDuplicates(ListFiles(Dir, '*', True), 1);
  AssertEquals(2, Length(G));
  AssertEquals(2, Length(G[1].Files));
  AssertEquals(5, G[1].Size);
  AssertContains('a.txt', G[1].Files[0]);
  AssertContains('b.txt', G[1].Files[1]);
end;

procedure TDuplicatesTests.BiggestWasteFirst;
var
  G: TDupGroups;
begin
  G := FindDuplicates(ListFiles(Dir, '*', True), 1);
  AssertEquals(3, Length(G[0].Files));
  AssertEquals(2000, Wasted(G[0]));
end;

procedure TDuplicatesTests.IgnoresSmallFiles;
begin
  AssertEquals(1, Length(FindDuplicates(ListFiles(Dir, '*', True), 100)));
end;

initialization
  RegisterTests(TDuplicatesTests);
end.
