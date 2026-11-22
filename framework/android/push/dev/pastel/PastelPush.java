// Push messages through Firebase Cloud Messaging (Pastel.Push). Compiled into the
// app only when its libraries have Firebase's messaging (pastel package puts it in).
//
// Pascal takes what came with take(): lines "token\t<token>", "message\t<title>\t<body>\t<data as JSON>\t<opened 0/1>",
// "error\t<text>".
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.content.Intent;
import android.os.Bundle;

import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.messaging.FirebaseMessaging;

import java.util.ArrayList;
import java.util.Map;

import org.json.JSONObject;

public final class PastelPush {
    private PastelPush() { }

    private static final ArrayList<String> queue = new ArrayList<String>();

    static String clean(String s) {
        return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ');
    }

    static synchronized void add(String line) {
        queue.add(line);
        while (queue.size() > 100) {
            queue.remove(0);
        }
    }

    static void message(String title, String body, Map<String, String> data, boolean opened) {
        JSONObject j = new JSONObject();
        try {
            for (Map.Entry<String, String> e : data.entrySet()) {
                j.put(e.getKey(), e.getValue());
            }
        } catch (Exception e) {
            // a key Java's JSON refuses
        }
        add("message\t" + clean(title) + "\t" + clean(body) + "\t" + j.toString().replace('\n', ' ') + "\t" + (opened ? "1" : "0"));
    }

    /** What came since the last call, a line each; "" when nothing. */
    public static synchronized String take(String unused) {
        if (queue.isEmpty()) {
            return "";
        }
        StringBuilder b = new StringBuilder();
        for (String s : queue) {
            b.append(s).append('\n');
        }
        queue.clear();
        return b.toString();
    }

    /** The device's token (it comes as a "token" line). */
    public static String requestToken(String unused) {
        FirebaseMessaging.getInstance().getToken().addOnCompleteListener(new OnCompleteListener<String>() {
            public void onComplete(Task<String> t) {
                if (t.isSuccessful() && t.getResult() != null) {
                    add("token\t" + t.getResult());
                } else {
                    add("error\tno push token: " + clean(t.getException() == null ? "" : t.getException().toString()));
                }
            }
        });
        return "";
    }

    public static String subscribe(String topic) {
        FirebaseMessaging.getInstance().subscribeToTopic(topic);
        return "";
    }

    public static String unsubscribe(String topic) {
        FirebaseMessaging.getInstance().unsubscribeFromTopic(topic);
        return "";
    }

    /** the app was opened by a tap on a push message's notification: its data is in the intent */
    public static void opened(Intent i) {
        Bundle b = i.getExtras();
        java.util.HashMap<String, String> data = new java.util.HashMap<String, String>();
        for (String k : b.keySet()) {
            if (k.startsWith("google.") || k.startsWith("gcm.") || k.equals("from") || k.equals("collapse_key")) {
                continue;
            }
            Object v = b.get(k);
            if (v != null) {
                data.put(k, v.toString());
            }
        }
        message("", "", data, true);
        i.removeExtra("google.message_id");
    }
}
