unit Text_Test;

{$mode objfpc}{$H+}

interface

uses
  Pastel.Testing, Pastel.Text;

type
  TTextTests = class(TTestSuite)
  published
    procedure UpperCaseOfEveryLanguage;
    procedure LowerCaseOfEveryLanguage;
    procedure TurkishAndAzerbaijaniI;
    procedure CapitalizeFirstLetter;
    procedure CountsCharactersNotBytes;
    procedure CopiesCharacters;
    procedure ShortensWithEllipsis;
  end;

implementation

procedure TTextTests.UpperCaseOfEveryLanguage;
begin
  AssertEquals('AYŞE ĞÜÖÇ ÆØÅ ΑΒΓ ПРИВЕТ', Upper('ayşe ğüöç æøå αβγ привет'));
end;

procedure TTextTests.LowerCaseOfEveryLanguage;
begin
  AssertEquals('çiğdem ünal', Lower('ÇİĞDEM ÜNAL'));
end;

procedure TTextTests.TurkishAndAzerbaijaniI;
begin
  AssertEquals('İSTANBUL', Upper('istanbul', 'tr'));
  AssertEquals('ISTANBUL', Upper('istanbul'));
  AssertEquals('ılık', Lower('ILIK', 'tr'));
  AssertEquals('ilık', Lower('İLIK', 'az'));
  AssertEquals('İLİK', Upper('ilik', 'az'));
end;

procedure TTextTests.CapitalizeFirstLetter;
begin
  AssertEquals('Şehir', Capitalize('şehir'));
  AssertEquals('İzmir', Capitalize('izmir', 'tr'));
  AssertEquals('', Capitalize(''));
end;

procedure TTextTests.CountsCharactersNotBytes;
begin
  AssertEquals(4, CharCount('ağaç'));
  AssertEquals(6, Length('ağaç'));
  AssertEquals(0, CharCount(''));
end;

procedure TTextTests.CopiesCharacters;
begin
  AssertEquals('ğa', CharCopy('ağaç', 2, 2));
  AssertEquals('aç', CharCopy('ağaç', 3, 10));
  AssertEquals('', CharCopy('ağaç', 9, 1));
end;

procedure TTextTests.ShortensWithEllipsis;
begin
  AssertEquals('kısa', Shorten('kısa', 10));
  AssertEquals('çok uz…', Shorten('çok uzun bir yazı', 7));
end;

initialization
  RegisterTests(TTextTests);
end.
