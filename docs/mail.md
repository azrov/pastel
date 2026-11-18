# E-mail: `Pastel.Mail`

Messages sent with SMTP: a password reset, an invoice, a reminder of an appointment. Any mail server works — your
own, a mail service (Amazon SES, Mailgun, SendGrid, Brevo), or a mailbox with an app password (Gmail, Outlook).

```pascal
uses Pastel.Mail;

Mailer := TMailer.FromConfig(Config);
Mailer.Send('ayse@example.com', 'Your appointment', 'Tomorrow at 10:00. See you!');
```

```toml
# config.toml
[mail]
host = "smtp.example.com"
port = 587
user = "salon@example.com"
password = ""              # MYAPP_MAIL_PASSWORD in the environment, not in the file
from = "Salon Ayşe <salon@example.com>"
```

## Messages

```pascal
M := TMailMessage.Create;
M.AddTo('ayse@example.com', 'Ayşe Kaya');
M.AddCc('kasa@example.com');
M.AddBcc('arsiv@example.com');
M.ReplyTo := 'destek@example.com';
M.Subject := 'Fatura 2026-114';
M.Text := 'Faturanız ektedir.';
M.Html := '<p>Faturanız <b>ektedir</b>.</p>';
M.AttachBytes(Report.ToBytes, 'fatura-2026-114.pdf', 'application/pdf');
M.Attach('price-list.xlsx');
Mailer.Send(M);            // frees M
```

With `Text` and `Html` both, mail programs show the one they can; names, subjects and texts in any language are
encoded for mail (UTF-8). `From` of the message, if set, is used instead of the mailer's.

## TLS and passwords

| `security` | |
|---|---|
| `"auto"` (default) | port 465: TLS from the start; else STARTTLS when the server offers it — and it must when there is a password |
| `"tls"` | TLS from the start (port 465) |
| `"starttls"` | plain, then STARTTLS; a server without it is refused |
| `"none"` | never TLS: a mail server on the same computer or private network |

The server's certificate is checked like HTTPS's ([system.md](system.md)). With `"auto"` a password never goes
over a connection that is not encrypted: a server without STARTTLS gets an error instead. On Android the phone's
own TLS is used.

## Errors

`ESmtpError` says what went wrong and what the server answered:

```
the mail server smtp.example.com refused the user name and password: 535 5.7.8 authentication failed
the mail server smtp.example.com refused the recipient nobody@example.com: 550 5.1.1 no such user
the mail server smtp.example.com:587: cannot connect to smtp.example.com:587 (is the server running? is the port right?)
```

Sending takes a moment (seconds with a slow server): in a web server it runs in the request's thread; in an app,
send from a worker (`Pastel.Workers`) so the window does not wait.

## While developing, and in tests

Without `host`, a message is not sent: it is written to the log, so a program can be developed without a mail
server. In tests `CaptureMails` keeps the messages instead of sending them:

```pascal
CaptureMails;
Shop.ResetPassword('ayse@example.com');
AssertEquals(1, Length(CapturedMails));
AssertTrue(Pos('Subject: Password reset', CapturedMails[0]) > 0);
```
