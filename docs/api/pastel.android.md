# Pastel.Android

The bridge to Android: an app is a NativeActivity, so it needs no
  Java code. Android calls ANativeActivity_onCreate (exported by the app's
  libmain.so); Pastel then runs the app on a thread of its own, which gets the
  window, the touches and the keys from here.

  The calls from Android (window made, app paused, input...) arrive on Android's
  main thread; they are passed to the app thread through a pipe, and the ones
  that change the window or the input queue wait until the app thread has taken
  them (like android_native_app_glue of the NDK, written in Pascal).

`uses Pastel.Android;` · source: [framework/src/pastel.android.pas](../../framework/src/pastel.android.pas)

