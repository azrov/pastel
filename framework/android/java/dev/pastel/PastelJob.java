// Pascal code that Android runs from time to time, also when the app is
// closed: see PastelWork.java and Pastel.Background.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.os.PersistableBundle;

public class PastelJob extends JobService {
    static {
        // the app's library (Pascal), also when no activity loaded it
        System.loadLibrary("main");
    }

    /** Runs the job's Pascal function; true when it was done, false: Android tries again later. */
    private static native boolean nativeJob(String name, String filesDir);

    static int idOf(String name) {
        return 0x6000000 | (name.hashCode() & 0xFFFFFF);
    }

    static boolean schedule(Context c, String name, int minutes, boolean network) {
        JobScheduler js = (JobScheduler) c.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (js == null) {
            return false;
        }
        PersistableBundle extras = new PersistableBundle();
        extras.putString("name", name);
        JobInfo.Builder b = new JobInfo.Builder(idOf(name), new ComponentName(c, PastelJob.class))
            .setExtras(extras)
            .setPeriodic(Math.max(15, minutes) * 60000L);
        // also after the phone restarted: with [package.android] background = ["jobs"]
        if (c.getPackageManager().checkPermission("android.permission.RECEIVE_BOOT_COMPLETED", c.getPackageName())
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            b.setPersisted(true);
        }
        if (network) {
            b.setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY);
        }
        return js.schedule(b.build()) == JobScheduler.RESULT_SUCCESS;
    }

    static void cancel(Context c, String name) {
        JobScheduler js = (JobScheduler) c.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (js != null) {
            js.cancel(idOf(name));
        }
    }

    @Override
    public boolean onStartJob(final JobParameters params) {
        final String name = params.getExtras().getString("name", "");
        final String dir = getFilesDir().getAbsolutePath();
        new Thread(new Runnable() {
            public void run() {
                boolean ok = false;
                try {
                    ok = nativeJob(name, dir);
                } catch (Throwable e) {
                    android.util.Log.w("pastel", "the job " + name + " failed: " + e);
                }
                jobFinished(params, !ok);
            }
        }, "pastel-job-" + name).start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return true;        // stopped by Android before it was done: again later
    }
}
