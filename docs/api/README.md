# Pastel API reference

Made from the declarations and comments in `framework/src` (`npm run apidoc` in `vscode/`). The guides in [docs/](..) explain how the parts fit together.

| Unit | |
|---|---|
| [Pastel.Accessibility](pastel.accessibility.md) | Screen readers: what is on the screen, for people who cannot see it. |
| [Pastel.Additional](pastel.additional.md) | More standard controls, like the "Additional" page of Delphi's palette: |
| [Pastel.Android](pastel.android.md) | The bridge to Android: an app is a NativeActivity, so it needs no |
| [Pastel.Animate](pastel.animate.md) | Animations: a property goes to a new value smoothly. |
| [Pastel.App](pastel.app.md) | The application: window, event loop, hot reload. |
| [Pastel.Args](pastel.args.md) | Command-line arguments. |
| [Pastel.Assets](pastel.assets.md) | The files of a project's assets/ folder, inside the program. |
| [Pastel.Auth](pastel.auth.md) | Users, passwords and roles for a server, and login for its apps. |
| [Pastel.Background](pastel.background.md) | Work that goes on when the app is not on the screen. |
| [Pastel.Barcode](pastel.barcode.md) | QR codes and barcodes: made (drawn) by Pastel, for screens, labels and reports. |
| [Pastel.Binding](pastel.binding.md) | Data binding: fills a form's controls from a record and back. |
| [Pastel.Charts](pastel.charts.md) | Charts: bars, lines, pies and donuts, drawn by Pastel (the same on |
| [Pastel.Cipher](pastel.cipher.md) | Encryption: AES-256-GCM, and text sealed with a password. |
| [Pastel.Config](pastel.config.md) | Settings from files, environment variables and code. |
| [Pastel.Controls](pastel.controls.md) | More controls: check boxes, radio buttons, switches, lists, |
| [Pastel.CrashReport](pastel.crashreport.md) | Crash reports: what went wrong on users' machines, sent to you. |
| [Pastel.Crypto](pastel.crypto.md) | Hashes, signatures, passwords and random tokens. |
| [Pastel.Db](pastel.db.md) | Databases: SQLite, PostgreSQL, MySQL/MariaDB. |
| [Pastel.Device](pastel.device.md) | The phone's features: share, open, vibrate, notify, pick a file, |
| [Pastel.Dialogs](pastel.dialogs.md) | Dialogs: messages, questions, input, choosing files and folders. |
| [Pastel.Env](pastel.env.md) | Environment variables. |
| [Pastel.Files](pastel.files.md) | Files, folders and paths. |
| [Pastel.Forms](pastel.forms.md) | Building forms from .pform data. |
| [Pastel.Graphics](pastel.graphics.md) | Software 2D drawing: colors, an anti-aliased canvas and fonts. |
| [Pastel.Grids](pastel.grids.md) | Tables and trees. |
| [Pastel.Http](pastel.http.md) | HTTP and HTTPS client. |
| [Pastel.Icons](pastel.icons.md) | Icons: small line drawings for buttons, drawn at any size and in |
| [Pastel.Inputs](pastel.inputs.md) | Inputs for business apps: dates, amounts of money, numbers and times. |
| [Pastel.Java](pastel.java.md) | Java from Pascal: any class of Android (or of the app's own Java |
| [Pastel.Json](pastel.json.md) | JSON made easy, on top of Free Pascal's fpjson. |
| [Pastel.Jwt](pastel.jwt.md) | JSON Web Tokens (JWT) signed with HS256. |
| [Pastel.Lang](pastel.lang.md) | Translations and the number and date formats of a language. |
| [Pastel.Log](pastel.log.md) | Logging. |
| [Pastel.Mail](pastel.mail.md) | E-mail: messages sent with SMTP (a mail server, or a service like |
| [Pastel.Maps](pastel.maps.md) | A map in a form: TMapView. |
| [Pastel.Markdown](pastel.markdown.md) | Markdown to HTML, the way GitHub shows it. |
| [Pastel.Menus](pastel.menus.md) | Menus: a menu bar, pop-up (right click) menus and keyboard |
| [Pastel.NativeDialogs](pastel.nativedialogs.md) | The system's own open, save and folder dialogs. |
| [Pastel.NativeViews](pastel.nativeviews.md) | The phone's own views in a form: web pages, video, and sound. |
| [Pastel.Notifications.Android](pastel.notifications.android.md) | Notifications on Android (used by Pastel.Notifications): the |
| [Pastel.Notifications.Linux](pastel.notifications.linux.md) | Notifications on Linux (used by Pastel.Notifications): the |
| [Pastel.Notifications.Mac](pastel.notifications.mac.md) | Notifications on macOS (used by Pastel.Notifications): the |
| [Pastel.Notifications](pastel.notifications.md) | Notifications: a message in the system's notification area, now or |
| [Pastel.Notifications.Windows](pastel.notifications.windows.md) | Notifications on Windows (used by Pastel.Notifications): a message |
| [Pastel.Pages](pastel.pages.md) | HTML pages from templates, in the style of Laravel's Blade. |
| [Pastel.Pdf](pastel.pdf.md) | PDF files: pages with text, lines, boxes and pictures. |
| [Pastel.PForm](pastel.pform.md) | Reader for .pform files. |
| [Pastel.Print](pastel.print.md) | Printing and opening documents with the system. |
| [Pastel.Process](pastel.process.md) | Running other programs. |
| [Pastel.Push](pastel.push.md) | Push messages: a server sends, the phone shows (Firebase Cloud Messaging). |
| [Pastel.Report](pastel.report.md) | Reports: invoices, lists, letters as PDF (and HTML), written |
| [Pastel.SecureStore](pastel.securestore.md) | Secrets kept by the system: tokens, passwords, keys. |
| [Pastel.Sensors](pastel.sensors.md) | The phone's senses: motion, compass, light, steps; and NFC tags. |
| [Pastel.Serial](pastel.serial.md) | Serial ports: scales, barcode readers, cash drawers, receipt printers, Arduino boards. |
| [Pastel.Service](pastel.service.md) | Long-running programs (services, daemons). |
| [Pastel.Sheets](pastel.sheets.md) | Spreadsheets: Excel files (.xlsx) and CSV, written and read. |
| [Pastel.Speech](pastel.speech.md) | The app speaks, and listens. |
| [Pastel.Sync](pastel.sync.md) | Data that works offline and is synchronized with a server: the |
| [Pastel.SyncWeb](pastel.syncweb.md) | The server side of Pastel.Sync: one route that clients sync with. |
| [Pastel.Syntax](pastel.syntax.md) | Syntax highlighting for TMemo (and TEdit): SQL, Pascal, JSON. |
| [Pastel.Term](pastel.term.md) | Terminal output and input for console programs. |
| [Pastel.Testing](pastel.testing.md) | Unit testing. |
| [Pastel.Text](pastel.text.md) | Text helpers that understand UTF-8. |
| [Pastel.Tiles](pastel.tiles.md) | TTileView: many items with pictures, as a grid of tiles (posters) |
| [Pastel.Toml](pastel.toml.md) | A small TOML reader for pastel.toml files. |
| [Pastel.Tray](pastel.tray.md) | A desktop app in the system tray, and keys that work everywhere. |
| [Pastel.TrueType](pastel.truetype.md) | TrueType fonts in plain Pascal: reads a .ttf (or the first font of a |
| [Pastel.UI](pastel.ui.md) | Controls, layout and input handling. |
| [Pastel.Updater](pastel.updater.md) | The app updates itself. |
| [Pastel.VideoPlayer](pastel.videoplayer.md) | TVideoPlayer: video and live streams in the form, on computers and phones. |
| [Pastel.Web](pastel.web.md) | HTTP server for web APIs and sites. |
| [Pastel.WebImages](pastel.webimages.md) | Pictures from the web: posters, logos, avatars. |
| [Pastel.WebSocket](pastel.websocket.md) | WebSockets: a connection that stays open, messages both ways (chat, |
| [Pastel.Workers](pastel.workers.md) | Background work: a thread-safe queue and a pool of worker threads. |
| [Pastel.Xml](pastel.xml.md) | Writing XML: e-invoices, exports, feeds, settings for other programs. |
