// The phone's voice, ears and senses (Pastel.Sensors, Pastel.Speech, Pastel.Nfc):
// text to speech, the motion and other sensors, NFC tags. Readings are kept
// here and read by Pascal's timers; events go to a queue Pascal takes.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.speech.tts.TextToSpeech;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;

final class PastelSense {
    private PastelSense() { }

    private static final ArrayList<String> events = new ArrayList<String>();

    static synchronized void event(String s) {
        events.add(s);
        while (events.size() > 50) {
            events.remove(0);
        }
    }

    static synchronized String take() {
        if (events.isEmpty()) {
            return "";
        }
        StringBuilder b = new StringBuilder();
        for (String s : events) {
            b.append(s).append('\n');
        }
        events.clear();
        return b.toString();
    }

    // ---------- speech ----------

    private static TextToSpeech tts;
    private static boolean ttsReady;
    private static String pending, pendingLang;

    static void speak(final Activity a, final String text, final String lang) {
        a.runOnUiThread(new Runnable() {
            public void run() {
                if (tts == null) {
                    pending = text;
                    pendingLang = lang;
                    tts = new TextToSpeech(a.getApplicationContext(), new TextToSpeech.OnInitListener() {
                        public void onInit(int status) {
                            ttsReady = status == TextToSpeech.SUCCESS;
                            if (!ttsReady) {
                                event("speech-error\tthe phone has no voice for speaking");
                            } else if (pending != null) {
                                say(pending, pendingLang);
                                pending = null;
                            }
                        }
                    });
                } else if (ttsReady) {
                    say(text, lang);
                } else {
                    pending = text;
                    pendingLang = lang;
                }
            }
        });
    }

    @SuppressWarnings("deprecation")
    private static void say(String text, String lang) {
        if (lang != null && lang.length() > 0) {
            tts.setLanguage(android.os.Build.VERSION.SDK_INT >= 21 ? Locale.forLanguageTag(lang) : new Locale(lang));
        }
        tts.speak(text, TextToSpeech.QUEUE_ADD, null);
    }

    static void stopSpeaking() {
        if (tts != null) {
            tts.stop();
        }
    }

    static boolean speaking() {
        return tts != null && tts.isSpeaking();
    }

    // ---------- sensors ----------

    private static final HashMap<Integer, float[]> readings = new HashMap<Integer, float[]>();
    private static final HashMap<Integer, SensorEventListener> listeners = new HashMap<Integer, SensorEventListener>();

    /** Android's sensor type (1 accelerometer, 2 magnetic field, 4 gyroscope, 5 light, 8 proximity,
     *  19 step counter, 11 rotation vector...); false when the phone has none */
    static boolean startSensor(Context c, final int type) {
        SensorManager sm = (SensorManager) c.getSystemService(Context.SENSOR_SERVICE);
        if (sm == null) {
            return false;
        }
        Sensor s = sm.getDefaultSensor(type);
        if (s == null) {
            return false;
        }
        if (listeners.containsKey(type)) {
            return true;
        }
        SensorEventListener l = new SensorEventListener() {
            public void onSensorChanged(SensorEvent e) {
                synchronized (readings) {
                    readings.put(type, e.values.clone());
                }
            }

            public void onAccuracyChanged(Sensor s, int accuracy) {
            }
        };
        listeners.put(type, l);
        return sm.registerListener(l, s, SensorManager.SENSOR_DELAY_UI);
    }

    static void stopSensor(Context c, int type) {
        SensorManager sm = (SensorManager) c.getSystemService(Context.SENSOR_SERVICE);
        SensorEventListener l = listeners.remove(type);
        if (sm != null && l != null) {
            sm.unregisterListener(l);
        }
        synchronized (readings) {
            readings.remove(type);
        }
    }

    /** "x\ty\tz..." or "" before the first reading */
    static String read(int type) {
        float[] v;
        synchronized (readings) {
            v = readings.get(type);
        }
        if (v == null) {
            return "";
        }
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < v.length; i++) {
            if (i > 0) {
                b.append('\t');
            }
            b.append(v[i]);
        }
        return b.toString();
    }

    // ---------- NFC ----------

    static String startNfc(final Activity a) {
        final NfcAdapter nfc = NfcAdapter.getDefaultAdapter(a);
        if (nfc == null) {
            return "this device has no NFC";
        }
        if (!nfc.isEnabled()) {
            return "NFC is off (the phone's settings)";
        }
        a.runOnUiThread(new Runnable() {
            public void run() {
                nfc.enableReaderMode(a, new NfcAdapter.ReaderCallback() {
                    public void onTagDiscovered(Tag tag) {
                        StringBuilder id = new StringBuilder();
                        for (byte b : tag.getId()) {
                            id.append(String.format("%02X", b));
                        }
                        StringBuilder text = new StringBuilder();
                        try {
                            Ndef n = Ndef.get(tag);
                            if (n != null) {
                                n.connect();
                                NdefMessage m = n.getNdefMessage();
                                n.close();
                                if (m != null) {
                                    for (NdefRecord r : m.getRecords()) {
                                        if (text.length() > 0) {
                                            text.append('\u001f');
                                        }
                                        text.append(recordText(r));
                                    }
                                }
                            }
                        } catch (Exception e) {
                            // a tag without NDEF data: its id is enough
                        }
                        event("nfc\t" + id + "\t" + text.toString().replace('\t', ' ').replace('\n', ' '));
                    }
                }, NfcAdapter.FLAG_READER_NFC_A | NfcAdapter.FLAG_READER_NFC_B | NfcAdapter.FLAG_READER_NFC_F
                    | NfcAdapter.FLAG_READER_NFC_V, null);
            }
        });
        return "";
    }

    static void stopNfc(final Activity a) {
        final NfcAdapter nfc = NfcAdapter.getDefaultAdapter(a);
        if (nfc != null) {
            a.runOnUiThread(new Runnable() {
                public void run() {
                    nfc.disableReaderMode(a);
                }
            });
        }
    }

    /** a text record's text, an address record's address, else the payload as text */
    private static String recordText(NdefRecord r) {
        byte[] p = r.getPayload();
        try {
            if (r.getTnf() == NdefRecord.TNF_WELL_KNOWN && java.util.Arrays.equals(r.getType(), NdefRecord.RTD_TEXT)) {
                int langLen = p[0] & 0x3F;
                String enc = (p[0] & 0x80) == 0 ? "UTF-8" : "UTF-16";
                return new String(p, 1 + langLen, p.length - 1 - langLen, enc);
            }
            if (r.toUri() != null) {
                return r.toUri().toString();
            }
            return new String(p, "UTF-8");
        } catch (Exception e) {
            return "";
        }
    }
}
