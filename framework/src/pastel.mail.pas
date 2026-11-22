{ Pastel - e-mail: messages sent with SMTP (a mail server, or a service like
  Amazon SES, Mailgun, SendGrid, Gmail with an app password).

    Mailer := TMailer.FromConfig(Config);          // [mail] host, port, user, password, from
    Mailer.Send('ayse@example.com', 'Your appointment', 'Tomorrow at 10:00.');

    M := TMailMessage.Create;
    M.AddTo('ayse@example.com', 'Ayşe Kaya');
    M.Subject := 'Invoice 2026-114';
    M.Text := 'The invoice is attached.';
    M.Html := '<p>The invoice is <b>attached</b>.</p>';
    M.AttachBytes(Report.ToBytes, 'invoice.pdf', 'application/pdf');
    Mailer.Send(M);                                // frees M

  TLS: port 465 is TLS from the start, 587 (and 25) start plain and switch
  with STARTTLS; the server's certificate is checked like HTTPS's. Without a
  host (development) a message is written to the log instead of being sent;
  CaptureMails keeps them for tests. ESmtpError says what the server answered.
  Part of the Pastel project, MIT License. }
unit Pastel.Mail;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Pastel.Http, Pastel.Config;

type
  ESmtpError = class(Exception);

  TMailSecurity = (
    msAuto,       { 465: TLS; else STARTTLS when the server offers it, and it must for a password }
    msTls,        { TLS from the start }
    msStartTls,   { plain, then STARTTLS (required) }
    msNone        { never TLS: a mail server on this computer or in the same private network }
  );

  TMailAttachment = record
    Name, ContentType: string;
    Data: RawByteString;
  end;

  TMailMessage = class
  private
    FTo, FCc, FBcc: TStringList;
    FAttachments: array of TMailAttachment;
    FHeaders: TStringList;
    function GetAttachmentCount: Integer;
    function GetAttachment(I: Integer): TMailAttachment;
  public
    { 'Name <address>' or 'address'; '' takes the mailer's From }
    From: string;
    ReplyTo: string;
    Subject: string;
    { the plain text; with Html too, mail programs choose }
    Text: string;
    Html: string;
    constructor Create;
    destructor Destroy; override;
    procedure AddTo(const Address: string; const Name: string = '');
    procedure AddCc(const Address: string; const Name: string = '');
    procedure AddBcc(const Address: string; const Name: string = '');
    procedure Attach(const FileName: string; const Name: string = ''; const ContentType: string = '');
    procedure AttachBytes(const Data: TBytes; const Name, ContentType: string);
    { a header of your own: 'List-Unsubscribe', '<https://...>' }
    procedure AddHeader(const Name, Value: string);
    { 'Name <address>' lines }
    property Recipients: TStringList read FTo;
    property Cc: TStringList read FCc;
    property Bcc: TStringList read FBcc;
    property AttachmentCount: Integer read GetAttachmentCount;
    property Attachments[I: Integer]: TMailAttachment read GetAttachment;
    { the message as sent (RFC 5322 and MIME), without Bcc }
    function ToText(const DefaultFrom: string = ''): string;
  end;

  TMailer = class
  public
    Host: string;
    Port: Integer;
    User, Password: string;
    Security: TMailSecurity;
    { 'Name <address>': the sender of messages without one }
    From: string;
    { milliseconds for connecting and for each answer; default 30000 }
    Timeout: Integer;
    { Leave on. Off accepts any certificate (tests only). }
    VerifyCertificates: Boolean;
    { the name this computer says in EHLO; default its host name }
    HeloName: string;
    { Port 0: 587 (465 with msTls, 25 with msNone) }
    constructor Create(const AHost: string = ''; APort: Integer = 0);
    { [mail] host, port, user, password, from, security ("auto", "tls", "starttls", "none") }
    constructor FromConfig(C: TConfig; const Section: string = 'mail');
    { sends M and frees it }
    procedure Send(M: TMailMessage);
    procedure Send(const ATo, ASubject, AText: string);
  end;

{ 'Ayşe Kaya <ayse@example.com>' -> 'ayse@example.com' }
function MailAddressOf(const S: string): string;

{ Tests: messages are kept (Mails, as ToText gives them) instead of being sent or logged. }
procedure CaptureMails(Enable: Boolean = True);
function CapturedMails: TStringArray;
procedure ClearCapturedMails;

implementation

uses
  base64, Pastel.Log, Pastel.Files{$IFDEF UNIX}, Unix{$ENDIF};

var
  Captured: TStringList = nil;
  Capturing: Boolean = False;
  CaptureLock: TCriticalSection;

procedure CaptureMails(Enable: Boolean);
begin
  Capturing := Enable;
end;

function CapturedMails: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  CaptureLock.Enter;
  try
    SetLength(Result, Captured.Count);
    for I := 0 to Captured.Count - 1 do
      Result[I] := Captured[I];
  finally
    CaptureLock.Leave;
  end;
end;

procedure ClearCapturedMails;
begin
  CaptureLock.Enter;
  try
    Captured.Clear;
  finally
    CaptureLock.Leave;
  end;
end;

{ ---------------- text ---------------- }

function MailAddressOf(const S: string): string;
var
  A, B: Integer;
begin
  A := Pos('<', S);
  B := Pos('>', S);
  if (A > 0) and (B > A) then
    Result := Trim(Copy(S, A + 1, B - A - 1))
  else
    Result := Trim(S);
end;

function IsAscii(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if (Ord(C) > 126) or ((Ord(C) < 32) and (C <> #9)) then
      Exit(False);
  Result := True;
end;

{ a header's text: RFC 2047's =?UTF-8?B?...?= when it is not ASCII }
function HeaderText(const S: string): string;
begin
  if IsAscii(S) then
    Result := S
  else
    Result := '=?UTF-8?B?' + EncodeStringBase64(S) + '?=';
end;

{ 'Ayşe Kaya <ayse@x.com>' with the name encoded }
function HeaderAddress(const S: string): string;
var
  A: Integer;
  Name: string;
begin
  A := Pos('<', S);
  if A = 0 then
    Exit(Trim(S));
  Name := Trim(Copy(S, 1, A - 1));
  if (Length(Name) >= 2) and (Name[1] = '"') and (Name[Length(Name)] = '"') then
    Name := Copy(Name, 2, Length(Name) - 2);
  if Name = '' then
    Exit('<' + MailAddressOf(S) + '>');
  if IsAscii(Name) then
  begin
    if Name.IndexOfAny(['(', ')', '<', '>', '[', ']', ':', ';', '@', '\', ',', '.', '"']) >= 0 then
      Name := '"' + StringReplace(Name, '"', '\"', [rfReplaceAll]) + '"';
  end
  else
    Name := HeaderText(Name);
  Result := Name + ' <' + MailAddressOf(S) + '>';
end;

{ base64 in lines of 76 }
function Base64Lines(const Data: RawByteString): string;
var
  B: string;
  I: Integer;
begin
  B := EncodeStringBase64(Data);
  Result := '';
  I := 1;
  while I <= Length(B) do
  begin
    Result := Result + Copy(B, I, 76) + #13#10;
    Inc(I, 76);
  end;
end;

{ line ends as CR LF }
function CrLf(const S: string): string;
begin
  Result := StringReplace(StringReplace(S, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

function MailDate(T: TDateTime): string;
const
  Days: array[1..7] of string = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
  Months: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  Y, Mo, D: Word;
  Bias: Integer;
begin
  DecodeDate(T, Y, Mo, D);
  Bias := -GetLocalTimeOffset;     { minutes east of UTC }
  Result := Format('%s, %d %s %d %s %s%.2d%.2d', [Days[DayOfWeek(T)], D, Months[Mo], Y, FormatDateTime('hh:nn:ss', T),
    Copy('+-', Ord(Bias < 0) + 1, 1), Abs(Bias) div 60, Abs(Bias) mod 60]);
end;

function Boundary: string;
begin
  Result := '=_pastel_' + IntToHex(Random($7FFFFFFF), 8) + IntToHex(Random($7FFFFFFF), 8);
end;

function GuessType(const FileName: string): string;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  case E of
    '.pdf': Result := 'application/pdf';
    '.png': Result := 'image/png';
    '.jpg', '.jpeg': Result := 'image/jpeg';
    '.gif': Result := 'image/gif';
    '.txt': Result := 'text/plain; charset=utf-8';
    '.csv': Result := 'text/csv; charset=utf-8';
    '.html', '.htm': Result := 'text/html; charset=utf-8';
    '.json': Result := 'application/json';
    '.zip': Result := 'application/zip';
    '.xlsx': Result := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    '.docx': Result := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  else
    Result := 'application/octet-stream';
  end;
end;

{ ---------------- TMailMessage ---------------- }

constructor TMailMessage.Create;
begin
  inherited Create;
  FTo := TStringList.Create;
  FCc := TStringList.Create;
  FBcc := TStringList.Create;
  FHeaders := TStringList.Create;
end;

destructor TMailMessage.Destroy;
begin
  FHeaders.Free;
  FBcc.Free;
  FCc.Free;
  FTo.Free;
  inherited Destroy;
end;

function Named(const Address, Name: string): string;
begin
  if Name = '' then
    Result := Address
  else
    Result := Name + ' <' + Address + '>';
end;

procedure TMailMessage.AddTo(const Address, Name: string);
begin
  FTo.Add(Named(Address, Name));
end;

procedure TMailMessage.AddCc(const Address, Name: string);
begin
  FCc.Add(Named(Address, Name));
end;

procedure TMailMessage.AddBcc(const Address, Name: string);
begin
  FBcc.Add(Named(Address, Name));
end;

procedure TMailMessage.Attach(const FileName, Name, ContentType: string);
var
  N: string;
begin
  N := Name;
  if N = '' then
    N := ExtractFileName(FileName);
  AttachBytes(ReadBytes(FileName), N, ContentType);
end;

procedure TMailMessage.AttachBytes(const Data: TBytes; const Name, ContentType: string);
var
  A: TMailAttachment;
begin
  SetLength(A.Data, Length(Data));
  if Length(Data) > 0 then
    Move(Data[0], A.Data[1], Length(Data));
  A.Name := Name;
  A.ContentType := ContentType;
  if A.ContentType = '' then
    A.ContentType := GuessType(Name);
  FAttachments := Concat(FAttachments, [A]);
end;

procedure TMailMessage.AddHeader(const Name, Value: string);
begin
  FHeaders.Add(Name + ': ' + Value);
end;

function TMailMessage.GetAttachmentCount: Integer;
begin
  Result := Length(FAttachments);
end;

function TMailMessage.GetAttachment(I: Integer): TMailAttachment;
begin
  Result := FAttachments[I];
end;

function TMailMessage.ToText(const DefaultFrom: string): string;
var
  H, Body, B1, B2, F, S: string;
  I: Integer;
  A: TMailAttachment;

  function List(L: TStrings): string;
  var
    J: Integer;
  begin
    Result := '';
    for J := 0 to L.Count - 1 do
    begin
      if J > 0 then
        Result := Result + ','#13#10' ';
      Result := Result + HeaderAddress(L[J]);
    end;
  end;

  function TextPart(const Kind, Content: string): string;
  begin
    Result := 'Content-Type: text/' + Kind + '; charset=utf-8'#13#10;
    if IsAscii(StringReplace(StringReplace(Content, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll])) then
      Result := Result + 'Content-Transfer-Encoding: 7bit'#13#10#13#10 + CrLf(Content) + #13#10
    else
      Result := Result + 'Content-Transfer-Encoding: base64'#13#10#13#10 + Base64Lines(CrLf(Content));
  end;

begin
  F := From;
  if F = '' then
    F := DefaultFrom;
  H := 'From: ' + HeaderAddress(F) + #13#10;
  if FTo.Count > 0 then
    H := H + 'To: ' + List(FTo) + #13#10;
  if FCc.Count > 0 then
    H := H + 'Cc: ' + List(FCc) + #13#10;
  if ReplyTo <> '' then
    H := H + 'Reply-To: ' + HeaderAddress(ReplyTo) + #13#10;
  H := H + 'Subject: ' + HeaderText(Subject) + #13#10 +
    'Date: ' + MailDate(Now) + #13#10 +
    'Message-ID: <' + LowerCase(IntToHex(Random($7FFFFFFF), 8) + IntToHex(GetTickCount64, 12)) + '.pastel@' +
      Copy(MailAddressOf(F), Pos('@', MailAddressOf(F)) + 1, MaxInt) + '>'#13#10 +
    'MIME-Version: 1.0'#13#10;
  for S in FHeaders do
    H := H + S + #13#10;
  { the text: plain, HTML, or both to choose from }
  if (Html <> '') and (Text <> '') then
  begin
    B2 := Boundary;
    Body := 'Content-Type: multipart/alternative; boundary="' + B2 + '"'#13#10#13#10 +
      '--' + B2 + #13#10 + TextPart('plain', Text) + '--' + B2 + #13#10 + TextPart('html', Html) + '--' + B2 + '--'#13#10;
  end
  else if Html <> '' then
    Body := TextPart('html', Html)
  else
    Body := TextPart('plain', Text);
  if Length(FAttachments) > 0 then
  begin
    B1 := Boundary;
    S := 'Content-Type: multipart/mixed; boundary="' + B1 + '"'#13#10#13#10 + '--' + B1 + #13#10 + Body;
    for I := 0 to High(FAttachments) do
    begin
      A := FAttachments[I];
      S := S + '--' + B1 + #13#10 +
        'Content-Type: ' + A.ContentType + '; name="' + HeaderText(A.Name) + '"'#13#10 +
        'Content-Disposition: attachment; filename="' + HeaderText(A.Name) + '"'#13#10 +
        'Content-Transfer-Encoding: base64'#13#10#13#10 + Base64Lines(A.Data);
    end;
    Body := S + '--' + B1 + '--'#13#10;
  end;
  Result := H + Body;
end;

{ ---------------- SMTP ---------------- }

type
  { one conversation with the server }
  TSmtp = class
  private
    FMailer: TMailer;
    FConn: TNetConnection;
    FExtensions: TStringList;
    FTlsAsked: Boolean;
    function Answer(Conn: TNetConnection; out Text: string): Integer;
    function Command(Conn: TNetConnection; const Line: string; Expect: Integer; const What: string): string;
    procedure Hello(Conn: TNetConnection);
    function StartTls(Conn: TNetConnection): string;
  public
    constructor Create(AMailer: TMailer);
    destructor Destroy; override;
    procedure Open;
    procedure SendMessage(const Sender: string; const Rcpt: TStringArray; const Data: string);
    procedure Quit;
  end;

constructor TSmtp.Create(AMailer: TMailer);
begin
  inherited Create;
  FMailer := AMailer;
  FExtensions := TStringList.Create;
end;

destructor TSmtp.Destroy;
begin
  FConn.Free;
  FExtensions.Free;
  inherited Destroy;
end;

{ the server's answer, all its lines: 250-first / 250 last }
function TSmtp.Answer(Conn: TNetConnection; out Text: string): Integer;
var
  L: string;
begin
  Text := '';
  repeat
    L := Conn.ReadLine;
    if Text <> '' then
      Text := Text + #10;
    Text := Text + Copy(L, 5, MaxInt);
  until (Length(L) < 4) or (L[4] <> '-');
  Result := StrToIntDef(Copy(L, 1, 3), 0);
end;

function TSmtp.Command(Conn: TNetConnection; const Line: string; Expect: Integer; const What: string): string;
var
  Code: Integer;
begin
  if Line <> '' then
    Conn.WriteText(Line + #13#10);
  Code := Answer(Conn, Result);
  if Code div 100 <> Expect div 100 then
    raise ESmtpError.CreateFmt('the mail server %s refused %s: %d %s',
      [FMailer.Host, What, Code, StringReplace(Result, #10, ' ', [rfReplaceAll])]);
end;

procedure TSmtp.Hello(Conn: TNetConnection);
var
  Text: string;
  Name: string;
begin
  Name := FMailer.HeloName;
  if Name = '' then
    {$IFDEF UNIX}Name := GetHostName{$ELSE}Name := GetEnvironmentVariable('COMPUTERNAME'){$ENDIF};
  if Name = '' then
    Name := 'localhost';
  Text := Command(Conn, 'EHLO ' + Name, 250, 'EHLO');
  FExtensions.Text := UpperCase(Text);
end;

{ before TLS: the greeting, EHLO, STARTTLS }
function TSmtp.StartTls(Conn: TNetConnection): string;
begin
  Result := '';
  Command(Conn, '', 220, 'the connection');
  Hello(Conn);
  if FExtensions.IndexOf('STARTTLS') < 0 then
  begin
    if FMailer.Security = msStartTls then
      Exit(Format('the mail server %s does not offer STARTTLS', [FMailer.Host]));
    Exit('-plain');      { msAuto: the plain connection goes on }
  end;
  Command(Conn, 'STARTTLS', 220, 'STARTTLS');
  FTlsAsked := True;
end;

procedure TSmtp.Open;
var
  Port: Integer;
  Text: string;
begin
  Port := FMailer.Port;
  case FMailer.Security of
    msTls:
      FConn := NetConnect(FMailer.Host, Port, True, nil, FMailer.Timeout, FMailer.VerifyCertificates, FMailer.Timeout);
    msNone:
      FConn := NetConnect(FMailer.Host, Port, False, nil, FMailer.Timeout, True, FMailer.Timeout);
    msStartTls:
      FConn := NetConnect(FMailer.Host, Port, True, @StartTls, FMailer.Timeout, FMailer.VerifyCertificates, FMailer.Timeout);
    msAuto:
      if Port = 465 then
        FConn := NetConnect(FMailer.Host, Port, True, nil, FMailer.Timeout, FMailer.VerifyCertificates, FMailer.Timeout)
      else
      try
        FConn := NetConnect(FMailer.Host, Port, True, @StartTls, FMailer.Timeout, FMailer.VerifyCertificates, FMailer.Timeout);
      except
        on E: ENetError do
          if E.Message = '-plain' then
          begin
            { no STARTTLS: plain, but then no password goes over it }
            if FMailer.User <> '' then
              raise ESmtpError.CreateFmt('the mail server %s does not offer STARTTLS: the password would go unencrypted ' +
                '(security = "none" if that is really wanted)', [FMailer.Host]);
            FConn := NetConnect(FMailer.Host, Port, False, nil, FMailer.Timeout, True, FMailer.Timeout);
          end
          else
            raise;
      end;
  end;
  if (FMailer.Security in [msTls, msNone]) or not FTlsAsked then
    Command(FConn, '', 220, 'the connection');
  Hello(FConn);
  { the password: AUTH PLAIN, else LOGIN }
  if FMailer.User <> '' then
  begin
    Text := '';
    if FExtensions.Count > 0 then
      Text := ' ' + FExtensions.Text;
    if Pos('PLAIN', Text) > 0 then
      Command(FConn, 'AUTH PLAIN ' + EncodeStringBase64(#0 + FMailer.User + #0 + FMailer.Password), 235, 'the user name and password')
    else
    begin
      Command(FConn, 'AUTH LOGIN', 334, 'AUTH LOGIN');
      Command(FConn, EncodeStringBase64(FMailer.User), 334, 'the user name');
      Command(FConn, EncodeStringBase64(FMailer.Password), 235, 'the user name and password');
    end;
  end;
end;

procedure TSmtp.SendMessage(const Sender: string; const Rcpt: TStringArray; const Data: string);
var
  R, Body: string;
begin
  Command(FConn, 'MAIL FROM:<' + Sender + '>', 250, 'the sender ' + Sender);
  for R in Rcpt do
    Command(FConn, 'RCPT TO:<' + R + '>', 250, 'the recipient ' + R);
  Command(FConn, 'DATA', 354, 'DATA');
  { a line starting with a dot gets one more }
  Body := StringReplace(#13#10 + Data, #13#10'.', #13#10'..', [rfReplaceAll]);
  Delete(Body, 1, 2);
  if not Body.EndsWith(#13#10) then
    Body := Body + #13#10;
  FConn.WriteText(Body + '.'#13#10);
  Command(FConn, '', 250, 'the message');
end;

procedure TSmtp.Quit;
var
  Text: string;
begin
  try
    FConn.WriteText('QUIT'#13#10);
    Answer(FConn, Text);
  except
    { the message is sent; how the server says goodbye does not matter }
  end;
end;

{ ---------------- TMailer ---------------- }

constructor TMailer.Create(const AHost: string; APort: Integer);
begin
  inherited Create;
  Host := AHost;
  Port := APort;
  Timeout := 30000;
  VerifyCertificates := True;
end;

constructor TMailer.FromConfig(C: TConfig; const Section: string);
var
  S: string;
begin
  Create(C.Get(Section + '.host'), C.GetInt(Section + '.port', 0));
  User := C.Get(Section + '.user');
  Password := C.Get(Section + '.password');
  From := C.Get(Section + '.from');
  S := LowerCase(C.Get(Section + '.security', 'auto'));
  case S of
    'tls', 'ssl': Security := msTls;
    'starttls': Security := msStartTls;
    'none': Security := msNone;
    'auto': Security := msAuto;
  else
    raise EConfigError.CreateFmt('%s.security must be "auto", "tls", "starttls" or "none", not "%s"', [Section, S]);
  end;
end;

procedure TMailer.Send(const ATo, ASubject, AText: string);
var
  M: TMailMessage;
begin
  M := TMailMessage.Create;
  M.AddTo(ATo);
  M.Subject := ASubject;
  M.Text := AText;
  Send(M);
end;

procedure TMailer.Send(M: TMailMessage);
var
  Data, Sender, S: string;
  Rcpt: TStringArray;
  Smtp: TSmtp;
  Saved: Integer;
begin
  try
    if (M.From = '') and (From = '') then
      raise ESmtpError.Create('a message needs a sender: TMailer.From ([mail] from) or the message''s From');
    if M.Recipients.Count + M.Cc.Count + M.Bcc.Count = 0 then
      raise ESmtpError.Create('a message needs a recipient');
    Data := M.ToText(From);
    if Capturing then
    begin
      CaptureLock.Enter;
      try
        Captured.Add(Data);
      finally
        CaptureLock.Leave;
      end;
      Exit;
    end;
    if Host = '' then
    begin
      { development: no mail server set; the message goes to the log }
      Log.Fields(['to', M.Recipients.CommaText, 'subject', M.Subject]).Info(
        'mail not sent: no mail server set ([mail] host)'#10 + M.Text);
      Exit;
    end;
    Rcpt := nil;
    for S in M.Recipients do
      Rcpt := Concat(Rcpt, [MailAddressOf(S)]);
    for S in M.Cc do
      Rcpt := Concat(Rcpt, [MailAddressOf(S)]);
    for S in M.Bcc do
      Rcpt := Concat(Rcpt, [MailAddressOf(S)]);
    if M.From <> '' then
      Sender := MailAddressOf(M.From)
    else
      Sender := MailAddressOf(From);
    Saved := Port;
    if Port = 0 then
      case Security of
        msTls: Port := 465;
        msNone: Port := 25;
      else
        Port := 587;
      end;
    Smtp := TSmtp.Create(Self);
    try
      try
        Smtp.Open;
        Smtp.SendMessage(Sender, Rcpt, Data);
        Smtp.Quit;
      except
        on E: ENetError do
          raise ESmtpError.CreateFmt('the mail server %s:%d: %s', [Host, Port, E.Message]);
      end;
    finally
      Smtp.Free;
      Port := Saved;
    end;
  finally
    M.Free;
  end;
end;

initialization
  Captured := TStringList.Create;
  CaptureLock := TCriticalSection.Create;
  Randomize;

finalization
  CaptureLock.Free;
  Captured.Free;
end.
