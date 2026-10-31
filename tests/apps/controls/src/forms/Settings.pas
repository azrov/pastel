{ The code of the Settings form. Show it as a dialog:

    if SettingsForm.ShowModal = mrOk then ...

  The buttons close it with their ModalResult. }
unit Settings;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.UI, Settings.g;

type
  TSettingsForm = class(TSettingsFormBase)
  end;

var
  SettingsForm: TSettingsForm;

implementation

end.
