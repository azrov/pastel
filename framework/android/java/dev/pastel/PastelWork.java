// Work that goes on when the app is not on the screen:
//  - PastelWork (a foreground service): the app keeps running with a
//    notification while it plays music, tracks the place, uploads... ; its
//    Pascal code goes on as before (Pastel.Background's StartBackgroundWork).
//  - PastelJob (a JobService): Pascal code run by Android from time to time,
//    also when the app is closed (Pastel.Background's RegisterBackgroundJob
//    and ScheduleBackgroundJob): the app's library is loaded without a window
//    and the job's Pascal function is called on a thread of its own.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

public class PastelWork extends Service {
    static final int ID = 0x7a57;
    static final String CHANNEL = "pastel_work";
    static volatile boolean running;

    /** Kind: 1 data sync, 2 media playback, 8 location, 16 connected device (Android's ServiceInfo types). */
    static void start(Context c, String title, String text, int kind) {
        Intent i = new Intent(c, PastelWork.class);
        i.putExtra("title", title);
        i.putExtra("text", text);
        i.putExtra("kind", kind);
        if (Build.VERSION.SDK_INT >= 26) {
            try {
                // Android 8's startForegroundService: newer than the android.jar Pastel is built with
                Context.class.getMethod("startForegroundService", Intent.class).invoke(c, i);
                return;
            } catch (Exception e) {
                android.util.Log.w("pastel", "startForegroundService: " + e);
            }
        }
        c.startService(i);
    }

    static void stop(Context c) {
        c.stopService(new Intent(c, PastelWork.class));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String title = intent == null ? "" : intent.getStringExtra("title");
        String text = intent == null ? "" : intent.getStringExtra("text");
        int kind = intent == null ? 1 : intent.getIntExtra("kind", 1);
        Notification n = notification(this, title, text);
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                // startForeground(int, Notification, int type): Android 10's; reflection for the android.jar Pastel is built with
                Service.class.getMethod("startForeground", int.class, Notification.class, int.class)
                    .invoke(this, ID, n, kind);
            } else {
                startForeground(ID, n);
            }
            running = true;
        } catch (Throwable e) {
            android.util.Log.w("pastel", "the background work could not start: " + e);
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    static Notification notification(Context c, String title, String text) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            try {
                Class<?> ch = Class.forName("android.app.NotificationChannel");
                Object channel = ch.getConstructor(String.class, CharSequence.class, int.class)
                    .newInstance(CHANNEL, "Background work", 2);      // IMPORTANCE_LOW: no sound
                NotificationManager.class.getMethod("createNotificationChannel", ch).invoke(nm, channel);
                b = Notification.Builder.class.getConstructor(Context.class, String.class).newInstance(c, CHANNEL);
            } catch (Exception e) {
                b = new Notification.Builder(c);
            }
        } else {
            b = new Notification.Builder(c);
        }
        Intent open = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        b.setContentTitle(title == null ? "" : title)
            .setContentText(text == null ? "" : text)
            .setSmallIcon(PastelNotifications.icon(c))
            .setOngoing(true);
        if (open != null) {
            b.setContentIntent(PendingIntent.getActivity(c, ID, open, PendingIntent.FLAG_UPDATE_CURRENT | 0x04000000));
        }
        return b.build();
    }

    static void update(Context c, String title, String text) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.notify(ID, notification(c, title, text));
    }

    @Override
    public void onDestroy() {
        running = false;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
