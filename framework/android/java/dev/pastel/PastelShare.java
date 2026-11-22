// Pastel's app as a target of Android's share menu: the text, the subject and
// the files another app shares ([package.android] receive_shares in
// pastel.toml lists the kinds). The files are copied into the app's cache (in
// a thread of their own), then Pascal takes it all at once (takeShared).
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Parcelable;
import java.util.ArrayList;

final class PastelShare {
    /** subject \u0001 text \u0001 type \u0001 files (\u0002 between them); null when nothing waits */
    private static String pending = null;

    static synchronized String take() {
        String s = pending;
        pending = null;
        return s == null ? "" : s;
    }

    private static synchronized void put(String s) {
        pending = s;
    }

    static void note(final Context c, final Intent i) {
        if (i == null) {
            return;
        }
        final String action = i.getAction();
        if (!Intent.ACTION_SEND.equals(action) && !Intent.ACTION_SEND_MULTIPLE.equals(action)) {
            return;
        }
        CharSequence t = i.getCharSequenceExtra(Intent.EXTRA_TEXT);
        final String text = t == null ? "" : t.toString();
        final String subject = i.getStringExtra(Intent.EXTRA_SUBJECT) == null ? "" : i.getStringExtra(Intent.EXTRA_SUBJECT);
        final String type = i.getType() == null ? "" : i.getType();
        final ArrayList<Uri> uris = new ArrayList<Uri>();
        try {
            if (Intent.ACTION_SEND.equals(action)) {
                Parcelable p = i.getParcelableExtra(Intent.EXTRA_STREAM);
                if (p instanceof Uri) {
                    uris.add((Uri) p);
                }
            } else {
                ArrayList<Parcelable> list = i.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
                if (list != null) {
                    for (Parcelable p : list) {
                        if (p instanceof Uri) {
                            uris.add((Uri) p);
                        }
                    }
                }
            }
        } catch (Exception e) {
            android.util.Log.w("pastel", "shared files: " + e);
        }
        // taken once: the activity made again (a turned phone) does not share it again
        i.setAction(Intent.ACTION_MAIN);
        new Thread(new Runnable() {
            public void run() {
                StringBuilder files = new StringBuilder();
                for (Uri u : uris) {
                    try {
                        String path = PastelActivity.copyToCache(c, u, "shared").getAbsolutePath();
                        if (files.length() > 0) {
                            files.append('\u0002');
                        }
                        files.append(path);
                    } catch (Exception e) {
                        android.util.Log.w("pastel", "shared file " + u + ": " + e);
                    }
                }
                put(subject + '\u0001' + text + '\u0001' + type + '\u0001' + files);
            }
        }).start();
    }
}
