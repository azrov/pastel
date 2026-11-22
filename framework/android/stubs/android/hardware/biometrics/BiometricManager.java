// Only to compile Pastel's Java against an older android.jar (Android 10 and newer have it).
package android.hardware.biometrics;

public class BiometricManager {
    public int canAuthenticate() { return 0; }
    public int canAuthenticate(int authenticators) { return 0; }
}
