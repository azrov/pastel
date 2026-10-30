{ Tests for src/services/notes.pas. Run them with: pastel test }
unit Notes_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Testing, Pastel.Json, Pastel.Files, Notes;

type
  TNotesTests = class(TTestSuite)
  private
    Dir: string;
    Store: TNoteStore;
    procedure AddWithoutTitle;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AddsAndFinds;
    procedure ListsNewestFirst;
    procedure UpdatesAndRemoves;
    procedure TitleIsRequired;
    procedure KeepsNotesInAFile;
  end;

implementation

procedure TNotesTests.SetUp;
begin
  Dir := MakeTempDir('notes-test');
  Store := TNoteStore.Create(Dir + 'notes.json');
end;

procedure TNotesTests.TearDown;
begin
  Store.Free;
  DeleteDir(Dir);
end;

procedure TNotesTests.AddsAndFinds;
var
  N: TJSONObject;
begin
  Store.Add('Alışveriş', 'süt, ekmek').Free;
  N := Store.Find(1);
  try
    AssertEquals('Alışveriş', JStr(N, 'title'));
    AssertEquals('süt, ekmek', JStr(N, 'text'));
    AssertNil(Store.Find(99));
  finally
    N.Free;
  end;
end;

procedure TNotesTests.ListsNewestFirst;
var
  L: TJSONArray;
begin
  Store.Add('first', '').Free;
  Store.Add('second', '').Free;
  L := Store.List;
  try
    AssertEquals(2, L.Count);
    AssertEquals('second', JStr(L, '[0].title'));
  finally
    L.Free;
  end;
end;

procedure TNotesTests.UpdatesAndRemoves;
begin
  Store.Add('old', '').Free;
  Store.Update(1, 'new', 'text').Free;
  AssertEquals(1, Store.Count);
  AssertNil(Store.Update(5, 'x', ''));
  AssertTrue(Store.Remove(1));
  AssertFalse(Store.Remove(1));
  AssertEquals(0, Store.Count);
end;

procedure TNotesTests.AddWithoutTitle;
begin
  Store.Add('   ', 'text');
end;

procedure TNotesTests.TitleIsRequired;
begin
  AssertRaises(ENoteError, @AddWithoutTitle);
end;

procedure TNotesTests.KeepsNotesInAFile;
var
  Again: TNoteStore;
begin
  Store.Add('kept', '').Free;
  Again := TNoteStore.Create(Dir + 'notes.json');
  try
    AssertEquals(1, Again.Count);
    Again.Add('next', '').Free;
    AssertEquals(2, JInt(Again.Find(2), 'id'));
  finally
    Again.Free;
  end;
end;

initialization
  RegisterTests(TNotesTests);
end.
