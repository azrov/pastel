// What opened the app besides its icon: a link ([package] links: shop://...,
// https://shop.example.com/app) or one of its shortcuts (a long press on the
// icon, Android 7.1 and newer); the shortcuts themselves; and video in a small
// window over other apps (picture-in-picture, Android 8 and newer).
//
// Shortcuts and picture-in-picture came after Android 6 (the platform Pastel's
// classes are built with): they are reached by reflection.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import java.lang.reflect.Method;
import java.util.ArrayList;

final class PastelLinks {
    static final String SHORTCUT = "dev.pastel.shortcut";

    private static String link = null;
    private static String shortcut = null;

    static synchronized String takeLink() {
        String s = link;
        link = null;
        return s == null ? "" : s;
    }

    static synchronized String takeShortcut() {
        String s = shortcut;
        shortcut = null;
        return s == null ? "" : s;
    }

    /** The intent that started (or came back to) the activity: a link, a shortcut. Taken once. */
    static synchronized void note(Intent i) {
        if (i == null) {
            return;
        }
        String id = i.getStringExtra(SHORTCUT);
        if (id != null) {
            shortcut = id;
            i.removeExtra(SHORTCUT);
            i.setAction(Intent.ACTION_MAIN);
            i.setData(null);
            return;
        }
        if (Intent.ACTION_VIEW.equals(i.getAction()) && i.getData() != null) {
            link = i.getData().toString();
            // the activity made again (a turned phone) does not get it again
            i.setAction(Intent.ACTION_MAIN);
            i.setData(null);
        }
    }

    // ---------- the icon's shortcuts ----------

    /** id \u0001 title \u0001 icon file (a PNG; "" none), \u0002 between them; "" removes them. "" or why not. */
    static String setShortcuts(Context c, String spec) {
        if (Build.VERSION.SDK_INT < 25) {
            return "the icon's shortcuts need Android 7.1 or newer";
        }
        try {
            Object manager = c.getSystemService(Class.forName("android.content.pm.ShortcutManager"));
            Class<?> infoClass = Class.forName("android.content.pm.ShortcutInfo");
            Class<?> builderClass = Class.forName("android.content.pm.ShortcutInfo$Builder");
            Class<?> iconClass = Class.forName("android.graphics.drawable.Icon");
            ArrayList<Object> list = new ArrayList<Object>();
            if (spec.length() > 0) {
                int rank = 0;
                for (String one : spec.split("\u0002")) {
                    String[] p = one.split("\u0001", -1);
                    if (p.length < 3) {
                        continue;
                    }
                    Intent open = new Intent(c, PastelActivity.class);
                    open.setAction(Intent.ACTION_MAIN);
                    open.putExtra(SHORTCUT, p[0]);
                    open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    Object b = builderClass.getConstructor(Context.class, String.class).newInstance(c, p[0]);
                    builderClass.getMethod("setShortLabel", CharSequence.class).invoke(b, p[1]);
                    builderClass.getMethod("setLongLabel", CharSequence.class).invoke(b, p[1]);
                    builderClass.getMethod("setIntent", Intent.class).invoke(b, open);
                    builderClass.getMethod("setRank", int.class).invoke(b, rank++);
                    if (p[2].length() > 0) {
                        Bitmap bmp = BitmapFactory.decodeFile(p[2]);
                        if (bmp != null) {
                            Object icon = iconClass.getMethod("createWithBitmap", Bitmap.class).invoke(null, bmp);
                            builderClass.getMethod("setIcon", iconClass).invoke(b, icon);
                        }
                    }
                    list.add(builderClass.getMethod("build").invoke(b));
                }
            }
            manager.getClass().getMethod("setDynamicShortcuts", java.util.List.class).invoke(manager, list);
            return "";
        } catch (java.lang.reflect.InvocationTargetException e) {
            return String.valueOf(e.getCause());
        } catch (Exception e) {
            return e.toString();
        }
    }

    // ---------- picture-in-picture ----------

    static boolean pipAllowed(Activity a) {
        if (Build.VERSION.SDK_INT < 26) {
            return false;
        }
        try {
            android.content.pm.ActivityInfo info = a.getPackageManager().getActivityInfo(a.getComponentName(), 0);
            // ActivityInfo.FLAG_SUPPORTS_PICTURE_IN_PICTURE (hidden): the manifest's supportsPictureInPicture
            return (info.flags & 0x400000) != 0;
        } catch (Exception e) {
            return true;      // asked anyway: Android says no if it is not allowed
        }
    }

    /** PictureInPictureParams with the aspect (Android 8) and auto-enter (Android 12). */
    static Object pipParams(int w, int h, boolean auto) throws Exception {
        Class<?> builderClass = Class.forName("android.app.PictureInPictureParams$Builder");
        Object b = builderClass.getConstructor().newInstance();
        if (w > 0 && h > 0) {
            // Android takes 1:2.39 to 2.39:1
            double r = (double) w / h;
            if (r > 2.39) { w = 239; h = 100; }
            if (r < 1 / 2.39) { w = 100; h = 239; }
            builderClass.getMethod("setAspectRatio", android.util.Rational.class)
                .invoke(b, new android.util.Rational(w, h));
        }
        if (Build.VERSION.SDK_INT >= 31) {
            builderClass.getMethod("setAutoEnterEnabled", boolean.class).invoke(b, auto);
        }
        return builderClass.getMethod("build").invoke(b);
    }

    /** "" or why not */
    static String enterPip(Activity a, int w, int h) {
        if (!pipAllowed(a)) {
            return Build.VERSION.SDK_INT < 26 ? "picture-in-picture needs Android 8 or newer"
                : "the app does not have [package.android] picture_in_picture = true";
        }
        try {
            Class<?> paramsClass = Class.forName("android.app.PictureInPictureParams");
            Method m = Activity.class.getMethod("enterPictureInPictureMode", paramsClass);
            Object ok = m.invoke(a, pipParams(w, h, false));
            return Boolean.TRUE.equals(ok) ? "" : "Android did not let it (picture-in-picture is off for this app)";
        } catch (java.lang.reflect.InvocationTargetException e) {
            return String.valueOf(e.getCause());
        } catch (Exception e) {
            return e.toString();
        }
    }

    /** Android 12 and newer: into picture-in-picture by itself when the user leaves the app. */
    static void setPipAuto(Activity a, int w, int h, boolean auto) {
        if (Build.VERSION.SDK_INT < 26 || !pipAllowed(a)) {
            return;
        }
        try {
            Class<?> paramsClass = Class.forName("android.app.PictureInPictureParams");
            Activity.class.getMethod("setPictureInPictureParams", paramsClass).invoke(a, pipParams(w, h, auto));
        } catch (Exception e) {
            android.util.Log.w("pastel", "picture-in-picture: " + e);
        }
    }

    static boolean inPip(Activity a) {
        if (Build.VERSION.SDK_INT < 24) {
            return false;
        }
        try {
            return Boolean.TRUE.equals(Activity.class.getMethod("isInPictureInPictureMode").invoke(a));
        } catch (Exception e) {
            return false;
        }
    }
}
