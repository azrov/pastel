{ Pastel - pictures from the web: posters, logos, avatars.

    B := WebImage('https://example.com/poster.jpg');   // nil while it comes
    if B <> nil then C.DrawBitmap(B, X, Y, W, H);

  Four threads fetch them (what is asked last, first: what is on the screen
  now); the window paints again when one comes. They are kept in memory (the
  ones used least go: MaxWebImages) and in a cache folder, made smaller on the
  way (WebImageMaxSide), so a list of thousands of posters stays light. A
  bitmap given by WebImage is for drawing at once: do not keep it.
  TImage.Url and TTileView use it. Part of the Pastel project, MIT License. }
unit Pastel.WebImages;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Graphics;

{ The picture, or nil while it comes (or when it failed: WebImageFailed). Main thread only. }
function WebImage(const Url: string): TBitmap32;
function WebImageFailed(const Url: string): Boolean;
{ Forgets the pictures in memory (not the cache folder). }
procedure ClearWebImages;
{ The cache folder (default: the user's cache folder / the program's name / images). }
function WebImageCacheDir: string;

var
  MaxWebImages: Integer = 250;
  { pictures are made smaller than this on the longer side (pixels) }
  WebImageMaxSide: Integer = 360;
  WebImageUserAgent: string = '';
  { '' : the default cache folder; set it to change the place }
  WebImageCache: string = '';

implementation

uses
  SyncObjs, Math, Pastel.Http, Pastel.Files, Pastel.Env, Pastel.UI;

type
  TImageLoader = class(TThread)
  protected
    procedure Execute; override;
  end;

  TArrival = class
    procedure Arrived;
  end;

var
  Lock: TCriticalSection;
  Images: TStringList;         { url -> TBitmap32 (nil: failed); main thread only }
  Done: TStringList;           { url -> TBitmap32 (nil: failed), from the loaders }
  Wanted: TStringList;         { urls to fetch, newest last }
  Busy: TStringList;           { urls being fetched }
  Loaders: array[0..3] of TImageLoader;
  Arrival: TArrival;
  Queued: Boolean;

function WebImageCacheDir: string;
var
  Base: string;
begin
  if WebImageCache <> '' then
    Exit(WebImageCache);
  {$IFDEF WINDOWS}
  Base := GetEnv('LOCALAPPDATA');
  {$ELSE}
  Base := GetEnv('XDG_CACHE_HOME');
  if (Base = '') and (GetEnv('HOME') <> '') then
    Base := JoinPath([GetEnv('HOME'), '.cache']);
  {$ENDIF}
  if Base = '' then
    Base := GetTempDir;
  Result := JoinPath([Base, ChangeFileExt(ExtractFileName(ParamStr(0)), ''), 'images']);
end;

{$push}{$Q-}{$R-}
function CacheFile(const Url: string): string;
var
  H: QWord;
  I: Integer;
begin
  { FNV-1a of the address: a short, safe name }
  H := QWord($CBF29CE484222325);
  for I := 1 to Length(Url) do
  begin
    H := H xor Ord(Url[I]);
    H := H * QWord($100000001B3);
  end;
  Result := IncludeTrailingPathDelimiter(WebImageCacheDir) + IntToHex(H, 16);
end;
{$pop}

{ a smaller copy (box filter) when it is bigger than MaxSide }
function Shrunk(B: TBitmap32; MaxSide: Integer): TBitmap32;
var
  W, H, X, Y, SX, SY, X0, X1, Y0, Y1, N: Integer;
  R, G, Bl, A: Cardinal;
  P: Cardinal;
  Scale: Double;
begin
  if (MaxSide <= 0) or (Max(B.Width, B.Height) <= MaxSide) then
    Exit(B);
  Scale := MaxSide / Max(B.Width, B.Height);
  W := Max(1, Round(B.Width * Scale));
  H := Max(1, Round(B.Height * Scale));
  Result := TBitmap32.Create;
  Result.SetSize(W, H);
  for Y := 0 to H - 1 do
  begin
    Y0 := Y * B.Height div H;
    Y1 := Max(Y0 + 1, (Y + 1) * B.Height div H);
    for X := 0 to W - 1 do
    begin
      X0 := X * B.Width div W;
      X1 := Max(X0 + 1, (X + 1) * B.Width div W);
      R := 0; G := 0; Bl := 0; A := 0; N := 0;
      for SY := Y0 to Y1 - 1 do
        for SX := X0 to X1 - 1 do
        begin
          P := B.Pixels[SY * B.Width + SX];
          Inc(A, P shr 24);
          Inc(R, (P shr 16) and $FF);
          Inc(G, (P shr 8) and $FF);
          Inc(Bl, P and $FF);
          Inc(N);
        end;
      Result.Pixels[Y * W + X] := ((A div N) shl 24) or ((R div N) shl 16) or ((G div N) shl 8) or (Bl div N);
    end;
  end;
  B.Free;
end;

procedure TArrival.Arrived;
begin
  Queued := False;
  { the controls that show web pictures paint again }
  InvalidateArea(RectI(0, 0, 0, 0));
end;

procedure TImageLoader.Execute;
var
  Url, F: string;
  B: TBitmap32;
  Http: THttpClient;
  R: THttpResponse;
  M: TMemoryStream;
begin
  Http := THttpClient.Create;
  try
    if WebImageUserAgent <> '' then
      Http.UserAgent := WebImageUserAgent;
    Http.Timeout := 20000;
    while not Terminated do
    begin
      Url := '';
      Lock.Enter;
      try
        if Wanted.Count > 0 then
        begin
          Url := Wanted[Wanted.Count - 1];
          Wanted.Delete(Wanted.Count - 1);
          Busy.Add(Url);
        end;
      finally
        Lock.Leave;
      end;
      if Url = '' then
      begin
        Sleep(25);
        Continue;
      end;
      B := TBitmap32.Create;
      M := TMemoryStream.Create;
      try
        try
          F := CacheFile(Url);
          if FileExists(F) then
            M.LoadFromFile(F)
          else
          begin
            if FileExists(Url) then
              M.LoadFromFile(Url)
            else
            begin
              R := Http.Get(Url);
              if R.Status <> 200 then
                raise Exception.CreateFmt('%d', [R.Status]);
              if R.Body <> '' then
                M.WriteBuffer(R.Body[1], Length(R.Body));
            end;
          end;
          M.Position := 0;
          B.LoadFromStream(M);
          B := Shrunk(B, WebImageMaxSide);
          if not FileExists(F) then
          try
            ForceDirectories(ExtractFileDir(F));
            M.SaveToFile(F);
          except
            { the cache is only a help }
          end;
        except
          FreeAndNil(B);
        end;
      finally
        M.Free;
      end;
      Lock.Enter;
      try
        Busy.Delete(Busy.IndexOf(Url));
        Done.AddObject(Url, B);
        if not Queued then
        begin
          Queued := True;
          TThread.Queue(nil, @Arrival.Arrived);
        end;
      finally
        Lock.Leave;
      end;
    end;
  finally
    Http.Free;
  end;
end;

{ what the loaders brought: into Images; the least used go when there are too many }
procedure TakeDone;
var
  I: Integer;
begin
  Lock.Enter;
  try
    for I := 0 to Done.Count - 1 do
      if Images.IndexOf(Done[I]) < 0 then
        Images.AddObject(Done[I], Done.Objects[I])
      else
        Done.Objects[I].Free;
    Done.Clear;
  finally
    Lock.Leave;
  end;
  while Images.Count > Max(16, MaxWebImages) do
  begin
    Images.Objects[0].Free;
    Images.Delete(0);
  end;
end;

function WebImage(const Url: string): TBitmap32;
var
  I: Integer;
begin
  Result := nil;
  if Url = '' then
    Exit;
  if Done.Count > 0 then
    TakeDone;
  I := Images.IndexOf(Url);
  if I >= 0 then
  begin
    Result := TBitmap32(Images.Objects[I]);
    { used: the newest }
    if I < Images.Count - 1 then
      Images.Move(I, Images.Count - 1);
    Exit;
  end;
  Lock.Enter;
  try
    if Busy.IndexOf(Url) >= 0 then
      Exit;
    I := Wanted.IndexOf(Url);
    if I >= 0 then
      Wanted.Delete(I);
    Wanted.Add(Url);
    { what scrolled away long ago: not fetched }
    if Wanted.Count > 200 then
      Wanted.Delete(0);
    if Loaders[0] = nil then
    begin
      IsMultiThread := True;
      for I := 0 to High(Loaders) do
        Loaders[I] := TImageLoader.Create(False);
    end;
  finally
    Lock.Leave;
  end;
end;

function WebImageFailed(const Url: string): Boolean;
var
  I: Integer;
begin
  if Done.Count > 0 then
    TakeDone;
  I := Images.IndexOf(Url);
  Result := (I >= 0) and (Images.Objects[I] = nil);
end;

procedure ClearWebImages;
var
  I: Integer;
begin
  for I := 0 to Images.Count - 1 do
    Images.Objects[I].Free;
  Images.Clear;
end;

procedure ImageHook(const Url: string; out B: TBitmap32; out Failed: Boolean);
begin
  B := WebImage(Url);
  Failed := (B = nil) and WebImageFailed(Url);
end;

var
  I: Integer;

initialization
  Lock := TCriticalSection.Create;
  Images := TStringList.Create;
  Done := TStringList.Create;
  Wanted := TStringList.Create;
  Busy := TStringList.Create;
  Arrival := TArrival.Create;
  WebImageHook := @ImageHook;

finalization
  { a loader may wait for a slow server: they end with the program (nothing
    they use is freed) }
  for I := 0 to High(Loaders) do
    if Loaders[I] <> nil then
      Loaders[I].Terminate;
  if Loaders[0] = nil then
  begin
    ClearWebImages;
    Images.Free;
    Done.Free;
    Wanted.Free;
    Busy.Free;
    Arrival.Free;
    Lock.Free;
  end;
end.
