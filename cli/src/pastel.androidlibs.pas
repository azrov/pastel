{ Pastel - Android libraries in an app: [package.android] libraries.

    [package.android]
    libraries = ["androidx.browser:browser:1.8.0", "libs/scanner.aar", "libs/util.jar"]
    repositories = ["https://maven.google.com", "https://repo1.maven.org/maven2"]   # the default

  A Maven coordinate brings what it needs (its POM's compile and runtime
  dependencies); when two ask for one library, the highest version is used.
  Files come once into ~/.pastel/maven. An .aar gives its classes (and libs/*.jar),
  its resources (and R classes for its code), its assets, its native libraries
  and its manifest's parts (permissions, activities, services, receivers,
  providers) to the .apk/.aab. A repository is a URL or a folder.
  Part of the Pastel project, MIT License. }
unit Pastel.AndroidLibs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Project;

type
  TAndroidLibrary = record
    Name: string;            { group:artifact:version, or the file's name }
    Dir: string;             { unpacked .aar, with a path delimiter; '' for a .jar }
    Jars: TStringArray;      { classes.jar and libs/*.jar, or the .jar }
    PackageName: string;     { the .aar's manifest package }
    Res: string;             { its res folder when it has resources, else '' }
    Assets: string;          { its assets folder, or '' }
    MinSdk: Integer;
    { the Android platform it must be built against (its aar-metadata's minCompileSdk); 0: any }
    CompileSdk: Integer;
  end;
  TAndroidLibraries = array of TAndroidLibrary;

{ The project's libraries with what they need, unpacked into Work (with a
  path delimiter); '' or what went wrong. }
function ResolveAndroidLibraries(Project: TPastelProject; const Work: string; out Libs: TAndroidLibraries): string;
{ What the libraries' manifests add: <uses-permission> and like lines (Perms, not
  in Have already), <application> children (Parts), <queries> (Queries); the highest
  minSdkVersion. AppId replaces the applicationId placeholder. }
procedure LibraryManifests(const Libs: TAndroidLibraries; const AppId, Have: string; out Perms, Parts, Queries: string;
  out MinSdk: Integer);
{ The Java jars of the libraries (for javac's classpath and the dexer). }
function LibraryJars(const Libs: TAndroidLibraries): TStringArray;
{ google-services.json (Firebase) as Android string resources for AppId:
  the XML, '' when the project has none; Err when it is wrong. }
function GoogleServicesXml(const Root, AppId: string; out Err: string): string;

{ True when one of the jars has the class (a path: com/google/x/Y.class). }
function JarsHaveClass(const Jars: TStringArray; const ClassFile: string): Boolean;

{ Maven versions: <0, 0, >0 (1.10 > 1.9; 1.0 > 1.0-rc1). }
function CompareMavenVersions(const A, B: string): Integer;

implementation

uses
  Math, DOM, XMLRead, zipper, fpjson, jsonparser, Pastel.Console, Pastel.Runtime, Pastel.Http, Pastel.Files, Pastel.Builder;

const
  DefaultRepositories: array[0..1] of string = ('https://maven.google.com', 'https://repo1.maven.org/maven2');

{ ---- versions ---- }

function QualifierRank(const Q: string): Integer;
var
  L: string;
begin
  L := LowerCase(Q);
  if (L = '') or (L = 'final') or (L = 'ga') or (L = 'release') then
    Result := 5
  else if (L = 'sp') then
    Result := 6
  else if (Copy(L, 1, 8) = 'snapshot') then
    Result := 4
  else if (Copy(L, 1, 2) = 'rc') or (Copy(L, 1, 2) = 'cr') then
    Result := 3
  else if (Copy(L, 1, 4) = 'beta') or (L = 'b') then
    Result := 2
  else if (Copy(L, 1, 5) = 'alpha') or (L = 'a') then
    Result := 1
  else if (Copy(L, 1, 9) = 'milestone') or (L = 'm') or (Copy(L, 1, 3) = 'dev') then
    Result := 1
  else
    Result := 5;
end;

procedure SplitVersion(const V: string; out Parts: TStringArray);
var
  I, Start: Integer;
  function Kind(C: Char): Integer;
  begin
    if C in ['0'..'9'] then
      Result := 1
    else if C in ['.', '-', '_', '+'] then
      Result := 0
    else
      Result := 2;
  end;
begin
  Parts := nil;
  I := 1;
  while I <= Length(V) do
  begin
    if Kind(V[I]) = 0 then
    begin
      Inc(I);
      Continue;
    end;
    Start := I;
    while (I <= Length(V)) and (Kind(V[I]) = Kind(V[Start])) do
      Inc(I);
    Parts := Concat(Parts, [Copy(V, Start, I - Start)]);
  end;
end;

function CompareMavenVersions(const A, B: string): Integer;
var
  PA, PB: TStringArray;
  I: Integer;
  X, Y: string;
  NX, NY: Int64;
  DX, DY: Boolean;
begin
  SplitVersion(A, PA);
  SplitVersion(B, PB);
  for I := 0 to Max(Length(PA), Length(PB)) - 1 do
  begin
    if I < Length(PA) then X := PA[I] else X := '';
    if I < Length(PB) then Y := PB[I] else Y := '';
    DX := (X <> '') and (X[1] in ['0'..'9']);
    DY := (Y <> '') and (Y[1] in ['0'..'9']);
    if DX and DY then
    begin
      NX := StrToInt64Def(X, 0);
      NY := StrToInt64Def(Y, 0);
      if NX <> NY then
        Exit(Ord(NX > NY) * 2 - 1);
      Continue;
    end;
    { 1.0 = 1.0.0; a number after the end: newer; a word (rc, beta): older }
    if DX then
    begin
      if (Y = '') and (StrToInt64Def(X, 0) = 0) then
        Continue;
      Exit(1);
    end;
    if DY then
    begin
      if (X = '') and (StrToInt64Def(Y, 0) = 0) then
        Continue;
      Exit(-1);
    end;
    if QualifierRank(X) <> QualifierRank(Y) then
      Exit(Ord(QualifierRank(X) > QualifierRank(Y)) * 2 - 1);
    if CompareText(X, Y) <> 0 then
      Exit(Ord(CompareText(X, Y) > 0) * 2 - 1);
  end;
  Result := 0;
end;

{ "[1.2,2.0)" -> 1.2; "[1.4]" -> 1.4; "1.5" -> 1.5 }
function PlainVersion(const V: string): string;
var
  S: string;
  I: Integer;
begin
  S := Trim(V);
  if (S <> '') and (S[1] in ['[', '(']) then
  begin
    S := Copy(S, 2, MaxInt);
    I := Pos(',', S);
    if I = 1 then
    begin
      { (,2.0]: the upper end }
      S := Copy(S, 2, MaxInt);
      I := 0;
    end;
    if I > 0 then
      S := Copy(S, 1, I - 1);
    while (S <> '') and (S[Length(S)] in [']', ')']) do
      Delete(S, Length(S), 1);
  end;
  Result := Trim(S);
end;

{ ---- XML ---- }

function ReadXml(const FileName: string): TXMLDocument;
begin
  Result := nil;
  ReadXMLFile(Result, FileName);
end;

function Child(E: TDOMNode; const Name: string): TDOMElement;
var
  N: TDOMNode;
begin
  Result := nil;
  if E = nil then
    Exit;
  N := E.FirstChild;
  while N <> nil do
  begin
    if (N.NodeType = ELEMENT_NODE) and (UTF8Encode(N.NodeName) = Name) then
      Exit(TDOMElement(N));
    N := N.NextSibling;
  end;
end;

function ChildText(E: TDOMNode; const Name: string): string;
var
  C: TDOMElement;
begin
  C := Child(E, Name);
  if C = nil then
    Result := ''
  else
    Result := Trim(UTF8Encode(C.TextContent));
end;

function Attr(E: TDOMNode; const Name: string): string;
begin
  if (E = nil) or (E.NodeType <> ELEMENT_NODE) then
    Exit('');
  Result := UTF8Encode(TDOMElement(E).GetAttribute(UnicodeString(Name)));
end;

function XmlEscape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

{ an element as text, for the app's manifest: tools: attributes left out,
  the applicationId placeholder and names relative to Pkg (".Foo") filled in }
function ElementText(E: TDOMNode; const Pkg, AppId, Indent: string): string;
var
  I: Integer;
  A: TDOMNode;
  N, V: string;
  C: TDOMNode;
  Inner: string;
begin
  Result := Indent + '<' + UTF8Encode(E.NodeName);
  for I := 0 to E.Attributes.Length - 1 do
  begin
    A := E.Attributes[I];
    N := UTF8Encode(A.NodeName);
    if (Copy(N, 1, 6) = 'tools:') or (N = 'xmlns:tools') or (Copy(N, 1, 5) = 'xmlns') then
      Continue;
    V := StringReplace(UTF8Encode(A.NodeValue), '${applicationId}', AppId, [rfReplaceAll]);
    if ((N = 'android:name') or (N = 'android:targetActivity')) and
       ((UTF8Encode(E.NodeName) = 'activity') or (UTF8Encode(E.NodeName) = 'service') or (UTF8Encode(E.NodeName) = 'receiver') or
        (UTF8Encode(E.NodeName) = 'provider') or (UTF8Encode(E.NodeName) = 'activity-alias')) then
    begin
      if (V <> '') and (V[1] = '.') then
        V := Pkg + V
      else if (V <> '') and (Pos('.', V) = 0) then
        V := Pkg + '.' + V;
    end;
    Result := Result + ' ' + N + '="' + XmlEscape(V) + '"';
  end;
  Inner := '';
  C := E.FirstChild;
  while C <> nil do
  begin
    if (C.NodeType = ELEMENT_NODE) and (Attr(C, 'tools:node') <> 'remove') then
      Inner := Inner + ElementText(C, Pkg, AppId, Indent + '  ');
    C := C.NextSibling;
  end;
  if Inner = '' then
    Result := Result + '/>' + LineEnding
  else
    Result := Result + '>' + LineEnding + Inner + Indent + '</' + UTF8Encode(E.NodeName) + '>' + LineEnding;
end;

{ ---- Maven ---- }

type
  TCoord = record
    Group, Artifact, Version: string;
  end;

  TResolver = class
    Repos: TStringArray;
    Cache: string;
    Err: string;
    Chosen: TStringList;       { group:artifact -> version (the highest asked for) }
    Seen: TStringList;         { group:artifact:version read already }
    Order: TStringList;        { group:artifact, the order they were first met }
    constructor Create;
    destructor Destroy; override;
    function Fetch(const C: TCoord; const Ext: string; out FileName: string): Boolean;
    function Deps(const C: TCoord; out Packaging: string): TStringArray;
    procedure Walk(const C: TCoord; Depth: Integer);
  end;

function ParseCoord(const S: string; out C: TCoord): Boolean;
var
  P: TStringArray;
begin
  P := S.Split([':']);
  Result := Length(P) = 3;
  if Result then
  begin
    C.Group := Trim(P[0]);
    C.Artifact := Trim(P[1]);
    C.Version := PlainVersion(P[2]);
    Result := (C.Group <> '') and (C.Artifact <> '') and (C.Version <> '');
  end;
end;

function CoordKey(const C: TCoord): string;
begin
  Result := C.Group + ':' + C.Artifact;
end;

constructor TResolver.Create;
begin
  Chosen := TStringList.Create;
  Seen := TStringList.Create;
  Seen.Sorted := True;
  Order := TStringList.Create;
end;

destructor TResolver.Destroy;
begin
  Order.Free;
  Seen.Free;
  Chosen.Free;
  inherited;
end;

procedure CopyBytes(const Source, Dest: string);
var
  A, B: TFileStream;
begin
  A := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
  try
    B := TFileStream.Create(Dest, fmCreate);
    try
      B.CopyFrom(A, 0);
    finally
      B.Free;
    end;
  finally
    A.Free;
  end;
end;

function TResolver.Fetch(const C: TCoord; const Ext: string; out FileName: string): Boolean;
var
  Rel, R, Src: string;
  Resp: THttpResponse;
begin
  Rel := StringReplace(C.Group, '.', '/', [rfReplaceAll]) + '/' + C.Artifact + '/' + C.Version + '/' +
    C.Artifact + '-' + C.Version + '.' + Ext;
  FileName := Cache + SetDirSeparators(Rel);
  if FileExists(FileName) then
    Exit(True);
  for R in Repos do
  begin
    if (Copy(R, 1, 7) = 'http://') or (Copy(R, 1, 8) = 'https://') then
    begin
      try
        Src := R;
        while (Src <> '') and (Src[Length(Src)] = '/') do
          Delete(Src, Length(Src), 1);
        Resp := HttpGet(Src + '/' + Rel);
      except
        on E: Exception do
        begin
          Err := Format('%s: %s', [R, E.Message]);
          Continue;
        end;
      end;
      if Resp.Status <> 200 then
        Continue;
      ForceDirectories(ExtractFileDir(FileName));
      WriteText(FileName + '.part', Resp.Body);
      RenameFile(FileName + '.part', FileName);
      Exit(True);
    end
    else
    begin
      { a folder laid out like a Maven repository }
      Src := IncludeTrailingPathDelimiter(R) + SetDirSeparators(Rel);
      if FileExists(Src) then
      begin
        ForceDirectories(ExtractFileDir(FileName));
        CopyBytes(Src, FileName);
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

{ the POM's dependencies (group:artifact:version), with what its parents say }
function TResolver.Deps(const C: TCoord; out Packaging: string): TStringArray;
var
  Props, Managed: TStringList;
  Pom: string;
  Doc: TXMLDocument;
  Root, D, N: TDOMNode;
  Chain: array of TXMLDocument;
  P: TCoord;
  I, Depth: Integer;
  G, A, V, Scope, Typ: string;

  function Expand(const S: string): string;
  var
    I, J, K: Integer;
    Key: string;
  begin
    Result := S;
    for K := 1 to 5 do
    begin
      I := Pos('${', Result);
      if I = 0 then
        Break;
      J := Pos('}', Result, I);
      if J = 0 then
        Break;
      Key := Copy(Result, I + 2, J - I - 2);
      Result := Copy(Result, 1, I - 1) + Props.Values[Key] + Copy(Result, J + 1, MaxInt);
    end;
  end;

  procedure ReadProps(R: TDOMNode; const Version, Group: string);
  var
    N: TDOMNode;
  begin
    if Props.IndexOfName('project.version') < 0 then
    begin
      Props.Values['project.version'] := Version;
      Props.Values['version'] := Version;
      Props.Values['pom.version'] := Version;
      Props.Values['project.groupId'] := Group;
    end;
    N := Child(R, 'properties');
    if N = nil then
      Exit;
    N := N.FirstChild;
    while N <> nil do
    begin
      if (N.NodeType = ELEMENT_NODE) and (Props.IndexOfName(UTF8Encode(N.NodeName)) < 0) then
        Props.Values[UTF8Encode(N.NodeName)] := Trim(UTF8Encode(N.TextContent));
      N := N.NextSibling;
    end;
  end;

begin
  Result := nil;
  Packaging := 'jar';
  if not Fetch(C, 'pom', Pom) then
    Exit;
  Props := TStringList.Create;
  Managed := TStringList.Create;
  Chain := nil;
  try
    Doc := ReadXml(Pom);
    Chain := [Doc];
    Root := Doc.DocumentElement;
    Packaging := ChildText(Root, 'packaging');
    if Packaging = '' then
      Packaging := 'jar';
    ReadProps(Root, C.Version, C.Group);
    { the parents: properties and the versions they manage }
    N := Root;
    Depth := 0;
    while (Child(N, 'parent') <> nil) and (Depth < 6) do
    begin
      P.Group := ChildText(Child(N, 'parent'), 'groupId');
      P.Artifact := ChildText(Child(N, 'parent'), 'artifactId');
      P.Version := ChildText(Child(N, 'parent'), 'version');
      if Props.IndexOfName('project.parent.version') < 0 then
        Props.Values['project.parent.version'] := P.Version;
      if not Fetch(P, 'pom', Pom) then
        Break;
      Doc := ReadXml(Pom);
      Chain := Concat(Chain, [Doc]);
      N := Doc.DocumentElement;
      ReadProps(N, P.Version, P.Group);
      Inc(Depth);
    end;
    for I := 0 to High(Chain) do
    begin
      D := Child(Child(Chain[I].DocumentElement, 'dependencyManagement'), 'dependencies');
      if D = nil then
        Continue;
      D := D.FirstChild;
      while D <> nil do
      begin
        if (D.NodeType = ELEMENT_NODE) and (D.NodeName = 'dependency') then
        begin
          A := Expand(ChildText(D, 'groupId')) + ':' + Expand(ChildText(D, 'artifactId'));
          if Managed.IndexOfName(A) < 0 then
            Managed.Values[A] := Expand(ChildText(D, 'version'));
        end;
        D := D.NextSibling;
      end;
    end;
    D := Child(Chain[0].DocumentElement, 'dependencies');
    if D <> nil then
    begin
      D := D.FirstChild;
      while D <> nil do
      begin
        if (D.NodeType = ELEMENT_NODE) and (D.NodeName = 'dependency') then
        begin
          G := Expand(ChildText(D, 'groupId'));
          A := Expand(ChildText(D, 'artifactId'));
          V := Expand(ChildText(D, 'version'));
          Scope := LowerCase(ChildText(D, 'scope'));
          Typ := LowerCase(ChildText(D, 'type'));
          if V = '' then
            V := Managed.Values[G + ':' + A];
          if ((Scope = '') or (Scope = 'compile') or (Scope = 'runtime')) and (LowerCase(ChildText(D, 'optional')) <> 'true') and
             (Typ <> 'pom') and (G <> '') and (A <> '') and (PlainVersion(V) <> '') and (Pos('${', V) = 0) then
            Result := Concat(Result, [G + ':' + A + ':' + PlainVersion(V)]);
        end;
        D := D.NextSibling;
      end;
    end;
  finally
    for I := 0 to High(Chain) do
      Chain[I].Free;
    Managed.Free;
    Props.Free;
  end;
end;

procedure TResolver.Walk(const C: TCoord; Depth: Integer);
var
  Key, Packaging, S: string;
  D: TCoord;
  I: Integer;
begin
  if (Err <> '') or (Depth > 40) then
    Exit;
  Key := CoordKey(C);
  I := Chosen.IndexOfName(Key);
  if I < 0 then
  begin
    Chosen.Values[Key] := C.Version;
    Order.Add(Key);
  end
  else if CompareMavenVersions(C.Version, Chosen.ValueFromIndex[I]) > 0 then
    Chosen.ValueFromIndex[I] := C.Version;
  if Seen.IndexOf(Key + ':' + C.Version) >= 0 then
    Exit;
  Seen.Add(Key + ':' + C.Version);
  for S in Deps(C, Packaging) do
    if ParseCoord(S, D) then
      Walk(D, Depth + 1);
end;

{ ---- unpacking ---- }

function UnpackAar(const Aar, Dir: string; var L: TAndroidLibrary): string;
var
  Z: TUnZipper;
  Doc: TXMLDocument;
  F: string;
begin
  Result := '';
  DeleteTree(ExcludeTrailingPathDelimiter(Dir));
  ForceDirectories(Dir);
  Z := TUnZipper.Create;
  try
    Z.FileName := Aar;
    Z.OutputPath := Dir;
    try
      Z.UnZipAllFiles;
    except
      on E: Exception do
        Exit(Format('%s is not an .aar (zip): %s', [ExtractFileName(Aar), E.Message]));
    end;
  finally
    Z.Free;
  end;
  L.Dir := Dir;
  L.Jars := nil;
  if FileExists(Dir + 'classes.jar') then
    L.Jars := [Dir + 'classes.jar'];
  if DirectoryExists(Dir + 'libs') then
    for F in ListFiles(Dir + 'libs', '*.jar', False) do
      L.Jars := Concat(L.Jars, [F]);
  if DirectoryExists(Dir + 'res') and (Length(ListFiles(Dir + 'res', '*', True)) > 0) then
    L.Res := Dir + 'res';
  if DirectoryExists(Dir + 'assets') and (Length(ListFiles(Dir + 'assets', '*', True)) > 0) then
    L.Assets := Dir + 'assets';
  L.MinSdk := 0;
  if FileExists(Dir + 'AndroidManifest.xml') then
  begin
    try
      Doc := ReadXml(Dir + 'AndroidManifest.xml');
      try
        L.PackageName := Attr(Doc.DocumentElement, 'package');
        L.MinSdk := StrToIntDef(Attr(Child(Doc.DocumentElement, 'uses-sdk'), 'android:minSdkVersion'), 0);
      finally
        Doc.Free;
      end;
    except
      on E: Exception do
        Exit(Format('%s: its AndroidManifest.xml: %s', [L.Name, E.Message]));
    end;
  end;
  { minCompileSdk=31: its resources use attributes of Android 12 (android:attr/lStar...) }
  L.CompileSdk := 0;
  F := Dir + 'META-INF' + PathDelim + 'com' + PathDelim + 'android' + PathDelim + 'build' + PathDelim + 'gradle' +
    PathDelim + 'aar-metadata.properties';
  if FileExists(F) then
    with TStringList.Create do
    try
      LoadFromFile(F);
      L.CompileSdk := StrToIntDef(Trim(Values['minCompileSdk']), 0);
    finally
      Free;
    end;
  if (L.Res <> '') and (L.PackageName = '') then
    Result := L.Name + ': resources without a package in its AndroidManifest.xml';
end;

function SafeName(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if not (Result[I] in ['a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_']) then
      Result[I] := '_';
end;

function ResolveAndroidLibraries(Project: TPastelProject; const Work: string; out Libs: TAndroidLibraries): string;
var
  R: TResolver;
  S, F, Key, Packaging: string;
  C, D: TCoord;
  L: TAndroidLibrary;
  I: Integer;
  Coords, Queue: TStringArray;
  Needed: TStringList;
begin
  Result := '';
  Libs := nil;
  if Length(Project.AndroidLibraries) = 0 then
    Exit;
  R := TResolver.Create;
  try
    R.Repos := Project.AndroidRepositories;
    for I := 0 to High(R.Repos) do
      if not ((Copy(R.Repos[I], 1, 7) = 'http://') or (Copy(R.Repos[I], 1, 8) = 'https://')) then
        if (Copy(R.Repos[I], 1, 1) = '/') or (Copy(R.Repos[I], 1, 1) = '\') or (Copy(R.Repos[I], 2, 1) = ':') then
          R.Repos[I] := ExpandFileName(SetDirSeparators(R.Repos[I]))
        else
          R.Repos[I] := ExpandFileName(Project.Root + SetDirSeparators(R.Repos[I]));
    if Length(R.Repos) = 0 then
      for S in DefaultRepositories do
        R.Repos := Concat(R.Repos, [S]);
    { PASTEL_MAVEN_CACHE: another folder (a CI's cache, tests) }
    R.Cache := GetEnvironmentVariable('PASTEL_MAVEN_CACHE');
    if R.Cache = '' then
      R.Cache := PastelHome + 'maven';
    R.Cache := IncludeTrailingPathDelimiter(R.Cache);
    Coords := nil;
    for S in Project.AndroidLibraries do
    begin
      L := Default(TAndroidLibrary);
      if (LowerCase(ExtractFileExt(S)) = '.aar') or (LowerCase(ExtractFileExt(S)) = '.jar') then
      begin
        { a file of the project }
        F := ExpandFileName(Project.Root + SetDirSeparators(S));
        if not FileExists(F) then
          Exit(Format('[package.android] libraries: there is no file %s', [S]));
        L.Name := ExtractFileName(F);
        if LowerCase(ExtractFileExt(F)) = '.jar' then
          L.Jars := [F]
        else
        begin
          Result := UnpackAar(F, Work + 'libs' + PathDelim + SafeName(L.Name) + PathDelim, L);
          if Result <> '' then
            Exit;
        end;
        Libs := Concat(Libs, [L]);
      end
      else if ParseCoord(S, C) then
        Coords := Concat(Coords, [S])
      else
        Exit(Format('[package.android] libraries: "%s" is not a file (.aar, .jar) or group:artifact:version', [S]));
    end;
    if Length(Coords) = 0 then
      Exit;
    for S in Coords do
    begin
      ParseCoord(S, C);
      if not R.Fetch(C, 'pom', F) then
      begin
        Result := Format('%s is not in the repositories (%s)', [S, string.Join(', ', R.Repos)]);
        if R.Err <> '' then
          Result := Result + ': ' + R.Err;
        Exit;
      end;
      R.Walk(C, 0);
      if R.Err <> '' then
        Exit(R.Err);
    end;
    { what the chosen versions need (a version left behind may have needed more) }
    Needed := TStringList.Create;
    try
      Queue := nil;
      for S in Coords do
      begin
        ParseCoord(S, C);
        Queue := Concat(Queue, [CoordKey(C)]);
      end;
      I := 0;
      while I < Length(Queue) do
      begin
        Key := Queue[I];
        Inc(I);
        if Needed.IndexOf(Key) >= 0 then
          Continue;
        Needed.Add(Key);
        C.Group := Copy(Key, 1, Pos(':', Key) - 1);
        C.Artifact := Copy(Key, Pos(':', Key) + 1, MaxInt);
        C.Version := R.Chosen.Values[Key];
        for F in R.Deps(C, Packaging) do
          if ParseCoord(F, D) then
            Queue := Concat(Queue, [CoordKey(D)]);
      end;
      { the chosen versions, in the order they were met }
      for Key in R.Order do
      begin
        if Needed.IndexOf(Key) < 0 then
          Continue;
        C.Group := Copy(Key, 1, Pos(':', Key) - 1);
        C.Artifact := Copy(Key, Pos(':', Key) + 1, MaxInt);
        C.Version := R.Chosen.Values[Key];
        L := Default(TAndroidLibrary);
        L.Name := Key + ':' + C.Version;
        R.Deps(C, Packaging);
        if (LowerCase(Packaging) = 'pom') then
          Continue;
        if R.Fetch(C, 'aar', F) then
        begin
          Result := UnpackAar(F, Work + 'libs' + PathDelim + SafeName(L.Name) + PathDelim, L);
          if Result <> '' then
            Exit;
        end
        else if R.Fetch(C, 'jar', F) then
          L.Jars := [F]
        else
          Exit(Format('%s: no .aar or .jar in the repositories', [L.Name]));
        Libs := Concat(Libs, [L]);
      end;
    finally
      Needed.Free;
    end;
  finally
    R.Free;
  end;
end;

procedure LibraryManifests(const Libs: TAndroidLibraries; const AppId, Have: string; out Perms, Parts, Queries: string;
  out MinSdk: Integer);
var
  L: TAndroidLibrary;
  Doc: TXMLDocument;
  N, C: TDOMNode;
  Names: TStringList;
  Key, Line: string;
begin
  Perms := '';
  Parts := '';
  Queries := '';
  MinSdk := 0;
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    for L in Libs do
    begin
      if L.MinSdk > MinSdk then
        MinSdk := L.MinSdk;
      if (L.Dir = '') or not FileExists(L.Dir + 'AndroidManifest.xml') then
        Continue;
      Doc := ReadXml(L.Dir + 'AndroidManifest.xml');
      try
        N := Doc.DocumentElement.FirstChild;
        while N <> nil do
        begin
          if (N.NodeType = ELEMENT_NODE) and (Attr(N, 'tools:node') <> 'remove') then
            case UTF8Encode(N.NodeName) of
              'uses-permission', 'uses-permission-sdk-23', 'permission', 'uses-feature':
                begin
                  Line := ElementText(N, L.PackageName, AppId, '  ');
                  Key := UTF8Encode(N.NodeName) + ' ' + StringReplace(Attr(N, 'android:name'), '${applicationId}', AppId, [rfReplaceAll]);
                  if (Names.IndexOf(Key) < 0) and
                     ((Attr(N, 'android:name') = '') or (Pos('"' + Attr(N, 'android:name') + '"', Have) = 0)) then
                  begin
                    Names.Add(Key);
                    Perms := Perms + Line;
                  end;
                end;
              'queries':
                Queries := Queries + ElementText(N, L.PackageName, AppId, '  ');
              'application':
                begin
                  C := N.FirstChild;
                  while C <> nil do
                  begin
                    if (C.NodeType = ELEMENT_NODE) and (Attr(C, 'tools:node') <> 'remove') then
                    begin
                      Line := ElementText(C, L.PackageName, AppId, '    ');
                      Key := 'app ' + UTF8Encode(C.NodeName) + ' ' + Attr(C, 'android:name');
                      if Names.IndexOf(Key) < 0 then
                      begin
                        Names.Add(Key);
                        Parts := Parts + Line;
                      end;
                    end;
                    C := C.NextSibling;
                  end;
                end;
            end;
          N := N.NextSibling;
        end;
      finally
        Doc.Free;
      end;
    end;
  finally
    Names.Free;
  end;
end;

function JarsHaveClass(const Jars: TStringArray; const ClassFile: string): Boolean;
var
  J: string;
  Z: TUnZipper;
  I: Integer;
begin
  Result := False;
  for J in Jars do
  begin
    Z := TUnZipper.Create;
    try
      Z.FileName := J;
      try
        Z.Examine;
        for I := 0 to Z.Entries.Count - 1 do
          if Z.Entries[I].ArchiveFileName = ClassFile then
            Exit(True);
      except
        { not a jar }
      end;
    finally
      Z.Free;
    end;
  end;
end;

function LibraryJars(const Libs: TAndroidLibraries): TStringArray;
var
  L: TAndroidLibrary;
begin
  Result := nil;
  for L in Libs do
    Result := Concat(Result, L.Jars);
end;

function GoogleServicesXml(const Root, AppId: string; out Err: string): string;
var
  Data: TJSONData;
  Info, Client, O: TJSONObject;
  Clients, Arr: TJSONArray;
  I, J: Integer;
  Values: TStringList;
  K: string;

  procedure Put(const Name, Value: string);
  begin
    if Value <> '' then
      Values.Add('  <string name="' + Name + '" translatable="false">' + XmlEscape(Value) + '</string>');
  end;

begin
  Result := '';
  Err := '';
  if not FileExists(Root + 'google-services.json') then
    Exit;
  try
    Data := GetJSON(ReadText(Root + 'google-services.json'));
  except
    on E: Exception do
    begin
      Err := 'google-services.json: ' + E.Message;
      Exit;
    end;
  end;
  Values := TStringList.Create;
  try
    if not (Data is TJSONObject) then
    begin
      Err := 'google-services.json is not Firebase''s file';
      Exit;
    end;
    Info := TJSONObject(Data).Get('project_info', TJSONObject(nil));
    Clients := TJSONObject(Data).Get('client', TJSONArray(nil));
    Client := nil;
    if Clients <> nil then
      for I := 0 to Clients.Count - 1 do
        if (Clients[I] is TJSONObject) then
        begin
          O := TJSONObject(Clients[I]).Get('client_info', TJSONObject(nil));
          if (O <> nil) and (O.Get('android_client_info', TJSONObject(nil)) <> nil) and
             (O.Objects['android_client_info'].Get('package_name', '') = AppId) then
            Client := TJSONObject(Clients[I]);
        end;
    if (Info = nil) or (Client = nil) then
    begin
      Err := Format('google-services.json has no app "%s" (Firebase console: add an Android app with that package name)',
        [AppId]);
      Exit;
    end;
    Put('gcm_defaultSenderId', Info.Get('project_number', ''));
    Put('project_id', Info.Get('project_id', ''));
    Put('google_storage_bucket', Info.Get('storage_bucket', ''));
    Put('firebase_database_url', Info.Get('firebase_url', ''));
    Put('google_app_id', Client.Objects['client_info'].Get('mobilesdk_app_id', ''));
    Arr := Client.Get('api_key', TJSONArray(nil));
    if (Arr <> nil) and (Arr.Count > 0) and (Arr[0] is TJSONObject) then
    begin
      K := TJSONObject(Arr[0]).Get('current_key', '');
      Put('google_api_key', K);
      Put('google_crash_reporting_api_key', K);
    end;
    Arr := Client.Get('oauth_client', TJSONArray(nil));
    if Arr <> nil then
      for J := 0 to Arr.Count - 1 do
        if (Arr[J] is TJSONObject) and (TJSONObject(Arr[J]).Get('client_type', 0) = 3) then
        begin
          Put('default_web_client_id', TJSONObject(Arr[J]).Get('client_id', ''));
          Break;
        end;
    Result := '<?xml version="1.0" encoding="utf-8"?>' + LineEnding + '<resources>' + LineEnding +
      Values.Text + '</resources>' + LineEnding;
  finally
    Values.Free;
    Data.Free;
  end;
end;

end.
