{ Tests of Pastel.NativeViews on a computer: where a native view goes, the
  web box, sound through a player program. }
unit nativeviews_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Controls, Pastel.NativeViews;

type
  TNativeViewsTests = class(TTestSuite)
  private
    FJson: string;
    FCompleted, FPrepared: Integer;
    FError: string;
    procedure JsDone(Sender: TObject; const Json: string);
    procedure Completed(Sender: TObject);
    procedure Prepared(Sender: TObject);
    procedure Failed(Sender: TObject; const Message: string);
  published
    procedure ShownOnlyWhereSeen;
    procedure WebBrowserOnAComputer;
    procedure SoundThroughAPlayer;
  end;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF} Pastel.Env, Pastel.Files;

type
  TSeenView = class(TWebBrowser)
  public
    function Seen(out R, S: TRectI): Boolean;
  end;

function TSeenView.Seen(out R, S: TRectI): Boolean;
begin
  Result := OnScreen(R, S);
end;

function Twice(const R: TRectI): TRectI;
begin
  Result := RectI(R.X * 2, R.Y * 2, R.W * 2, R.H * 2);
end;

procedure TNativeViewsTests.JsDone(Sender: TObject; const Json: string);
begin
  FJson := Json;
end;

procedure TNativeViewsTests.Completed(Sender: TObject);
begin
  Inc(FCompleted);
end;

procedure TNativeViewsTests.Prepared(Sender: TObject);
begin
  Inc(FPrepared);
end;

procedure TNativeViewsTests.Failed(Sender: TObject; const Message: string);
begin
  FError := Message;
end;

procedure TNativeViewsTests.ShownOnlyWhereSeen;
var
  F: TForm;
  Box: TScrollBox;
  V: TSeenView;
  R, S: TRectI;
  Menu: TPopup;
  Old: TForm;
begin
  Old := MainForm;
  F := TForm.Create(nil);
  try
    MainForm := F;
    WindowPixelRect := @Twice;
    Box := TScrollBox.Create(F);
    Box.Parent := F;
    Box.Height := 100;
    V := TSeenView.Create(F);
    V.Parent := Box;
    V.Height := 300;
    F.Layout(400, 300);
    AssertTrue(V.Seen(R, S), 'on the form');
    AssertEquals(300, R.H);
    AssertEquals(100, S.H, 'the scroll box cuts it');
    V.Visible := False;
    F.Layout(400, 300);
    AssertFalse(V.Seen(R, S), 'hidden');
    V.Visible := True;
    Box.Visible := False;
    F.Layout(400, 300);
    AssertFalse(V.Seen(R, S), 'its parent hidden');
    Box.Visible := True;
    F.Layout(400, 300);
    Menu := TPopup.Create(F);
    Menu.Width := 50;
    Menu.Height := 20;
    Menu.Popup(F, RectI(300, 200, 20, 20));
    F.Layout(400, 300);
    AssertTrue(V.Seen(R, S), 'a menu elsewhere leaves it');
    F.ClosePopup(Menu);
    Menu.Popup(F, RectI(10, 10, 20, 20));
    F.Layout(400, 300);
    AssertFalse(V.Seen(R, S), 'a menu over it hides it');
    F.ClosePopup(Menu);
    Menu.Modal := True;
    F.ShowPopup(Menu);
    AssertFalse(V.Seen(R, S), 'a dialog (the window dimmed) hides it');
    F.ClosePopup(Menu);
    AssertTrue(V.Seen(R, S));
    MainForm := nil;
    AssertFalse(V.Seen(R, S), 'a form not on the screen');
  finally
    MainForm := Old;
    WindowPixelRect := nil;
    F.Free;
  end;
end;

procedure TNativeViewsTests.WebBrowserOnAComputer;
var
  W: TWebBrowser;
begin
  W := TWebBrowser.Create(nil);
  try
    W.Navigate('https://example.com/');
    AssertEquals('https://example.com/', W.Url);
    AssertFalse(W.CanGoBack);
    FJson := '';
    W.EvaluateJavaScript('1 + 1', @JsDone);
    AssertEquals('null', FJson, 'no page to run it in');
    W.LoadHtml('<h1>Hi</h1>');
    AssertEquals('', W.Url);
  finally
    W.Free;
  end;
end;

procedure TNativeViewsTests.SoundThroughAPlayer;
var
  Dir, OldPath: string;
  P: TMediaPlayer;
  Until_: QWord;
begin
  {$IFDEF UNIX}
  Dir := MakeTempDir('pastel-player');
  OldPath := GetEnv('PATH');
  try
    { a "player" that plays for a moment and writes what it was given }
    WriteText(Dir + 'mpv', '#!/bin/sh' + LineEnding + 'echo "$@" > "' + Dir + 'args"' + LineEnding + 'sleep 0.3' + LineEnding);
    fpChmod(Dir + 'mpv', &755);
    SetEnv('PATH', ExcludeTrailingPathDelimiter(Dir) + ':/bin:/usr/bin');
    P := TMediaPlayer.Create(nil);
    try
      P.OnCompleted := @Completed;
      P.OnPrepared := @Prepared;
      P.OnError := @Failed;
      P.Url := '/music/song.mp3';
      P.Volume := 0.5;
      FCompleted := 0;
      P.Play;
      AssertTrue(P.Playing, FError);
      AssertEquals(1, FPrepared);
      Until_ := GetTickCount64 + 3000;
      while (FCompleted = 0) and (GetTickCount64 < Until_) do
      begin
        ProcessTimers(GetTickCount64);
        Sleep(20);
      end;
      AssertEquals(1, FCompleted, 'the end of the sound');
      AssertFalse(P.Playing);
      AssertTrue(Pos('/music/song.mp3', ReadText(Dir + 'args')) > 0);
      AssertTrue(Pos('--volume=50', ReadText(Dir + 'args')) > 0);
      { no player at all: said so }
      SetEnv('PATH', '/nonexistent');
      FError := '';
      P.Play;
      AssertFalse(P.Playing);
      AssertTrue(Pos('mpv', FError) > 0, FError);
    finally
      P.Free;
    end;
  finally
    SetEnv('PATH', OldPath);
    DeleteDir(Dir);
  end;
  {$ENDIF}
end;

initialization
  RegisterTests(TNativeViewsTests);

end.
