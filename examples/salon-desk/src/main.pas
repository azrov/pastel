program salon_desk;

{$mode objfpc}{$H+}

uses
  Pastel.App, Home, Settings;

begin
  Application.Initialize;
  Application.CreateForm(THomeForm, HomeForm);
  Application.CreateForm(TSettingsForm, SettingsForm);
  Application.Run;
end.
