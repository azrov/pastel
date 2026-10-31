{ contacts - a desktop address book; the contacts live in a SQLite file. }
program contacts;

{$mode objfpc}{$H+}

uses
  Pastel.App, Home;

begin
  Application.Initialize;
  Application.CreateForm(THomeForm, HomeForm);
  Application.Run;
end.
