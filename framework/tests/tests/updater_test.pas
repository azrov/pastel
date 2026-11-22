{ Tests of Pastel.Updater: versions, the update file. }
unit updater_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Updater;

type
  TUpdaterTests = class(TTestSuite)
  published
    procedure Versions;
    procedure TheUpdateFile;
  end;

implementation

procedure TUpdaterTests.Versions;
begin
  AssertTrue(CompareVersions('1.10.0', '1.9.2') > 0);
  AssertTrue(CompareVersions('1.0.0', '1.0.0-beta.2') > 0, 'a release after its betas');
  AssertTrue(CompareVersions('2.0.0-beta.10', '2.0.0-beta.9') > 0);
  AssertTrue(CompareVersions('v1.2', '1.2.0') = 0);
  AssertTrue(CompareVersions('1.2.3', '1.2.4') < 0);
end;

procedure TUpdaterTests.TheUpdateFile;
var
  Info: TUpdateInfo;
  Json: string;
begin
  Json := '{"version": "1.5.0", "notes": "Faster", "files": {"' + UpdatePlatform +
    '": {"url": "https://x/shop.bin", "sha256": "ABC"}}}';
  AssertTrue(UpdateFromManifest(Json, '1.4.2', Info), 'newer');
  AssertEquals('1.5.0', Info.Version);
  AssertEquals('https://x/shop.bin', Info.Url);
  AssertEquals('abc', Info.Sha256);
  AssertEquals('Faster', Info.Notes);
  AssertFalse(UpdateFromManifest(Json, '1.5.0', Info), 'the same version');
  AssertFalse(UpdateFromManifest('{"version": "9.0", "files": {"other-os": {"url": "u"}}}', '1.0', Info),
    'nothing for this platform');
  try
    UpdateFromManifest('not json', '1.0', Info);
    Fail('not JSON');
  except
    on E: EUpdateError do ;
  end;
  try
    DownloadUpdate(Info);
    Fail('no checksum: not downloaded');
  except
    on E: EUpdateError do ;
  end;
end;

initialization
  RegisterTests(TUpdaterTests);

end.
