// Barcode and QR scanning with Google's code scanner (Pastel.Device's
// ScanBarcode): its own camera screen, no camera permission needed. Compiled
// into the app only when its libraries have
// com.google.android.gms:play-services-code-scanner.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;

import com.google.android.gms.tasks.OnCanceledListener;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning;

public final class PastelScanner {
    private PastelScanner() { }

    static String format(int f) {
        switch (f) {
            case 1: return "Code128";
            case 2: return "Code39";
            case 4: return "Code93";
            case 8: return "Codabar";
            case 16: return "DataMatrix";
            case 32: return "EAN13";
            case 64: return "EAN8";
            case 128: return "ITF";
            case 256: return "QR";
            case 512: return "UPCA";
            case 1024: return "UPCE";
            case 2048: return "PDF417";
            case 4096: return "Aztec";
            default: return "Unknown";
        }
    }

    public static void scan(Activity a, final int code) {
        GmsBarcodeScanning.getClient(a).startScan()
            .addOnSuccessListener(new OnSuccessListener<Barcode>() {
                public void onSuccess(Barcode b) {
                    String v = b.getRawValue() == null ? "" : b.getRawValue();
                    PastelActivity.result(code, 1, format(b.getFormat()) + "\t" + v);
                }
            })
            .addOnCanceledListener(new OnCanceledListener() {
                public void onCanceled() {
                    PastelActivity.result(code, 0, "canceled");
                }
            })
            .addOnFailureListener(new OnFailureListener() {
                public void onFailure(Exception e) {
                    PastelActivity.result(code, 0, e.toString());
                }
            });
    }
}
