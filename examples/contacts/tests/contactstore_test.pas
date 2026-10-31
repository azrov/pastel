{ Tests for src/services/contactstore.pas. Run them with: pastel test }
unit ContactStore_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, ContactStore;

type
  TContactStoreTests = class(TTestSuite)
  private
    FileName: string;
    Store: TContactStore;
    procedure SaveNameless;
    procedure SaveBadEmail;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AddsAndLists;
    procedure SortsByName;
    procedure Filters;
    procedure Updates;
    procedure Deletes;
    procedure Validates;
    procedure KeepsTheContacts;
  end;

implementation

procedure TContactStoreTests.SetUp;
begin
  FileName := GetTempFileName('', 'contacts') + '.db';
  Store := TContactStore.Create('sqlite:' + FileName);
end;

procedure TContactStoreTests.TearDown;
begin
  Store.Free;
  DeleteFile(FileName);
end;

procedure TContactStoreTests.AddsAndLists;
var
  Id: Int64;
begin
  Id := Store.Save(NewContact('Ayşe Yılmaz', '0532 111 22 33', 'ayse@example.com'));
  AssertTrue(Id > 0);
  AssertEquals(1, Store.Count);
  AssertEquals('Ayşe Yılmaz', Store.Get(Id).Name);
  AssertEquals('0532 111 22 33', Store.List[0].Phone);
end;

procedure TContactStoreTests.SortsByName;
begin
  Store.Save(NewContact('zeynep', '', ''));
  Store.Save(NewContact('Ali', '', ''));
  Store.Save(NewContact('Mehmet', '', ''));
  AssertEquals('Ali', Store.List[0].Name);
  AssertEquals('zeynep', Store.List[2].Name);
end;

procedure TContactStoreTests.Filters;
begin
  Store.Save(NewContact('Ali Can', '555 01', 'ali@example.com'));
  Store.Save(NewContact('Veli', '555 02', 'veli@work.org'));
  AssertEquals(1, Length(Store.List('ali')));
  AssertEquals(2, Length(Store.List('555')));
  AssertEquals(1, Length(Store.List('WORK')));
  AssertEquals(0, Length(Store.List('nobody')));
end;

procedure TContactStoreTests.Updates;
var
  C: TContact;
begin
  C := NewContact('Ali', '1', '');
  C.Id := Store.Save(C);
  C.Phone := '2';
  AssertEquals(C.Id, Store.Save(C));
  AssertEquals('2', Store.Get(C.Id).Phone);
  AssertEquals(1, Store.Count);
end;

procedure TContactStoreTests.Deletes;
var
  Id: Int64;
begin
  Id := Store.Save(NewContact('Ali', '', ''));
  Store.Delete(Id);
  AssertEquals(0, Store.Count);
end;

procedure TContactStoreTests.SaveNameless;
begin
  Store.Save(NewContact('  ', '1', ''));
end;

procedure TContactStoreTests.SaveBadEmail;
begin
  Store.Save(NewContact('Ali', '', 'not-an-address'));
end;

procedure TContactStoreTests.Validates;
begin
  AssertRaises(EContactInvalid, @SaveNameless);
  AssertRaises(EContactInvalid, @SaveBadEmail);
  AssertEquals(0, Store.Count);
end;

procedure TContactStoreTests.KeepsTheContacts;
begin
  Store.Save(NewContact('Ali', '', ''));
  Store.Free;
  Store := TContactStore.Create('sqlite:' + FileName);
  AssertEquals(1, Store.Count);
end;

initialization
  RegisterTests(TContactStoreTests);
end.
