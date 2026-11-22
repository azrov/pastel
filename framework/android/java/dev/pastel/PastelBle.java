// Bluetooth Low Energy (Pastel.Bluetooth): scanning, connecting, reading,
// writing and notifications of characteristics. Events go into PastelSense's
// queue as "ble-..." lines; values are hex.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.util.HashMap;
import java.util.UUID;

final class PastelBle {
    private PastelBle() { }

    private static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final HashMap<String, BluetoothGatt> gatts = new HashMap<String, BluetoothGatt>();
    private static ScanCallback scanning;

    private static String hex(byte[] b) {
        if (b == null) {
            return "";
        }
        StringBuilder s = new StringBuilder();
        for (byte x : b) {
            s.append(String.format("%02X", x));
        }
        return s.toString();
    }

    private static byte[] bytes(String h) {
        byte[] b = new byte[h.length() / 2];
        for (int i = 0; i < b.length; i++) {
            b[i] = (byte) Integer.parseInt(h.substring(i * 2, i * 2 + 2), 16);
        }
        return b;
    }

    private static BluetoothAdapter adapter(Context c) {
        BluetoothManager m = (BluetoothManager) c.getSystemService(Context.BLUETOOTH_SERVICE);
        return m == null ? null : m.getAdapter();
    }

    /** "" or why not */
    static String scan(Context c, int seconds) {
        BluetoothAdapter a = adapter(c);
        if (a == null || a.getBluetoothLeScanner() == null) {
            return a == null ? "this device has no Bluetooth" : "Bluetooth is off";
        }
        stopScan(c);
        scanning = new ScanCallback() {
            @Override
            public void onScanResult(int type, ScanResult r) {
                BluetoothDevice d = r.getDevice();
                String name = d.getName() == null ? "" : d.getName().replace('\t', ' ');
                PastelSense.event("ble-found\t" + d.getAddress() + "\t" + name + "\t" + r.getRssi());
            }

            @Override
            public void onScanFailed(int code) {
                PastelSense.event("ble-error\t\tscanning failed (" + code + ")");
            }
        };
        try {
            a.getBluetoothLeScanner().startScan(scanning);
        } catch (SecurityException e) {
            scanning = null;
            return "no permission for Bluetooth: RequestPermissions([dpBluetooth])";
        }
        final Context ctx = c;
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            public void run() {
                stopScan(ctx);
                PastelSense.event("ble-scan-done");
            }
        }, Math.max(1, seconds) * 1000L);
        return "";
    }

    static void stopScan(Context c) {
        BluetoothAdapter a = adapter(c);
        if (scanning != null && a != null && a.getBluetoothLeScanner() != null) {
            try {
                a.getBluetoothLeScanner().stopScan(scanning);
            } catch (Exception e) {
                // off meanwhile
            }
        }
        scanning = null;
    }

    static String connect(Context c, final String address) {
        BluetoothAdapter a = adapter(c);
        if (a == null) {
            return "this device has no Bluetooth";
        }
        try {
            BluetoothDevice d = a.getRemoteDevice(address);
            BluetoothGatt g = d.connectGatt(c, false, new BluetoothGattCallback() {
                @Override
                public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
                    if (state == BluetoothProfile.STATE_CONNECTED) {
                        PastelSense.event("ble-connected\t" + address);
                        g.discoverServices();
                    } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
                        PastelSense.event("ble-disconnected\t" + address);
                        synchronized (gatts) {
                            gatts.remove(address);
                        }
                        g.close();
                    }
                }

                @Override
                public void onServicesDiscovered(BluetoothGatt g, int status) {
                    StringBuilder s = new StringBuilder();
                    for (BluetoothGattService sv : g.getServices()) {
                        for (BluetoothGattCharacteristic ch : sv.getCharacteristics()) {
                            if (s.length() > 0) {
                                s.append(',');
                            }
                            s.append(sv.getUuid()).append('/').append(ch.getUuid());
                        }
                    }
                    PastelSense.event("ble-services\t" + address + "\t" + s);
                }

                @Override
                public void onCharacteristicRead(BluetoothGatt g, BluetoothGattCharacteristic ch, int status) {
                    PastelSense.event("ble-read\t" + address + "\t" + ch.getUuid() + "\t" + hex(ch.getValue()) + "\t" + status);
                }

                @Override
                public void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic ch, int status) {
                    PastelSense.event("ble-written\t" + address + "\t" + ch.getUuid() + "\t\t" + status);
                }

                @Override
                public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic ch) {
                    PastelSense.event("ble-changed\t" + address + "\t" + ch.getUuid() + "\t" + hex(ch.getValue()));
                }
            });
            synchronized (gatts) {
                gatts.put(address, g);
            }
            return "";
        } catch (SecurityException e) {
            return "no permission for Bluetooth: RequestPermissions([dpBluetooth])";
        } catch (IllegalArgumentException e) {
            return "\"" + address + "\" is not a Bluetooth address";
        }
    }

    private static BluetoothGattCharacteristic find(BluetoothGatt g, String service, String ch) {
        BluetoothGattService s = g.getService(UUID.fromString(service));
        return s == null ? null : s.getCharacteristic(UUID.fromString(ch));
    }

    /** op: read, write, notify (value "1"/"0"); "" or why not */
    static String gatt(String address, String service, String ch, String op, String value) {
        BluetoothGatt g;
        synchronized (gatts) {
            g = gatts.get(address);
        }
        if (g == null) {
            return "not connected to " + address;
        }
        try {
            BluetoothGattCharacteristic c = find(g, service, ch);
            if (c == null) {
                return "the device has no characteristic " + ch;
            }
            if (op.equals("read")) {
                return g.readCharacteristic(c) ? "" : "it cannot be read now";
            }
            if (op.equals("write")) {
                c.setValue(bytes(value));
                return g.writeCharacteristic(c) ? "" : "it cannot be written now";
            }
            boolean on = value.equals("1");
            g.setCharacteristicNotification(c, on);
            BluetoothGattDescriptor d = c.getDescriptor(CCCD);
            if (d != null) {
                d.setValue(on ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    : BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE);
                g.writeDescriptor(d);
            }
            return "";
        } catch (SecurityException e) {
            return "no permission for Bluetooth";
        } catch (IllegalArgumentException e) {
            return "not a UUID: " + e.getMessage();
        }
    }

    static void disconnect(String address) {
        BluetoothGatt g;
        synchronized (gatts) {
            g = gatts.get(address);
        }
        if (g != null) {
            try {
                g.disconnect();
            } catch (SecurityException e) {
                // nothing to do
            }
        }
    }
}
