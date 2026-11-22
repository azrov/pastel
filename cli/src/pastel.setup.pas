{ Pastel - "pastel setup android": what making Android apps needs, checked one
  by one, and set up where Pastel can (the compilers' parts, bundletool, the
  SDK's packages with Android's sdkmanager when --yes is given).
  Part of the Pastel project, MIT License. }
unit Pastel.Setup;

{$mode objfpc}{$H+}

interface

{ The Android tools after the compilers ("pastel doctor --install android"):
  Java, the SDK, its platform and build tools, adb and a phone, bundletool.
  Yes: Android's sdkmanager installs the SDK's missing packages (accepting
  their licenses). True when an .apk can be made. }
function SetupAndroid(Yes: Boolean): Boolean;

implementation

uses
  Classes, SysUtils, Process, Zipper, {$IFDEF UNIX}BaseUnix,{$ENDIF} Pastel.Console, Pastel.Builder, Pastel.Package,
  Pastel.Runtime, Pastel.Http, Pastel.Files;

const
  { what Google Play asks for (2026): Android 16 }
  WantedApi = 36;
  WantedBuildTools = '36.0.0';
  BundletoolVersion = '1.17.2';
  {$IFDEF WINDOWS}
  Exe = '.exe';
  Bat = '.bat';
  {$ELSE}
  Exe = '';
  Bat = '';
  {$ENDIF}

function OnPath(const Name: string): string;
begin
  Result := ExeSearch(Name + Exe, GetEnvironmentVariable('PATH'));
end;

procedure Line(Ok: Boolean; const What, Detail: string);
begin
  if Ok then
    WriteLn('  ', MarkOk, ' ', What, '  ', Dim(Detail))
  else
    WriteLn('  ', MarkFail, ' ', What, '  ', Dim(Detail));
end;

{ the Java that comes with Android Studio (when Java is not on the PATH) }
function StudioJava: string;
var
  D: string;
begin
  Result := '';
  for D in TStringArray.Create(
    {$IFDEF WINDOWS}
    GetEnvironmentVariable('ProgramFiles') + '\Android\Android Studio\jbr',
    {$ELSE}
    GetUserDir + 'android-studio/jbr', '/opt/android-studio/jbr', '/snap/android-studio/current/jbr',
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
    {$ENDIF}
    '') do
    if (D <> '') and FileExists(IncludeTrailingPathDelimiter(D) + 'bin' + PathDelim + 'javac' + Exe) then
      Exit(IncludeTrailingPathDelimiter(D) + 'bin');
end;

function SdkManager(const Sdk: string): string;
var
  F: string;
begin
  Result := '';
  if Sdk = '' then
    Exit;
  for F in TStringArray.Create('cmdline-tools' + PathDelim + 'latest' + PathDelim + 'bin' + PathDelim + 'sdkmanager' + Bat,
    'tools' + PathDelim + 'bin' + PathDelim + 'sdkmanager' + Bat) do
    if FileExists(Sdk + F) then
      Exit(Sdk + F);
end;

{ sdkmanager installs the packages, its licenses answered yes }
function RunSdkManager(const Tool, Sdk: string; const Packages: array of string): Boolean;
var
  P: TProcess;
  S: string;
  Yes: AnsiString;
  I: Integer;
begin
  P := TProcess.Create(nil);
  try
    P.Executable := Tool;
    P.Parameters.Add('--sdk_root=' + ExcludeTrailingPathDelimiter(Sdk));
    for S in Packages do
      P.Parameters.Add(S);
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    Yes := '';
    for I := 1 to 20 do
      Yes := Yes + 'y' + LineEnding;
    P.Input.Write(Yes[1], Length(Yes));
    P.CloseInput;
    S := '';
    while P.Running or (P.Output.NumBytesAvailable > 0) do
      if P.Output.NumBytesAvailable > 0 then
      begin
        SetLength(S, P.Output.NumBytesAvailable);
        P.Output.Read(S[1], Length(S));
      end
      else
        Sleep(50);
    Result := P.ExitStatus = 0;
  finally
    P.Free;
  end;
end;

{ The SDK in the user's own folder (no sudo): ~/Android/Sdk, %LOCALAPPDATA%\Android\Sdk }
function UserSdkDir: string;
begin
  {$IFDEF WINDOWS}
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'Android' + PathDelim + 'Sdk' + PathDelim;
  {$ELSE}
  Result := GetUserDir + 'Android' + PathDelim + 'Sdk' + PathDelim;
  {$ENDIF}
end;

{ Android's command-line tools (sdkmanager) from Google, into Sdk/cmdline-tools/latest;
  the sdkmanager, or '' (and why: Err) }
function InstallCmdlineTools(const Sdk: string; out Err: string): string;
const
  {$IFDEF WINDOWS}
  Zip = 'commandlinetools-win-11076708_latest.zip';
  {$ELSE}
  {$IFDEF DARWIN}
  Zip = 'commandlinetools-mac-11076708_latest.zip';
  {$ELSE}
  Zip = 'commandlinetools-linux-11076708_latest.zip';
  {$ENDIF}
  {$ENDIF}
var
  Tmp, Dest: string;
  U: TUnZipper;
  F: string;
begin
  Result := '';
  Err := '';
  Tmp := GetTempDir + 'pastel-cmdline-tools' + PathDelim;
  DeleteTree(ExcludeTrailingPathDelimiter(Tmp));
  ForceDirectories(Tmp);
  Status('Downloading', 'Android''s command-line tools (sdkmanager), about 150 MB');
  try
    HttpDownload('https://dl.google.com/android/repository/' + Zip, Tmp + Zip);
    U := TUnZipper.Create;
    try
      U.FileName := Tmp + Zip;
      U.OutputPath := Tmp;
      U.UnZipAllFiles;
    finally
      U.Free;
    end;
  except
    on E: Exception do
    begin
      Err := E.Message;
      Exit;
    end;
  end;
  { the zip has cmdline-tools/; sdkmanager wants it as cmdline-tools/latest }
  Dest := Sdk + 'cmdline-tools' + PathDelim + 'latest';
  ForceDirectories(Sdk + 'cmdline-tools');
  DeleteTree(Dest);
  if not RenameFile(Tmp + 'cmdline-tools', Dest) then
  begin
    Err := 'cannot put the tools into ' + Dest;
    Exit;
  end;
  {$IFDEF UNIX}
  for F in ListFiles(Dest + PathDelim + 'bin', '*', False) do
    fpChmod(F, &755);
  {$ENDIF}
  DeleteTree(ExcludeTrailingPathDelimiter(Tmp));
  Result := SdkManager(Sdk);
  if Result = '' then
    Err := 'no sdkmanager in what came';
end;

function Devices(const Adb: string): TStringArray;
var
  Args: TStringList;
  Output, L: string;
begin
  Result := nil;
  Args := TStringList.Create;
  try
    Args.Add('devices');
    if RunCapture(Adb, Args, GetCurrentDir, Output) <> 0 then
      Exit;
  finally
    Args.Free;
  end;
  for L in Output.Split([#10]) do
    if (Pos(#9, L) > 0) and not L.StartsWith('List') then
      Result := Concat(Result, [Trim(StringReplace(L, #9, '  ', []))]);
end;

function SetupAndroid(Yes: Boolean): Boolean;
var
  Sdks, Missing, Phones: TStringArray;
  Sdk, Manager, Javac, Keytool, Jarsigner, Aapt, Aapt2, Zipalign, Signer, D8, Adb, Bundletool, S: string;
  Jars: TAndroidJars;
  Api: Integer;
  ApkOk, AabOk, JavaOk: Boolean;
begin
  WriteLn;
  WriteLn(Bold('Android''s tools'));
  { Java: keytool signs every .apk; javac for the app's own Java and "pastel java add" of its classes }
  Javac := OnPath('javac');
  Keytool := OnPath('keytool');
  Jarsigner := OnPath('jarsigner');
  JavaOk := (Javac <> '') and (Keytool <> '');
  if JavaOk then
    Line(True, 'Java (a JDK)', Javac)
  else
  begin
    Line(False, 'Java (a JDK)', 'javac and keytool are not on the PATH');
    S := StudioJava;
    if S <> '' then
      Hint('Android Studio has one: add ' + S + ' to the PATH')
    else
      {$IFDEF LINUX}
      Hint('sudo apt install default-jdk-headless');
      {$ELSE}
      Hint('install a JDK (17 or newer: https://adoptium.net), or Android Studio');
      {$ENDIF}
  end;

  { the SDK }
  Sdks := AndroidSdkDirs;
  Sdk := '';
  if Length(Sdks) > 0 then
    Sdk := Sdks[0];
  Manager := SdkManager(Sdk);
  { no sdkmanager (an SDK of Ubuntu's packages, or none): Google's, into the user's own SDK }
  if (Manager = '') and Yes then
  begin
    Manager := SdkManager(UserSdkDir);
    if Manager = '' then
      Manager := InstallCmdlineTools(UserSdkDir, S);
    if Manager <> '' then
      Sdk := UserSdkDir
    else
      Fail('Android''s command-line tools could not be fetched: ' + S);
  end;
  if Sdk <> '' then
    Line(True, 'Android SDK', ExcludeTrailingPathDelimiter(Sdk))
  else
  begin
    Line(False, 'Android SDK', 'not found (ANDROID_HOME, ~/Android/Sdk)');
    {$IFDEF LINUX}
    Hint('Android Studio''s SDK (set ANDROID_HOME), or: sudo apt install aapt zipalign apksigner android-sdk-platform-23 adb');
    {$ELSE}
    Hint('install Android Studio; its SDK Manager installs the rest. Then set ANDROID_HOME to the SDK''s folder');
    {$ENDIF}
  end;

  { the SDK's packages, by sdkmanager }
  Jars := AndroidJars;
  Missing := nil;
  if (Length(Jars) = 0) or (Jars[0].Api < WantedApi) then
    Missing := Concat(Missing, [Format('platforms;android-%d', [WantedApi])]);
  if (AndroidTool('aapt2') = '') or (AndroidTool('apksigner') = '') or (AndroidTool('d8') = '') then
    Missing := Concat(Missing, ['build-tools;' + WantedBuildTools]);
  if (OnPath('adb') = '') and not FileExists(Sdk + 'platform-tools' + PathDelim + 'adb' + Exe) then
    Missing := Concat(Missing, ['platform-tools']);
  if (Length(Missing) > 0) and (Manager <> '') then
  begin
    if Yes then
    begin
      Status('Installing', string.Join(' ', Missing) + ' (sdkmanager; Android''s licenses accepted)');
      if RunSdkManager(Manager, Sdk, Missing) then
        Jars := AndroidJars
      else
        Fail('sdkmanager did not install them: run it yourself to see why');
    end
    else
      Hint('Pastel can install them with Android''s sdkmanager (accepting Android''s licenses): pastel setup android --yes');
    if (Length(Missing) > 0) and (Manager = '') and not Yes then
      Hint('pastel setup android --yes fetches Android''s sdkmanager into ' + UserSdkDir + ' and installs them (Android''s licenses accepted)');
  end;

  { the platform: what the app is made against }
  if Length(Jars) > 0 then
  begin
    Api := Jars[0].Api;
    Line(True, Format('platform: Android API %d', [Api]), Jars[0].Path);
    if Api < 33 then
      WriteLn('      ', Dim(Format('apps for phones: yes; Google Play needs API %d (platforms;android-%d)', [WantedApi, WantedApi])));
  end
  else
    Line(False, 'platform (android.jar)', Format('none: platforms;android-%d', [WantedApi]));

  { the build tools }
  Aapt := AndroidTool('aapt');
  Aapt2 := AndroidTool('aapt2');
  Zipalign := AndroidTool('zipalign');
  Signer := AndroidTool('apksigner');
  D8 := AndroidTool('d8');
  if D8 = '' then
    D8 := OnPath('dx');
  if D8 = '' then
    D8 := OnPath('dalvik-exchange');
  Line((Aapt <> '') and (Zipalign <> '') and (Signer <> ''), 'build tools for .apk (aapt, zipalign, apksigner)', Aapt);
  Line(Aapt2 <> '', 'aapt2, for Google Play''s .aab', Aapt2);
  Line(D8 <> '', 'd8, for the app''s own Java (src/java)', D8);

  { a phone }
  Adb := OnPath('adb');
  if (Adb = '') and FileExists(Sdk + 'platform-tools' + PathDelim + 'adb' + Exe) then
    Adb := Sdk + 'platform-tools' + PathDelim + 'adb' + Exe;
  Line(Adb <> '', 'adb, for pastel run --target android', Adb);
  if Adb = '' then
    {$IFDEF LINUX}
    Hint('sudo apt install adb (or the SDK''s platform-tools)')
    {$ELSE}
    Hint('Android Studio''s SDK Manager: "Android SDK Platform-Tools"')
    {$ENDIF}
  else
  begin
    Phones := Devices(Adb);
    if Length(Phones) = 0 then
      WriteLn('      ', Dim('no phone connected: USB debugging on (Settings > Developer options), then the cable'))
    else
      for S in Phones do
        WriteLn('      ', Dim('phone: ' + S));
  end;

  { bundletool, from Google's releases on GitHub }
  Bundletool := FindBundletool;
  if Bundletool = '' then
  begin
    S := PastelHome + 'android' + PathDelim + 'bundletool-all-' + BundletoolVersion + '.jar';
    try
      ForceDirectories(ExtractFilePath(S));
      Status('Downloading', 'bundletool ' + BundletoolVersion);
      HttpDownload(Format('https://github.com/google/bundletool/releases/download/%s/bundletool-all-%s.jar',
        [BundletoolVersion, BundletoolVersion]), S + '.part');
      RenameFile(S + '.part', S);
      Bundletool := FindBundletool;
    except
      on E: Exception do
      begin
        DeleteFile(S + '.part');
        Fail('bundletool could not be downloaded: ' + E.Message);
      end;
    end;
  end;
  Line(Bundletool <> '', 'bundletool, for Google Play''s .aab', Bundletool);

  { what works now }
  ApkOk := (Aapt <> '') and (Zipalign <> '') and (Signer <> '') and (Keytool <> '') and (Length(Jars) > 0);
  AabOk := (Aapt2 <> '') and (Bundletool <> '') and (Jarsigner <> '') and (Length(Jars) > 0) and (Jars[0].Api >= 33);
  WriteLn;
  WriteLn(Bold('Ready'));
  Line(ApkOk, 'pastel package apk', 'an app to install on phones');
  Line(ApkOk and (Adb <> ''), 'pastel run --target android', 'the app on a phone (F9 in VS Code)');
  Line(AabOk, 'pastel package aab', 'for Google Play (with your key: [package.android] keystore)');
  Line(Length(Jars) > 0, 'pastel java add', 'Android''s classes as Pascal');
  Line(JavaOk and (D8 <> ''), 'Java files of the app (src/java)', '');
  Result := ApkOk;
end;

end.
