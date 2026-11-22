{ Tests of Pastel.Mail: the message's text (MIME) and a conversation with a
  small SMTP server of the test's own. }
unit mail_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Sockets, base64, Pastel.Testing, Pastel.Mail;

type
  { a mail server that takes every message (no TLS) and keeps what it was told }
  TFakeSmtp = class(TThread)
  private
    FListener: TSocket;
    FLock: TCriticalSection;
    FLog: TStringList;
    FData: TStringList;
    procedure Serve(S: TSocket);
  public
    Port: Word;
    Extensions: string;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
    function Log: string;
    function LastData: string;
  end;

  TMailTests = class(TTestSuite)
  private
    FServer: TFakeSmtp;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure MessageText;
    procedure NamesAndSubjectsInUtf8;
    procedure Attachments;
    procedure SentWithSmtp;
    procedure PasswordNeverGoesPlainUnasked;
    procedure WithoutPasswordPlainIsFine;
    procedure RefusedRecipient;
    procedure CapturedForTests;
    procedure Sha1ForWebSockets;
    procedure TlsAndStartTls;
  end;

implementation

uses
  Pastel.Crypto{$IFDEF UNIX}, BaseUnix{$ENDIF};

{ ---- the fake server ---- }

constructor TFakeSmtp.Create;
var
  A: TInetSockAddr;
  L: TSockLen;
begin
  FLock := TCriticalSection.Create;
  FLog := TStringList.Create;
  FData := TStringList.Create;
  Extensions := '250-AUTH PLAIN LOGIN'#13#10'250 8BITMIME';
  FListener := fpSocket(AF_INET, SOCK_STREAM, 0);
  A := Default(TInetSockAddr);
  A.sin_family := AF_INET;
  A.sin_addr := StrToNetAddr('127.0.0.1');
  A.sin_port := 0;
  fpBind(FListener, @A, SizeOf(A));
  fpListen(FListener, 4);
  L := SizeOf(A);
  fpGetSockName(FListener, @A, @L);
  Port := NToHs(A.sin_port);
  inherited Create(False);
end;

destructor TFakeSmtp.Destroy;
begin
  Terminate;
  fpShutdown(FListener, 2);
  CloseSocket(FListener);
  WaitFor;
  FData.Free;
  FLog.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TFakeSmtp.Execute;
var
  S: TSocket;
begin
  while not Terminated do
  begin
    S := fpAccept(FListener, nil, nil);
    if (S < 0) or Terminated then
      Break;
    try
      Serve(S);
    except
    end;
    CloseSocket(S);
  end;
end;

procedure TFakeSmtp.Serve(S: TSocket);

  procedure Say(const T: string);
  var
    X: string;
  begin
    X := T + #13#10;
    fpSend(S, @X[1], Length(X), 0);
  end;

  function Hear(out L: string): Boolean;
  var
    C: Char;
  begin
    L := '';
    repeat
      if fpRecv(S, @C, 1, 0) <> 1 then
        Exit(False);
      if C = #10 then
        Break;
      if C <> #13 then
        L := L + C;
    until False;
    Result := True;
  end;

var
  L, D: string;
begin
  Say('220 fake.test ESMTP');
  while Hear(L) do
  begin
    FLock.Enter;
    FLog.Add(L);
    FLock.Leave;
    if L.StartsWith('EHLO') then
      Say('250-fake.test'#13#10 + Extensions)
    else if L.StartsWith('AUTH PLAIN') then
      Say('235 ok')
    else if L.StartsWith('MAIL FROM') then
      Say('250 ok')
    else if L.StartsWith('RCPT TO:<nobody@') then
      Say('550 5.1.1 no such user')
    else if L.StartsWith('RCPT TO') then
      Say('250 ok')
    else if L = 'DATA' then
    begin
      Say('354 go on');
      D := '';
      while Hear(L) and (L <> '.') do
        D := D + L + #10;
      FLock.Enter;
      FData.Add(D);
      FLock.Leave;
      Say('250 queued');
    end
    else if L = 'QUIT' then
    begin
      Say('221 bye');
      Exit;
    end
    else
      Say('500 what?');
  end;
end;

function TFakeSmtp.Log: string;
begin
  FLock.Enter;
  try
    Result := FLog.Text;
  finally
    FLock.Leave;
  end;
end;

function TFakeSmtp.LastData: string;
begin
  FLock.Enter;
  try
    if FData.Count = 0 then
      Result := ''
    else
      Result := FData[FData.Count - 1];
  finally
    FLock.Leave;
  end;
end;

{ ---- the tests ---- }

procedure TMailTests.SetUp;
begin
  FServer := nil;
end;

procedure TMailTests.TearDown;
begin
  CaptureMails(False);
  ClearCapturedMails;
  FServer.Free;
end;

procedure TMailTests.MessageText;
var
  M: TMailMessage;
  T: string;
begin
  M := TMailMessage.Create;
  try
    M.From := 'Salon <salon@example.com>';
    M.AddTo('ali@example.com');
    M.AddCc('veli@example.com', 'Veli');
    M.AddBcc('hidden@example.com');
    M.Subject := 'Tomorrow';
    M.Text := 'Hello'#10'.a line with a dot';
    T := M.ToText;
  finally
    M.Free;
  end;
  AssertTrue(Pos('From: Salon <salon@example.com>'#13#10, T) > 0, T);
  AssertTrue(Pos('To: ali@example.com'#13#10, T) > 0, T);
  AssertTrue(Pos('Cc: Veli <veli@example.com>'#13#10, T) > 0, T);
  AssertFalse(Pos('hidden', T) > 0, 'Bcc is not in the message');
  AssertTrue(Pos('Subject: Tomorrow'#13#10, T) > 0, T);
  AssertTrue(Pos('Content-Type: text/plain; charset=utf-8', T) > 0, T);
  AssertTrue(Pos('Hello'#13#10'.a line', T) > 0, 'CR LF line ends');
  AssertTrue(Pos('Message-ID: <', T) > 0);
  AssertTrue(Pos('@example.com>', T) > 0);
end;

procedure TMailTests.NamesAndSubjectsInUtf8;
var
  M: TMailMessage;
  T: string;
begin
  M := TMailMessage.Create;
  try
    M.From := 'salon@example.com';
    M.AddTo('ayse@example.com', 'Ayşe Kaya');
    M.Subject := 'Randevunuz yarın';
    M.Text := 'Görüşmek üzere';
    M.Html := '<p>Görüşmek üzere</p>';
    T := M.ToText;
  finally
    M.Free;
  end;
  AssertTrue(Pos('To: =?UTF-8?B?' + EncodeStringBase64('Ayşe Kaya') + '?= <ayse@example.com>', T) > 0, T);
  AssertTrue(Pos('Subject: =?UTF-8?B?' + EncodeStringBase64('Randevunuz yarın') + '?=', T) > 0, T);
  AssertTrue(Pos('multipart/alternative', T) > 0, T);
  AssertTrue(Pos('text/html', T) > 0, T);
  AssertTrue(Pos(EncodeStringBase64('Görüşmek üzere'), T) > 0, 'the text in base64');
end;

procedure TMailTests.Attachments;
var
  M: TMailMessage;
  T: string;
  B: TBytes;
begin
  B := TBytes.Create(37, 80, 68, 70);   { %PDF }
  M := TMailMessage.Create;
  try
    M.From := 'a@example.com';
    M.AddTo('b@example.com');
    M.Text := 'attached';
    M.AttachBytes(B, 'fatura.pdf', '');
    AssertEquals(1, M.AttachmentCount);
    AssertEquals('application/pdf', M.Attachments[0].ContentType);
    T := M.ToText;
  finally
    M.Free;
  end;
  AssertTrue(Pos('multipart/mixed', T) > 0, T);
  AssertTrue(Pos('filename="fatura.pdf"', T) > 0, T);
  AssertTrue(Pos(EncodeStringBase64('%PDF'), T) > 0, T);
end;

procedure TMailTests.SentWithSmtp;
var
  Mailer: TMailer;
  M: TMailMessage;
begin
  FServer := TFakeSmtp.Create;
  Mailer := TMailer.Create('127.0.0.1', FServer.Port);
  try
    Mailer.Security := msNone;
    Mailer.User := 'salon';
    Mailer.Password := 'gizli';
    Mailer.From := 'Salon <salon@example.com>';
    M := TMailMessage.Create;
    M.AddTo('ali@example.com');
    M.AddBcc('boss@example.com');
    M.Subject := 'Hi';
    M.Text := 'first'#10'.dot';
    Mailer.Send(M);
  finally
    Mailer.Free;
  end;
  AssertTrue(Pos('AUTH PLAIN ' + EncodeStringBase64(#0'salon'#0'gizli'), FServer.Log) > 0, FServer.Log);
  AssertTrue(Pos('MAIL FROM:<salon@example.com>', FServer.Log) > 0, FServer.Log);
  AssertTrue(Pos('RCPT TO:<ali@example.com>', FServer.Log) > 0, FServer.Log);
  AssertTrue(Pos('RCPT TO:<boss@example.com>', FServer.Log) > 0, 'Bcc gets it too');
  AssertTrue(Pos('QUIT', FServer.Log) > 0, FServer.Log);
  AssertTrue(Pos('Subject: Hi', FServer.LastData) > 0, FServer.LastData);
  AssertTrue(Pos(#10'..dot'#10, FServer.LastData) > 0, 'a dot at a line''s start is doubled');
end;

procedure TMailTests.PasswordNeverGoesPlainUnasked;
var
  Mailer: TMailer;
  Msg: string;
begin
  FServer := TFakeSmtp.Create;     { offers no STARTTLS }
  Mailer := TMailer.Create('127.0.0.1', FServer.Port);
  try
    Mailer.User := 'salon';
    Mailer.Password := 'gizli';
    Mailer.From := 'salon@example.com';
    Msg := '';
    try
      Mailer.Send('ali@example.com', 'x', 'y');
    except
      on E: ESmtpError do
        Msg := E.Message;
    end;
  finally
    Mailer.Free;
  end;
  AssertTrue(Pos('STARTTLS', Msg) > 0, Msg);
  AssertFalse(Pos('AUTH', FServer.Log) > 0, 'the password was not sent');
end;

procedure TMailTests.WithoutPasswordPlainIsFine;
var
  Mailer: TMailer;
begin
  FServer := TFakeSmtp.Create;
  Mailer := TMailer.Create('127.0.0.1', FServer.Port);
  try
    Mailer.From := 'salon@example.com';
    Mailer.Send('ali@example.com', 'Plain', 'text');
  finally
    Mailer.Free;
  end;
  AssertTrue(Pos('Subject: Plain', FServer.LastData) > 0, FServer.Log);
end;

procedure TMailTests.RefusedRecipient;
var
  Mailer: TMailer;
  Msg: string;
begin
  FServer := TFakeSmtp.Create;
  Mailer := TMailer.Create('127.0.0.1', FServer.Port);
  try
    Mailer.Security := msNone;
    Mailer.From := 'salon@example.com';
    Msg := '';
    try
      Mailer.Send('nobody@example.com', 'x', 'y');
    except
      on E: ESmtpError do
        Msg := E.Message;
    end;
  finally
    Mailer.Free;
  end;
  AssertTrue(Pos('nobody@example.com', Msg) > 0, Msg);
  AssertTrue(Pos('550', Msg) > 0, Msg);
end;

procedure TMailTests.CapturedForTests;
var
  Mailer: TMailer;
begin
  CaptureMails;
  Mailer := TMailer.Create('mail.invalid');
  try
    Mailer.From := 'salon@example.com';
    Mailer.Send('ali@example.com', 'Kept', 'not sent');
  finally
    Mailer.Free;
  end;
  AssertEquals(1, Length(CapturedMails));
  AssertTrue(Pos('Subject: Kept', CapturedMails[0]) > 0);
end;

procedure TMailTests.Sha1ForWebSockets;
begin
  AssertEquals('a9993e364706816aba3e25717850c26c9cd0d89d', ToHex(Sha1('abc')));
  AssertEquals('da39a3ee5e6b4b0d3255bfef95601890afd80709', ToHex(Sha1('')));
  AssertEquals('84983e441c3bd26ebaae4aa1f95129e5e54670f1',
    ToHex(Sha1('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')));
end;

{ a real mail server with TLS (tests/smtp-tls.py, started by tests/run.sh):
  PASTEL_TEST_SMTP=localhost:<starttls port>:<tls port>, its certificate in SSL_CERT_FILE }
procedure TMailTests.TlsAndStartTls;
var
  P: TStringArray;
  Mailer: TMailer;
  Msg: string;
begin
  P := GetEnvironmentVariable('PASTEL_TEST_SMTP').Split([':']);
  if Length(P) <> 3 then
    Skip('PASTEL_TEST_SMTP is not set (tests/run.sh starts a mail server)');
  { STARTTLS, required by the server, with a password }
  Mailer := TMailer.Create(P[0], StrToInt(P[1]));
  try
    Mailer.User := 'salon';
    Mailer.Password := 'gizli';
    Mailer.From := 'Salon <salon@example.com>';
    Mailer.Send('ali@example.com', 'Over STARTTLS', 'secret text');
  finally
    Mailer.Free;
  end;
  { TLS from the start }
  Mailer := TMailer.Create(P[0], StrToInt(P[2]));
  try
    Mailer.Security := msTls;
    Mailer.User := 'salon';
    Mailer.Password := 'gizli';
    Mailer.From := 'salon@example.com';
    Mailer.Send('veli@example.com', 'Over TLS', 'text');
  finally
    Mailer.Free;
  end;
  { a certificate for another name is refused }
  Mailer := TMailer.Create('127.0.0.1', StrToInt(P[2]));
  try
    Mailer.Security := msTls;
    Mailer.From := 'salon@example.com';
    Msg := '';
    try
      Mailer.Send('veli@example.com', 'x', 'y');
    except
      on E: ESmtpError do
        Msg := E.Message;
    end;
    AssertTrue(Pos('not trusted', Msg) > 0, Msg);
  finally
    Mailer.Free;
  end;
end;

initialization
  RegisterTests(TMailTests);

end.
