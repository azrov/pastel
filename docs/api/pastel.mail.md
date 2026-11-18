# Pastel.Mail

E-mail: messages sent with SMTP (a mail server, or a service like
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

`uses Pastel.Mail;` · source: [framework/src/pastel.mail.pas](../../framework/src/pastel.mail.pas)

**Contents:** [ESmtpError](#esmtperror) · [TMailSecurity](#tmailsecurity) · [TMailAttachment](#tmailattachment) · [TMailMessage](#tmailmessage) · [TMailer](#tmailer) · [MailAddressOf](#mailaddressof) · [CaptureMails](#capturemails) · [CapturedMails](#capturedmails) · [ClearCapturedMails](#clearcapturedmails)

## Types

### ESmtpError

```pascal
type ESmtpError = class(Exception)
```

### TMailSecurity

```pascal
type TMailSecurity = (msAuto, msTls, msStartTls, msNone)
```

- `msAuto` 465: TLS; else STARTTLS when the server offers it, and it must for a password
- `msTls` TLS from the start
- `msStartTls` plain, then STARTTLS (required)
- `msNone` never TLS: a mail server on this computer or in the same private network
### TMailAttachment

```pascal
type TMailAttachment = record
```

| | |
|---|---|
| `Name: string` |  |
| `ContentType: string` |  |
| `Data: RawByteString` |  |

### TMailMessage

```pascal
type TMailMessage = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure AddTo(const Address: string; const Name: string = '')` |  |
| `procedure AddCc(const Address: string; const Name: string = '')` |  |
| `procedure AddBcc(const Address: string; const Name: string = '')` |  |
| `procedure Attach(const FileName: string; const Name: string = ''; const ContentType: string = '')` |  |
| `procedure AttachBytes(const Data: TBytes; const Name: string; const ContentType: string)` |  |
| `procedure AddHeader(const Name: string; const Value: string)` | a header of your own: 'List-Unsubscribe', '<https://...>' |
| `property Recipients: TStringList` | 'Name <address>' lines |
| `property Cc: TStringList` |  |
| `property Bcc: TStringList` |  |
| `property AttachmentCount: Integer` |  |
| `property Attachments[I: Integer]: TMailAttachment` |  |
| `function ToText(const DefaultFrom: string = ''): string` | the message as sent (RFC 5322 and MIME), without Bcc |

### TMailer

```pascal
type TMailer = class
```

| | |
|---|---|
| `constructor Create(const AHost: string = ''; APort: Integer = 0)` | Port 0: 587 (465 with msTls, 25 with msNone) |
| `constructor FromConfig(C: TConfig; const Section: string = 'mail')` | [mail] host, port, user, password, from, security ("auto", "tls", "starttls", "none") |
| `procedure Send(M: TMailMessage)` | sends M and frees it |
| `procedure Send(const ATo: string; const ASubject: string; const AText: string)` |  |

## Routines

### MailAddressOf

```pascal
function MailAddressOf(const S: string): string
```

'Ayşe Kaya <ayse@example.com>' -> 'ayse@example.com'

### CaptureMails

```pascal
procedure CaptureMails(Enable: Boolean = True)
```

Tests: messages are kept (Mails, as ToText gives them) instead of being sent or logged.

### CapturedMails

```pascal
function CapturedMails: TStringArray
```

### ClearCapturedMails

```pascal
procedure ClearCapturedMails
```

