// Secrets kept encrypted (Pastel.SecureStore): a key of Android's Keystore,
// which never leaves the phone's secure hardware, encrypts each value
// (AES-GCM) into the app's own preferences. Android 5 and older: the app's
// private preferences only.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Base64;

import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class PastelSecure {
    private PastelSecure() { }

    private static final String ALIAS = "pastel_secure";

    private static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("pastel_secure", Context.MODE_PRIVATE);
    }

    private static SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(ALIAS)) {
            return ((KeyStore.SecretKeyEntry) ks.getEntry(ALIAS, null)).getSecretKey();
        }
        KeyGenerator g = KeyGenerator.getInstance("AES", "AndroidKeyStore");
        g.init(new android.security.keystore.KeyGenParameterSpec.Builder(ALIAS,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT | android.security.keystore.KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build());
        return g.generateKey();
    }

    /** "" or what went wrong */
    static String set(Context c, String name, String value) {
        try {
            String stored;
            if (Build.VERSION.SDK_INT >= 23) {
                Cipher ci = Cipher.getInstance("AES/GCM/NoPadding");
                ci.init(Cipher.ENCRYPT_MODE, key());
                byte[] iv = ci.getIV();
                byte[] enc = ci.doFinal(value.getBytes("UTF-8"));
                byte[] all = new byte[iv.length + enc.length];
                System.arraycopy(iv, 0, all, 0, iv.length);
                System.arraycopy(enc, 0, all, iv.length, enc.length);
                stored = "k1:" + Base64.encodeToString(all, Base64.NO_WRAP);
            } else {
                stored = "p0:" + Base64.encodeToString(value.getBytes("UTF-8"), Base64.NO_WRAP);
            }
            prefs(c).edit().putString(name, stored).apply();
            return "";
        } catch (Exception e) {
            return e.toString();
        }
    }

    /** the value; "\u0001" when there is none */
    static String get(Context c, String name) {
        String s = prefs(c).getString(name, null);
        if (s == null) {
            return "\u0001";
        }
        try {
            byte[] all = Base64.decode(s.substring(3), Base64.NO_WRAP);
            if (s.startsWith("p0:")) {
                return new String(all, "UTF-8");
            }
            Cipher ci = Cipher.getInstance("AES/GCM/NoPadding");
            ci.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, all, 0, 12));
            return new String(ci.doFinal(all, 12, all.length - 12), "UTF-8");
        } catch (Exception e) {
            // the key went (the phone's lock was reset): the value is lost
            return "\u0001";
        }
    }

    static void delete(Context c, String name) {
        prefs(c).edit().remove(name).apply();
    }
}
