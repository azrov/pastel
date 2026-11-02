// Pastel's activity on Android: Android's NativeActivity (the app itself is
// libmain.so, written in Pascal), and the letters the on-screen keyboard types.
//
// NativeActivity gives the native code key codes only: a Turkish "ş" or an
// "é" from the on-screen keyboard has no key code, so it is lost there. This
// class takes the typed text first and hands it to Pastel (nativeText); the
// other keys (Backspace, Enter, the arrows, Back) go on to the native code.
//
// Built into framework/android/classes.dex by tools/android-dex.sh; that file
// is put into every .apk by "pastel package apk".
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.NativeActivity;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;

public class PastelActivity extends NativeActivity {
    static {
        // the same library NativeActivity loads; loaded here so nativeText is found
        System.loadLibrary("main");
    }

    private static native void nativeText(String text);

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int action = event.getAction();
        // text typed at once (other alphabets, suggestions, emoji): no key code
        if (action == KeyEvent.ACTION_MULTIPLE && event.getKeyCode() == KeyEvent.KEYCODE_UNKNOWN) {
            String s = event.getCharacters();
            if (s != null && s.length() > 0) {
                nativeText(s);
                return true;
            }
        }
        // a key that types a letter in the keyboard's language
        if (action == KeyEvent.ACTION_DOWN && !event.isCtrlPressed() && !event.isAltPressed()) {
            int c = event.getUnicodeChar(event.getMetaState());
            if (c > 0 && (c & KeyCharacterMap.COMBINING_ACCENT) == 0 && !Character.isISOControl(c)) {
                nativeText(new String(Character.toChars(c)));
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
