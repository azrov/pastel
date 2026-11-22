// Only to compile Pastel's Java against an older android.jar: the phone has the
// real class (Android 9 and newer). Not in the app.
package android.hardware.biometrics;

public class BiometricPrompt {
    public static class Builder {
        public Builder(android.content.Context c) { }
        public Builder setTitle(CharSequence t) { return this; }
        public Builder setSubtitle(CharSequence t) { return this; }
        public Builder setNegativeButton(CharSequence t, java.util.concurrent.Executor e,
            android.content.DialogInterface.OnClickListener l) { return this; }
        public Builder setDeviceCredentialAllowed(boolean b) { return this; }
        public Builder setAllowedAuthenticators(int a) { return this; }
        public BiometricPrompt build() { return null; }
    }

    public abstract static class AuthenticationCallback {
        public void onAuthenticationError(int code, CharSequence s) { }
        public void onAuthenticationHelp(int code, CharSequence s) { }
        public void onAuthenticationSucceeded(AuthenticationResult r) { }
        public void onAuthenticationFailed() { }
    }

    public static class AuthenticationResult { }

    public void authenticate(android.os.CancellationSignal c, java.util.concurrent.Executor e, AuthenticationCallback cb) { }
}
