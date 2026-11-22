// The camera's picture in a form (Pastel.Camera's TCameraView): Camera2 into a
// TextureView, photos (JPEG) into a file, the torch. A view of PastelViews.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.content.Context;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Size;
import android.view.Surface;
import android.view.TextureView;

import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.util.Arrays;

final class PastelCamera implements TextureView.SurfaceTextureListener {
    interface Events {
        void event(String text);
    }

    final TextureView view;
    private final Activity activity;
    private final Events events;
    private HandlerThread thread;
    private Handler handler;
    private CameraDevice device;
    private CameraCaptureSession session;
    private CaptureRequest.Builder preview;
    private ImageReader reader;
    private Size previewSize;
    private int sensor;
    private boolean wanted, front, torch, hasFlash;
    private String photoPath;

    PastelCamera(Activity a, Events ev) {
        activity = a;
        events = ev;
        view = new TextureView(a);
        view.setSurfaceTextureListener(this);
    }

    // ---------- what Pascal asks (on the UI thread) ----------

    void start(boolean useFront) {
        front = useFront;
        wanted = true;
        if (view.isAvailable()) {
            open();
        }
    }

    void stop() {
        wanted = false;
        close();
    }

    void setTorch(boolean on) {
        torch = on;
        if (preview != null && session != null && hasFlash) {
            preview.set(CaptureRequest.FLASH_MODE, on ? CaptureRequest.FLASH_MODE_TORCH : CaptureRequest.FLASH_MODE_OFF);
            try {
                session.setRepeatingRequest(preview.build(), null, handler);
            } catch (Exception ex) {
                events.event("error\t" + ex.getMessage());
            }
        }
    }

    void photo(String path) {
        if (device == null || session == null || reader == null) {
            events.event("error\tthe camera is not on (Start)");
            return;
        }
        photoPath = path;
        try {
            CaptureRequest.Builder b = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
            b.addTarget(reader.getSurface());
            b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            b.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation());
            if (torch && hasFlash) {
                b.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH);
            }
            session.capture(b.build(), null, handler);
        } catch (Exception ex) {
            events.event("error\t" + ex.getMessage());
        }
    }

    // ---------- the camera ----------

    private int jpegOrientation() {
        int rotation = activity.getWindowManager().getDefaultDisplay().getRotation() * 90;
        if (front) {
            return (sensor + rotation) % 360;
        }
        return (sensor - rotation + 360) % 360;
    }

    private void open() {
        close();
        CameraManager cm = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);
        try {
            String id = null;
            for (String c : cm.getCameraIdList()) {
                Integer facing = cm.getCameraCharacteristics(c).get(CameraCharacteristics.LENS_FACING);
                boolean isFront = facing != null && facing == CameraCharacteristics.LENS_FACING_FRONT;
                if (isFront == front) {
                    id = c;
                    break;
                }
            }
            if (id == null && cm.getCameraIdList().length > 0) {
                id = cm.getCameraIdList()[0];
            }
            if (id == null) {
                events.event("error\tthis device has no camera");
                return;
            }
            CameraCharacteristics ch = cm.getCameraCharacteristics(id);
            Integer so = ch.get(CameraCharacteristics.SENSOR_ORIENTATION);
            sensor = so == null ? 90 : so;
            Boolean flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
            hasFlash = flash != null && flash;
            StreamConfigurationMap map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            previewSize = choose(map.getOutputSizes(SurfaceTexture.class), 1920, 1080);
            Size jpeg = choose(map.getOutputSizes(ImageFormat.JPEG), 4000, 3000);
            thread = new HandlerThread("pastel-camera");
            thread.start();
            handler = new Handler(thread.getLooper());
            reader = ImageReader.newInstance(jpeg.getWidth(), jpeg.getHeight(), ImageFormat.JPEG, 2);
            reader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                public void onImageAvailable(ImageReader r) {
                    save(r);
                }
            }, handler);
            cm.openCamera(id, new CameraDevice.StateCallback() {
                public void onOpened(CameraDevice d) {
                    device = d;
                    startPreview();
                }

                public void onDisconnected(CameraDevice d) {
                    d.close();
                    device = null;
                }

                public void onError(CameraDevice d, int error) {
                    d.close();
                    device = null;
                    events.event("error\tthe camera cannot be opened (" + error + ")");
                }
            }, handler);
        } catch (SecurityException ex) {
            events.event("error\tno permission for the camera");
        } catch (Exception ex) {
            events.event("error\t" + ex.getMessage());
        }
    }

    /** the largest size not over the limit, of the screen's shape if possible */
    private static Size choose(Size[] sizes, int maxW, int maxH) {
        Size best = sizes[0];
        long bestArea = 0;
        for (Size s : sizes) {
            long area = (long) s.getWidth() * s.getHeight();
            if (s.getWidth() <= maxW && s.getHeight() <= maxH && area > bestArea) {
                best = s;
                bestArea = area;
            }
        }
        return best;
    }

    private void startPreview() {
        try {
            SurfaceTexture t = view.getSurfaceTexture();
            t.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
            final Surface surface = new Surface(t);
            preview = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            preview.addTarget(surface);
            preview.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            device.createCaptureSession(Arrays.asList(surface, reader.getSurface()),
                new CameraCaptureSession.StateCallback() {
                    public void onConfigured(CameraCaptureSession s) {
                        if (device == null) {
                            return;
                        }
                        session = s;
                        if (torch && hasFlash) {
                            preview.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH);
                        }
                        try {
                            s.setRepeatingRequest(preview.build(), null, handler);
                            events.event("started\t" + previewSize.getWidth() + "\t" + previewSize.getHeight());
                        } catch (CameraAccessException ex) {
                            events.event("error\t" + ex.getMessage());
                        }
                        activity.runOnUiThread(new Runnable() {
                            public void run() {
                                fit();
                            }
                        });
                    }

                    public void onConfigureFailed(CameraCaptureSession s) {
                        events.event("error\tthe camera's picture cannot be shown");
                    }
                }, handler);
        } catch (Exception ex) {
            events.event("error\t" + ex.getMessage());
        }
    }

    private void save(ImageReader r) {
        Image img = r.acquireLatestImage();
        if (img == null) {
            return;
        }
        String path = photoPath;
        try {
            ByteBuffer buf = img.getPlanes()[0].getBuffer();
            byte[] bytes = new byte[buf.remaining()];
            buf.get(bytes);
            FileOutputStream out = new FileOutputStream(path);
            try {
                out.write(bytes);
            } finally {
                out.close();
            }
            events.event("photo\t" + path);
        } catch (Exception ex) {
            events.event("error\tthe photo cannot be saved: " + ex.getMessage());
        } finally {
            img.close();
        }
    }

    /** the picture fills the view without being stretched (cut at the sides) */
    void fit() {
        if (previewSize == null || view.getWidth() == 0) {
            return;
        }
        int rotation = activity.getWindowManager().getDefaultDisplay().getRotation();
        float vw = view.getWidth();
        float vh = view.getHeight();
        Matrix m = new Matrix();
        RectF viewRect = new RectF(0, 0, vw, vh);
        // the camera's picture lies on its side for a phone held upright
        boolean sideways = rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_180;
        float pw = sideways ? previewSize.getHeight() : previewSize.getWidth();
        float ph = sideways ? previewSize.getWidth() : previewSize.getHeight();
        if (rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270) {
            RectF buffer = new RectF(0, 0, previewSize.getHeight(), previewSize.getWidth());
            buffer.offset(viewRect.centerX() - buffer.centerX(), viewRect.centerY() - buffer.centerY());
            m.setRectToRect(viewRect, buffer, Matrix.ScaleToFit.FILL);
            float scale = Math.max(vh / previewSize.getHeight(), vw / previewSize.getWidth());
            m.postScale(scale, scale, viewRect.centerX(), viewRect.centerY());
            m.postRotate(90 * (rotation - 2), viewRect.centerX(), viewRect.centerY());
        } else {
            float scale = Math.max(vw / pw, vh / ph);
            m.setScale(pw * scale / vw, ph * scale / vh, viewRect.centerX(), viewRect.centerY());
            if (rotation == Surface.ROTATION_180) {
                m.postRotate(180, viewRect.centerX(), viewRect.centerY());
            }
        }
        view.setTransform(m);
    }

    void close() {
        if (session != null) {
            try {
                session.close();
            } catch (RuntimeException ex) {
                // closed
            }
            session = null;
        }
        if (device != null) {
            device.close();
            device = null;
        }
        if (reader != null) {
            reader.close();
            reader = null;
        }
        if (thread != null) {
            thread.quitSafely();
            thread = null;
            handler = null;
        }
        preview = null;
    }

    // ---------- the view's surface ----------

    public void onSurfaceTextureAvailable(SurfaceTexture s, int w, int h) {
        if (wanted) {
            open();
        }
    }

    public void onSurfaceTextureSizeChanged(SurfaceTexture s, int w, int h) {
        fit();
    }

    public boolean onSurfaceTextureDestroyed(SurfaceTexture s) {
        close();
        return true;
    }

    public void onSurfaceTextureUpdated(SurfaceTexture s) {
    }
}
