// Pastel's activity on Android: Android's NativeActivity (the app itself is
// libmain.so, written in Pascal), and the on-screen keyboard.
//
// NativeActivity's own view is not a text editor, so on many phones the
// on-screen keyboard does not come up for it, and it cannot say which keyboard
// an edit needs. This class adds a small, invisible editor view that holds a
// copy of the focused edit's text and selection (editStart, editSync): the
// keyboard sees the real text around the cursor - for its suggestions,
// corrections, swipe and voice typing - and edits the copy; every change goes
// to Pascal as the whole text and selection (nativeEdit), and what Pascal
// changes itself (a tap that moves the cursor, a paste) comes back with
// editSync. Enter (Done, Next, Search...) and Tab go as keys (nativeKey).
//
// Built into framework/android/classes.dex by tools/android-dex.sh; that file
// is put into every .apk by "pastel package apk".
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.NativeActivity;
import android.app.PendingIntent;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Vibrator;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ConnectException;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.net.UnknownHostException;
import java.security.cert.X509Certificate;
import java.util.List;
import java.util.Map;
import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLException;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

public class PastelActivity extends NativeActivity {
    static {
        // the same library NativeActivity loads; loaded here so nativeText is found
        System.loadLibrary("main");
    }

    private static native void nativeText(String text);
    /** The focused edit's text after the keyboard changed it: selection and the word being composed (-1: none), in UTF-16 units. */
    private static native void nativeEdit(String text, int selStart, int selEnd, int composeStart, int composeEnd, int gen);
    private static native void nativeKey(int keyCode);
    /** The answer to a request (a picked file, a photo, a permission, a place): its code, 1 or 0, a text. */
    private static native void nativeResult(int code, int ok, String text);
    /** The parts of the window the system covers (status bar, navigation bar, keyboard), in pixels. */
    private static native void nativeInsets(int top, int bottom, int left, int right);
    /** Runs what Pastel.Java's JavaRunOnUiThread gave, on this (the UI) thread. */
    private static native void nativeRun(long token);
    /** TalkBack's action on a control Pascal drew (PastelAccess) */
    private static native void nativeAccess(int id, int action);

    private KeyboardView keyboardView;
    private PastelAccess accessView;

    /** "1" while TalkBack (or another screen reader) is on */
    public String accessOn() {
        return PastelAccess.on(this) ? "1" : "";
    }

    /** the controls on the screen, for TalkBack (PastelAccess.update's lines) */
    public void accessTree(final String tree) {
        runOnUiThread(new Runnable() {
            public void run() {
                if (accessView != null) {
                    accessView.update(tree);
                }
            }
        });
    }
    private int inputType = EditorInfo.TYPE_CLASS_TEXT;
    private int imeOptions = EditorInfo.IME_ACTION_DONE;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        noteClicked(getIntent());          // opened by a tap on a notification
        PastelShare.note(this, getIntent());   // or by another app's share menu
        PastelLinks.note(getIntent());         // or by a link, or one of its shortcuts
        keyboardView = new KeyboardView(this);
        addContentView(keyboardView, new ViewGroup.LayoutParams(1, 1));
        // what TalkBack reads: the controls Pascal draws, as virtual views
        accessView = new PastelAccess(this, new PastelAccess.Actions() {
            public void action(int id, int action) {
                nativeAccess(id, action);
            }
        });
        addContentView(accessView, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT));
        // what of the window the system bars and the keyboard cover: drawn around, not under
        // (apps made for Android 15 are drawn behind the bars)
        final View decor = getWindow().getDecorView();
        decor.getViewTreeObserver().addOnGlobalLayoutListener(new android.view.ViewTreeObserver.OnGlobalLayoutListener() {
            private int last = -1;
            public void onGlobalLayout() {
                android.graphics.Rect visible = new android.graphics.Rect();
                decor.getWindowVisibleDisplayFrame(visible);
                int[] at = new int[2];
                decor.getLocationOnScreen(at);
                int top = Math.max(0, visible.top - at[1]);
                int left = Math.max(0, visible.left - at[0]);
                int bottom = Math.max(0, at[1] + decor.getHeight() - visible.bottom);
                int right = Math.max(0, at[0] + decor.getWidth() - visible.right);
                int key = ((top * 31 + bottom) * 31 + left) * 31 + right;
                if (key != last) {
                    last = key;
                    nativeInsets(top, bottom, left, right);
                }
            }
        });
        registerBack();
        PastelViews.sink = new PastelViews.Sink() {
            public void send(int code, String text) {
                nativeResult(code, 1, text);
            }
            public void back() {
                nativeKey(KeyEvent.KEYCODE_BACK);
            }
        };
    }

    /** The app is on the screen (a push message then goes to Pascal, not into a notification). */
    static volatile boolean onScreen;

    @Override
    protected void onResume() {
        super.onResume();
        onScreen = true;
    }

    @Override
    protected void onPause() {
        onScreen = false;
        super.onPause();
    }

    // ---------- push messages (Pastel.Push; PastelPush is in the app only with Firebase's library) ----------

    /** PastelPush's static method (a String argument, a String answer); "!" when the app has no push */
    public String pushCall(String method, String arg) {
        try {
            Class<?> c = Class.forName("dev.pastel.PastelPush");
            Object r = c.getMethod(method, String.class).invoke(null, arg);
            return r == null ? "" : r.toString();
        } catch (ClassNotFoundException e) {
            return "!the app has no push messages: [package.android] libraries = [\"com.google.firebase:firebase-messaging:24.1.0\"] and google-services.json";
        } catch (Throwable e) {
            Throwable t = e.getCause() != null ? e.getCause() : e;
            return "!" + t;
        }
    }

    /** opened by a tap on a push message's notification */
    private void pushOpened(Intent i) {
        if (i == null || i.getExtras() == null || i.getExtras().get("google.message_id") == null) {
            return;
        }
        try {
            Class.forName("dev.pastel.PastelPush").getMethod("opened", Intent.class).invoke(null, i);
        } catch (Throwable e) {
            android.util.Log.w("pastel", "push: " + e);
        }
    }

    @Override
    protected void onDestroy() {
        PastelViews.destroyAll(this);
        super.onDestroy();
    }

    /** An answer to Pascal from Pastel's other classes. */
    static void result(int code, int ok, String text) {
        nativeResult(code, ok, text);
    }

    // ---------- scanning (PastelScanner is in the app only with Google's code scanner) ----------

    public void scanBarcode(int code) {
        try {
            Class.forName("dev.pastel.PastelScanner").getMethod("scan", android.app.Activity.class, int.class)
                .invoke(null, this, code);
        } catch (ClassNotFoundException e) {
            nativeResult(code, 0, "the app has no scanner: [package.android] libraries = "
                + "[\"com.google.android.gms:play-services-code-scanner:16.1.0\"]");
        } catch (Throwable e) {
            nativeResult(code, 0, (e.getCause() != null ? e.getCause() : e).toString());
        }
    }

    // ---------- voice, senses, NFC (Pastel.Speech, Pastel.Sensors, Pastel.Nfc) ----------

    public void speak(String text, String lang) {
        PastelSense.speak(this, text, lang);
    }

    public void stopSpeaking() {
        PastelSense.stopSpeaking();
    }

    public String speaking() {
        return PastelSense.speaking() ? "1" : "";
    }

    private final java.util.HashSet<Integer> listenCodes = new java.util.HashSet<Integer>();

    /** speech to text with the phone's recognizer (its own small window) */
    public void listen(int code, String lang) {
        Intent i = new Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        if (lang.length() > 0) {
            i.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, lang);
        }
        try {
            listenCodes.add(code);
            startActivityForResult(i, code);
        } catch (Exception e) {
            listenCodes.remove(code);
            nativeResult(code, 0, "this phone has no speech recognition");
        }
    }

    public String startSensor(int type) {
        return PastelSense.startSensor(this, type) ? "1" : "";
    }

    public void stopSensor(int type) {
        PastelSense.stopSensor(this, type);
    }

    public String readSensor(int type) {
        return PastelSense.read(type);
    }

    public String startNfc() {
        return PastelSense.startNfc(this);
    }

    public void stopNfc() {
        PastelSense.stopNfc(this);
    }

    public String senseTake() {
        return PastelSense.take();
    }

    public String bleScan(int seconds) {
        return PastelBle.scan(this, seconds);
    }

    public void bleStopScan() {
        PastelBle.stopScan(this);
    }

    public String bleConnect(String address) {
        return PastelBle.connect(this, address);
    }

    public String bleGatt(String address, String service, String ch, String op, String value) {
        return PastelBle.gatt(address, service, ch, op, value);
    }

    public void bleDisconnect(String address) {
        PastelBle.disconnect(address);
    }

    // ---------- secrets (Pastel.SecureStore) ----------

    public String secureSet(String name, String value) {
        return PastelSecure.set(this, name, value);
    }

    public String secureGet(String name) {
        return PastelSecure.get(this, name);
    }

    public void secureDelete(String name) {
        PastelSecure.delete(this, name);
    }

    // ---------- "is it you?" (Pastel.Device's Authenticate) ----------

    public void authenticate(int code, String title, String subtitle, boolean allowPin) {
        PastelAuth.authenticate(this, code, title, subtitle, allowPin, new PastelAuth.Answer() {
            public void answer(int c, boolean ok, String text) {
                nativeResult(c, ok ? 1 : 0, text);
            }
        });
    }

    /** "biometric", "credential" or "" */
    public String authAvailable() {
        return PastelAuth.available(this);
    }

    // ---------- Android's views over the window (Pastel.NativeViews) ----------

    /** kind: "web", "video" or "audio" (no view); id: a request number, its events come as answers */
    public void viewCreate(int id, String kind) {
        PastelViews.create(this, id, kind);
    }

    public void viewBounds(int id, int x, int y, int w, int h, int cx, int cy, int cw, int ch, boolean visible) {
        PastelViews.bounds(this, id, x, y, w, h, cx, cy, cw, ch, visible);
    }

    public void viewRun(int id, String op, String arg) {
        PastelViews.run(this, id, op, arg);
    }

    public String viewState(int id) {
        return PastelViews.state(id);
    }

    public void viewDestroy(int id) {
        PastelViews.destroy(this, id);
    }

    // ---------- Back (Android 13 and newer: the system's back callback) ----------

    /**
     * Android 16 gives apps made for it no Back key any more (KEYCODE_BACK):
     * Back comes to a callback. It goes to Pascal like the key did (closes the
     * menu or dialog on top, else the app). Through reflection: the class is
     * newer than the android.jar Pastel is built with.
     */
    private void registerBack() {
        if (Build.VERSION.SDK_INT < 33) {
            return;
        }
        try {
            Class<?> cb = Class.forName("android.window.OnBackInvokedCallback");
            Object callback = java.lang.reflect.Proxy.newProxyInstance(cb.getClassLoader(), new Class<?>[] { cb },
                new java.lang.reflect.InvocationHandler() {
                    public Object invoke(Object proxy, java.lang.reflect.Method m, Object[] args) {
                        String n = m.getName();
                        if (n.equals("onBackInvoked")) {
                            nativeKey(KeyEvent.KEYCODE_BACK);
                            return null;
                        }
                        if (n.equals("hashCode")) {
                            return Integer.valueOf(System.identityHashCode(proxy));
                        }
                        if (n.equals("equals")) {
                            return Boolean.valueOf(args != null && proxy == args[0]);
                        }
                        if (n.equals("toString")) {
                            return "PastelBack";
                        }
                        return null;
                    }
                });
            Object dispatcher = getClass().getMethod("getOnBackInvokedDispatcher").invoke(this);
            dispatcher.getClass().getMethod("registerOnBackInvokedCallback", int.class, cb)
                .invoke(dispatcher, 0, callback);
        } catch (Throwable e) {
            android.util.Log.w("pastel", "no back callback: " + e);
        }
    }

    // ---------- the window ----------

    private boolean fullScreen;

    /** The status and navigation bars hidden (a kiosk, a game, a video), or shown again. */
    public void setFullScreen(final boolean on) {
        runOnUiThread(new Runnable() {
            public void run() {
                View decor = getWindow().getDecorView();
                if (on) {
                    // LAYOUT_STABLE, LAYOUT_HIDE_NAVIGATION, LAYOUT_FULLSCREEN, HIDE_NAVIGATION, FULLSCREEN, IMMERSIVE_STICKY
                    decor.setSystemUiVisibility(0x100 | 0x200 | 0x400 | 0x2 | 0x4 | 0x1000);
                } else {
                    decor.setSystemUiVisibility(0);
                }
                fullScreen = on;
            }
        });
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus && fullScreen) {
            setFullScreen(true);       // the bars come back after a dialog or the keyboard
        }
    }

    /** The screen stays on (a recipe, a map) or goes dark by itself again. */
    public void keepScreenOn(final boolean on) {
        runOnUiThread(new Runnable() {
            public void run() {
                if (on) {
                    getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            }
        });
    }

    /** Called by Pastel (on its own thread) when an edit gets the focus: its keyboard, its text and selection. */
    public void editStart(final int type, final int options, final String text, final int selStart, final int selEnd,
                          final int gen) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                inputType = type;
                imeOptions = options;
                keyboardView.set(text, selStart, selEnd, gen);
                keyboardView.setFocusable(true);
                keyboardView.setFocusableInTouchMode(true);
                keyboardView.requestFocus();
                InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm != null) {
                    imm.restartInput(keyboardView);
                    imm.showSoftInput(keyboardView, InputMethodManager.SHOW_IMPLICIT);
                }
            }
        });
    }

    /** The old way (an edit without its text): kept for apps built with an older Pastel. */
    public void showKeyboard(int type, int options) {
        editStart(type, options, "", 0, 0, 0);
    }

    /** Pastel changed the focused edit itself (a tap moved the cursor, a paste, Text := ...): the copy follows. */
    public void editSync(final String text, final int selStart, final int selEnd, final int gen) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                boolean changed = keyboardView.set(text, selStart, selEnd, gen);
                InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm == null) {
                    return;
                }
                if (changed) {
                    imm.restartInput(keyboardView);        // the keyboard reads the new text again
                } else {
                    imm.updateSelection(keyboardView, selStart, selEnd, -1, -1);
                }
            }
        });
    }

    /** The size of text chosen in the phone's settings (1 is normal). */
    public float fontScale() {
        return getResources().getConfiguration().fontScale;
    }

    /**
     * HTTP and HTTPS for Pastel.Http on Android: the phone's own TLS, its
     * certificates and its proxy (apps cannot load OpenSSL there). Called from
     * any Pastel thread. The answer: "status\ntext\nfinal address\n", the
     * headers ("Name: value\n"), an empty line, then the body; status 0 and
     * the reason when no answer came.
     */
    public static byte[] http(String method, String address, String headers, byte[] body, int timeoutMs,
                              boolean follow, boolean verify) {
        String host = address;
        try {
            URL url = new URL(address);
            host = url.getHost();
            HttpURLConnection c = (HttpURLConnection) url.openConnection();
            if (!verify && c instanceof HttpsURLConnection) {
                trustAll((HttpsURLConnection) c);
            }
            c.setConnectTimeout(timeoutMs);
            c.setReadTimeout(timeoutMs);
            c.setInstanceFollowRedirects(follow);
            c.setUseCaches(false);
            c.setRequestMethod(method);
            for (String line : headers.split("\n")) {
                int i = line.indexOf(':');
                if (i > 0) {
                    c.setRequestProperty(line.substring(0, i).trim(), line.substring(i + 1).trim());
                }
            }
            if (body != null) {
                c.setDoOutput(true);
                c.setFixedLengthStreamingMode(body.length);
                OutputStream out = c.getOutputStream();
                out.write(body);
                out.close();
            }
            int status = c.getResponseCode();
            String text = c.getResponseMessage();
            InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
            ByteArrayOutputStream answer = new ByteArrayOutputStream();
            StringBuilder head = new StringBuilder();
            head.append(status).append('\n').append(text == null ? "" : text).append('\n')
                .append(c.getURL().toString()).append('\n');
            for (Map.Entry<String, List<String>> h : c.getHeaderFields().entrySet()) {
                if (h.getKey() == null) {
                    continue;   // the status line
                }
                for (String v : h.getValue()) {
                    head.append(h.getKey()).append(": ").append(v).append('\n');
                }
            }
            head.append('\n');
            answer.write(head.toString().getBytes("UTF-8"));
            if (in != null) {
                byte[] buf = new byte[16384];
                int n;
                while ((n = in.read(buf)) > 0) {
                    answer.write(buf, 0, n);
                }
                in.close();
            }
            c.disconnect();
            return answer.toByteArray();
        } catch (UnknownHostException e) {
            return failure("cannot find server \"" + host + "\" (check the address and the network)");
        } catch (SocketTimeoutException e) {
            return failure("server \"" + host + "\" did not answer in time");
        } catch (ConnectException e) {
            return failure("cannot connect to \"" + host + "\" (is the server running, and is the port right?)");
        } catch (SSLException e) {
            return failure("the secure connection to \"" + host + "\" failed: " + e.getMessage());
        } catch (java.net.UnknownServiceException e) {
            // a release build does not send plain http:// (Android's network security)
            return failure("plain http:// to \"" + host + "\" is off in this build: use https://,"
                + " or allow it with [package.android] cleartext = true in pastel.toml");
        } catch (Exception e) {
            return failure(e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    private static byte[] failure(String reason) {
        try {
            return ("0\n" + reason.replace('\n', ' ') + "\n\n\n").getBytes("UTF-8");
        } catch (Exception e) {
            return new byte[0];
        }
    }

    /** VerifyCertificates = False: any certificate (only for testing). */
    private static void trustAll(HttpsURLConnection c) throws Exception {
        TrustManager[] all = new TrustManager[] { new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] chain, String type) { }
            public void checkServerTrusted(X509Certificate[] chain, String type) { }
        } };
        SSLContext ssl = SSLContext.getInstance("TLS");
        ssl.init(null, all, null);
        c.setSSLSocketFactory(ssl.getSocketFactory());
        c.setHostnameVerifier(new HostnameVerifier() {
            public boolean verify(String name, SSLSession session) { return true; }
        });
    }

    // ---------- the phone's features, for Pastel.Device ----------

    private void ui(Runnable r) {
        runOnUiThread(r);
    }

    public String clipboardText() {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm == null || !cm.hasPrimaryClip() || cm.getPrimaryClip().getItemCount() == 0) {
            return "";
        }
        CharSequence t = cm.getPrimaryClip().getItemAt(0).coerceToText(this);
        return t == null ? "" : t.toString();
    }

    public void setClipboardText(final String text) {
        ui(new Runnable() {
            public void run() {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (cm != null) {
                    cm.setPrimaryClip(ClipData.newPlainText("text", text));
                }
            }
        });
    }

    public void shareText(final String text, final String subject) {
        ui(new Runnable() {
            public void run() {
                Intent i = new Intent(Intent.ACTION_SEND);
                i.setType("text/plain");
                i.putExtra(Intent.EXTRA_TEXT, text);
                if (subject.length() > 0) {
                    i.putExtra(Intent.EXTRA_SUBJECT, subject);
                }
                startActivity(Intent.createChooser(i, null));
            }
        });
    }

    public void shareFile(final String path, final String mime) {
        ui(new Runnable() {
            public void run() {
                Intent i = new Intent(Intent.ACTION_SEND);
                Uri uri = PastelFiles.uriFor(PastelActivity.this, new File(path));
                i.setType(mime.length() > 0 ? mime : getContentResolver().getType(uri));
                i.putExtra(Intent.EXTRA_STREAM, uri);
                i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                startActivity(Intent.createChooser(i, null));
            }
        });
    }

    public boolean openUrl(final String url) {
        ui(new Runnable() {
            public void run() {
                try {
                    Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    if (url.startsWith("/")) {
                        File f = new File(url);
                        Uri uri = PastelFiles.uriFor(PastelActivity.this, f);
                        i.setDataAndType(uri, getContentResolver().getType(uri));
                        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    }
                    startActivity(i);
                } catch (Exception e) {
                    android.util.Log.w("pastel", "cannot open " + url + ": " + e);
                }
            }
        });
        return true;
    }

    public void vibrate(int ms) {
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v != null) {
            v.vibrate(ms);
        }
    }

    public void notify(int id, String title, String text) {
        PastelNotifications.post(this, String.valueOf(id), title, text);
    }

    // notifications (PastelNotifications.java): now, at a time, taken back; which one was tapped
    public void showNotification(String name, String title, String text) {
        PastelNotifications.post(this, name, title, text);
    }

    public void scheduleNotification(String name, String title, String text, long at, long repeatMs) {
        PastelNotifications.schedule(this, name, title, text, at, repeatMs);
    }

    public void cancelNotification(String name) {
        PastelNotifications.cancel(this, name);
    }

    public void cancelAllNotifications() {
        PastelNotifications.cancelAll(this);
    }

    /** Pastel.Java: runs a Pascal method on the UI thread (views, Toast). */
    public void runOnUi(final long token) {
        runOnUiThread(new Runnable() {
            public void run() {
                nativeRun(token);
            }
        });
    }

    public String takeClickedNotification() {
        String s = PastelNotifications.clicked;
        PastelNotifications.clicked = "";
        return s == null ? "" : s;
    }

    private void noteClicked(Intent i) {
        pushOpened(i);
        String name = i == null ? null : i.getStringExtra(PastelNotifications.EXTRA);
        if (name != null) {
            PastelNotifications.clicked = name;
            i.removeExtra(PastelNotifications.EXTRA);
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        noteClicked(intent);
        PastelShare.note(this, intent);
        PastelLinks.note(intent);
    }

    // ---------- links, the icon's shortcuts, picture-in-picture (PastelLinks) ----------

    public String takeLink() {
        return PastelLinks.takeLink();
    }

    public String takeShortcut() {
        return PastelLinks.takeShortcut();
    }

    public String setShortcuts(String spec) {
        return PastelLinks.setShortcuts(this, spec);
    }

    private volatile boolean pipAuto = false;
    private volatile int pipW = 16, pipH = 9;

    public String enterPip(final int w, final int h) {
        final String[] answer = { "" };
        final java.util.concurrent.CountDownLatch done = new java.util.concurrent.CountDownLatch(1);
        ui(new Runnable() {
            public void run() {
                answer[0] = PastelLinks.enterPip(PastelActivity.this, w, h);
                done.countDown();
            }
        });
        try {
            done.await(2, java.util.concurrent.TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            // the answer stays ""
        }
        return answer[0];
    }

    /** "1" in picture-in-picture, else "" */
    public String inPip() {
        return PastelLinks.inPip(this) ? "1" : "";
    }

    public void setPipAuto(final boolean auto, final int w, final int h) {
        pipAuto = auto;
        pipW = w;
        pipH = h;
        ui(new Runnable() {
            public void run() {
                PastelLinks.setPipAuto(PastelActivity.this, w, h, auto);
            }
        });
    }

    /** Android 8 to 11: Home pressed while a video plays - into picture-in-picture (12 and newer do it by themselves) */
    @Override
    protected void onUserLeaveHint() {
        super.onUserLeaveHint();
        if (pipAuto && Build.VERSION.SDK_INT >= 26 && Build.VERSION.SDK_INT < 31) {
            PastelLinks.enterPip(this, pipW, pipH);
        }
    }

    // ---------- contacts and the calendar (PastelPeople) ----------

    public void pickContact(final int code, final boolean email) {
        ui(new Runnable() {
            public void run() {
                PastelPeople.pick(PastelActivity.this, code, email);
            }
        });
    }

    public String readContacts(String search) {
        return PastelPeople.read(this, search);
    }

    public String addContact(String name, String phone, String email) {
        return PastelPeople.add(this, name, phone, email);
    }

    public String addEvent(String title, String begin, String end, boolean allDay, String place, String notes) {
        return PastelPeople.addEvent(this, title, begin, end, allDay, place, notes);
    }

    public String readEvents(String from, String till) {
        return PastelPeople.events(this, from, till);
    }

    // ---------- permissions ----------

    /** What to do when a permission asked for inside another request comes back (the camera for a photo). */
    private final java.util.HashMap<Integer, Runnable> afterPermission = new java.util.HashMap<Integer, Runnable>();
    // Android takes request codes of 16 bits: Pastel's code is found again through them
    private final java.util.HashMap<Integer, Integer> pendingPermission = new java.util.HashMap<Integer, Integer>();
    private final java.util.HashMap<Integer, String> pendingNames = new java.util.HashMap<Integer, String>();

    private boolean granted(String name) {
        if (Build.VERSION.SDK_INT < 23 || Build.VERSION.SDK_INT < newIn(name)) {
            return true;        // asked at install time, or not asked for on this Android (given without asking)
        }
        if (name.equals("android.permission.WRITE_EXTERNAL_STORAGE") && Build.VERSION.SDK_INT >= 29) {
            return true;        // Android 10 and newer: the gallery needs none (MediaStore)
        }
        return checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED;
    }

    /** The Android a runtime permission came with; before it there is nothing to ask. */
    private static int newIn(String name) {
        if (name.equals("android.permission.POST_NOTIFICATIONS")) {
            return 33;
        }
        if (name.equals("android.permission.BLUETOOTH_CONNECT") || name.equals("android.permission.BLUETOOTH_SCAN")) {
            return 31;
        }
        return 0;
    }

    /** granted, denied (may be asked again), blocked (denied for good: only the app's settings give it), unknown (never asked) */
    public String permissionState(String name) {
        if (granted(name)) {
            return "granted";
        }
        boolean asked = getSharedPreferences("pastel", MODE_PRIVATE).getBoolean("asked:" + name, false);
        if (!asked) {
            return "unknown";
        }
        return shouldShowRequestPermissionRationale(name) ? "denied" : "blocked";
    }

    /** True when the app's manifest names the permission (only those can be asked for). */
    public boolean declaresPermission(String name) {
        try {
            String[] all = getPackageManager().getPackageInfo(getPackageName(), PackageManager.GET_PERMISSIONS)
                .requestedPermissions;
            if (all != null) {
                for (String p : all) {
                    if (p.equals(name)) {
                        return true;
                    }
                }
            }
        } catch (Exception e) {
            // not known: as not declared
        }
        return false;
    }

    public void requestPermission(final int code, final String name) {
        requestPermissions(code, name);
    }

    /** Several at once (names one per line); the answer's text: name=granted|denied|blocked, a line each. */
    public void requestPermissions(final int code, final String names) {
        final java.util.ArrayList<String> ask = new java.util.ArrayList<String>();
        StringBuilder all = new StringBuilder();
        for (String n : names.split("\n")) {
            if (n.length() == 0) {
                continue;
            }
            all.append(n).append("=granted\n");
            if (!granted(n)) {
                ask.add(n);
            }
        }
        if (ask.isEmpty()) {
            Runnable then = afterPermission.remove(code);
            if (then != null) {
                then.run();
            } else {
                nativeResult(code, 1, all.toString());
            }
            return;
        }
        ui(new Runnable() {
            public void run() {
                android.content.SharedPreferences.Editor e = getSharedPreferences("pastel", MODE_PRIVATE).edit();
                for (String n : ask) {
                    e.putBoolean("asked:" + n, true);
                }
                e.apply();
                pendingPermission.put(code & 0xFFFF, Integer.valueOf(code));
                pendingNames.put(code & 0xFFFF, names);
                requestPermissions(ask.toArray(new String[0]), code & 0xFFFF);
            }
        });
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] names, int[] results) {
        Integer full = pendingPermission.remove(requestCode);
        String asked = pendingNames.remove(requestCode);
        int code = full == null ? requestCode : full.intValue();
        StringBuilder sb = new StringBuilder();
        boolean all = true;
        String[] list = asked != null ? asked.split("\n") : names;
        for (String n : list) {
            if (n.length() == 0) {
                continue;
            }
            String state = granted(n) ? "granted" : (shouldShowRequestPermissionRationale(n) ? "denied" : "blocked");
            if (!state.equals("granted")) {
                all = false;
            }
            sb.append(n).append('=').append(state).append('\n');
        }
        Runnable then = afterPermission.remove(code);
        if (then != null) {
            if (all) {
                then.run();
            } else {
                nativeResult(code, 0, "no permission for the camera");
            }
            return;
        }
        nativeResult(code, all ? 1 : 0, sb.toString());
    }

    // ---------- work in the background (PastelWork.java, PastelJob.java) ----------

    public void startWork(String title, String text, int kind) {
        PastelWork.start(this, title, text, kind);
    }

    public void updateWork(String title, String text) {
        PastelWork.update(this, title, text);
    }

    public void stopWork() {
        PastelWork.stop(this);
    }

    /** "1" while it runs (a string: what Pastel.Android's calls read) */
    public String workRunning() {
        return PastelWork.running ? "1" : "";
    }

    public String scheduleJob(String name, int minutes, boolean network) {
        return Build.VERSION.SDK_INT >= 21 && PastelJob.schedule(this, name, minutes, network) ? "1" : "";
    }

    public void cancelJob(String name) {
        if (Build.VERSION.SDK_INT >= 21) {
            PastelJob.cancel(this, name);
        }
    }

    // ---------- the phone's own date and time pickers ----------

    /** A date (month 1..12); the answer: "y-m-d", or nothing when cancelled. */
    public void pickDate(final int code, final int year, final int month, final int day) {
        ui(new Runnable() {
            public void run() {
                final boolean[] done = { false };
                android.app.DatePickerDialog dlg = new android.app.DatePickerDialog(PastelActivity.this,
                    new android.app.DatePickerDialog.OnDateSetListener() {
                        public void onDateSet(android.widget.DatePicker v, int y, int m, int d) {
                            if (!done[0]) {
                                done[0] = true;
                                nativeResult(code, 1, y + "-" + (m + 1) + "-" + d);
                            }
                        }
                    }, year, month - 1, day);
                dlg.setOnDismissListener(new android.content.DialogInterface.OnDismissListener() {
                    public void onDismiss(android.content.DialogInterface di) {
                        if (!done[0]) {
                            done[0] = true;
                            nativeResult(code, 0, "");
                        }
                    }
                });
                dlg.show();
            }
        });
    }

    /** A time of day; the answer: "h:m", or nothing when cancelled. */
    public void pickTime(final int code, final int hour, final int minute) {
        ui(new Runnable() {
            public void run() {
                final boolean[] done = { false };
                android.app.TimePickerDialog dlg = new android.app.TimePickerDialog(PastelActivity.this,
                    new android.app.TimePickerDialog.OnTimeSetListener() {
                        public void onTimeSet(android.widget.TimePicker v, int h, int m) {
                            if (!done[0]) {
                                done[0] = true;
                                nativeResult(code, 1, h + ":" + m);
                            }
                        }
                    }, hour, minute, android.text.format.DateFormat.is24HourFormat(PastelActivity.this));
                dlg.setOnDismissListener(new android.content.DialogInterface.OnDismissListener() {
                    public void onDismiss(android.content.DialogInterface di) {
                        if (!done[0]) {
                            done[0] = true;
                            nativeResult(code, 0, "");
                        }
                    }
                });
                dlg.show();
            }
        });
    }

    /** The app's page in the phone's settings: where a permission denied for good is given. */
    public void openAppSettings() {
        ui(new Runnable() {
            public void run() {
                try {
                    Intent i = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", getPackageName(), null));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(i);
                } catch (Exception e) {
                    android.util.Log.w("pastel", "cannot open the app's settings: " + e);
                }
            }
        });
    }

    private final java.util.HashMap<Integer, String> photos = new java.util.HashMap<Integer, String>();

    public void pickFile(final int code, final String mime) {
        ui(new Runnable() {
            public void run() {
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType(mime.length() > 0 ? mime : "*/*");
                try {
                    startActivityForResult(Intent.createChooser(i, null), code);
                } catch (Exception e) {
                    nativeResult(code, 0, e.toString());
                }
            }
        });
    }

    public void takePhoto(final int code) {
        final Runnable shoot = new Runnable() {
            public void run() {
                int rc = code & 0xFFFF;
                File f = new File(getCacheDir(), "photo-" + System.currentTimeMillis() + ".jpg");
                photos.put(rc, f.getAbsolutePath());
                photoCodes.put(rc, Integer.valueOf(code));
                Intent i = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                Uri uri = PastelFiles.uriFor(PastelActivity.this, f);
                i.putExtra(MediaStore.EXTRA_OUTPUT, uri);
                i.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
                i.setClipData(ClipData.newRawUri("photo", uri));
                try {
                    startActivityForResult(i, rc);
                } catch (android.content.ActivityNotFoundException e) {
                    photos.remove(rc);
                    nativeResult(code, 0, "there is no camera app on this phone");
                } catch (SecurityException e) {
                    photos.remove(rc);
                    nativeResult(code, 0, "no permission for the camera");
                } catch (Exception e) {
                    photos.remove(rc);
                    nativeResult(code, 0, e.toString());
                }
            }
        };
        // an app whose manifest names the camera must have it before the camera app may open
        // (Android refuses with "Permission Denial" otherwise); other apps need nothing
        final String cam = "android.permission.CAMERA";
        if (declaresPermission(cam) && !granted(cam)) {
            afterPermission.put(code, new Runnable() {
                public void run() {
                    ui(shoot);
                }
            });
            requestPermissions(code, cam);
            return;
        }
        ui(shoot);
    }

    private final java.util.HashMap<Integer, Integer> photoCodes = new java.util.HashMap<Integer, Integer>();

    private static void copy(InputStream in, OutputStream out) throws java.io.IOException {
        byte[] buf = new byte[65536];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        in.close();
        out.close();
    }

    /** A picture into the phone's gallery (Pictures/folder); the answer: where it went, or "!" and why not. */
    public String saveToGallery(String path, String folder, String mime) {
        try {
            File f = new File(path);
            if (Build.VERSION.SDK_INT >= 29) {
                android.content.ContentValues v = new android.content.ContentValues();
                v.put(MediaStore.MediaColumns.DISPLAY_NAME, f.getName());
                v.put(MediaStore.MediaColumns.MIME_TYPE, mime);
                v.put("relative_path", "Pictures/" + folder);       // MediaColumns.RELATIVE_PATH (Android 10)
                v.put("is_pending", 1);                             // MediaColumns.IS_PENDING
                Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
                if (uri == null) {
                    return "!the gallery did not take the picture";
                }
                copy(new java.io.FileInputStream(f), getContentResolver().openOutputStream(uri));
                v.clear();
                v.put("is_pending", 0);
                getContentResolver().update(uri, v, null, null);
                return uri.toString();
            }
            // older phones: the Pictures folder (WRITE_EXTERNAL_STORAGE)
            File dir = new File(android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_PICTURES), folder);
            dir.mkdirs();
            File to = new File(dir, f.getName());
            copy(new java.io.FileInputStream(f), new FileOutputStream(to));
            sendBroadcast(new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(to)));
            return to.getAbsolutePath();
        } catch (SecurityException e) {
            return "!no permission to write into the gallery (Android 9 and older: permissions = [\"storage\"])";
        } catch (Exception e) {
            return "!" + e;
        }
    }

    @Override
    protected void onActivityResult(int code, int result, Intent data) {
        super.onActivityResult(code, result, data);
        if (listenCodes.remove(code)) {
            java.util.ArrayList<String> r = data == null ? null
                : data.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS);
            if (result == RESULT_OK && r != null && !r.isEmpty()) {
                nativeResult(code, 1, r.get(0));
            } else {
                nativeResult(code, 0, "canceled");
            }
            return;
        }
        if (PastelPeople.pickCodes.remove(code)) {
            PastelPeople.picked(this, code, result, data);
            return;
        }
        if (PastelAuth.lockCodes.remove(code)) {
            nativeResult(code, result == RESULT_OK ? 1 : 0, result == RESULT_OK ? "" : "canceled");
            return;
        }
        if (photos.containsKey(code)) {
            String path = photos.remove(code);
            Integer full = photoCodes.remove(code);
            File f = new File(path);
            nativeResult(full == null ? code : full.intValue(), result == RESULT_OK && f.length() > 0 ? 1 : 0, path);
            return;
        }
        if (result != RESULT_OK || data == null || data.getData() == null) {
            nativeResult(code, 0, "");
            return;
        }
        // a picked file: copied into the app's cache, so Pascal can open it as a file
        try {
            nativeResult(code, 1, copyToCache(this, data.getData(), "picked").getAbsolutePath());
        } catch (Exception e) {
            nativeResult(code, 0, e.toString());
        }
    }

    /** A file of another app (a content: address) as a file of this app's cache, in folder. */
    static File copyToCache(Context ctx, Uri uri, String folder) throws Exception {
        String name = "file";
        Cursor c = ctx.getContentResolver().query(uri, new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null);
        if (c != null) {
            if (c.moveToFirst() && c.getString(0) != null) {
                name = c.getString(0).replace('/', '_');
            }
            c.close();
        } else if (uri.getLastPathSegment() != null) {
            name = uri.getLastPathSegment().replace('/', '_');
        }
        File dir = new File(ctx.getCacheDir(), folder);
        dir.mkdirs();
        File f = new File(dir, name);
        InputStream in = ctx.getContentResolver().openInputStream(uri);
        OutputStream out = new FileOutputStream(f);
        byte[] buf = new byte[65536];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        in.close();
        out.close();
        return f;
    }

    /** What another app shared with this one (PastelShare), once; "" when nothing. */
    public String takeShared() {
        return PastelShare.take();
    }

    public void location(final int code, final int timeoutMs) {
        ui(new Runnable() {
            public void run() {
                final LocationManager lm = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
                if (lm == null) {
                    nativeResult(code, 0, "no location service");
                    return;
                }
                try {
                    // a recent one is good enough
                    Location best = null;
                    for (String p : lm.getProviders(true)) {
                        Location l = lm.getLastKnownLocation(p);
                        if (l != null && (best == null || l.getTime() > best.getTime())) {
                            best = l;
                        }
                    }
                    if (best != null && System.currentTimeMillis() - best.getTime() < 120000) {
                        nativeResult(code, 1, best.getLatitude() + "," + best.getLongitude() + "," + best.getAccuracy());
                        return;
                    }
                    final boolean[] done = { false };
                    final LocationListener listener = new LocationListener() {
                        public void onLocationChanged(Location l) {
                            if (!done[0]) {
                                done[0] = true;
                                lm.removeUpdates(this);
                                nativeResult(code, 1, l.getLatitude() + "," + l.getLongitude() + "," + l.getAccuracy());
                            }
                        }
                        public void onStatusChanged(String p, int s, Bundle b) { }
                        public void onProviderEnabled(String p) { }
                        public void onProviderDisabled(String p) { }
                    };
                    String provider = lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ? LocationManager.GPS_PROVIDER
                        : LocationManager.NETWORK_PROVIDER;
                    lm.requestLocationUpdates(provider, 0, 0, listener, Looper.getMainLooper());
                    new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                        public void run() {
                            if (!done[0]) {
                                done[0] = true;
                                lm.removeUpdates(listener);
                                nativeResult(code, 0, "the place was not found in time (is location on?)");
                            }
                        }
                    }, timeoutMs);
                } catch (SecurityException e) {
                    nativeResult(code, 0, "no permission for the location");
                } catch (Exception e) {
                    nativeResult(code, 0, e.toString());
                }
            }
        });
    }

    /** Called by Pastel when no edit has the focus any more. */
    public void hideKeyboard() {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm != null) {
                    imm.hideSoftInputFromWindow(keyboardView.getWindowToken(), 0);
                }
                keyboardView.clearFocus();
            }
        });
    }

    /**
     * The invisible view the on-screen keyboard types into: a copy of the
     * focused edit (its text, selection and the word being composed) that the
     * keyboard reads and changes like an EditText's. Each change goes to Pascal
     * whole (nativeEdit); Pascal's own changes come back with set (editSync).
     */
    private class KeyboardView extends View {
        final android.text.Editable text = android.text.Editable.Factory.getInstance().newEditable("");
        /** the last of Pascal's states copied: answers carry it, so Pascal drops those made before */
        int gen;
        /** inside the keyboard's beginBatchEdit..endBatchEdit: one answer at the end */
        int batch;
        boolean dirty;

        KeyboardView(Context context) {
            super(context);
        }

        /** Pascal's text and selection; true when the text was another. */
        boolean set(String s, int a, int b, int g) {
            gen = g;
            boolean changed = !s.contentEquals(text);
            if (changed) {
                text.replace(0, text.length(), s);
            }
            BaseInputConnection.removeComposingSpans(text);
            int n = text.length();
            android.text.Selection.setSelection(text, clamp(a, n), clamp(b, n));
            return changed;
        }

        int clamp(int v, int n) {
            return v < 0 ? 0 : (v > n ? n : v);
        }

        int selStart() {
            return Math.min(android.text.Selection.getSelectionStart(text), android.text.Selection.getSelectionEnd(text));
        }

        int selEnd() {
            return Math.max(android.text.Selection.getSelectionStart(text), android.text.Selection.getSelectionEnd(text));
        }

        boolean multiLine() {
            return (inputType & EditorInfo.TYPE_TEXT_FLAG_MULTI_LINE) != 0;
        }

        /** the copy changed: Pascal gets it (once per batch) */
        void report() {
            if (batch > 0) {
                dirty = true;
                return;
            }
            dirty = false;
            nativeEdit(text.toString(), selStart(), selEnd(), BaseInputConnection.getComposingSpanStart(text),
                BaseInputConnection.getComposingSpanEnd(text), gen);
        }

        /** a change made here, not by the keyboard: the keyboard is told where the cursor is */
        void changedHere() {
            report();
            InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            if (imm != null) {
                imm.updateSelection(this, selStart(), selEnd(), BaseInputConnection.getComposingSpanStart(text),
                    BaseInputConnection.getComposingSpanEnd(text));
            }
        }

        /** typed text in place of the selection */
        void insert(String s) {
            BaseInputConnection.removeComposingSpans(text);
            int a = selStart();
            text.replace(a, selEnd(), s);
            android.text.Selection.setSelection(text, a + s.length());
            changedHere();
        }

        /** Backspace (forward: Delete): the selection, else one letter - a whole emoji, an accented letter */
        void delete(boolean forward) {
            BaseInputConnection.removeComposingSpans(text);
            int a = selStart();
            int b = selEnd();
            if (a == b) {
                java.text.BreakIterator it = java.text.BreakIterator.getCharacterInstance();
                it.setText(text.toString());
                if (forward) {
                    if (b >= text.length()) {
                        return;
                    }
                    b = it.following(b);
                } else {
                    if (a == 0) {
                        return;
                    }
                    a = it.preceding(a);
                }
                if (a < 0 || b < 0 || a >= b) {
                    return;
                }
            }
            text.delete(a, b);
            android.text.Selection.setSelection(text, a);
            changedHere();
        }

        @Override
        public boolean onCheckIsTextEditor() {
            return true;
        }

        @Override
        public InputConnection onCreateInputConnection(EditorInfo out) {
            out.inputType = inputType;
            out.imeOptions = imeOptions | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
            out.initialSelStart = selStart();
            out.initialSelEnd = selEnd();
            out.initialCapsMode = android.text.TextUtils.getCapsMode(text, selStart(), inputType);
            return new Connection(this);
        }

        private class Connection extends BaseInputConnection {
            Connection(View view) {
                super(view, true);
            }

            @Override
            public android.text.Editable getEditable() {
                return text;
            }

            @Override
            public boolean beginBatchEdit() {
                batch++;
                return true;
            }

            @Override
            public boolean endBatchEdit() {
                if (batch > 0) {
                    batch--;
                }
                if (batch == 0 && dirty) {
                    report();
                }
                return batch > 0;
            }

            @Override
            public boolean commitText(CharSequence t, int newCursorPosition) {
                // Enter as text in a one-line edit: the edit's Enter (Done, Search...), not a line break
                if (!multiLine() && t != null && t.toString().equals("\n")) {
                    finishComposingText();
                    nativeKey(KeyEvent.KEYCODE_ENTER);
                    return true;
                }
                boolean r = super.commitText(t, newCursorPosition);
                report();
                return r;
            }

            @Override
            public boolean setComposingText(CharSequence t, int newCursorPosition) {
                boolean r = super.setComposingText(t, newCursorPosition);
                report();
                return r;
            }

            @Override
            public boolean setComposingRegion(int start, int end) {
                boolean r = super.setComposingRegion(start, end);
                report();
                return r;
            }

            @Override
            public boolean finishComposingText() {
                boolean r = super.finishComposingText();
                report();
                return r;
            }

            @Override
            public boolean deleteSurroundingText(int before, int after) {
                boolean r = super.deleteSurroundingText(before, after);
                report();
                return r;
            }

            // Android 7's, in letters (code points): not in the android.jar Pastel is built with
            public boolean deleteSurroundingTextInCodePoints(int before, int after) {
                String s = text.toString();
                int a = selStart();
                int b = selEnd();
                int from = a;
                for (int i = 0; i < before && from > 0; i++) {
                    from = s.offsetByCodePoints(from, -1);
                }
                int to = b;
                for (int i = 0; i < after && to < s.length(); i++) {
                    to = s.offsetByCodePoints(to, 1);
                }
                beginBatchEdit();
                text.delete(b, to);
                text.delete(from, a);
                endBatchEdit();
                report();
                return true;
            }

            @Override
            public boolean setSelection(int start, int end) {
                boolean r = super.setSelection(start, end);
                report();
                return r;
            }

            @Override
            public boolean commitCorrection(android.view.inputmethod.CorrectionInfo info) {
                boolean r = super.commitCorrection(info);
                report();
                return r;
            }

            @Override
            public android.view.inputmethod.ExtractedText getExtractedText(
                    android.view.inputmethod.ExtractedTextRequest request, int flags) {
                android.view.inputmethod.ExtractedText et = new android.view.inputmethod.ExtractedText();
                et.text = text.toString();
                et.startOffset = 0;
                et.selectionStart = selStart();
                et.selectionEnd = selEnd();
                et.partialStartOffset = -1;
                et.partialEndOffset = -1;
                et.flags = multiLine() ? 0 : android.view.inputmethod.ExtractedText.FLAG_SINGLE_LINE;
                return et;
            }

            @Override
            public boolean performContextMenuAction(int id) {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (id == android.R.id.selectAll) {
                    android.text.Selection.setSelection(text, 0, text.length());
                    changedHere();
                } else if ((id == android.R.id.copy || id == android.R.id.cut) && cm != null && selEnd() > selStart()
                           && (inputType & 0xFFF) != (EditorInfo.TYPE_CLASS_TEXT | EditorInfo.TYPE_TEXT_VARIATION_PASSWORD)) {
                    cm.setPrimaryClip(ClipData.newPlainText("text", text.subSequence(selStart(), selEnd())));
                    if (id == android.R.id.cut) {
                        delete(false);
                    }
                } else if (id == android.R.id.paste && cm != null && cm.hasPrimaryClip()
                           && cm.getPrimaryClip().getItemCount() > 0) {
                    CharSequence t = cm.getPrimaryClip().getItemAt(0).coerceToText(PastelActivity.this);
                    if (t != null) {
                        insert(t.toString());
                    }
                } else {
                    return false;
                }
                return true;
            }

            @Override
            public boolean sendKeyEvent(KeyEvent event) {
                if (event.getAction() != KeyEvent.ACTION_DOWN) {
                    return true;
                }
                int code = event.getKeyCode();
                switch (code) {
                    case KeyEvent.KEYCODE_DEL:
                        delete(false);
                        return true;
                    case KeyEvent.KEYCODE_FORWARD_DEL:
                        delete(true);
                        return true;
                    case KeyEvent.KEYCODE_ENTER:
                    case KeyEvent.KEYCODE_NUMPAD_ENTER:
                        if (multiLine()) {
                            insert("\n");
                        } else {
                            nativeKey(KeyEvent.KEYCODE_ENTER);
                        }
                        return true;
                    case KeyEvent.KEYCODE_TAB:
                        nativeKey(KeyEvent.KEYCODE_TAB);
                        return true;
                    case KeyEvent.KEYCODE_DPAD_LEFT:
                    case KeyEvent.KEYCODE_DPAD_RIGHT: {
                        String s = text.toString();
                        int p = code == KeyEvent.KEYCODE_DPAD_LEFT
                            ? (selStart() > 0 ? s.offsetByCodePoints(selStart(), -1) : 0)
                            : (selEnd() < s.length() ? s.offsetByCodePoints(selEnd(), 1) : s.length());
                        BaseInputConnection.removeComposingSpans(text);
                        android.text.Selection.setSelection(text, p);
                        changedHere();
                        return true;
                    }
                    default:
                        break;
                }
                int c = event.getUnicodeChar(event.getMetaState());
                if (c > 0 && !Character.isISOControl(c)) {
                    insert(new String(Character.toChars(c)));
                } else {
                    nativeKey(code);
                }
                return true;
            }

            @Override
            public boolean performEditorAction(int action) {
                finishComposingText();
                if (action == EditorInfo.IME_ACTION_NEXT) {
                    nativeKey(KeyEvent.KEYCODE_TAB);
                } else {
                    nativeKey(KeyEvent.KEYCODE_ENTER);
                }
                return true;
            }
        }
    }

    /** Letters of a hardware keyboard: into the edit's copy while an edit has the keyboard, else to Pascal. */
    private void typed(String s) {
        if (keyboardView != null && keyboardView.hasFocus()) {
            keyboardView.insert(s);
        } else {
            nativeText(s);
        }
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int action = event.getAction();
        // text typed at once (other alphabets, suggestions, emoji): no key code
        if (action == KeyEvent.ACTION_MULTIPLE && event.getKeyCode() == KeyEvent.KEYCODE_UNKNOWN) {
            String s = event.getCharacters();
            if (s != null && s.length() > 0) {
                typed(s);
                return true;
            }
        }
        // a key of a hardware keyboard that types a letter in the keyboard's language
        if (action == KeyEvent.ACTION_DOWN && !event.isCtrlPressed() && !event.isAltPressed()) {
            int c = event.getUnicodeChar(event.getMetaState());
            if (c > 0 && (c & KeyCharacterMap.COMBINING_ACCENT) == 0 && !Character.isISOControl(c)) {
                typed(new String(Character.toChars(c)));
                return true;
            }
        }
        if (action == KeyEvent.ACTION_UP && !event.isCtrlPressed()) {
            int c = event.getUnicodeChar(event.getMetaState());
            if (c > 0 && (c & KeyCharacterMap.COMBINING_ACCENT) == 0 && !Character.isISOControl(c)) {
                return true;
            }
        }
        return super.dispatchKeyEvent(event);
    }
}
