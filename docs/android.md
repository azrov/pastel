# Android

The same Pascal code and `.pform` forms run on Android phones and tablets. An app is built as `libmain.so` and packed into an `.apk` that runs as a *NativeActivity*: there is no Java code, and Pastel draws the forms itself, as on the desktop.

> **A preview.** Building and packing are tested on every change; running is being tried on real phones now. Tell us what you see: an issue with the phone's model and Android version, and the log (`pastel run --target android` shows it).

## Phones, TV boxes and the emulator

An Android device has one of four kinds of processor (CPU). Pastel builds for all of them, and one `.apk` can carry all four:

| Target | Android's name | Devices | Android |
|---|---|---|---|
| `android-arm64` | `arm64-v8a` | most phones and tablets since about 2016 | 5 and newer |
| `android-arm` | `armeabi-v7a` | older phones, most TV boxes, cheap tablets; 64-bit phones run it too | 4.4 and newer |
| `android-x86_64` | `x86_64` | the Android emulator on a PC (Android Studio's, or others) | 5 and newer |
| `android-x86` | `x86` | older emulators, a few Intel tablets | 4.4 and newer |

`adb shell getprop ro.product.cpu.abilist` tells a device's kind; *Settings → About* does too on most phones.

## Setting it up (once)

On Linux (Ubuntu, Mint, Debian):

```sh
sudo apt install fpc fpc-source                                     # the compiler and its sources
sudo apt install binutils-aarch64-linux-gnu binutils-arm-linux-gnueabi binutils-x86-64-linux-gnu binutils-i686-linux-gnu
sudo apt install aapt zipalign apksigner android-sdk-platform-23 default-jdk-headless adb
pastel doctor --install android
```

`pastel doctor --install android` sets up every kind of device whose binutils (assembler and linker) are installed, once, into `~/.pastel/` (about half a minute):

- **the compilers**: the ARM 64-bit one comes with the `fpc` package; the ARM 32-bit (`ppcrossarm`) and x86 (`ppcross386`) ones are built from Free Pascal's sources (`fpc-source`) — a few seconds each. The 64-bit PC compiler makes x86_64 code itself.
- **Free Pascal's units** for Android, for each kind.
- **small stand-ins for the phone's system libraries**, so **the Android NDK is not needed**.

The third line brings Android's packing tools, a platform (`android.jar`), Java (to sign) and `adb` (to install on a connected phone or emulator). With Android Studio installed, its SDK is used too (`ANDROID_HOME`, or `~/Android/Sdk`).

`pastel setup android` does the same and then checks Android's tools one by one (Java, the SDK, the platform, the
build tools, `adb` and the phone, bundletool for Google Play) and says which commands work;
`pastel setup android --yes` installs the missing packages with Android's `sdkmanager` — Android Studio's, or, when
there is none (Ubuntu's packages), Google's command-line tools fetched into `~/Android/Sdk` (no `sudo`). The newest
build tools of the SDKs come before older ones on the `PATH`.

`pastel doctor` then shows `✓ android-arm64`, `✓ android-arm`, `✓ android-x86_64`, `✓ android-x86`. One kind alone: `pastel doctor --install android-arm`.

**Free Pascal's sources from freepascal.org** (an archive you unpacked, instead of `fpc-source`) work too: point `FPCDIR` at the folder that has `compiler/` and `rtl/` in it.

```sh
FPCDIR=~/fpc-3.2.2-src pastel doctor --install android
```

## Making an app for the phone

In VS Code: **Pastel: New Project…** → *Mobile* → *Android App*. Or in a terminal:

```sh
pastel new app shop --phone             # forms made for phones; any app project works too
cd shop
pastel build --target android-arm       # build/android-arm/debug/libmain.so (any target above)
pastel package apk                      # dist/shop-0.1.0.apk for every kind set up, signed, ready to install
pastel package apk --target android-arm # only one kind: a smaller .apk
```

`pastel build --target android` is `android-arm64`. `pastel package apk` puts in every kind this computer is set up for; with `platforms = ["android-arm64", "android-arm"]` in `pastel.toml`, exactly those.

To have it built with the others, add it to the platforms in `pastel.toml`:

```toml
[targets]
platforms = ["linux", "windows", "android"]
```

## Forms for phones

`--phone` (on `pastel new app` and `pastel new form`; the wizard's *Android App* uses it, and **New Form…** in a phone app too) makes forms for small, upright screens: the controls are stacked (`Layout = Flow`) and as wide as the screen, and edits and buttons are 48 pixels high — the size a finger hits. The designer's size box shows the form at *Phone 360 × 640*.

```
object HomeForm: THomeForm
  Width = 360
  Height = 640
  Padding = 16
  Gap = 12
  object NameEdit: TEdit
    Height = 48
    Placeholder = 'Your name'
  end
  object SendButton: TButton
    Height = 48
    Text = 'Send'
    OnClick = SendClick
  end
end
```

A free-placed form (`Layout = Free`) works on a phone too: give the controls `Anchors` so they follow the screen's width.

## In VS Code

The status bar shows the **platform** F9 and Ctrl+F9 use (like Delphi's *Target Platforms*); a phone app (`platforms = ["android"]`) starts on *android*. Click it to choose another one.

| Platform | F9 | Ctrl+F9 |
|---|---|---|
| this computer (`linux`, `windows`) | build and run | build |
| `android` | build for the connected phone's or emulator's CPU, install, start, show the log | `pastel package apk`: one `.apk` for every kind set up |
| `android-arm`, `android-x86_64`… | the same, for that kind only | an `.apk` for that kind |
| another desktop (`windows` on Linux) | build (it cannot run here) | build |

## Trying it on your phone

1. On the phone: *Settings → About phone*, tap *Build number* seven times; then *Settings → Developer options → USB debugging* on.
2. Connect it with USB and allow the computer on the phone; `adb devices` lists it.
3. In the project:

```sh
pastel run --target android
```

**Hot reload on the phone**: while it runs, save a `.pform` file and the phone shows the change at once, keeping what was typed — the debug build asks `pastel run` for its form through the USB cable (`adb reverse`, port 7865). Code changes need `pastel run` again.

It asks the phone which kind of CPU it has, packs a debug `.apk` for it, installs it, starts it and shows its log (`WriteLn`, errors) until `Ctrl+C`. Without a cable: copy `dist/shop-0.1.0.apk` (made by `pastel package apk`, with every kind) to the phone or TV box and open it (allow installing from this source once).

## When the app closes

The phone's log says why. `pastel run --target android` (F9) shows it after starting the app; for an app started on the phone itself (or a TV box over the network: `adb connect 192.168.1.50:5555`):

```sh
pastel logcat              # the app's lines, by its package name; Ctrl+C stops
```

In VS Code: **Pastel: Android Log**. Only the app's lines are shown — those of its processes, its start and its end, and crash reports. A crash in the Pascal code shows where it was, from the debug build:

```
15:43:01 F libc: Fatal signal 11 (SIGSEGV), code 1, fault addr 0x0 in tid 4330
15:43:01 F DEBUG:     #00 pc 0006d4d8  /data/app/dev.pastel.shop-1/lib/arm/libmain.so   <- ClearClick (Home.pas:33)
```

What to look for:

| In the log | What it means |
|---|---|
| `dlopen failed`, `UnsatisfiedLinkError` | Android could not load `libmain.so`: the line says which name is missing |
| `Fatal signal 11 (SIGSEGV)` and a `backtrace` | the Pascal code crashed: the `<-` lines say where |
| `pastel` lines | what the app writes (`WriteLn`, errors it caught) |

`pastel logcat --all` shows every line of the phone. The whole log is in `build/android/logcat.txt`: send it with the phone's model and Android version when you ask for help.

## When the phone stops the app

An app in the background can be stopped by Android to free memory (and, after a change of some settings, opened
again). When the user comes back, the app starts again — and Pastel puts back what its forms showed: the text of
edits, check boxes, choices of lists, the tab, scroll positions, the controls of frames. `OnCreate` runs after that,
so it sees the values.

What is not in a control is the app's to keep: write it in `SaveState` (lines of text) in `OnSaveState`, read it
back in `OnCreate`:

```pascal
procedure THomeForm.FormSaveState(Sender: TObject);
begin
  SaveState.Values['customer'] := IntToStr(FCustomerId);
end;

procedure THomeForm.FormCreate(Sender: TObject);
begin
  FCustomerId := StrToIntDef(SaveState.Values['customer'], 0);   // 0 the first time
end;
```

It is for a short time (what the user was doing), not for data: data goes to the database or to files.

## Trying it in the emulator

No phone at hand? Android Studio's emulator runs Android on the PC (*Device Manager → Create device*, an *x86_64* system image). Start it; `adb devices` lists it like a phone, and `pastel run --target android` (F9) installs the `x86_64` build there. The emulator needs the PC's virtualization (KVM on Linux, enabled in the BIOS).

## What is different on a phone

| | |
|---|---|
| **Fingers** | A tap is a click, two quick taps a double click; holding a finger still is a right click (popup menus); dragging up and down scrolls lists, grids and scroll boxes, and a quick swipe lets them glide on (a finger stops them). Sliders, splitters, paint boxes and edits get the finger's movement themselves. |
| **Back button** | Closes the dialog or menu on top; on the main form it closes the app (`OnCloseQuery` can say no). On Android 13 and newer it comes through the system's back callback, as Android 16 requires of apps made for it. |
| **Keyboard** | The on-screen keyboard comes up for an edit (a tap brings it back after the back button closed it) and goes when the focus leaves it. It is the kind the edit needs: `KeyboardType = ktNumber` (numbers), `ktDecimal`, `ktPhone`, `ktEmail`, `ktUrl`, `ktTime`; `TNumberEdit`, `TCurrencyEdit` and `TTimeEdit` choose by themselves, `Password` hides the suggestions. Its Enter key says what `ReturnKeyType` says (Done, Next — to the next control —, Go, Search, Send); in a `TMemo` it makes a new line. The keyboard sees the edit's real text and cursor (Pastel's activity keeps a copy of the focused edit, like Android's own edits): suggestions, corrections, swipe and voice typing, Backspace into the word before, the keyboard's paste and select all; the word being composed is underlined. The edit's rules stay (`MaxLength`, a `TMaskEdit`'s mask). While it is up, the form is laid out in the part above it, so the edit stays in sight. Every letter arrives whole — ş, ğ, é, other alphabets, emoji. Hardware keyboards work too. |
| **Size** | The form fills the screen; `Width` and `Height` are only its design size. Use `Anchors` (or `Layout = Flow`) so the controls follow the screen, also when the phone is turned. The screen's density is taken into account: a 40-pixel button is as big as on a desktop monitor. Tablets and TVs: `MaxContentWidth`, `ScreenClass` and views (`Home.tablet.pform`), see [forms.md](forms.md#phones-tablets-tvs-and-windows-of-every-size). The text size of the phone's settings makes text larger. |
| **TV boxes** | The remote's arrows move the focus from control to control, OK presses; the app is on Android TV's home screen (with a banner made from the icon) and in a TV box's app list. |
| **Dark mode and language** | Follow the phone's settings (`Appearance = System`, the built-in translations). |
| **Files** | `GetUserDir`, settings files and SQLite databases go into the app's own folder, which stays when the app is updated. The project's `assets/` are inside the app. |
| **Fonts** | The phone's own (Roboto); text is drawn by Pastel's TrueType reader, without FreeType. |
| **Desktop only** | A menu bar, a splitter and a status bar are for desktops (the designer's palette says so). System file dialogs are not there yet: Pastel's own dialog is used. |

## Data, the network and the phone's features

- **Databases**: `Pastel.Db` with SQLite works on the phone as on a computer. Android does not let apps load the
  phone's own SQLite, so every app that uses `Pastel.Db` carries one (about 0.9 MB per kind of CPU; `pastel package apk`
  puts it in by itself). The file goes into the app's own folder: `TDatabase.Open('sqlite:shop.db')`.
- **HTTP and HTTPS**: `Pastel.Http` (and `Pastel.Sync`) use the phone's own: its certificates, its proxy. A server on
  the local network (`http://192.168.1.20:8080`) is fine in a debug build; a release build sends only `https://`
  (as Android Studio's apps), unless `[package.android] cleartext = true` allows plain `http://` too. Android's HTTP
  has no `PATCH`: Pastel sends `POST` with `X-HTTP-Method-Override: PATCH`, which Pastel's web server understands.
- **The phone's features** — share, call, open, vibrate, notify, pick a file, take a photo, the place — are in
  `Pastel.Device` ([device.md](device.md)). Copy and paste in edits use the phone's clipboard.
- **Anything else of Android** — every Java class, and Java files of your own: [java.md](java.md)
  (`pastel java add android.speech.tts.TextToSpeech`).
- **Web pages, video, sound and the camera** in a form: `TWebBrowser`, `TVideoView`, `TMediaPlayer`, `TCameraView`
  (`Pastel.NativeViews`, [controls.md](controls.md#web-pages-video-and-sound)): Android's own WebView, VideoView,
  MediaPlayer and Camera2.
- **Maps**: `TMapView` ([controls.md](controls.md#tmapview)), drawn by Pastel from map tiles, as on computers.
- **Push messages** (Firebase) and **"is it you?"** (fingerprint, face, PIN): [device.md](device.md#push-messages).

## Android libraries (.aar, Maven)

Libraries made for Android — AndroidX, Google's and Firebase's, a scanner's SDK — go into `[package.android] libraries`:
Maven coordinates (what each needs comes with it) or `.aar`/`.jar` files of the project.

```toml
[package.android]
libraries = ["androidx.browser:browser:1.8.0", "libs/scanner.aar", "libs/util.jar"]
# repositories = ["https://maven.google.com", "https://repo1.maven.org/maven2"]   # the default; a folder works too
```

`pastel package apk` (and `aab`) fetches them once into `~/.pastel/maven/` (`PASTEL_MAVEN_CACHE`: another folder) — their POM's compile and runtime
dependencies too; when two ask for one library, the highest version wins — and puts into the app what each brings:
its classes (with R classes for its resources), its resources, assets and native libraries (`jni/<abi>/*.so`, for
the app's CPUs), and its manifest's parts: permissions, activities, services, receivers, providers (`${applicationId}`
filled in, `tools:node="remove"` left out). The app starts from the highest Android version a library asks for.
`pastel java add` and `pastel java search` see their classes, so they are used from Pascal like Android's own
([java.md](java.md)). A `google-services.json` (Firebase) next to `pastel.toml` becomes the values Firebase's
libraries read.

Libraries with resources need `aapt2`, and newer ones (Java 8 code, AndroidX) `d8` — Android's build tools 28 or
newer (`pastel setup android --yes`); Ubuntu's `dx` dexes only older, plain ones. A library made against a newer
Android than the platform here (AndroidX's `core` needs API 31: `android:attr/lStar`) is said before packing, with
what to install.

## Work when the app is not on the screen

`Pastel.Background` ([device.md](device.md#background-work-and-jobs)):

- **Background work** the user started — music, a route, an upload — keeps the app running with a notification
  until it is done: `StartBackgroundWork('Uploading photos', '3 of 20', bkDataSync)` ... `StopBackgroundWork`.
  Android's foreground service; its kind is in `pastel.toml`.
- **Background jobs**: a Pascal function Android runs from time to time — also when the app is closed, and after the
  phone restarted: `RegisterBackgroundJob('sync', @SyncNow)` in an initialization, `ScheduleBackgroundJob('sync', 60)`.
  Android's JobScheduler (15 minutes at least, when the phone sees fit); the function runs on a thread of its own,
  without the window: data, files, HTTP.

```toml
[package.android]
background = ["jobs", "data_sync"]    # jobs; data_sync, media_playback, location, connected_device: background work
```

## Threads

Pascal runs on a thread of its own — the app's thread — and draws the whole window itself; Android's views and
callbacks are on Android's UI thread. Pastel keeps it so: a long event handler does not freeze Android (no "app
isn't responding"), and Pascal code never waits for Java's thread. What crosses goes through Pastel's bridge: calls
to Java run on Android's thread (`Pastel.Java` from any thread), answers come back as events on the app's thread
(`OnPermissions`, `OnPicked`, the native views' events). Background jobs run on threads of their own. Your own
threads (`TThread`, `Pastel.Workers`) are as on a computer; `TThread.Synchronize`/`Queue` reach the app's thread.

## Google Play

Google Play takes an Android App Bundle (`.aab`), signed with your own key, made for a recent Android:

```sh
pastel keystore                                     # once: keys/upload.keystore, written into pastel.toml
PASTEL_KEYSTORE_PASSWORD=... pastel package aab     # dist/shop-1.0.0.aab, every kind of CPU in it
```

```toml
[package.android]
keystore = "keys/upload.keystore"
alias = "upload"
# target_sdk = 36       # the Android version the app is made for: 36 unless set (Google Play's rule since August 2026)
```

It needs `aapt2` and a platform of Android 13 (API 33) or newer — Android Studio's SDK Manager: **Android SDK
Build-Tools 36** and **Android 16 (API 36)**, with `ANDROID_HOME` set — and bundletool (`bundletool-all-<version>.jar`
from [its releases](https://github.com/google/bundletool/releases), into `~/.pastel/android/`, or `PASTEL_BUNDLETOOL`).
Ubuntu's own `aapt`/`aapt2` read platforms up to Android 14 (34): enough, Pastel takes the newest they read. Upload it
in the Play Console; Play makes the `.apk` for each phone.

What Google Play and new phones ask of an app, Pastel does by itself:

- **Made for Android 16** (`targetSdkVersion` 36). An `.apk` too, when a platform of Android 13 or newer is installed;
  with only an older one (Ubuntu's `android-sdk-platform-23`) it is made for that, and runs on new phones in an older mode.
- **16 KB memory pages** (newer phones such as the Pixel 8 and later; Google Play's rule since November 2025): the
  app's library and SQLite are laid out for them, and still run on every older phone.
- **Drawn behind the status and navigation bars** (Android 15 and newer): Pastel keeps the form between them.
- **Back**: Android 16 no longer sends the Back key to apps made for it; Pastel's apps ask for it, so Back still
  closes a popup, goes back a form or leaves the app.
- **The icon in the phone's shape** (circle, squircle, rounded square — Android 8 and newer), made from `assets/icon.png`.
- **The phone's light or dark look** for the window and the status bar's icons (Android 10 and newer).
- **Backup**: the app's data (its database, its settings) goes into the phone's backup, and comes back on a new
  phone; `backup = false` keeps it out (an app that keeps sign-in tokens, say).

## The app's id, name, icon and key

```toml
[project]
title = "Shop"                     # the name under the icon

[package.android]
id = "com.example.shop"            # the app's id on the phone and in Google Play (default: dev.pastel.<name>)
orientation = "portrait"           # or "landscape"; default: turns with the phone
keystore = "keys/shop.keystore"    # the release key (default: a debug key made once in ~/.pastel/android/)
alias = "shop"
splash = "#1E1B2E"                 # the color behind the icon while the app starts (default: the phone's light or dark)
cleartext = true                   # plain http:// in a release build too (default: https:// only)
backup = false                     # the app's data out of the phone's backup (default: in it)
receive_shares = ["text/plain", "image/*"]   # in other apps' share menu (device.md: shared with the app)
```

The icon is `assets/icon.png` (a square PNG, 512 × 512 is best; `pastel new app` puts Pastel's there to replace, and **Pastel: Set App Icon…** in VS Code copies yours there) — the same picture as on the desktop, in Android's five sizes. On Android 8 and newer the phone cuts it to its own shape: an icon with a background of its own (a colored square, as Pastel's) fills the shape, its background color around it; a picture on transparent stays inside the circle every shape keeps, on white. The version is `[project] version` (`1.2.3` becomes the version code 10203).

A release key is made once and kept safe — Google Play and updates need the same key every time ([pastel keystore](commands.md#pastel-keystore)):

```sh
pastel keystore                                   # keys/upload.keystore, written into pastel.toml
PASTEL_KEYSTORE_PASSWORD=... pastel package aab
```

## An example

[salon-phone](https://github.com/azrov/pastel-demos/tree/main/salon-phone) in pastel-demos: the salon's appointments
on the phone — a day's list, a new appointment, Done, Call, Share, Sync with the same server as the desktop app —
with salon-core, the same library as the desktop app and the server.

## Not there yet

- Tried on real devices: an ARM 32-bit phone (Android 10) and a TV box run apps, the keyboard works; ARM 64-bit, x86 and Android 4.4–5 are checked (the right instructions, Android's library format) but not yet run on such devices; SQLite, HTTPS, `Pastel.Device` and the `.aab` are new and wait for their first runs on phones — reports are welcome
- Web pages, video and the camera's picture over the app's window: a dialog, or a menu over them, hides them
  while it is open (the phone's view would cover it)
- Google Play's in-app purchases and ads (their libraries go in with `libraries`; Pascal's side through
  [java.md](java.md) until Pastel has its own)
- Widgets on the home screen
- Databases other than SQLite on the phone (PostgreSQL and MySQL clients are not there); a phone app talks to a server instead (`Pastel.Sync`)

See the [roadmap](../ROADMAP.md#15--android-in-preview).
