// Pastel's files for other apps: a photo the camera app saves for Pastel, a
// file shared with another app. content://<app id>.files/<path> gives the
// file at <path> (only in the app's own folders), like AndroidX's
// FileProvider, without the support library.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

public class PastelFiles extends ContentProvider {
    public static Uri uriFor(android.content.Context c, File f) {
        return new Uri.Builder().scheme("content").authority(c.getPackageName() + ".files")
            .path(f.getAbsolutePath()).build();
    }

    private File fileOf(Uri uri) throws FileNotFoundException {
        File f = new File(uri.getPath());
        try {
            String path = f.getCanonicalPath();
            String data = getContext().getApplicationInfo().dataDir;
            File ext = getContext().getExternalFilesDir(null);
            if (path.startsWith(new File(data).getCanonicalPath() + "/")
                    || (ext != null && path.startsWith(ext.getCanonicalPath() + "/"))) {
                return f;
            }
        } catch (IOException e) {
            // not readable: refused below
        }
        throw new FileNotFoundException("not a file of this app: " + uri);
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        File f = fileOf(uri);
        int m = mode.contains("w") ? ParcelFileDescriptor.MODE_READ_WRITE | ParcelFileDescriptor.MODE_CREATE
            | ParcelFileDescriptor.MODE_TRUNCATE : ParcelFileDescriptor.MODE_READ_ONLY;
        return ParcelFileDescriptor.open(f, m);
    }

    @Override
    public String getType(Uri uri) {
        String ext = MimeTypeMap.getFileExtensionFromUrl(uri.toString());
        String t = ext == null ? null : MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.toLowerCase());
        return t != null ? t : "application/octet-stream";
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        File f;
        try {
            f = fileOf(uri);
        } catch (FileNotFoundException e) {
            return null;
        }
        MatrixCursor c = new MatrixCursor(new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE });
        c.addRow(new Object[] { f.getName(), f.length() });
        return c;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException();
    }

    @Override
    public int delete(Uri uri, String selection, String[] args) {
        throw new UnsupportedOperationException();
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] args) {
        throw new UnsupportedOperationException();
    }
}
