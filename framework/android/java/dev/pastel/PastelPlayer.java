// The video player of TVideoPlayer (Pastel.VideoPlayer) on Android: ExoPlayer
// (androidx.media3) when the app has it in [package.android] libraries, else
// Android's MediaPlayer. ExoPlayer is used through reflection, so Pastel needs
// none of its classes to compile; it plays HLS, MPEG-TS streams, MP4, MKV.
// Over the picture: a band with a title, a line, the progress and the time
// (TVideoPlayer.ShowInfo), and a spinner while it waits for the stream.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.graphics.Color;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.List;

final class PastelPlayer {
    interface Events {
        void event(String text);
    }

    /** a frame that keeps the picture's shape: black bars around it */
    static final class Fit extends FrameLayout {
        float aspect;
        final View child;

        Fit(Activity a, View c) {
            super(a);
            child = c;
            setBackgroundColor(Color.BLACK);
            addView(c, new FrameLayout.LayoutParams(1, 1, Gravity.CENTER));
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            int w = MeasureSpec.getSize(ws);
            int h = MeasureSpec.getSize(hs);
            int cw = w;
            int ch = h;
            if (aspect > 0 && w > 0 && h > 0) {
                if (w / (float) h > aspect) {
                    cw = Math.round(h * aspect);
                } else {
                    ch = Math.round(w / aspect);
                }
            }
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) child.getLayoutParams();
            if (p.width != cw || p.height != ch) {
                p.width = cw;
                p.height = ch;
            }
            super.onMeasure(ws, hs);
        }
    }

    final View view;
    private final Activity act;
    private final Events events;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final SurfaceView surface;
    private final Fit fit;
    private final LinearLayout band;
    private final TextView title, line, time;
    private final ProgressBar bar, spinner;

    // ExoPlayer (reflection) or MediaPlayer
    private Object exo;
    private Class<?> exoClass;
    private MediaPlayer mp;
    private boolean surfaceReady, mpPrepared;
    private String url = "", agent = "";
    private volatile String state = "idle";
    private volatile long position, duration;
    private float volume = 1f;
    private boolean muted;
    private long infoUntil;
    private final Runnable ticker;

    PastelPlayer(Activity a, Events ev) {
        act = a;
        events = ev;
        surface = new SurfaceView(a);
        fit = new Fit(a, surface);
        FrameLayout root = new FrameLayout(a);
        root.setBackgroundColor(Color.BLACK);
        root.addView(fit, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        spinner = new ProgressBar(a);
        spinner.setIndeterminate(true);
        spinner.setVisibility(View.GONE);
        root.addView(spinner, new FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER));

        band = new LinearLayout(a);
        band.setOrientation(LinearLayout.VERTICAL);
        band.setBackgroundColor(0xC0101014);
        band.setPadding(dp(20), dp(14), dp(20), dp(16));
        title = text(a, 20, true, Color.WHITE);
        line = text(a, 15, false, 0xFFCFD3DC);
        bar = new ProgressBar(a, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(1000);
        time = text(a, 13, false, 0xFFCFD3DC);
        band.addView(title);
        band.addView(line);
        band.addView(bar, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(10)));
        band.addView(time);
        band.setVisibility(View.GONE);
        root.addView(band, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));
        view = root;

        surface.getHolder().addCallback(new SurfaceHolder.Callback() {
            public void surfaceCreated(SurfaceHolder h) {
                surfaceReady = true;
                if (mp != null) {
                    mp.setDisplay(h);
                }
            }

            public void surfaceChanged(SurfaceHolder h, int f, int w, int hh) { }

            public void surfaceDestroyed(SurfaceHolder h) {
                surfaceReady = false;
                if (mp != null) {
                    mp.setDisplay(null);
                }
            }
        });
        root.setOnTouchListener(new View.OnTouchListener() {
            float dx, dy;

            public boolean onTouch(View v, MotionEvent e) {
                if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    dx = e.getX();
                    dy = e.getY();
                } else if (e.getActionMasked() == MotionEvent.ACTION_UP
                        && Math.abs(e.getX() - dx) < dp(16) && Math.abs(e.getY() - dy) < dp(16)) {
                    events.event("tap\t" + Math.round(e.getX()) + "\t" + Math.round(e.getY())
                        + "\t" + v.getWidth() + "\t" + v.getHeight());
                }
                return true;
            }
        });
        ticker = new Runnable() {
            public void run() {
                poll();
                updateBand();
                ui.postDelayed(this, 500);
            }
        };
        ui.postDelayed(ticker, 500);
    }

    private int dp(int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
            act.getResources().getDisplayMetrics()));
    }

    private static TextView text(Activity a, int sp, boolean bold, int color) {
        TextView t = new TextView(a);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setSingleLine(true);
        if (bold) {
            t.setTypeface(t.getTypeface(), android.graphics.Typeface.BOLD);
        }
        return t;
    }

    static boolean hasExo() {
        try {
            Class.forName("androidx.media3.exoplayer.ExoPlayer");
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    String engine() {
        return hasExo() ? "exoplayer" : "mediaplayer";
    }

    private void setState(String s) {
        if (!s.equals(state)) {
            state = s;
            spinner.setVisibility(s.equals("loading") ? View.VISIBLE : View.GONE);
            events.event("state\t" + s);
        }
    }

    private static String clean(String s) {
        return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ').replace('\u0001', ' ').replace('\u0002', ' ');
    }

    // ---------- what Pascal asks ----------

    void run(String op, String arg) {
        if (op.equals("open")) {
            int i = arg.indexOf('\n');
            url = i >= 0 ? arg.substring(0, i) : arg;
            agent = i >= 0 ? arg.substring(i + 1) : "";
            open();
        } else if (op.equals("play")) {
            if (exo != null) {
                call("play");
            } else if (mp != null && mpPrepared) {
                mp.start();
                setState("playing");
            }
        } else if (op.equals("pause")) {
            if (exo != null) {
                call("pause");
            } else if (mp != null && mpPrepared) {
                mp.pause();
                setState("paused");
            }
        } else if (op.equals("stop")) {
            stop();
            setState("idle");
        } else if (op.equals("seek")) {
            long ms = Long.parseLong(arg);
            if (exo != null) {
                call("seekTo", new Class<?>[] {long.class}, ms);
            } else if (mp != null && mpPrepared) {
                mp.seekTo((int) ms);
            }
        } else if (op.equals("volume")) {
            volume = Float.parseFloat(arg);
            applyVolume();
        } else if (op.equals("mute")) {
            muted = arg.equals("1");
            applyVolume();
        } else if (op.equals("track")) {
            int i = arg.indexOf(' ');
            selectTrack(arg.substring(0, i), Integer.parseInt(arg.substring(i + 1)));
        } else if (op.equals("info")) {
            String[] p = arg.split("\n", -1);
            title.setText(p.length > 0 ? p[0] : "");
            line.setText(p.length > 1 ? p[1] : "");
            line.setVisibility(line.getText().length() > 0 ? View.VISIBLE : View.GONE);
            int secs = p.length > 2 ? Integer.parseInt(p[2]) : 4;
            infoUntil = secs > 0 ? System.currentTimeMillis() + secs * 1000L : Long.MAX_VALUE;
            band.setVisibility(View.VISIBLE);
            updateBand();
        } else if (op.equals("hideinfo")) {
            infoUntil = 0;
            band.setVisibility(View.GONE);
        }
    }

    /** position (ms), duration (ms; 0 live), state */
    String state() {
        return position + "\t" + duration + "\t" + state + "\t" + engine();
    }

    void release() {
        ui.removeCallbacks(ticker);
        stop();
    }

    private void applyVolume() {
        float v = muted ? 0f : volume;
        if (exo != null) {
            call("setVolume", new Class<?>[] {float.class}, v);
        } else if (mp != null) {
            mp.setVolume(v, v);
        }
    }

    private void stop() {
        if (exo != null) {
            call("release");
            exo = null;
        }
        if (mp != null) {
            try {
                mp.release();
            } catch (RuntimeException e) {
                // gone already
            }
            mp = null;
        }
        mpPrepared = false;
        position = 0;
        duration = 0;
    }

    private void open() {
        stop();
        setState("loading");
        if (hasExo()) {
            try {
                openExo();
                return;
            } catch (Throwable t) {
                exo = null;
                android.util.Log.w("pastel", "ExoPlayer could not start, MediaPlayer plays: " + t);
            }
        }
        openMediaPlayer();
    }

    // ---------- MediaPlayer ----------

    private void openMediaPlayer() {
        mp = new MediaPlayer();
        mp.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
            public void onPrepared(MediaPlayer p) {
                mpPrepared = true;
                duration = Math.max(0, p.getDuration());
                p.setVolume(muted ? 0f : volume, muted ? 0f : volume);
                p.start();
                setState("playing");
                sendTracks();
            }
        });
        mp.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
            public void onCompletion(MediaPlayer p) {
                setState("ended");
            }
        });
        mp.setOnErrorListener(new MediaPlayer.OnErrorListener() {
            public boolean onError(MediaPlayer p, int what, int extra) {
                events.event("error\tthe stream cannot be played (" + what + ", " + extra + ")");
                setState("error");
                return true;
            }
        });
        mp.setOnInfoListener(new MediaPlayer.OnInfoListener() {
            public boolean onInfo(MediaPlayer p, int what, int extra) {
                if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) {
                    setState("loading");
                } else if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) {
                    setState(p.isPlaying() ? "playing" : "paused");
                }
                return false;
            }
        });
        mp.setOnVideoSizeChangedListener(new MediaPlayer.OnVideoSizeChangedListener() {
            public void onVideoSizeChanged(MediaPlayer p, int w, int h) {
                resize(w, h, 1f);
            }
        });
        try {
            HashMap<String, String> headers = new HashMap<String, String>();
            if (agent.length() > 0) {
                headers.put("User-Agent", agent);
            }
            if (url.startsWith("/")) {
                mp.setDataSource(url);
            } else {
                mp.setDataSource(act, Uri.parse(url), headers);
            }
            if (surfaceReady) {
                mp.setDisplay(surface.getHolder());
            }
            mp.prepareAsync();
        } catch (Exception e) {
            events.event("error\t" + clean(e.getMessage()));
            setState("error");
        }
    }

    // ---------- ExoPlayer, through reflection ----------

    private Object call(String name) {
        return call(name, new Class<?>[0]);
    }

    private Object call(String name, Class<?>[] types, Object... args) {
        try {
            return exoClass.getMethod(name, types).invoke(exo, args);
        } catch (Exception e) {
            android.util.Log.w("pastel", "ExoPlayer." + name + ": " + e);
            return null;
        }
    }

    private static Object invoke(Object o, String cls, String name, Class<?>[] types, Object... args)
            throws Exception {
        return Class.forName(cls).getMethod(name, types).invoke(o, args);
    }

    private void openExo() throws Exception {
        Class<?> bc = Class.forName("androidx.media3.exoplayer.ExoPlayer$Builder");
        Object b = bc.getConstructor(android.content.Context.class).newInstance(act);
        if (agent.length() > 0) {
            Class<?> fc = Class.forName("androidx.media3.datasource.DefaultHttpDataSource$Factory");
            Object f = fc.getConstructor().newInstance();
            fc.getMethod("setUserAgent", String.class).invoke(f, agent);
            fc.getMethod("setAllowCrossProtocolRedirects", boolean.class).invoke(f, true);
            Class<?> mc = Class.forName("androidx.media3.exoplayer.source.DefaultMediaSourceFactory");
            Object m = mc.getConstructor(Class.forName("androidx.media3.datasource.DataSource$Factory")).newInstance(f);
            bc.getMethod("setMediaSourceFactory",
                Class.forName("androidx.media3.exoplayer.source.MediaSource$Factory")).invoke(b, m);
        }
        exoClass = Class.forName("androidx.media3.exoplayer.ExoPlayer");
        exo = bc.getMethod("build").invoke(b);
        exoClass.getMethod("setVideoSurfaceView", SurfaceView.class).invoke(exo, surface);
        Class<?> lc = Class.forName("androidx.media3.common.Player$Listener");
        Object listener = Proxy.newProxyInstance(lc.getClassLoader(), new Class<?>[] {lc}, new InvocationHandler() {
            public Object invoke(Object p, Method m, Object[] a) {
                String n = m.getName();
                if (n.equals("hashCode")) {
                    return System.identityHashCode(p);
                }
                if (n.equals("equals")) {
                    return p == a[0];
                }
                if (n.equals("toString")) {
                    return "PastelPlayer.Listener";
                }
                try {
                    if (n.equals("onPlaybackStateChanged")) {
                        int s = (Integer) a[0];
                        if (s == 2) {
                            setState("loading");
                        } else if (s == 4) {
                            setState("ended");
                        } else if (s == 3) {
                            Object playing = call("isPlaying");
                            setState(Boolean.TRUE.equals(playing) ? "playing" : "paused");
                        }
                    } else if (n.equals("onIsPlayingChanged")) {
                        if ((Boolean) a[0]) {
                            setState("playing");
                        } else if (state.equals("playing")) {
                            setState("paused");
                        }
                    } else if (n.equals("onPlayerError")) {
                        Throwable t = (Throwable) a[0];
                        String code = "";
                        try {
                            code = (String) t.getClass().getMethod("getErrorCodeName").invoke(t);
                        } catch (Exception e) {
                            // an older version
                        }
                        events.event("error\t" + clean(t.getMessage()) + (code.length() > 0 ? " (" + code + ")" : ""));
                        setState("error");
                    } else if (n.equals("onTracksChanged")) {
                        sendTracks();
                    } else if (n.equals("onVideoSizeChanged")) {
                        Object vs = a[0];
                        int w = vs.getClass().getField("width").getInt(vs);
                        int h = vs.getClass().getField("height").getInt(vs);
                        float r = vs.getClass().getField("pixelWidthHeightRatio").getFloat(vs);
                        resize(w, h, r);
                    }
                } catch (Exception e) {
                    android.util.Log.w("pastel", "player event " + n + ": " + e);
                }
                return null;
            }
        });
        exoClass.getMethod("addListener", lc).invoke(exo, listener);
        Class<?> ic = Class.forName("androidx.media3.common.MediaItem");
        Object item = ic.getMethod("fromUri", String.class).invoke(null, url);
        exoClass.getMethod("setMediaItem", ic).invoke(exo, item);
        exoClass.getMethod("prepare").invoke(exo);
        exoClass.getMethod("setPlayWhenReady", boolean.class).invoke(exo, true);
        applyVolume();
    }

    private void resize(final int w, final int h, final float ratio) {
        ui.post(new Runnable() {
            public void run() {
                if (w > 0 && h > 0) {
                    fit.aspect = w * ratio / h;
                    fit.requestLayout();
                    events.event("size\t" + w + "\t" + h);
                }
            }
        });
    }

    private void poll() {
        try {
            if (exo != null) {
                Object p = call("getCurrentPosition");
                Object d = call("getDuration");
                position = p == null ? 0 : (Long) p;
                long dd = d == null ? 0 : (Long) d;
                Object live = call("isCurrentMediaItemLive");
                duration = (dd < 0 || Boolean.TRUE.equals(live)) ? 0 : dd;
            } else if (mp != null && mpPrepared) {
                position = mp.getCurrentPosition();
                duration = Math.max(0, mp.getDuration());
            }
        } catch (RuntimeException e) {
            // not ready
        }
    }

    private static String clock(long ms) {
        long s = ms / 1000;
        if (s >= 3600) {
            return String.format("%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60);
        }
        return String.format("%d:%02d", s / 60, s % 60);
    }

    private void updateBand() {
        if (band.getVisibility() != View.VISIBLE) {
            return;
        }
        if (System.currentTimeMillis() > infoUntil) {
            band.setVisibility(View.GONE);
            return;
        }
        if (duration > 0) {
            bar.setVisibility(View.VISIBLE);
            bar.setProgress((int) (position * 1000 / duration));
            time.setText(clock(position) + " / " + clock(duration));
        } else {
            bar.setVisibility(View.GONE);
            time.setText(state.equals("loading") ? "..." : "LIVE");
        }
    }

    // ---------- tracks: "kind\u0002id\u0002selected\u0002language\u0002title" joined by \u0001 ----------

    private void sendTracks() {
        StringBuilder s = new StringBuilder();
        try {
            if (exo != null) {
                Object tracks = call("getCurrentTracks");
                List<?> groups = (List<?>) tracks.getClass().getMethod("getGroups").invoke(tracks);
                for (int g = 0; g < groups.size(); g++) {
                    Object grp = groups.get(g);
                    int type = (Integer) invoke(grp, "androidx.media3.common.Tracks$Group", "getType", new Class<?>[0]);
                    if (type != 1 && type != 3) {
                        continue;
                    }
                    int n = grp.getClass().getField("length").getInt(grp);
                    for (int i = 0; i < n; i++) {
                        Object f = invoke(grp, "androidx.media3.common.Tracks$Group", "getTrackFormat",
                            new Class<?>[] {int.class}, i);
                        boolean sel = (Boolean) invoke(grp, "androidx.media3.common.Tracks$Group", "isTrackSelected",
                            new Class<?>[] {int.class}, i);
                        Object lang = f.getClass().getField("language").get(f);
                        Object label = f.getClass().getField("label").get(f);
                        if (s.length() > 0) {
                            s.append('\u0001');
                        }
                        s.append(type == 1 ? "audio" : "sub").append('\u0002').append(g * 100 + i).append('\u0002')
                            .append(sel ? "1" : "0").append('\u0002').append(clean(lang == null ? "" : lang.toString()))
                            .append('\u0002').append(clean(label == null ? "" : label.toString()));
                    }
                }
            } else if (mp != null) {
                MediaPlayer.TrackInfo[] info = mp.getTrackInfo();
                for (int i = 0; i < info.length; i++) {
                    int t = info[i].getTrackType();
                    if (t != MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_AUDIO
                            && t != MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_TIMEDTEXT
                            && t != 4) {
                        continue;
                    }
                    if (s.length() > 0) {
                        s.append('\u0001');
                    }
                    s.append(t == MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_AUDIO ? "audio" : "sub").append('\u0002')
                        .append(i).append('\u0002').append("0").append('\u0002')
                        .append(clean(info[i].getLanguage())).append('\u0002').append("");
                }
            }
        } catch (Exception e) {
            android.util.Log.w("pastel", "tracks: " + e);
        }
        events.event("tracks\t" + s);
    }

    private void selectTrack(String kind, int id) {
        try {
            if (exo != null) {
                Object params = call("getTrackSelectionParameters");
                Object b = params.getClass().getMethod("buildUpon").invoke(params);
                Class<?> bc = Class.forName("androidx.media3.common.TrackSelectionParameters$Builder");
                int type = kind.equals("audio") ? 1 : 3;
                if (id < 0) {
                    bc.getMethod("setTrackTypeDisabled", int.class, boolean.class).invoke(b, type, true);
                } else {
                    Object tracks = call("getCurrentTracks");
                    List<?> groups = (List<?>) tracks.getClass().getMethod("getGroups").invoke(tracks);
                    Object grp = groups.get(id / 100);
                    Object tg = invoke(grp, "androidx.media3.common.Tracks$Group", "getMediaTrackGroup", new Class<?>[0]);
                    Class<?> tgc = Class.forName("androidx.media3.common.TrackGroup");
                    Class<?> oc = Class.forName("androidx.media3.common.TrackSelectionOverride");
                    Object ov = oc.getConstructor(tgc, int.class).newInstance(tg, id % 100);
                    bc.getMethod("setTrackTypeDisabled", int.class, boolean.class).invoke(b, type, false);
                    bc.getMethod("setOverrideForType", oc).invoke(b, ov);
                }
                Object np = bc.getMethod("build").invoke(b);
                exoClass.getMethod("setTrackSelectionParameters",
                    Class.forName("androidx.media3.common.TrackSelectionParameters")).invoke(exo, np);
            } else if (mp != null && mpPrepared) {
                if (id >= 0) {
                    mp.selectTrack(id);
                } else {
                    MediaPlayer.TrackInfo[] info = mp.getTrackInfo();
                    for (int i = 0; i < info.length; i++) {
                        if (info[i].getTrackType() == MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_TIMEDTEXT) {
                            try {
                                mp.deselectTrack(i);
                            } catch (RuntimeException e) {
                                // not selected
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            events.event("error\tthe track cannot be chosen: " + clean(e.toString()));
        }
        sendTracks();
    }
}
