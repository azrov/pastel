unit Files_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Files;

type
  TFilesTests = class(TTestSuite)
  private
    Dir: string;
    procedure ReadMissing;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure WritesAndReadsUtf8Text;
    procedure WriteCreatesFoldersAndLeavesNoTempFile;
    procedure AppendsText;
    procedure ReadsAndWritesLines;
    procedure ReadsAndWritesBytes;
    procedure SkipsByteOrderMark;
    procedure MissingFileGivesClearError;
    procedure ListsFilesSortedAndRecursive;
    procedure ListsFolders;
    procedure CopiesMovesAndDeletes;
    procedure DeletesWholeFolder;
    procedure JoinsPaths;
    procedure FormatsSizes;
    procedure KnowsSizeAndRelativePath;
  end;

implementation

procedure TFilesTests.SetUp;
begin
  Dir := MakeTempDir('pastel-files-test');
end;

procedure TFilesTests.TearDown;
begin
  DeleteDir(Dir);
end;

procedure TFilesTests.WritesAndReadsUtf8Text;
begin
  WriteText(Dir + 'a.txt', 'Çiğdem ağacı' + LineEnding);
  AssertEquals('Çiğdem ağacı' + LineEnding, ReadText(Dir + 'a.txt'));
  WriteText(Dir + 'a.txt', 'yeni');
  AssertEquals('yeni', ReadText(Dir + 'a.txt'));
  WriteText(Dir + 'empty.txt', '');
  AssertEquals('', ReadText(Dir + 'empty.txt'));
end;

procedure TFilesTests.WriteCreatesFoldersAndLeavesNoTempFile;
begin
  WriteText(JoinPath([Dir, 'x', 'y', 'z.txt']), 'deep');
  AssertEquals('deep', ReadText(JoinPath([Dir, 'x', 'y', 'z.txt'])));
  AssertEquals(1, Length(ListFiles(JoinPath([Dir, 'x', 'y']))));
end;

procedure TFilesTests.AppendsText;
begin
  AppendText(Dir + 'log/app.log', 'one' + #10);
  AppendText(Dir + 'log/app.log', 'two' + #10);
  AssertEquals('one'#10'two'#10, ReadText(Dir + 'log/app.log'));
end;

procedure TFilesTests.ReadsAndWritesLines;
var
  L: TStringArray;
begin
  WriteLines(Dir + 'l.txt', ['bir', 'iki', 'üç']);
  L := ReadLines(Dir + 'l.txt');
  AssertEquals(3, Length(L));
  AssertEquals('üç', L[2]);
end;

procedure TFilesTests.ReadsAndWritesBytes;
var
  B: TBytes;
begin
  B := nil;
  SetLength(B, 3);
  B[0] := 0; B[1] := 255; B[2] := 10;
  WriteBytes(Dir + 'b.bin', B);
  B := ReadBytes(Dir + 'b.bin');
  AssertEquals(3, Length(B));
  AssertEquals(255, B[1]);
  AssertEquals(3, FileSize(Dir + 'b.bin'));
end;

procedure TFilesTests.SkipsByteOrderMark;
begin
  WriteText(Dir + 'bom.txt', #$EF#$BB#$BF'merhaba');
  AssertEquals('merhaba', ReadText(Dir + 'bom.txt'));
end;

procedure TFilesTests.ReadMissing;
begin
  ReadText(Dir + 'nope.txt');
end;

procedure TFilesTests.MissingFileGivesClearError;
begin
  AssertRaises(EFileError, @ReadMissing);
  try
    ReadMissing;
  except
    on E: EFileError do
    begin
      AssertContains('nope.txt', E.Message);
      AssertContains('cannot read', E.Message);
    end;
  end;
end;

procedure TFilesTests.ListsFilesSortedAndRecursive;
var
  L: TStringArray;
begin
  WriteText(Dir + 'b.txt', '');
  WriteText(Dir + 'a.txt', '');
  WriteText(Dir + 'c.log', '');
  WriteText(JoinPath([Dir, 'sub', 'd.txt']), '');
  L := ListFiles(Dir, '*.txt');
  AssertEquals(2, Length(L));
  AssertEquals('a.txt', ExtractFileName(L[0]));
  AssertEquals('b.txt', ExtractFileName(L[1]));
  L := ListFiles(Dir, '*.txt', True);
  AssertEquals(3, Length(L));
  AssertEquals(4, Length(ListFiles(Dir, '*', True)));
end;

procedure TFilesTests.ListsFolders;
var
  L: TStringArray;
begin
  EnsureDir(Dir + 'beta');
  EnsureDir(Dir + 'alfa');
  WriteText(Dir + 'file.txt', '');
  L := ListDirs(Dir);
  AssertEquals(2, Length(L));
  AssertEquals('alfa', ExtractFileName(L[0]));
end;

procedure TFilesTests.CopiesMovesAndDeletes;
begin
  WriteText(Dir + 'src.txt', 'data');
  CopyFile(Dir + 'src.txt', JoinPath([Dir, 'copy', 'dst.txt']));
  AssertEquals('data', ReadText(JoinPath([Dir, 'copy', 'dst.txt'])));
  MoveFile(Dir + 'src.txt', Dir + 'moved.txt');
  AssertFalse(FileExists(Dir + 'src.txt'));
  AssertEquals('data', ReadText(Dir + 'moved.txt'));
  DeleteFileIfExists(Dir + 'moved.txt');
  DeleteFileIfExists(Dir + 'moved.txt');
  AssertFalse(FileExists(Dir + 'moved.txt'));
end;

procedure TFilesTests.DeletesWholeFolder;
begin
  WriteText(JoinPath([Dir, 'tree', 'a', 'b', 'c.txt']), 'x');
  WriteText(JoinPath([Dir, 'tree', 'd.txt']), 'x');
  DeleteDir(Dir + 'tree');
  AssertFalse(DirectoryExists(Dir + 'tree'));
end;

procedure TFilesTests.JoinsPaths;
var
  S: string;
begin
  S := DirectorySeparator;
  AssertEquals('data' + S + 'users' + S + 'ali.json', JoinPath(['data', 'users', 'ali.json']));
  AssertEquals('data' + S + 'x', JoinPath(['data/', '/x']));
  AssertEquals('a' + S + 'b', JoinPath(['', 'a', '', 'b']));
end;

procedure TFilesTests.FormatsSizes;
begin
  AssertEquals('0 B', FormatSize(0));
  AssertEquals('1023 B', FormatSize(1023));
  AssertEquals('1.5 KB', FormatSize(1536));
  AssertEquals('1.2 GB', FormatSize(1300000000));
  AssertEquals('500 MB', FormatSize(500 * 1024 * 1024));
end;

procedure TFilesTests.KnowsSizeAndRelativePath;
begin
  WriteText(JoinPath([Dir, 'r', 'x.txt']), 'ağaç');
  AssertEquals(6, FileSize(JoinPath([Dir, 'r', 'x.txt'])));
  AssertEquals(JoinPath(['r', 'x.txt']), RelativePath(JoinPath([Dir, 'r', 'x.txt']), Dir));
  AssertTrue(FileModified(JoinPath([Dir, 'r', 'x.txt'])) > Now - 1);
  AssertTrue(DirectoryExists(AppDir));
end;

initialization
  RegisterTests(TFilesTests);
end.
