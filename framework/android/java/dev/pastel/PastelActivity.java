// Pastel's activity on Android: Android's NativeActivity (the app itself is
// libmain.so, written in Pascal), and the on-screen keyboard.
//
// NativeActivity's own view is not a text editor, so on many phones the
// on-screen keyboard does not come up for it, and it cannot say which keyboard
// an edit needs. This class adds a small, invisible editor view: when an edit
// gets the focus, Pastel calls showKeyboard with the kind of keyboard (text,
// number, phone, e-mail...) and what Enter does (Done, Next, Search...); the
// keyboard types into that view, and the view hands the text on to Pastel
// (nativeText) and the keys that edit it (nativeKey: Backspace, Enter, Tab).
// Words the keyboard is still composing (with suggestions) are typed and
// replaced as they change.
//
// Built into framework/android/classes.dex by tools/android-dex.sh; that file
// is put into every .apk by "pastel package apk".
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.NativeActivity;
import android.content.Context;
import android.os.Bundle;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

public class PastelActivity extends NativeActivity {
    static {
        // the same library NativeActivity loads; loaded here so nativeText is found
        System.loadLibrary("main");
    }

    private static native void nativeText(String text);
    private static native void nativeKey(int keyCode);

    private KeyboardView keyboardView;
    private int inputType = EditorInfo.TYPE_CLASS_TEXT;
    private int imeOptions = EditorInfo.IME_ACTION_DONE;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        keyboardView = new KeyboardView(this);
        addContentView(keyboardView, new ViewGroup.LayoutParams(1, 1));
    }

    /** Called by Pastel (on its own thread) when an edit gets the focus. */
    public void showKeyboard(final int type, final int options) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                inputType = type;
                imeOptions = options;
                keyboardView.composing = 0;
                keyboardView.setFocusable(true);
                keyboardView.setFocusableInTouchMode(true);
                keyboardView.requestFocus();
                InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm != null) {
                    imm.restartInput(keyboardView);
                    imm.showSoftInput(keyboardView, InputMethodManager.SHOW_IMPLICIT);
                }
            }
        });
    }

    /** The size of text chosen in the phone's settings (1 is normal). */
    public float fontScale() {
        return getResources().getConfiguration().fontScale;
    }

    /** Called by Pastel when no edit has the focus any more. */
    public void hideKeyboard() {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm != null) {
                    imm.hideSoftInputFromWindow(keyboardView.getWindowToken(), 0);
                }
                keyboardView.composing = 0;
                keyboardView.clearFocus();
            }
        });
    }

    /** The invisible view the on-screen keyboard types into. */
    private class KeyboardView extends View {
        /** Letters of the word being composed, already handed to Pastel. */
        int composing;

        KeyboardView(Context context) {
            super(context);
        }

        @Override
        public boolean onCheckIsTextEditor() {
            return true;
        }

        @Override
        public InputConnection onCreateInputConnection(EditorInfo out) {
            out.inputType = inputType;
            out.imeOptions = imeOptions | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
            out.initialSelStart = 0;
            out.initialSelEnd = 0;
            return new Connection(this);
        }

        private void deleteComposing() {
            for (int i = 0; i < composing; i++) {
                nativeKey(KeyEvent.KEYCODE_DEL);
            }
            composing = 0;
        }

        private class Connection extends BaseInputConnection {
            Connection(View view) {
                super(view, false);
            }

            @Override
            public boolean commitText(CharSequence text, int newCursorPosition) {
                deleteComposing();
                if (text != null && text.length() > 0) {
                    nativeText(text.toString());
                }
                return true;
            }

            @Override
            public boolean setComposingText(CharSequence text, int newCursorPosition) {
                deleteComposing();
                if (text != null && text.length() > 0) {
                    String s = text.toString();
                    nativeText(s);
                    composing = s.codePointCount(0, s.length());
                }
                return true;
            }

            @Override
            public boolean finishComposingText() {
                composing = 0;
                return true;
            }

            @Override
            public boolean deleteSurroundingText(int before, int after) {
                deleteComposing();
                for (int i = 0; i < before; i++) {
                    nativeKey(KeyEvent.KEYCODE_DEL);
                }
                for (int i = 0; i < after; i++) {
                    nativeKey(KeyEvent.KEYCODE_FORWARD_DEL);
                }
                return true;
            }

            @Override
            public boolean sendKeyEvent(KeyEvent event) {
                if (event.getAction() != KeyEvent.ACTION_DOWN) {
                    return true;
                }
                int code = event.getKeyCode();
                int c = event.getUnicodeChar(event.getMetaState());
                if (code == KeyEvent.KEYCODE_DEL || code == KeyEvent.KEYCODE_FORWARD_DEL
                        || code == KeyEvent.KEYCODE_ENTER || code == KeyEvent.KEYCODE_TAB) {
                    deleteComposing();
                    nativeKey(code);
                } else if (c > 0 && !Character.isISOControl(c)) {
                    nativeText(new String(Character.toChars(c)));
                } else {
                    nativeKey(code);
                }
                return true;
            }

            @Override
            public boolean performEditorAction(int action) {
                composing = 0;
                if (action == EditorInfo.IME_ACTION_NEXT) {
                    nativeKey(KeyEvent.KEYCODE_TAB);
                } else {
                    nativeKey(KeyEvent.KEYCODE_ENTER);
                }
                return true;
            }
        }
    }

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
        // a key of a hardware keyboard that types a letter in the keyboard's language
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
