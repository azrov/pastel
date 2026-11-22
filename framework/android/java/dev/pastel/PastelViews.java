// Android's own views over Pascal's window (Pastel.NativeViews: TWebBrowser,
// TVideoPlayer) and sound without a view (TMediaPlayer).
//
// Pascal draws the whole window itself (a NativeActivity owns its surface), so
// a native view lives in a small window of its own over the app's, at the
// place of its Pascal control: Pascal sends where it is (pixels of the app's
// window) as it moves. The little window lets the rest of the screen's touches
// through, and takes the keyboard only after it was touched (an input of a web
// page), giving it back on a touch outside it.
//
// Events go back to Pascal as the answers of the view's request number:
// "kind\tdata..." lines.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.graphics.PixelFormat;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.util.SparseArray;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.VideoView;

final class PastelViews {
    private PastelViews() { }

    interface Sink {
        void send(int code, String text);
        void back();
    }

    static final class Entry {
        int id;
        String kind;
        View view;               // the web or video view, in a frame
        FrameLayout frame;
        WebView web;
        VideoView video;
        PastelCamera camera;
        PastelPlayer pp;         // TVideoPlayer
        MediaPlayer player;      // audio, or the video's once it is prepared
        WindowManager.LayoutParams lp;
        boolean added, visible, focused;
        int x, y, w, h;
        volatile String url = "", title = "";
        volatile boolean canBack, canForward, prepared, looping;
        volatile int duration;
        float volume = 1f;
        Object backCallback;
    }

    private static final SparseArray<Entry> views = new SparseArray<Entry>();
    static Sink sink;

    private static void send(Entry e, String text) {
        if (sink != null) {
            sink.send(e.id, text);
        }
    }

    private static String clean(String s) {
        return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ');
    }

    // ---------- create, place, remove ----------

    static void create(final Activity a, final int id, final String kind) {
        a.runOnUiThread(new Runnable() {
            public void run() {
                if (views.get(id) != null) {
                    return;
                }
                Entry e = new Entry();
                e.id = id;
                e.kind = kind;
                synchronized (views) {
                    views.put(id, e);
                }
                if (kind.equals("audio")) {
                    return;
                }
                e.frame = new FrameLayout(a);
                if (kind.equals("web")) {
                    e.web = newWeb(a, e);
                    e.view = e.web;
                } else if (kind.equals("player")) {
                    final Entry pe = e;
                    e.pp = new PastelPlayer(a, new PastelPlayer.Events() {
                        public void event(String text) {
                            send(pe, text);
                        }
                    });
                    e.view = e.pp.view;
                } else if (kind.equals("camera")) {
                    final Entry ce = e;
                    e.camera = new PastelCamera(a, new PastelCamera.Events() {
                        public void event(String text) {
                            send(ce, text);
                        }
                    });
                    e.view = e.camera.view;
                } else {
                    e.video = newVideo(a, e);
                    e.view = e.video;
                }
                e.frame.addView(e.view, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.CENTER));
                watchTouches(a, e);
            }
        });
    }

    /** Where the view is (x, y, w, h: pixels of the app's window), the part of it seen
     *  (cx, cy, cw, ch: a scrolling parent cuts it) and whether it is seen at all. */
    static void bounds(final Activity a, final int id, final int x, final int y, final int w, final int h,
            final int cx, final int cy, final int cw, final int ch, final boolean visible) {
        a.runOnUiThread(new Runnable() {
            public void run() {
                Entry e = views.get(id);
                if (e == null || e.frame == null) {
                    return;
                }
                e.x = cx;
                e.y = cy;
                e.w = Math.max(1, cw);
                e.h = Math.max(1, ch);
                e.visible = visible && cw > 0 && ch > 0;
                // the whole view in the window of the part seen
                FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) e.view.getLayoutParams();
                if (p.width != Math.max(1, w) || p.height != Math.max(1, h) || p.leftMargin != x - cx
                        || p.topMargin != y - cy) {
                    p.width = Math.max(1, w);
                    p.height = Math.max(1, h);
                    p.leftMargin = x - cx;
                    p.topMargin = y - cy;
                    p.gravity = Gravity.LEFT | Gravity.TOP;
                    e.view.setLayoutParams(p);
                }
                apply(a, e);
            }
        });
    }

    private static int flags(Entry e) {
        int f = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
            | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
        if (!e.focused) {
            f |= WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
        }
        return f;
    }

    private static void apply(final Activity a, final Entry e) {
        if (a.isFinishing()) {
            return;
        }
        WindowManager wm = a.getWindowManager();
        View decor = a.getWindow().getDecorView();
        if (decor.getWindowToken() == null) {
            // the app's window is not there yet: in a moment
            decor.postDelayed(new Runnable() {
                public void run() {
                    if (views.get(e.id) == e) {
                        apply(a, e);
                    }
                }
            }, 100);
            return;
        }
        if (!e.visible) {
            if (e.added) {
                e.frame.setVisibility(View.GONE);
                if (e.focused) {
                    e.focused = false;
                    e.lp.flags = flags(e);
                    wm.updateViewLayout(e.frame, e.lp);
                }
            }
            return;
        }
        if (e.lp == null) {
            e.lp = new WindowManager.LayoutParams(WindowManager.LayoutParams.TYPE_APPLICATION_PANEL, flags(e),
                PixelFormat.TRANSLUCENT);
            e.lp.gravity = Gravity.LEFT | Gravity.TOP;
            e.lp.token = decor.getWindowToken();
            e.lp.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN;
        }
        e.lp.x = e.x;
        e.lp.y = e.y;
        e.lp.width = e.w;
        e.lp.height = e.h;
        e.lp.flags = flags(e);
        try {
            if (!e.added) {
                wm.addView(e.frame, e.lp);
                e.added = true;
                registerBack(e);
            } else {
                e.frame.setVisibility(View.VISIBLE);
                wm.updateViewLayout(e.frame, e.lp);
            }
        } catch (RuntimeException ex) {
            android.util.Log.w("pastel", "the native view cannot be shown: " + ex);
        }
    }

    /** Touched: it takes the keyboard (a web page's input); touched outside: gives it back. */
    private static void watchTouches(final Activity a, final Entry e) {
        e.frame.setOnTouchListener(new View.OnTouchListener() {
            public boolean onTouch(View v, MotionEvent ev) {
                if (ev.getActionMasked() == MotionEvent.ACTION_OUTSIDE) {
                    focus(a, e, false);
                }
                return false;
            }
        });
        if (e.pp != null) {
            return;          // the player tells of taps itself
        }
        e.view.setOnTouchListener(new View.OnTouchListener() {
            public boolean onTouch(View v, MotionEvent ev) {
                if (ev.getActionMasked() == MotionEvent.ACTION_DOWN && e.web != null) {
                    focus(a, e, true);
                }
                return false;
            }
        });
        e.view.setOnKeyListener(new View.OnKeyListener() {
            public boolean onKey(View v, int code, KeyEvent ev) {
                if (code == KeyEvent.KEYCODE_BACK && ev.getAction() == KeyEvent.ACTION_UP) {
                    back(a, e);
                    return true;
                }
                return code == KeyEvent.KEYCODE_BACK;
            }
        });
    }

    private static void focus(Activity a, Entry e, boolean on) {
        if (e.focused == on || !e.added) {
            return;
        }
        e.focused = on;
        e.lp.flags = flags(e);
        try {
            a.getWindowManager().updateViewLayout(e.frame, e.lp);
        } catch (RuntimeException ex) {
            // removed meanwhile
        }
        if (on) {
            e.view.requestFocus();
        }
    }

    /** Back while the view has the keyboard: the page before, else Pascal's Back */
    private static void back(Activity a, Entry e) {
        if (e.web != null && e.web.canGoBack()) {
            e.web.goBack();
            return;
        }
        focus(a, e, false);
        if (sink != null) {
            sink.back();
        }
    }

    /** Android 13 and newer send Back to the focused window's callback, not as a key */
    private static void registerBack(final Entry e) {
        if (Build.VERSION.SDK_INT < 33 || e.web == null) {
            return;
        }
        try {
            Class<?> cb = Class.forName("android.window.OnBackInvokedCallback");
            final Activity a = (Activity) e.frame.getContext();
            e.backCallback = java.lang.reflect.Proxy.newProxyInstance(cb.getClassLoader(), new Class<?>[] { cb },
                new java.lang.reflect.InvocationHandler() {
                    public Object invoke(Object proxy, java.lang.reflect.Method m, Object[] args) {
                        String n = m.getName();
                        if (n.equals("onBackInvoked")) {
                            back(a, e);
                            return null;
                        }
                        if (n.equals("hashCode")) {
                            return Integer.valueOf(System.identityHashCode(proxy));
                        }
                        if (n.equals("equals")) {
                            return Boolean.valueOf(args != null && proxy == args[0]);
                        }
                        return n.equals("toString") ? "PastelViewBack" : null;
                    }
                });
            Object d = View.class.getMethod("findOnBackInvokedDispatcher").invoke(e.frame);
            if (d != null) {
                d.getClass().getMethod("registerOnBackInvokedCallback", int.class, cb).invoke(d, 0, e.backCallback);
            }
        } catch (Throwable ex) {
            android.util.Log.w("pastel", "no back callback for the view: " + ex);
        }
    }

    static void destroy(final Activity a, final int id) {
        a.runOnUiThread(new Runnable() {
            public void run() {
                Entry e = views.get(id);
                if (e == null) {
                    return;
                }
                synchronized (views) {
                    views.remove(id);
                }
                release(a, e);
            }
        });
    }

    private static void release(Activity a, Entry e) {
        if (e.player != null && e.video == null) {
            e.player.release();
        }
        e.player = null;
        if (e.video != null) {
            e.video.stopPlayback();
        }
        if (e.web != null) {
            e.web.stopLoading();
            e.web.destroy();
        }
        if (e.camera != null) {
            e.camera.close();
        }
        if (e.pp != null) {
            e.pp.release();
        }
        if (e.added) {
            try {
                a.getWindowManager().removeViewImmediate(e.frame);
            } catch (RuntimeException ex) {
                // the window went already
            }
            e.added = false;
        }
    }

    /** The activity goes: every view with it. */
    static void destroyAll(Activity a) {
        for (int i = 0; i < views.size(); i++) {
            release(a, views.valueAt(i));
        }
        synchronized (views) {
            views.clear();
        }
    }

    // ---------- web pages ----------

    private static WebView newWeb(final Activity a, final Entry e) {
        WebView w = new WebView(a);
        WebSettings s = w.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        w.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView v, String url, android.graphics.Bitmap icon) {
                e.url = url;
                send(e, "loading\t" + clean(url));
            }

            @Override
            public void onPageFinished(WebView v, String url) {
                e.url = url;
                e.title = v.getTitle() == null ? "" : v.getTitle();
                e.canBack = v.canGoBack();
                e.canForward = v.canGoForward();
                send(e, "loaded\t" + clean(url) + "\t" + clean(e.title));
            }

            @Override
            @SuppressWarnings("deprecation")
            public void onReceivedError(WebView v, int code, String description, String url) {
                send(e, "error\t" + clean(description) + "\t" + clean(url));
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView v, String url) {
                // links to other apps (tel:, mailto:, intent:, market:): the phone opens them
                if (url != null && !url.startsWith("http:") && !url.startsWith("https:") && !url.startsWith("file:")
                        && !url.startsWith("about:") && !url.startsWith("data:") && !url.startsWith("javascript:")) {
                    try {
                        a.startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW, Uri.parse(url)));
                    } catch (RuntimeException ex) {
                        send(e, "error\tno app opens " + clean(url) + "\t" + clean(url));
                    }
                    return true;
                }
                return false;
            }
        });
        w.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onReceivedTitle(WebView v, String title) {
                e.title = title == null ? "" : title;
            }
        });
        // the page talks to Pascal: pastel.post("text")
        w.addJavascriptInterface(new Object() {
            @JavascriptInterface
            public void post(String text) {
                send(e, "message\t" + (text == null ? "" : text.replace("\t", " ")));
            }
        }, "pastel");
        return w;
    }

    // ---------- video and sound ----------

    private static VideoView newVideo(final Activity a, final Entry e) {
        final VideoView v = new VideoView(a);
        v.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
            public void onPrepared(MediaPlayer mp) {
                e.player = mp;
                e.prepared = true;
                e.duration = mp.getDuration();
                mp.setLooping(e.looping);
                mp.setVolume(e.volume, e.volume);
                send(e, "prepared\t" + e.duration + "\t" + mp.getVideoWidth() + "\t" + mp.getVideoHeight());
            }
        });
        v.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
            public void onCompletion(MediaPlayer mp) {
                send(e, "completed");
            }
        });
        v.setOnErrorListener(new MediaPlayer.OnErrorListener() {
            public boolean onError(MediaPlayer mp, int what, int extra) {
                send(e, "error\tthe video cannot be played (" + what + ", " + extra + ")");
                return true;
            }
        });
        return v;
    }

    private static MediaPlayer newPlayer(final Entry e) {
        MediaPlayer mp = new MediaPlayer();
        mp.setAudioStreamType(AudioManager.STREAM_MUSIC);
        mp.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
            public void onPrepared(MediaPlayer p) {
                e.prepared = true;
                e.duration = p.getDuration();
                send(e, "prepared\t" + e.duration + "\t0\t0");
            }
        });
        mp.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
            public void onCompletion(MediaPlayer p) {
                send(e, "completed");
            }
        });
        mp.setOnErrorListener(new MediaPlayer.OnErrorListener() {
            public boolean onError(MediaPlayer p, int what, int extra) {
                send(e, "error\tthe sound cannot be played (" + what + ", " + extra + ")");
                return true;
            }
        });
        return mp;
    }

    private static Uri uriOf(String s) {
        if (s.startsWith("/")) {
            return Uri.fromFile(new java.io.File(s));
        }
        return Uri.parse(s);
    }

    // ---------- what Pascal asks ----------

    static void run(final Activity a, final int id, final String op, final String arg) {
        a.runOnUiThread(new Runnable() {
            public void run() {
                Entry e = views.get(id);
                if (e == null) {
                    return;
                }
                try {
                    if (e.web != null) {
                        web(e, op, arg);
                    } else if (e.pp != null) {
                        e.pp.run(op, arg);
                    } else if (e.camera != null) {
                        if (op.equals("start")) {
                            e.camera.start(arg.equals("front"));
                        } else if (op.equals("stop")) {
                            e.camera.stop();
                        } else if (op.equals("photo")) {
                            e.camera.photo(arg);
                        } else if (op.equals("torch")) {
                            e.camera.setTorch(arg.equals("1"));
                        }
                    } else {
                        media(a, e, op, arg);
                    }
                } catch (RuntimeException ex) {
                    send(e, "error\t" + clean(ex.toString()));
                }
            }
        });
    }

    private static void web(final Entry e, String op, String arg) {
        WebView w = e.web;
        if (op.equals("url")) {
            w.loadUrl(arg);
        } else if (op.equals("html")) {
            int i = arg.indexOf('\n');
            String base = i >= 0 ? arg.substring(0, i) : "";
            String html = i >= 0 ? arg.substring(i + 1) : arg;
            w.loadDataWithBaseURL(base.length() > 0 ? base : null, html, "text/html", "UTF-8", null);
        } else if (op.equals("back")) {
            w.goBack();
        } else if (op.equals("forward")) {
            w.goForward();
        } else if (op.equals("reload")) {
            w.reload();
        } else if (op.equals("stop")) {
            w.stopLoading();
        } else if (op.equals("js")) {
            int i = arg.indexOf('\n');
            final String tag = i >= 0 ? arg.substring(0, i) : "";
            w.evaluateJavascript(i >= 0 ? arg.substring(i + 1) : arg, new ValueCallback<String>() {
                public void onReceiveValue(String value) {
                    send(e, "js\t" + tag + "\t" + (value == null ? "null" : value.replace("\t", " ")));
                }
            });
        } else if (op.equals("zoom")) {
            w.getSettings().setSupportZoom(arg.equals("1"));
            w.getSettings().setBuiltInZoomControls(arg.equals("1"));
        }
    }

    private static void media(Activity a, final Entry e, String op, String arg) {
        if (op.equals("open")) {
            e.prepared = false;
            e.duration = 0;
            if (e.video != null) {
                e.player = null;
                e.video.setVideoURI(uriOf(arg));
            } else {
                if (e.player != null) {
                    e.player.release();
                }
                e.player = newPlayer(e);
                try {
                    e.player.setDataSource(a, uriOf(arg));
                } catch (java.io.IOException ex) {
                    send(e, "error\t" + clean(ex.getMessage()));
                    return;
                }
                e.player.setLooping(e.looping);
                e.player.setVolume(e.volume, e.volume);
                e.player.prepareAsync();
            }
        } else if (op.equals("play")) {
            if (e.video != null) {
                e.video.start();
            } else if (e.player != null) {
                e.player.start();
            }
        } else if (op.equals("pause")) {
            if (e.video != null) {
                e.video.pause();
            } else if (e.player != null && e.prepared) {
                e.player.pause();
            }
        } else if (op.equals("stop")) {
            if (e.video != null) {
                e.video.pause();
                e.video.seekTo(0);
            } else if (e.player != null && e.prepared) {
                e.player.pause();
                e.player.seekTo(0);
            }
        } else if (op.equals("seek")) {
            int ms = Integer.parseInt(arg);
            if (e.video != null) {
                e.video.seekTo(ms);
            } else if (e.player != null && e.prepared) {
                e.player.seekTo(ms);
            }
        } else if (op.equals("volume")) {
            e.volume = Float.parseFloat(arg);
            if (e.player != null) {
                e.player.setVolume(e.volume, e.volume);
            }
        } else if (op.equals("loop")) {
            e.looping = arg.equals("1");
            if (e.player != null) {
                e.player.setLooping(e.looping);
            }
        }
    }

    /** web: url, title, can go back (1/0), forward; media: position, duration (ms), playing (1/0) */
    static String state(int id) {
        Entry e;
        synchronized (views) {
            e = views.get(id);
        }
        if (e == null) {
            return "";
        }
        if (e.pp != null) {
            return e.pp.state();
        }
        if (e.kind.equals("web")) {
            return e.url + "\t" + e.title + "\t" + (e.canBack ? "1" : "0") + "\t" + (e.canForward ? "1" : "0");
        }
        int pos = 0;
        boolean playing = false;
        try {
            if (e.video != null) {
                pos = e.video.getCurrentPosition();
                playing = e.video.isPlaying();
            } else if (e.player != null && e.prepared) {
                pos = e.player.getCurrentPosition();
                playing = e.player.isPlaying();
            }
        } catch (RuntimeException ex) {
            // not ready
        }
        return pos + "\t" + e.duration + "\t" + (playing ? "1" : "0");
    }

}
