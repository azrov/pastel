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

## Trying it in the emulator

No phone at hand? Android Studio's emulator runs Android on the PC (*Device Manager → Create device*, an *x86_64* system image). Start it; `adb devices` lists it like a phone, and `pastel run --target android` (F9) installs the `x86_64` build there. The emulator needs the PC's virtualization (KVM on Linux, enabled in the BIOS).

## What is different on a phone

| | |
|---|---|
| **Fingers** | A tap is a click, two quick taps a double click; holding a finger still is a right click (popup menus); dragging up and down scrolls lists, grids and scroll boxes, and a quick swipe lets them glide on (a finger stops them). Sliders, splitters, paint boxes and edits get the finger's movement themselves. |
| **Back button** | Closes the dialog or menu on top; on the main form it closes the app (`OnCloseQuery` can say no). |
| **Keyboard** | The on-screen keyboard comes up for an edit (a tap brings it back after the back button closed it) and goes when the focus leaves it. It is the kind the edit needs: `KeyboardType = ktNumber` (numbers), `ktDecimal`, `ktPhone`, `ktEmail`, `ktUrl`, `ktTime`; `TNumberEdit`, `TCurrencyEdit` and `TTimeEdit` choose by themselves, `Password` hides the suggestions. Its Enter key says what `ReturnKeyType` says (Done, Next — to the next control —, Go, Search, Send); in a `TMemo` it makes a new line. Word suggestions work; while it is up, the form is laid out in the part above it, so the edit stays in sight. Every letter it types arrives — ş, ğ, é, other alphabets, emoji — through Pastel's small activity (`dev.pastel.PastelActivity`, the only Java in an app). Hardware keyboards work too. |
| **Size** | The form fills the screen; `Width` and `Height` are only its design size. Use `Anchors` (or `Layout = Flow`) so the controls follow the screen, also when the phone is turned. The screen's density is taken into account: a 40-pixel button is as big as on a desktop monitor. |
| **Dark mode and language** | Follow the phone's settings (`Appearance = System`, the built-in translations). |
| **Files** | `GetUserDir`, settings files and SQLite databases go into the app's own folder, which stays when the app is updated. The project's `assets/` are inside the app. |
| **Fonts** | The phone's own (Roboto); text is drawn by Pastel's TrueType reader, without FreeType. |
| **Desktop only** | A menu bar, a splitter and a status bar are for desktops (the designer's palette says so). System file dialogs are not there yet: Pastel's own dialog is used. |

## The app's id, name, icon and key

```toml
[project]
title = "Shop"                     # the name under the icon

[package.android]
id = "com.example.shop"            # the app's id on the phone and in Google Play (default: dev.pastel.<name>)
orientation = "portrait"           # or "landscape"; default: turns with the phone
keystore = "keys/shop.keystore"    # the release key (default: a debug key made once in ~/.pastel/android/)
alias = "shop"
```

The icon is `assets/icon.png` (a square PNG, 512 × 512 is best; `pastel new app` puts Pastel's there to replace, and **Pastel: Set App Icon…** in VS Code copies yours there) — the same picture as on the desktop, in Android's five sizes. The version is `[project] version` (`1.2.3` becomes the version code 10203).

A release key is made once with Java's `keytool` and kept safe — Google Play and updates need the same key every time:

```sh
keytool -genkeypair -keystore keys/shop.keystore -alias shop -keyalg RSA -keysize 2048 -validity 10000
PASTEL_KEYSTORE_PASSWORD=... pastel package apk
```

## Not there yet

- `.aab` bundles for Google Play (an `.apk` with a release key can be uploaded by other routes for now)
- Tried on real devices: an ARM 32-bit phone (Android 10) runs it; ARM 64-bit, x86 and Android 4.4–5 are checked (the right instructions, Android's library format) but not yet run on such devices — reports are welcome
- An example: the salon's agenda on the phone

See the [roadmap](../ROADMAP.md#15--android-in-preview).
