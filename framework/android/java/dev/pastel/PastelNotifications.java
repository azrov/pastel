// Pastel's notifications on Android: shown now, or at a time (also when the
// app is not running, and after the phone restarted), once or again and again.
//
// A scheduled notification is kept in the app's preferences (its name, title,
// text, time and how often it comes again) and given to AlarmManager; when the
// alarm goes off, this receiver shows it (and asks for the next time). After a
// restart of the phone (or an update of the app) Android forgets the alarms:
// this receiver is told and gives them again. A tap on a notification opens
// the app; Pastel learns which one was tapped (takeClicked).
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import java.util.Map;
import org.json.JSONObject;

public class PastelNotifications extends BroadcastReceiver {
    static final String PREFS = "pastel.notifications";
    static final String ACTION = "dev.pastel.NOTIFY";
    /** The extra of the activity's intent: the name of the notification tapped. */
    static final String EXTRA = "pastel.notification";
    private static final int FLAG_IMMUTABLE = 0x04000000;

    /** The name of the notification the user tapped last ('' when none since asked). */
    static String clicked = "";

    static int idOf(String name) {
        return name.hashCode();
    }

    /** Shows a notification now; the same name replaces the one before. */
    public static void post(Context c, String name, String title, String text) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }
        Notification.Builder b = null;
        if (Build.VERSION.SDK_INT >= 26) {
            // Android 8 and newer need a channel (built against Android 6: through reflection)
            try {
                Class<?> ch = Class.forName("android.app.NotificationChannel");
                Object channel = ch.getConstructor(String.class, CharSequence.class, int.class)
                    .newInstance("pastel", "Notifications", 3 /* IMPORTANCE_DEFAULT */);
                NotificationManager.class.getMethod("createNotificationChannel", ch).invoke(nm, channel);
                b = Notification.Builder.class.getConstructor(Context.class, String.class).newInstance(c, "pastel");
            } catch (Exception e) {
                android.util.Log.w("pastel", "notification channel: " + e);
            }
        }
        if (b == null) {
            b = new Notification.Builder(c);
        }
        // a tap opens the app and tells it which notification it was
        Intent open = new Intent(c, PastelActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        open.putExtra(EXTRA, name);
        int small = icon(c);
        b.setSmallIcon(small).setContentTitle(title).setContentText(text).setAutoCancel(true)
            .setContentIntent(PendingIntent.getActivity(c, idOf(name), open,
                PendingIntent.FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE));
        if (Build.VERSION.SDK_INT >= 16) {
            b.setStyle(new Notification.BigTextStyle().bigText(text));
        }
        nm.notify(idOf(name), b.build());
    }

    /** Shows it at the time given (milliseconds since 1970, UTC), then every repeatMs (0: once). */
    public static void schedule(Context c, String name, String title, String text, long at, long repeatMs) {
        try {
            JSONObject o = new JSONObject();
            o.put("title", title);
            o.put("text", text);
            o.put("at", at);
            o.put("repeat", repeatMs);
            prefs(c).edit().putString(name, o.toString()).apply();
        } catch (Exception e) {
            android.util.Log.w("pastel", "schedule " + name + ": " + e);
            return;
        }
        setAlarm(c, name, at);
    }

    /** Takes back a scheduled notification and the one shown. */
    public static void cancel(Context c, String name) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am != null) {
            am.cancel(alarmIntent(c, name));
        }
        prefs(c).edit().remove(name).apply();
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancel(idOf(name));
        }
    }

    public static void cancelAll(Context c) {
        for (String name : prefs(c).getAll().keySet()) {
            cancel(c, name);
        }
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancelAll();
        }
    }

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static PendingIntent alarmIntent(Context c, String name) {
        Intent i = new Intent(c, PastelNotifications.class);
        i.setAction(ACTION);
        i.putExtra("name", name);
        return PendingIntent.getBroadcast(c, idOf(name), i, PendingIntent.FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE);
    }

    // Android lets an alarm go off a little later while the phone sleeps (some
    // minutes at most): exact alarms need a permission the user must give.
    static void setAlarm(Context c, String name, long at) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) {
            return;
        }
        PendingIntent pi = alarmIntent(c, name);
        if (Build.VERSION.SDK_INT >= 23) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
        } else {
            am.set(AlarmManager.RTC_WAKEUP, at, pi);
        }
    }

    @Override
    public void onReceive(Context c, Intent intent) {
        String action = intent.getAction();
        if (ACTION.equals(action)) {
            String name = intent.getStringExtra("name");
            if (name != null) {
                fire(c, name);
            }
            return;
        }
        // the phone restarted or the app was updated: the alarms are given again
        long now = System.currentTimeMillis();
        for (Map.Entry<String, ?> e : prefs(c).getAll().entrySet()) {
            try {
                JSONObject o = new JSONObject(String.valueOf(e.getValue()));
                long at = o.getLong("at");
                if (at <= now && o.getLong("repeat") <= 0) {
                    fire(c, e.getKey());          // missed while the phone was off: shown now
                } else {
                    setAlarm(c, e.getKey(), next(at, o.getLong("repeat"), now));
                }
            } catch (Exception ex) {
                android.util.Log.w("pastel", "notification " + e.getKey() + ": " + ex);
            }
        }
    }

    static long next(long at, long repeat, long now) {
        if (repeat <= 0 || at > now) {
            return at;
        }
        return at + ((now - at) / repeat + 1) * repeat;
    }

    static void fire(Context c, String name) {
        String s = prefs(c).getString(name, null);
        if (s == null) {
            return;
        }
        try {
            JSONObject o = new JSONObject(s);
            post(c, name, o.getString("title"), o.getString("text"));
            long repeat = o.getLong("repeat");
            if (repeat > 0) {
                long at = next(o.getLong("at"), repeat, System.currentTimeMillis());
                o.put("at", at);
                prefs(c).edit().putString(name, o.toString()).apply();
                setAlarm(c, name, at);
            } else {
                prefs(c).edit().remove(name).apply();
            }
        } catch (Exception e) {
            android.util.Log.w("pastel", "notification " + name + ": " + e);
        }
    }

    /** The status bar icon (white, made from the app's icon), else the app's icon. */
    static int icon(Context c) {
        int small = c.getResources().getIdentifier("ic_stat_pastel", "drawable", c.getPackageName());
        return small != 0 ? small : c.getApplicationInfo().icon;
    }
}
