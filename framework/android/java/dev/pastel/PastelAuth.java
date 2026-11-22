// "Is it you?": the fingerprint, the face or the phone's PIN (Pastel.Device's
// Authenticate). Android 9 and newer: BiometricPrompt; older: the lock screen's
// own check (PIN, pattern, password).
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;

import java.util.HashSet;
import java.util.concurrent.Executor;

final class PastelAuth {
    private PastelAuth() { }

    interface Answer {
        void answer(int code, boolean ok, String text);
    }

    // Android's numbers (inlined here: the classes are newer than the android.jar)
    private static final int ERROR_CANCELED = 5;
    private static final int ERROR_USER_CANCELED = 10;
    private static final int ERROR_NEGATIVE_BUTTON = 13;
    private static final int BIOMETRIC_WEAK = 0x00FF;
    private static final int DEVICE_CREDENTIAL = 0x8000;

    /** request codes of the lock screen's check (older Android) */
    static final HashSet<Integer> lockCodes = new HashSet<Integer>();

    /** "biometric", "credential" (only the PIN...), or "" (neither is set up) */
    static String available(Context c) {
        KeyguardManager km = (KeyguardManager) c.getSystemService(Context.KEYGUARD_SERVICE);
        boolean secure = km != null && (Build.VERSION.SDK_INT >= 23 ? km.isDeviceSecure() : km.isKeyguardSecure());
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                BiometricManager bm = c.getSystemService(BiometricManager.class);
                int r = Build.VERSION.SDK_INT >= 30 ? bm.canAuthenticate(BIOMETRIC_WEAK) : bm.canAuthenticate();
                if (r == 0) {
                    return "biometric";
                }
            } catch (Throwable e) {
                // below
            }
        } else if (Build.VERSION.SDK_INT >= 23) {
            try {
                android.hardware.fingerprint.FingerprintManager fm = (android.hardware.fingerprint.FingerprintManager)
                    c.getSystemService(Context.FINGERPRINT_SERVICE);
                if (fm != null && fm.isHardwareDetected() && fm.hasEnrolledFingerprints()) {
                    return "biometric";
                }
            } catch (Throwable e) {
                // no permission or no sensor
            }
        }
        return secure ? "credential" : "";
    }

    static void authenticate(final Activity a, final int code, final String title, final String subtitle,
            final boolean allowPin, final Answer answer) {
        a.runOnUiThread(new Runnable() {
            public void run() {
                if (Build.VERSION.SDK_INT >= 28) {
                    try {
                        prompt(a, code, title, subtitle, allowPin, answer);
                        return;
                    } catch (Throwable e) {
                        android.util.Log.w("pastel", "BiometricPrompt: " + e);
                    }
                }
                lockScreen(a, code, title, subtitle, answer);
            }
        });
    }

    private static void prompt(Activity a, final int code, String title, String subtitle, boolean allowPin,
            final Answer answer) {
        final Handler h = new Handler(Looper.getMainLooper());
        Executor main = new Executor() {
            public void execute(Runnable r) {
                h.post(r);
            }
        };
        BiometricPrompt.Builder b = new BiometricPrompt.Builder(a).setTitle(title);
        if (subtitle.length() > 0) {
            b.setSubtitle(subtitle);
        }
        if (allowPin && Build.VERSION.SDK_INT >= 30) {
            b.setAllowedAuthenticators(BIOMETRIC_WEAK | DEVICE_CREDENTIAL);
        } else if (allowPin && Build.VERSION.SDK_INT == 29) {
            b.setDeviceCredentialAllowed(true);
        } else {
            b.setNegativeButton(a.getString(android.R.string.cancel), main, new DialogInterface.OnClickListener() {
                public void onClick(DialogInterface d, int which) {
                    // the callback's error comes too (ERROR_NEGATIVE_BUTTON)
                }
            });
        }
        final boolean[] done = { false };
        b.build().authenticate(new CancellationSignal(), main, new BiometricPrompt.AuthenticationCallback() {
            @Override
            public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult r) {
                if (!done[0]) {
                    done[0] = true;
                    answer.answer(code, true, "");
                }
            }

            @Override
            public void onAuthenticationError(int err, CharSequence s) {
                if (done[0]) {
                    return;
                }
                done[0] = true;
                if (err == ERROR_USER_CANCELED || err == ERROR_NEGATIVE_BUTTON || err == ERROR_CANCELED) {
                    answer.answer(code, false, "canceled");
                } else {
                    answer.answer(code, false, s == null ? "error " + err : s.toString());
                }
            }
        });
    }

    /** older Android: the lock screen asks for the PIN, the pattern or the password */
    private static void lockScreen(Activity a, int code, String title, String subtitle, Answer answer) {
        KeyguardManager km = (KeyguardManager) a.getSystemService(Context.KEYGUARD_SERVICE);
        Intent i = km == null || Build.VERSION.SDK_INT < 21 ? null : km.createConfirmDeviceCredentialIntent(title, subtitle);
        if (i == null) {
            answer.answer(code, false, "the phone has no screen lock (PIN, pattern, fingerprint) set up");
            return;
        }
        lockCodes.add(code);
        a.startActivityForResult(i, code);
    }
}
