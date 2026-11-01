program components_demo;

{$mode objfpc}{$H+}

uses
  Pastel.App, Home;

begin
  Application.Initialize;
  Application.CreateForm(THomeForm, HomeForm);
  Application.Run;
end.
