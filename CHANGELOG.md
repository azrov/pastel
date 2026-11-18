# Changelog

The `pastel` tool and the framework. The VS Code extension has its own list: [vscode/CHANGELOG.md](vscode/CHANGELOG.md). What is planned is in [ROADMAP.md](ROADMAP.md).

## 2.1.0-beta.2

The phone's features that were missing (see [docs/device.md](docs/device.md)):

- Links that open the app: `[package] links = ["shop://", "https://shop.example.com/app"]` and a `TLinkReceiver` (`OnLink`, also for the link that started the app). Android: the app's own scheme and its site's addresses (`pastel package apk` writes `dist/assetlinks.json` with the key's fingerprint for the site). Computers: the `.deb` and the Windows installer register the app's scheme, the app starts with the address
- The icon's shortcuts (a long press on it, Android 7.1+): `SetAppShortcuts([AppShortcut('new', 'New appointment', 'add')])`, a built-in icon for each; `TLinkReceiver.OnShortcut` gets which
- Contacts: `PickContact` (the phone's list, no permission), `ReadContacts` (all, with a search), `AddContact` (the contacts app, filled in)
- The calendar: `AddToCalendar` (the calendar app, filled in; on computers an `.ics` file in the calendar program), `ReadCalendar` (the events between two times)
- Picture-in-picture (Android 8+): `[package.android] picture_in_picture = true`, `EnterPictureInPicture`, `AutoPictureInPicture` (by itself when the user goes home), `InPictureInPicture`
- `OpenUrlHook` for tests; `LinkFromArguments`

## 2.1.0-beta.1

Styles: each platform's own look, and styles of your own (like FireMonkey's styles and `TStyleBook`). See [docs/styles.md](docs/styles.md).

- `style = "auto"` in `assets/theme.toml`: Fluent (Windows 11) on Windows, Material 3 on Android, Pastel elsewhere; or `"pastel"`, `"fluent"`, `"material"` everywhere. Without it an app looks as before
- A style sets the sizes, corners, borders and colors of buttons, edits, combo boxes, date pickers, checkboxes, radio buttons, switches, sliders, progress bars, lists, popups and dialogs, the keyboard's focus (a ring, or an outline), and the order of a dialog's buttons (Windows: OK Cancel; Material: text buttons)
- Style files: `assets/styles/<name>.pstyle` (TOML) starts from a `base` style and changes its colors (light and dark), `[button]`, `[flat_button]`, `[field]`, `[check]`, `[switch]`, `[slider]`, `[progress]`, `[popup]`, `[dialog]`, `[focus]`; a mistake is said with the value and why
- Looks: `[look.Name]` in a style file, used by a control's `StyleLookup` (buttons, labels, boxes, edits, combo boxes), with a `[look.Name.dark]` for the dark theme; `pastel check` warns about a look no style has
- From code: `UseStyle('material')`, `UIStyle` (the sizes of the style in use), `LoadStyle`, `FindLook`; for controls of your own `DrawFocus`, `PaintField`, `FieldHeight`, `StyleRadius`
- `PASTEL_STYLE=fluent` tries a style without changing a file; `pastel preview --style material`; the preview and the designer draw forms in the app's style and `assets/theme.toml` colors
- `pastel new app` writes `assets/theme.toml` with `style = "auto"`
- `assets/theme.toml`: `outline` (the border of edits in Fluent and Material)
- Danger buttons' text is dark on a light red (dark themes)

## 2.0.0-beta.15

Drawing is many times quicker, in debug builds too:

- A full window of a grid: 75 ms → 3 ms (1080p), 284 ms → 15 ms (4K); tiles 56 ms → 7 ms (4K) — smooth scrolling and animations on big and HiDPI screens
- Rounded rectangles are measured only at their edges; see-through fills work out each background color once; text is clipped per letter, not per pixel
- Scaled pictures (posters, photos, maps): about 13 times quicker, and the pixels at their edges no longer take color from their neighbors
- The same pixels as before (tests compare them with the pixel-by-pixel way)

## 2.0.0-beta.14

- Fixed: `TVideoPlayer` said "libmpv could not start" on computers in Turkish (and other languages that write 1,5): libmpv starts with C's numbers now
- Fixed: `TVideoPlayer` could freeze the app: libmpv's frames are drawn on a thread of their own now (libmpv waits for them), with float exceptions off as C code expects
- `pastel setup android --yes` fetches Google's command-line tools (sdkmanager) into `~/Android/Sdk` when there is no sdkmanager (Ubuntu's packages), then installs the platform and build tools
- The newest build tools of the SDKs come before an older `aapt` on the `PATH`
- A library made against a newer Android than the platform here (`androidx.core`: API 31) is said before packing, with what to install — not aapt2's "resource android:attr/lStar not found"

## 2.0.0-beta.13

From building Pastel TV, an IPTV player made with Pastel:

- `TVideoPlayer` (`Pastel.VideoPlayer`): video and live streams in the form — libmpv draws into the window on computers (HLS, MPEG-TS, MP4, MKV), ExoPlayer (when the app has it in `libraries`) or MediaPlayer on Android; audio tracks and subtitles (`Tracks`, `SelectTrack`), `Seek`, `UserAgent`, an info band (`ShowInfo`), `OnTap`/`OnDoubleTap`, `OnKeyDown` for a TV's remote
- `TTileView` (`Pastel.Tiles`): thousands of items with pictures as a grid of tiles or a list of rows, drawn only where seen; the arrows move between the tiles and go on at the edges (a remote)
- Pictures from the web: `TImage.Url`, `WebImage(Url)` (`Pastel.WebImages`): fetched on four threads, made smaller, kept in memory and in a cache folder
- `Res.SendFile` answers `Range` requests (206): videos seek, downloads go on
- `FitText`: a text cut to a width with '…', quick for long texts
- Fixed: in a language that writes 1,5 (Turkish, German...) icons were drawn wrong and PDFs, Excel files and the media players got 1,5 where they need 1.5 — `InvariantFormat` (`Pastel.Env`) for numbers of files and programs
- Fixed: `TTrayIcon.IconFile` changed while shown changes the icon (Linux)
- `pastel check`: a control named like a member of the form (`Loading`, `Title`, `Changed`...) is an error before the compiler says "Duplicate identifier"
- The build of the `pastel` tool has no notes left
- Designer palette: `TVideoPlayer` (Media), `TTileView` (Lists and tables)

## 2.0.0-beta.12

- Fixed: a TGrid with long texts in its cells (a database's text column: 100 KB in a cell) froze the app — cutting a text to its cell measured it once for every letter. Now only what can fit is measured, the cut found by halving, and a line break ends what a cell shows; 200 such rows paint in milliseconds

## 2.0.0-beta.11

- Fixed: on Linux (X11) a click whose event handler worked long (a slow query) left the whole desktop without clicks until it ended — SDL took the screen's mouse while a button was down. Pastel takes it now only while something is dragged
- `RunInBackground(Work, Done, Data)` (`Pastel.Workers`, `TBackgroundTask`): long work on a thread of its own, `Done` on the main thread, `Error`, `Cancel`; the window stays alive

## 2.0.0-beta.10

From building Pastel DB, a database client made with Pastel:

- Code in a memo: `OnHighlight` colors the text (`Pastel.Syntax`: `Syntax.Sql`, `Syntax.Pascal`, `Syntax.Json`, `HighlightCode` for another language; the theme's `SyntaxColor`s, light and dark)
- Words offered while typing: `Completions` and `OnCompletions` on TEdit and TMemo — a list under the caret (Up/Down, Enter or Tab, Escape, Ctrl+Space), the part after a dot completed (`orders.cu` → `customer_id`); `SqlKeywords`
- An exception an event handler does not catch no longer ends a window app: its message is shown and the app goes on, as in Delphi; `Application.OnException`, `HandleException`; reported by `Pastel.CrashReport` (where: `event`)
- `QueryValue` gives a fractional number as `20.5` (not `2.05E+001`)
- `pastel check`: a form named like the program's file (`Main.pform` next to `main.pas`) is an error (the compiler mixes the two up)

## 2.0.0-beta.9

What other toolkits have, now here too:

- Forms in windows of their own: `Form.Show` (computers; phones show it over the main form), `Showing`, closed by `Close`, a `ModalResult` button or the window's close button
- `Pastel.Animate`: `Animate(Control, 'Height', 240)`, `AnimateColor`, nine easings, `Repeating`/`Reverse`, `StopAnimations`
- Gestures: two fingers pinch and turn (Ctrl and the wheel on computers) → `OnGesture` / `TControl.Gesture`; `TMapView` zooms with them
- Drag and drop between controls: `DragMode = dmAutomatic`, `OnStartDrag`, `OnDragOver`, `OnDragDrop`, `OnEndDrag`, `Form.BeginDrag`; a finger too
- Screen readers: TalkBack reads Pastel's controls (kind, text, state) and clicks them (`Pastel.Accessibility`); `AccessibleName`
- `Pastel.Cipher`: AES-256-GCM (`AesGcmEncrypt`/`Decrypt`), `EncryptText`/`DecryptText` with a password (PBKDF2); NIST's vectors
- `Pastel.SecureStore`: `SecureSet`, `SecureGet`, `SecureDelete` - Android Keystore, Windows DPAPI, the Linux keyring (secret-tool)
- `Pastel.Barcode`: QR codes (every version and level, the best mask), Code 128, EAN-13; `TBarcode`, `BarcodeBitmap`, `SaveBarcodePng` (checked with ZXing); `ScanBarcode` on phones with Google's code scanner
- `Pastel.Serial`: serial ports (termios, Windows COM): `TSerialPort`, `ReadLine`, DTR/RTS, `ListSerialPorts`
- `Pastel.CrashReport`: uncaught exceptions kept and sent at the next start; `ReportError`
- `Pastel.Updater`: `CheckForUpdate`, `DownloadUpdate` (SHA-256 checked), `InstallUpdate` (Windows installer, AppImage, .apk); `pastel update-manifest`; `[package.android] permissions = ["install_updates"]`
- `Pastel.Speech`: `Speak`, `StopSpeaking`, `IsSpeaking` (Android, spd-say/espeak, Windows' voice, macOS); `Listen` (speech to text on phones)
- `Pastel.Sensors`: `TSensor` (accelerometer, gyroscope, compass, light, proximity, steps, pressure), `TNfcReader` (`["nfc"]`), `TBluetoothLE` (scan, connect, read, write, notifications)
- `Pastel.Tray`: `TTrayIcon` with a menu (Windows; Linux through libayatana-appindicator), `RegisterHotKey` (Windows, X11)
- Designer palette: `TBarcode`

## 2.0.0-beta.8

- `TMapView` (`Pastel.Maps`): a map drawn by Pastel from map tiles, the same on phones and computers — moved by a finger or the mouse, zoomed by a double tap, the wheel, + − buttons and the keys; markers (`OnMarkerClick`, the title of the one tapped), routes, `OnMapClick` with the place, `FitAll`, `PlaceAt`, `PointOf`; tiles of any server (`TileUrl`, default OpenStreetMap with its attribution) on a thread of their own, kept in memory and in a cache folder, a smaller zoom's tile shown while one comes
- `TCameraView`: the camera's picture in a form (Android's Camera2): `Start` (asks for the permission), `TakePhoto` (a JPEG the right way up, `OnPhoto`), `Front`, `Torch`
- `Authenticate(Reason, @Done)` and `CanAuthenticate` (`Pastel.Device`): the fingerprint, the face or the PIN — BiometricPrompt on Android 9 and newer, the lock screen's check on older ones; `[package.android] permissions = ["biometric"]`
- Push messages (`Pastel.Push`, `TPushNotifications`): Firebase Cloud Messaging — `RequestToken` (`OnToken`), `Subscribe`, `OnMessage` while the app is on the screen or when its notification opened it (`Opened`, `Data`); data messages shown as notifications when the app is not on the screen. `pastel package` puts Pastel's push service in when `libraries` has Firebase's messaging. `PushTestMessage` for tests
- Native views: a menu or drop-down no longer hides a web page, video or camera unless it is over them (a dialog or a drawer still does)
- `framework/android/stubs.jar`: newer Android classes Pastel's Java is compiled against (only on newer phones at run time)

## 2.0.0-beta.7

Android, the rest of the comparison with other toolkits:

- Android libraries: `[package.android] libraries` takes Maven coordinates (`androidx.browser:browser:1.8.0`; what each needs comes with it, the highest version wins, test and optional ones stay out, versions from parent POMs) and `.aar`/`.jar` files of the project; `repositories` (default: Google's and Maven Central; a folder works too), fetched once into `~/.pastel/maven/`. An `.aar` brings its classes (dexed with the app, with R classes for its resources; classes2.dex... beyond 64K methods), resources (`aapt2`), assets, native libraries for the app's CPUs and its manifest's permissions, activities, services, receivers, providers; the app starts from the highest Android version a library asks for. `pastel java add/search` see their classes. `google-services.json` becomes Firebase's values
- `Pastel.Background`: background work (`StartBackgroundWork`, `UpdateBackgroundWork`, `StopBackgroundWork`: a foreground service with its notification, of the kind `[package.android] background` names — `data_sync`, `media_playback`, `location`, `connected_device`) and background jobs (`RegisterBackgroundJob`, `ScheduleBackgroundJob`, `CancelBackgroundJob`, `RunBackgroundJob`, `InBackgroundJob`: a Pascal function Android's JobScheduler runs also when the app is closed and after a restart with `"jobs"`, on a thread of its own; computers: a timer while the app is open). The app's library answers Java also without its window (`JNI_OnLoad`)
- `Pastel.NativeViews`: `TWebBrowser` (Android's WebView: `Navigate`, `LoadHtml`, `GoBack`/`GoForward`, `EvaluateJavaScript`, `pastel.post` from the page to `OnMessage`, links to other apps opened by them), `TVideoView` (VideoView) and `TMediaPlayer` (MediaPlayer, no view; computers: mpv, ffplay, VLC, afplay or Windows Media Player). The phone's views lie over the app's window at their control's place, cut by scrolling parents, hidden with it, under a menu or dialog; touched, a web page takes the keyboard. Designer palette: *Media*
- docs: [android.md](docs/android.md) (libraries, background, threads), [device.md](docs/device.md#background-work-and-jobs), [controls.md](docs/controls.md#web-pages-video-and-sound)

## 2.0.0-beta.6

Android, after a look at how other toolkits do it:

- The on-screen keyboard sees the edit's real text and cursor: Pastel's activity keeps a copy of the focused edit (text, selection, the word being composed) that the keyboard reads and changes like an Android edit's, and Pascal gets the whole state after each change (applied through the edit's own rules: `MaxLength`, masks, undo). Suggestions and corrections, swipe and voice typing, Backspace into the word before, the keyboard's paste and select all; the composed word is underlined. `TCustomEdit.ImeChange`; `Utf16ToByteIndex`, `ByteToUtf16Index`
- Emoji and other letters beyond the first 65536 passed between Pascal and Android whole (JNI strings through UTF-16, not Java's modified UTF-8 — a debug build stopped on them)
- Back on Android 13 and newer through the system's back callback (`OnBackInvokedCallback`), as Android 16 requires of apps made for it; the manifest's opt-out is gone
- Permissions: `RequestPermissions([dpCamera, dpMicrophone], @Done)` in one question, `PermissionState` (`psNotAsked`, `psDenied`: explain then ask again, `psBlocked`: refused for good), `OpenAppSettings`; new `microphone`, `contacts`, `calendar`, `phone`, `storage`, `bluetooth` (`[package.android] permissions`); permissions Android does not ask for on an older version count as given
- `TakePhoto` asks for the camera first when the app's manifest names it (Android refused the camera app otherwise); clear errors (no camera app, no permission)
- `SaveToGallery(File, Folder)`: a picture into the phone's gallery (Android 10+: MediaStore, no permission); computers: the Pictures folder
- The phone's own date and time pickers for `TDatePicker` and `TTimeEdit` (`NativePicker`, default on; `TTimeEdit.PickTime`)
- `WindowState := wsFullScreen` on Android: the status and navigation bars hidden; `KeepScreenOn`
- `JavaCallbackSignature`: which of two interface methods of one name was called

## 2.0.0-beta.5

- Groups of projects (like Delphi's project group): a `pastel.toml` with `[group] projects = [...]` (and `run`) in the folder that holds them; there `pastel build` (`--all`: each project's platforms), `test`, `check`, `clean` go through the projects in order and say which failed, `pastel run [project]` runs one; `pastel new group` writes the file, libraries first. VS Code extension 1.5.7: the group in the side bar, an active project for F9, *Build All*

## 2.0.0-beta.4

- WebSockets (`Pastel.WebSocket`): `Web.WebSocket('/live/:room', Sockets)` on the server — `TWebSockets` with `OnOpen`, `OnMessage`, `OnBinary`, `OnClose`, `Broadcast`, `SendTo` (by a value of the clients: a user, a room), `SendToId`; the address's filters run first (`RequireJwt`...), pings find dead connections, `Stop` ends them. `TWebSocketClient` for apps and programs: `ws://` and `wss://`, events on the app's thread, a bearer token; on Android with the phone's own TLS
- E-mail (`Pastel.Mail`): `TMailer` (SMTP; TLS on 465, STARTTLS on 587, never a password over a plain connection unless asked; AUTH PLAIN and LOGIN; `[mail]` settings) and `TMailMessage` (To, Cc, Bcc, Reply-To, text and HTML, attachments, UTF-8 names and subjects); without a mail server messages go to the log; `CaptureMails` for tests
- `Pastel.Http`: `NetConnect` for other protocols (TCP, TLS with the same certificate checks as HTTPS, STARTTLS); on Android through the phone's own sockets and TLS. `Sha1` in `Pastel.Crypto`


- Windows: apps have no console window in debug builds either (no empty black window that closes the app with it); their `WriteLn` and errors go to the console that started them (`pastel run`, VS Code's terminal, cmd) or to where their output was sent, and not into message boxes; an app opened from Explorer shows a fatal error in a message box
- `pastel setup android`: the compilers' parts (`doctor --install android`), then Android's tools checked one by one — Java, the SDK, the platform, the build tools, `adb` and the phones connected, bundletool (downloaded) — and which commands work; `--yes` installs the SDK's missing packages with Android's sdkmanager
- `--target linux,windows`: several platforms in one `pastel build` or `pastel package` (and `--target android-arm64,android-arm` for `apk`/`aab`)

## 2.0.0-beta.2

- Java interfaces done by Pascal: `JavaImplement('android.view.View$OnClickListener', @Clicked)` gives a Java object whose methods call a Pascal method (`TJavaCallbackEvent`: the method's name, its arguments, the answer) — listeners, `Runnable`, `Comparator`; by default on the app's own thread (forms can be used), or at once on Java's. `pastel java add` writes `Implement` for interfaces: `JView_OnClickListener.Implement(@Clicked)`. Boxed values: `JavaInteger`, `JavaInt64`, `JavaBoolean`, `JavaSingle`, `JavaDouble`; `AsInteger`, `AsInt64`, `AsBoolean`, `AsDouble`, `AsString` of `TJavaObject`
- Android: what the forms show is kept when the phone stops the app in the background (out of memory, a change of settings) and is back when it opens again — controls' values, scroll positions, frames' controls, and the app's own lines (`TForm.SaveState`, `OnSaveState`)

## 2.0.0-beta.1

The betas are 2.0's from now on: since 1.5.0-beta.14 they have been adding what 2.0 is to have (dialogs without
waiting, notifications, Java, phone navigation, charts, frames...), not finishing 1.5. 2.0 is stable when Windows,
Linux, Android and web services are done and tried on real devices.

- Rows moved by the user: `AllowReorder` and `OnReorder` of `TListBox`, `TListView`, `TGrid` (a grip at each row's right, for the mouse and the finger; Ctrl+Up/Down); `TGrid.MoveRow`
- Frames: hot reload (a saved frame `.pform` updates its forms, keeping what was typed); in the designer's palette, one block on a form; *Pastel: New Frame…* (VS Code extension 1.5.6)
- `TControl.DragsAt`: a control says where a finger drags it instead of scrolling

## 1.5.0-beta.19

- `TChart`: bars, lines, pies and donuts drawn by Pastel, with a legend, values on hover, `OnItemClick`; data in the `.pform` (`Labels`, `Data`) or from code (`AddSeries`, `LoadJson`); `TCanvas32.FillPie`
- `TMaskEdit`: text in a fixed shape (`EditMask = '(000) 000 00 00'`, Delphi's mask characters), `Value`, `IsComplete`
- Frames: a part of forms with a `.pform` and code of its own (`pastel new frame Address`, `object Billing: TAddressFrame`), as often as needed on a form, each with its own controls and events; test scripts reach them as `Billing.StreetEdit`
- Files dropped from the file manager: `OnDropFiles` of the control under them (containers, images, lists, grids, memos) or of the form; `drop` in test scripts

## 1.5.0-beta.18

- Phone navigation: `TDrawer` (a menu sliding in from the side; a tap beside it or Back closes it), `TBottomSheet`, tabs at the bottom (`TTabControl.TabPosition = tpBottom`, `TTabSheet.TabIcon`); `TPopup.Side` for popups along a side of the window
- Pull down to refresh: `OnRefresh` and `Refreshing` of `TListView`, `TGrid`, `TScrollBox` (a finger on a phone, F5 on a computer)
- "Share → this app": `[package.android] receive_shares = ["text/plain", "image/*"]` puts the app in other apps' share menu; `TShareReceiver.OnShareReceived` gets the text, the subject and the files (copied into the app's cache); `TakeSharedContent`
- Escape (Back) closes a drop-down, a menu or a drawer before it reaches the form's Cancel button

## 1.5.0-beta.17

- `Pastel.Java`: Java from Pascal — any class by name (`JavaNew`, `JavaCall...`, `JavaStatic...`, `JavaField...`), `TJavaObject` (kept alive while used, let go by itself), Java exceptions as `EJavaError`, `JavaRunOnUiThread`, `JavaActivity`. On Android the app's Java; on computers a Java VM started when needed (desktop apps can use Java libraries)
- `pastel java add|remove|search`: typed Pascal for Java classes, like Delphi's Java2OP — read from `android.jar` (and `[java] jars`, and the project's own `src/java`) and written into `src/java/javaclasses.pas`: `JToast.makeText(JavaActivity, 'Saved', JToast.LENGTH_SHORT).show`; methods (inherited ones too), constructors (`New`), constants, static fields
- Java files of the app in `src/java`: compiled with Pastel's activity into the `.apk`/`.aab` (javac, and d8 or dx)
- `ShowToast(Msg)`: Android's Toast; drawn by Pastel near the bottom of the window elsewhere (`TForm.ShowToast`); clicks go through it

## 1.5.0-beta.16

- `Pastel.Notifications`: `ShowNotification`, `ScheduleNotification` (at a time; `riHourly`, `riDaily`, `riWeekly`), `CancelNotification`, `CancelAllNotifications`, and `TNotificationCenter` with `OnNotificationClick`. Each platform in its own unit: Android (the notification bar; scheduled ones also when the app is closed and after a restart, through AlarmManager; taps), Linux (D-Bus through gdbus: replaced and taken back; else notify-send), Windows (the notification area: a toast on Windows 10/11), macOS (the Notification Center). `CapturedNotifications` for tests
- Android: a white status bar icon made from `assets/icon.png` (or `assets/notification.png`); `Notify` goes through Pastel.Notifications
- Android's Java code starts to be split by feature (`PastelNotifications.java`)
- Event handlers get their real parameters in `pastel schema` (the designer writes `OnPaint`, `OnMouseDown`, `OnNotificationClick`... with the right ones); the waiting-free answers are `AResult` / `AName` (a form's own `ModalResult` and `Name` cannot be parameter names in objfpc)

## 1.5.0-beta.15

- Dialogs without waiting, the way for phones (and later the browser): `Form.ShowModal(@Done)`, `ShowMessage(Msg, @Done)`, `Ask(Msg, @Done)`, `MessageDlg(..., @Done)`, `InputQuery(Title, Prompt, Value, @Done)`, the file dialogs and `TOpenDialog.Execute(@Done)`, `TakePhoto(@Done)`, `PickFile(Mime, @Done)`, `GetLocation(@Done)`, `RequestPermission(P, @Done)`; they return at once and call your method with the answer. The waiting forms stay as they are
- `TPopup.ShowModal(Form, @Done, FreeWhenDone)`; `ReleaseLater` and `CallLater` for code that must run after the event that is running

## 1.5.0-beta.14

- Android: a dialog opened from a tap (`ShowModal`, `ShowMessage`, a picker) no longer makes Android say "not responding" at the next tap — every touch and key is given back to Android before it is handled

## 1.5.0-beta.13

- Android apps are made for Android 16 (`targetSdkVersion` 36, Google Play's rule since August 2026), with the newest platform the build tools read; `.aab` needs Android 13's platform (33) or newer
- 16 KB memory pages (newer phones, Google Play's rule): the app's library and SQLite are laid out for them
- Back still reaches the app on Android 16 (`enableOnBackInvokedCallback="false"`)
- The icon in the phone's shape (adaptive icon, Android 8+); the window and status bar in the phone's light or dark look (Android 10+); `[package.android] splash` colors the start (Android 12's splash screen)
- A release build sends only `https://` (debug builds and `[package.android] cleartext = true` allow `http://`), with a clear message when plain `http://` is refused; `[package.android] backup = false` keeps the app's data out of the phone's backup; right-to-left languages supported

## 1.5.0-beta.12

- Edits: a right click — on a phone a finger held on the text, which selects the word there — shows Cut, Copy, Paste and Select all (in the app's language; a password is not copied); a `PopupMenu` of your own replaces them
- Hot reload on the phone: `pastel run --target android` serves the project's forms through the USB cable (`adb reverse`); a debug build shows a saved `.pform` at once
- `pastel keystore`: an Android app's release key for Google Play, written into `pastel.toml`, kept out of git

## 1.5.0-beta.11

Windows, checked end to end (Pastel itself, desktop apps, databases, web servers and sync, run under Wine in the tests).

- HTTPS on Windows through Windows' own HTTP (WinINet): its certificates and proxy settings, no OpenSSL DLLs or `cacert.pem` next to the program (`PASTEL_HTTP=fpc` for Free Pascal's)
- SQLite on Windows: Pastel carries `sqlite3.dll` (64- and 32-bit, `tools/windows-sqlite.sh`); `pastel build --target windows` puts it next to programs that use `Pastel.Db`, packages and installers include it
- `SDL2.dll` and `freetype.dll`: fetched by the first Windows build that needs them; the Windows release of Pastel carries them next to `pastel.exe`
- Releases carry `framework/android` and `framework/windows` (Android apps from a release were missing Pastel's activity)
- Fixed: Windows builds that use `ShellApi` took Windows CE's unit; `Pastel.Print` and other units did not compile for Windows (`GetEnvironmentVariable` of the Windows unit)
- Windows without Segoe UI or Arial (Server Core, N editions): any TrueType font of the system, for forms and PDFs
- `pastel doctor` on Windows: HTTPS needs nothing; a Free Pascal that does not start is reported as such

## 1.5.0-beta.10

Phone apps, complete.

- SQLite on Android: Android does not let apps load the phone's own, so apps that use `Pastel.Db` carry one (built for the four kinds of CPU by `tools/android-sqlite.sh`, kept in `framework/android/lib/`); `pastel package apk` puts it in
- HTTPS on Android: `Pastel.Http` (and `Pastel.Sync`) use the phone's own HTTP — its certificates and proxy, no OpenSSL; `PATCH` goes as `POST` with `X-HTTP-Method-Override`, which `Pastel.Web` now understands
- `Pastel.Device` ([docs/device.md](docs/device.md)): `ShareText`, `ShareFile`, `OpenUrl` (`tel:`, `mailto:`, files), `Vibrate`, `Notify`, `PickFile`, `TakePhoto`, `GetLocation`, `RequestPermission`; on computers the browser, the open dialog and desktop notifications; `TOpenDialog` uses the phone's picker; copy and paste use the phone's clipboard
- `[package.android] permissions` (`location`, `notifications`, `camera`) and `target_sdk`
- `pastel package aab`: an Android App Bundle for Google Play (aapt2 and bundletool), made for Android 15 (target 35), signed with your key
- Apps drawn behind the system's bars (Android 15) keep the form between them; dialog forms taller than the screen fit under their title
- Example: [salon-phone](https://github.com/azrov/pastel-demos/tree/main/salon-phone) in pastel-demos

## 1.5.0-beta.9

Phones, tablets, TVs and windows of every size ([forms.md](docs/forms.md#phones-tablets-tvs-and-windows-of-every-size)).

- `ScreenClass` (`scPhone`, `scTablet`, `scDesktop`, `scTV`) and `OnScreenClassChange` on forms; a narrow window on a computer counts as a phone; `PASTEL_SCREEN=phone|tablet|tv|desktop` tries one
- Views, like FireMonkey's: `Home.tablet.pform` (also `phone`, `tv`, `desktop`) next to `Home.pform` changes values for that kind of screen — sizes, places, fonts, texts, `Visible`; applied when the app starts and when the screen changes, undone when another screen has none; a TV uses the tablet's view; `pastel build` and `pastel check` make sure a view has only the form's controls; hot reload watches view files too
- `MaxContentWidth` on forms and containers: the controls in the middle, at most that wide
- A TV's remote: the arrows move the focus to the nearest control in that direction, with a clear ring; OK presses, ticks, brings the keyboard; on Android always, on a computer with `PASTEL_SCREEN=tv`
- Android: the text size of the phone's settings (up to 1.3 times); apps are on Android TV's home screen, with a banner made from the icon, and need no touch screen

## 1.5.0-beta.8

- Android: the on-screen keyboard comes up for an edit on every phone and TV box — Pastel's activity has an editor view the keyboard types into (NativeActivity's own view is not one, so many devices showed no keyboard); a tap on an edit brings it back after the back button closed it
- The keyboard an edit needs: `KeyboardType` on `TEdit` and `TMemo` (`ktNumber`, `ktDecimal`, `ktPhone`, `ktEmail`, `ktUrl`, `ktTime`; FireMonkey's name); `TNumberEdit`, `TCurrencyEdit` and `TTimeEdit` choose by themselves; `Password` gets a password keyboard
- `ReturnKeyType`: what the keyboard's Enter key says and does — Done, Next (to the next control), Go, Search, Send; in a `TMemo` Enter makes a new line
- Word suggestions of the keyboard (composing text) and its Backspace work

## 1.5.0-beta.7

- Android: apps no longer stop as soon as their window shows ("EThread: CheckSynchronize called from non-main thread"): the app's own thread is its main thread for `TThread.Synchronize`, `Queue` and timers. Found with `pastel logcat` on a 32-bit ARM phone — the first run on a real device
- Android: when an app stops after an error, the phone no longer waits ten seconds for it to close

## 1.5.0-beta.6

- `pastel logcat`: the log of the app on the connected Android device, by its package name — its processes (learned from the system's start lines and the process list), its start and end, crash reports; a crash shows the Pascal function and line (`<- ClearClick (Home.pas:33)`, from the debug build); `--all`, `--clear`; the whole log is saved in `build/android/logcat.txt`
- `pastel run --target android` shows the app's log the same way (before: only some tags, without native crashes' `libc` lines)

## 1.5.0-beta.5

Android on every kind of device.

- New targets: `android-arm` (ARM 32-bit: older phones, TV boxes; Android 4.4 and newer), `android-x86_64` (the Android emulator on a PC) and `android-x86`, besides `android-arm64`
- `pastel doctor --install android` sets up all of them whose binutils are installed; the ARM 32-bit and x86 compilers are built from Free Pascal's sources (`fpc-source`, or the source archive with `FPCDIR`) in seconds — no NDK, no fpcupdeluxe
- `pastel package apk` makes one `.apk` with every kind set up (`lib/arm64-v8a`, `lib/armeabi-v7a`, `lib/x86_64`, `lib/x86`), or one kind with `--target`; apps install on Android 4.4 and newer; libraries carry both kinds of symbol tables for older Android
- `pastel run --target android` asks the phone or emulator for its CPU and builds for that
- The app's icon: `pastel new app` puts Pastel's icon in `assets/icon.png`, ready to be replaced; Linux docks match the window to the app's menu entry (`StartupWMClass`, the window's class); [forms.md](docs/forms.md#the-apps-icon) says where the icon shows up

## 1.5.0-beta.4

- `Pastel.Markdown`: Markdown to HTML the way GitHub shows it — headings with GitHub's ids, lists (nested, task boxes), tables with alignment, fenced code with its language, quotes, links, pictures, bare links, `~~strikethrough~~`; `TMarkdown.OnLink` changes every address, `HeadingIds` tells the ids ([docs/markdown.md](docs/markdown.md))
- Pastel's website is made with Pastel: `tools/website` (Pastel.Markdown, Pastel.Pages and Bootstrap 5) makes a home page, a download page and the documentation with a menu, a search, *On this page*, code colors and dark mode, and checks every link and #anchor; Node.js is no longer needed for it
- No more "Comment level 2 found" warnings when a program uses `Pastel.Pages`

## 1.5.0-beta.3

- `Pastel.Pages`: HTML pages from templates, like Laravel's Blade — `{{ }}` made safe for HTML, `{!! !!}`, `@if`/`@elseif`/`@else`, `@unless`, `@isset`, `@foreach` with `loop`, `@forelse`/`@empty`, `@extends`, `@section`, `@yield`, `@include`, `@json`, comments, filters (`upper`, `lower`, `number`, `default`, `length`, `trim`, `json`, your own); errors with the file and line; templates read again when they change; safe on the web server's threads
- `pastel new site`: a web site with a layout, a menu, Bootstrap 5, a home, an about and a contact page (a form checked on the server), static files and tests; `pastel package` takes the templates along
- [docs/pages.md](docs/pages.md)

## 1.5.0-beta.2

- Android: every letter the on-screen keyboard types (ş, ğ, é, other alphabets, emoji) arrives, through a small Java activity in the `.apk` (`dev.pastel.PastelActivity`, built once into `framework/android/classes.dex`)
- Android: a quick swipe lets lists glide on; the form is laid out above the on-screen keyboard
- `pastel new app --phone`, `pastel new form --phone`: forms for phones, stacked, with finger-sized controls; the wizard's Android App and New Form… in phone apps use them

## 1.5.0-beta.1

Android, as a preview.

- Apps build for Android: `pastel build --target android` makes `libmain.so`, a NativeActivity with no Java code; `pastel doctor --install android` sets it up with Free Pascal's ARM 64-bit compiler and the ARM binutils, without the NDK
- `pastel package apk`: an installable, signed `.apk` (a debug key, or `[package.android] keystore`), with the app's name, icon, id and version
- `pastel run --target android`: installs on the connected phone, starts it and shows its log
- On the phone: fingers (tap, double tap, long press for popup menus, scrolling), the back button, the on-screen keyboard, the screen's density, dark mode and language from the phone, the app's own folder
- `Pastel.TrueType`: TrueType fonts in plain Pascal, used on Android and where FreeType is missing (`PASTEL_FONT_ENGINE=pascal` to try it)
- `[package.android]` settings: `id`, `orientation`, `keystore`, `alias`
- The New Project wizard makes Android apps; the palette says which controls work on phones
- [docs/android.md](docs/android.md)

## 1.4.3

Delphi's standard components, completed.

- `Pastel.Additional`: `TGroupBox` (a framed group, free placement inside), `TRadioGroup` (Items, ItemIndex, Value, Columns, OnChange), `TShape` (rectangle, rounded, ellipse, circle), `TBevel` (a line or a frame), `TPaintBox` (OnPaint with the canvas, mouse events)
- The dialogs as components: `TOpenDialog`, `TSaveDialog`, `TSelectFolderDialog` with `Execute`
- `TabOrder` and `TabStop` on every control

## 1.4.2

- Icons can be pictures: `Icon = 'icons/logo.png'` on buttons, menu items, actions and grid icon columns, in their own colors; `LoadAppPicture`, `IconDrawing`, `IsPictureName`

## 1.4.1

- `pastel new form` and `pastel new control` refuse projects that have no windows (console, service, API) and say what to do instead
- `TControl.DesktopOnly`: a menu bar, a splitter and a status bar are for desktops; `pastel schema` tells each control's platforms (Windows, Linux; Android coming in 1.5)
- Screenshots of the designer and the New Project wizard in the README and the docs

## 1.4.0

Forms like Delphi.

- Free placement: `Layout = Free` on a form, card or column, and the new `TPanel` — controls stay where they are put (`Left`, `Top`) at their own size; `Anchors` (`[Left, Top, Right]`...) and `Dock` (`Top`, `Bottom`, `Left`, `Right`, `Fill`) follow the window like Delphi's `Anchors` and `Align`
- New apps and forms (`pastel new app`, `pastel new form`) are free-placed; `Layout = Flow` keeps the responsive rows and columns
- Sets in `.pform` files: `Anchors = [Left, Top, Right]`
- The designer is laid out like Delphi's IDE (extension 1.1.0)


Data made easier.

- `Pastel.Sync`: data that works offline — a SQLite file on every computer, synced with the server (ids made where records are made, the newer change wins, deletions travel); `Pastel.SyncWeb`: the server's route. The salon example runs on it
- `Pastel.Auth`: users, passwords (PBKDF2) and roles; login, refresh and logout routes; `RequireRole`; `TAuthClient` for apps; `LoginDialog`
- `pastel new model Customer name:string! email:string age:integer`: a migration, a model unit and its tests
- Backups: `TDatabase.Backup`, `BackupTo(Dir, Keep)`, `Restore` for SQLite, PostgreSQL and MySQL
- `TDataBinding.Rules` and `Validate`: required, email, number, integer, range, min, max, pattern; `OnValidate`; wrong edits get a red border (`TEdit.Error`)
- Built-in translations of the new messages in 11 languages
- `BackgroundImage` and `BackgroundFit` for forms, cards, rows and columns
- Buttons in any color: `TButton.Color` and `TextColor`
- New forms have `Pastel.Dialogs` in their `uses`, so `ShowMessage`, `MessageDlg` and `InputBox` work at once; when an everyday routine (`ShowMessage`, `IntToStr`, `TStringList`, `Min`...) is missing, `pastel build` says which unit has it
- The designer schema tells each property's default
- Builds are quieter: the "marked as inline is not inlined" notes are left out; [docs/packages.md](docs/packages.md) shows Free Pascal's own packages
- Documentation: [docs/sync.md](docs/sync.md), [docs/auth.md](docs/auth.md); models and backups in [docs/database.md](docs/database.md)

## 1.2.0

Everyday desktop comfort.

- Grids: `TGridColumn.Kind` — `Number`, `Money`, `Date` (shown the language's way, sorted as what they are, numbers typed the language's way), `Check` (a check box), `Icon`; `Decimals`; `Filter(Text)` shows only matching rows; `ToCsv`; `ToJson` gives numbers and true/false
- `TFlow`: a row that wraps into more lines
- Icons on menu items and on actions (their buttons and menu items share it)
- Grid values from JSON as plain numbers (`1380.6`, not `1.3806E+003`)
- The salon: invoices with a money and a check box column, and a search

## 1.1.0

Reports and documents.

- `Pastel.Report`: invoices, lists, letters as PDF or HTML, written from top to bottom; tables repeat their heads on new pages; footers with page numbers; a logo
- `Pastel.Pdf`: PDF pages drawn by the program (text, lines, boxes, PNG and JPEG pictures); TrueType fonts with only the used letters
- `Pastel.Sheets`: Excel files (`.xlsx`) written and read, CSV; `Pastel.Xml`: XML; `Pastel.Print`: printers, printing, opening a file with the system's program
- `TWebResponse.Bytes`: a PDF or a spreadsheet as the answer, shown or downloaded
- `pastel lang` collects the texts of the libraries an app uses too
- The salon: invoices as PDF, printed, all invoices as Excel, on the desktop and from the server (`/api/invoices/:id/pdf`, `/api/invoices.xlsx`); the salon's address in the settings
- Documentation: [docs/documents.md](docs/documents.md)

## 1.0.0

The first stable version: what the release candidates below brought, tested on Linux and Windows. From now on the framework API in `docs/api/stable.txt`, `pastel.toml`, `.pform` files and the `pastel` commands stay compatible for all of 1.x ([docs/compatibility.md](docs/compatibility.md)).

- Desktop apps: about 40 controls with dates, money, numbers and times (`Pastel.Inputs`), tool bars, status bars, splitters and 38 icons; the designer in VS Code with several controls at once and a structure list
- Packages: `pastel add`, `update`, `remove`, `search`; `pastel.lock`; the registry [pastel-packages](https://github.com/azrov/pastel-packages) and [pastel-extras](https://github.com/azrov/pastel-extras)
- Examples: a business system (salon: desktop app, server and a shared library), an address book, a text editor, a web API, command-line tools
- VS Code extension 1.0.4

## 1.0.0-rc.7

- VS Code 1.0.4: several controls selected at once in the designer, put into a row, column or card; a structure list; `pastel check` findings on the form; readable objects, lists and JSON in the debugger (`vscode/gdb/pastel.py`, also for gdb in a terminal)

## 1.0.0-rc.6

Packages, like Composer for PHP.

- `pastel add serial`, `pastel add x --git URL [--path folder] [--branch b]`, `pastel remove`, `pastel update`, `pastel search`, `pastel deps [--json]`
- `[dependencies]`: `serial = "^1.2"` (the registry), `{ git = "...", version = "^0.3" }`, `branch`, `rev`; versions are git tags, ranges like Composer and Cargo (`^`, `~`, `>=`)
- `pastel.lock`: the exact commit of every package, also of the packages they use; versions that cannot both be met are explained
- One cache for all projects (`~/.cache/pastel`, `PASTEL_CACHE`); building needs no network when the packages are there
- The registry: [github.com/azrov/pastel-packages](https://github.com/azrov/pastel-packages); `PASTEL_REGISTRY` for another one
- Building: units are compiled again when their sources move (another version of a package); FPC units for a cross target are taken from the package made for that system (`Serial` for Windows from rtl-extra)
- Documentation: [docs/packages.md](docs/packages.md)

## 1.0.0-rc.5

- `TSplitter`: a bar the user drags to share the room between two controls; `TToolBar` and `TStatusBar`
- Buttons: `Icon` (38 built-in line icons, `Pastel.Icons`; your own with `RegisterIcon`) and `Style = Flat`
- UI scripts: `drag Name dx dy`
- Examples: notepad has a tool bar with icons and a status bar; contacts a splitter

## 1.0.0-rc.4

- F9 in VS Code runs the right program: with a library's file open, the program that uses it (or a choice, remembered; *Pastel: Choose the Program to Run* changes it), or its tests when nothing uses it; `pastel run` in a library names the programs that use it
- Layout: in a row that is too narrow, growing controls give up width; `pastel check` warns about rows whose controls are still cut off
- `Pastel.Inputs`: `TDatePicker`, `TCalendarView` and `TCurrencyEdit` move from the components example into the framework; new `TNumberEdit` (a whole number with ▲▼, `Min`, `Max`, `Step`) and `TTimeEdit` (`HH:MM`, `Step` minutes); documented in the controls reference
- ROADMAP: the plan from 1.0 to 2.0

## 1.0.0-rc.3

A business system as an example.

- `examples/salon-core`, `salon-desk`, `salon-api`: customers, appointments and invoices; a desktop app that works offline on SQLite and syncs with its server; both share one library; English and Turkish
- Guide: a business system — desktop app and server (`docs/guide-business.md`)
- UI scripts: text of several lines (labels, memos) is compared with `|` between the lines

## 1.0.0-rc.2

Components and documentation.

- Controls and components of libraries (`[dependencies]`) are in the designer's toolbox, like the project's own; non-visual components (`TTimer`, `TAction`, `TDataBinding`, your own) are in the schema and the toolbox too
- `examples/components`: a library with `TStarRating`, `TCurrencyEdit`, `TDatePicker` and `TFormMemory`; `examples/components-demo` uses it
- `Pastel.Lang`: `MonthName`, `DayNameShort` in 11 languages
- UI scripts: `set Name.Property value`
- Documentation: an index of all topics, a reference of every control with examples (`docs/controls.md`), every command with examples (`docs/commands.md`), writing components (`docs/components.md`); `tests/docs-coverage.sh` fails when a control, command or example is not documented
- Dependencies can be given with a full path

## 1.0.0-rc.1

The release candidate for 1.0. From 1.0 on, the framework API in `docs/api/stable.txt`, `pastel.toml`, `.pform` files and the `pastel` commands stay compatible within 1.x ([docs/compatibility.md](docs/compatibility.md)).

- Project files: `pastel = "1.0"`; `pastel upgrade` brings 0.x projects up to date
- Contributing guide, security policy, code of conduct, issue and pull request forms
- Workflows to publish the VS Code extension on the Marketplace and Open VSX

## 0.7.0 — Road to 1.0

- The stable API is frozen in `docs/api/stable.txt` and checked by the tests; helpers for Pastel's own use are marked *Internal*
- `pastel.toml` records the Pastel version (`pastel = "0.7"`); `pastel upgrade [--check]`; unknown settings are reported
- Web server limits: body size (413), header size (431), slow clients (408), connections (503); `[server] max_body_mb`, `request_timeout`, `max_connections`
- Security: static files checked once more on the final path; `X-Content-Type-Options: nosniff`; behind a proxy only the last `X-Forwarded-For` address counts; faster rate limiter
- `tests/perf.sh`: start-up time, size, memory, requests per second, drawing speed ([docs/performance.md](docs/performance.md))
- CI for Linux, Linux ARM64 and Windows; release builds and `install.sh` for tags; the documentation as a website with checked links

## 0.6.0 — Desktop apps, complete and shippable

- `TGrid`, `TListView`, `TTreeView`; `TDataBinding` (controls ↔ JSON rows, objects, grid rows)
- Translations: `assets/lang/*.json`, `_('...')`, `pastel lang`; number and date formats of the language
- `assets/theme.toml`; the system's file dialogs; the `.exe` icon from `assets/icon.png`
- Packages: `pastel package appimage`, `installer` (Windows, NSIS), desktop `.deb` with menu entry and icon; SDL2 and FreeType DLLs next to Windows programs
- `pastel doctor --install windows`: builds for Windows on Linux without a cross-compiler
- Only what changed is repainted; `PASTEL_CHECK_REPAINT=1`
- The project's own controls (`src/controls/`, `pastel new control`) in `.pform` files, the designer and its toolbox

## 0.5.0 — Desktop apps, essentials

- About 20 new controls: check boxes, radio buttons, switches, combo boxes, list boxes, memos, images, tabs, scroll boxes, progress bars, sliders, spinners, menus, popup menus, actions, timers, tooltips
- Dialogs: `ShowMessage`, `Ask`, `MessageDlg`, `InputBox`, open/save/folder; several forms, `ShowModal`, `pastel new form`
- Text editing with selection, clipboard and undo; word-wrapped labels
- Dark theme, high-DPI drawing, assets compiled into release builds, window icon and fonts from `assets/`
- Hot reload keeps what the user typed and chose
- UI test scripts drive dialogs, menus and tabs
- Examples: `contacts` (SQLite address book), `notepad` (text editor)

## 0.4.0 — Code intelligence in VS Code

- Pascal completion, hover, parameter hints, go to definition, find references and rename, from the project, the framework and the Free Pascal sources
- Compiler errors while typing; quick fixes (add a unit to `uses`, complete a class)
- The API reference (`docs/api/`) made from the framework's comments

## 0.3.0 — Linux services

- `pastel new service` and `pastel new api`; `pastel migrate`; `pastel package deb` and `docker`
- `Pastel.Service` (systemd, signals, jobs), `Pastel.Web` (routes, JSON, static files, CORS, API keys, JWT, rate limits, validation), `Pastel.Db` (SQLite, PostgreSQL, MySQL, transactions, pool, migrations), `Pastel.Workers`, `Pastel.Crypto`, `Pastel.Jwt`
- VS Code: routes, jobs and migrations in the Pastel panel; ▶ Send above routes

## 0.2.0 — Console programs, complete

- `pastel test`, `run --watch`, `fmt`, `package`, `new lib`, local dependencies, profiles
- `Pastel.Testing`, `Pastel.Args`, `Pastel.Term`, `Pastel.Text`, `Pastel.Log`, `Pastel.Config`, `Pastel.Json`, `Pastel.Files`, `Pastel.Process`, `Pastel.Http`, `Pastel.Env`
- VS Code: test explorer, snippets, F5 debugging, format on save
- Examples: `dupfinder`, `weather`

## 0.1.0 — Foundation

- `pastel new`, `build`, `run`, `clean`, `targets`, `doctor`, `check`, `preview`, `schema`; cross-compiling to Windows and Raspberry Pi
- The UI framework: SDL2 window, FreeType text, `.pform` forms with generated base classes, flexbox-style layout, hot reload
- VS Code: form designer, `.pform` language support, run and build commands
