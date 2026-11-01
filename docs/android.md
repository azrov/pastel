# Android

The same Pascal code and `.pform` forms run on Android phones and tablets. An app is built as `libmain.so` and packed into an `.apk` that runs as a *NativeActivity*: there is no Java code, and Pastel draws the forms itself, as on the desktop.

> **A preview.** Building and packing are tested on every change; running is being tried on real phones now. Tell us what you see: an issue with the phone's model and Android version, and the log (`pastel run --target android` shows it).

## Setting it up (once)

On Linux (Ubuntu, Mint, Debian):

```sh
sudo apt install fpc fpc-source binutils-aarch64-linux-gnu      # the ARM 64-bit compiler comes with fpc
sudo apt install aapt zipalign apksigner android-sdk-platform-23 default-jdk-headless adb
pastel doctor --install android
```

`pastel doctor --install android` compiles Free Pascal's units for Android once (into `~/.pastel/`) and makes small stand-ins for the phone's system libraries, so **the Android NDK is not needed**. The second line brings Android's packing tools, a platform (`android.jar`), Java (to sign) and `adb` (to install on a connected phone). With Android Studio installed, its SDK is used too (`ANDROID_HOME`, or `~/Android/Sdk`).

`pastel doctor` then shows `✓ android-arm64`.

## Making an app for the phone

In VS Code: **Pastel: New Project…** → *Mobile* → *Android App*. Or any app project:

```sh
pastel new app shop
cd shop
pastel build --target android           # build/android-arm64/debug/libmain.so
pastel package apk                      # dist/shop-0.1.0.apk, signed, ready to install
```

To have it built with the others, add it to the platforms in `pastel.toml`:

```toml
[targets]
platforms = ["linux", "windows", "android"]
```

## Trying it on your phone

1. On the phone: *Settings → About phone*, tap *Build number* seven times; then *Settings → Developer options → USB debugging* on.
2. Connect it with USB and allow the computer on the phone; `adb devices` lists it.
3. In the project:

```sh
pastel run --target android
```

It packs a debug `.apk`, installs it, starts it and shows its log (`WriteLn`, errors) until `Ctrl+C`. Without a cable: copy `dist/shop-0.1.0.apk` to the phone and open it (allow installing from this source once).

## What is different on a phone

| | |
|---|---|
| **Fingers** | A tap is a click, two quick taps a double click; holding a finger still is a right click (popup menus); dragging up and down scrolls lists, grids and scroll boxes. Sliders, splitters, paint boxes and edits get the finger's movement themselves. |
| **Back button** | Closes the dialog or menu on top; on the main form it closes the app (`OnCloseQuery` can say no). |
| **Keyboard** | The on-screen keyboard comes up for an edit and goes when the focus leaves it. Hardware keyboards work too. |
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

The icon is `assets/icon.png` (a square PNG, 512 × 512 is best); the version is `[project] version` (`1.2.3` becomes the version code 10203).

A release key is made once with Java's `keytool` and kept safe — Google Play and updates need the same key every time:

```sh
keytool -genkeypair -keystore keys/shop.keystore -alias shop -keyalg RSA -keysize 2048 -validity 10000
PASTEL_KEYSTORE_PASSWORD=... pastel package apk
```

## Not there yet

- `.aab` bundles for Google Play (an `.apk` with a release key can be uploaded by other routes for now)
- Letters beyond A–Z from the on-screen keyboard (ş, ğ, é...): Android sends them in a way NativeActivity cannot read without Java; a small Java bridge is planned
- Forms made for phones (`pastel new form --phone`), flinging lists, the keyboard moving the form up
- 32-bit ARM phones (older than about 2017) and x86 emulators: only ARM 64-bit is built
- An example: the salon's agenda on the phone

See the [roadmap](../ROADMAP.md#15--android-in-preview).
