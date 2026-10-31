{ notepad - a small text editor: menus, shortcuts, file dialogs,
  "save changes?" on close. pastel run -- file.txt opens a file. }
program notepad;

{$mode objfpc}{$H+}

uses
  Pastel.App, Home;

begin
  Application.Initialize;
  Application.CreateForm(THomeForm, HomeForm);
  Application.Run;
end.
