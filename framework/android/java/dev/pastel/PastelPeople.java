// The phone's contacts and calendar for Pastel.Device: picking a contact (the
// phone's own list, no permission), reading them all ("contacts"), a new
// contact or calendar event filled in for the user to save (no permission),
// and the calendar's events between two times ("calendar").
//
// Times go to and from Pascal as local "yyyy-MM-dd HH:mm:ss" text: Java knows
// the phone's time zone.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.app.Activity;
import android.content.ContentUris;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CalendarContract;
import android.provider.ContactsContract;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.TimeZone;

final class PastelPeople {
    /** the requests waiting for a picked contact */
    static final HashSet<Integer> pickCodes = new HashSet<Integer>();

    private static String clean(String s) {
        return s == null ? "" : s.replace('\u0001', ' ').replace('\u0002', ' ').replace('\n', ' ');
    }

    // ---------- contacts ----------

    /** The phone's list of contacts: a phone number (email false) or an e-mail of one. */
    static void pick(Activity a, int code, boolean email) {
        Intent i = new Intent(Intent.ACTION_PICK);
        i.setType(email ? ContactsContract.CommonDataKinds.Email.CONTENT_TYPE
            : ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE);
        try {
            pickCodes.add(code);
            a.startActivityForResult(i, code);
        } catch (Exception e) {
            pickCodes.remove(code);
            PastelActivity.result(code, 0, "there is no contacts app on this phone");
        }
    }

    /** The answer of pick: name \u0001 phone \u0001 e-mail. */
    static void picked(Context c, int code, int result, Intent data) {
        if (result != Activity.RESULT_OK || data == null || data.getData() == null) {
            PastelActivity.result(code, 0, "canceled");
            return;
        }
        Cursor k = null;
        try {
            k = c.getContentResolver().query(data.getData(), null, null, null, null);
            if (k == null || !k.moveToFirst()) {
                PastelActivity.result(code, 0, "the contact could not be read");
                return;
            }
            String name = clean(k.getString(k.getColumnIndex(ContactsContract.Contacts.DISPLAY_NAME)));
            String mime = k.getString(k.getColumnIndex(ContactsContract.Data.MIMETYPE));
            // Phone.NUMBER and Email.ADDRESS are both the data's first column (DATA1)
            String value = clean(k.getString(k.getColumnIndex(ContactsContract.Data.DATA1)));
            if (ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE.equals(mime)) {
                PastelActivity.result(code, 1, name + '\u0001' + '\u0001' + value);
            } else {
                PastelActivity.result(code, 1, name + '\u0001' + value + '\u0001');
            }
        } catch (Exception e) {
            PastelActivity.result(code, 0, e.toString());
        } finally {
            if (k != null) {
                k.close();
            }
        }
    }

    /** All contacts (with search in their name, number or e-mail): lines of
     *  name \u0001 phones \u0001 e-mails (\u0002 between them); "!" and why when not. */
    static String read(Context c, String search) {
        LinkedHashMap<Long, String[]> people = new LinkedHashMap<Long, String[]>();
        String s = search == null ? "" : search.toLowerCase(Locale.ROOT);
        Cursor k = null;
        try {
            k = c.getContentResolver().query(ContactsContract.Data.CONTENT_URI,
                new String[] { ContactsContract.Data.CONTACT_ID, ContactsContract.Data.DISPLAY_NAME,
                    ContactsContract.Data.MIMETYPE, ContactsContract.Data.DATA1 },
                ContactsContract.Data.MIMETYPE + " IN (?, ?)",
                new String[] { ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                    ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE },
                ContactsContract.Data.DISPLAY_NAME + " COLLATE LOCALIZED ASC");
            if (k == null) {
                return "!the contacts could not be read";
            }
            while (k.moveToNext()) {
                long id = k.getLong(0);
                String[] p = people.get(id);
                if (p == null) {
                    p = new String[] { clean(k.getString(1)), "", "" };
                    people.put(id, p);
                }
                String v = clean(k.getString(3));
                if (v.length() == 0) {
                    continue;
                }
                int at = ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE.equals(k.getString(2)) ? 2 : 1;
                p[at] = p[at].length() == 0 ? v : p[at] + '\u0002' + v;
            }
        } catch (SecurityException e) {
            return "!no permission for the contacts: RequestPermission(dpContacts)";
        } catch (Exception e) {
            return "!" + e;
        } finally {
            if (k != null) {
                k.close();
            }
        }
        StringBuilder out = new StringBuilder();
        for (String[] p : people.values()) {
            if (s.length() > 0 && !(p[0] + ' ' + p[1] + ' ' + p[2]).toLowerCase(Locale.ROOT).contains(s)) {
                continue;
            }
            out.append(p[0]).append('\u0001').append(p[1]).append('\u0001').append(p[2]).append('\n');
        }
        return out.toString();
    }

    /** The contacts app with a new contact filled in. "" or why not. */
    static String add(Activity a, String name, String phone, String email) {
        Intent i = new Intent(ContactsContract.Intents.Insert.ACTION);
        i.setType(ContactsContract.RawContacts.CONTENT_TYPE);
        i.putExtra(ContactsContract.Intents.Insert.NAME, name);
        if (phone.length() > 0) {
            i.putExtra(ContactsContract.Intents.Insert.PHONE, phone);
        }
        if (email.length() > 0) {
            i.putExtra(ContactsContract.Intents.Insert.EMAIL, email);
        }
        try {
            a.startActivity(i);
            return "";
        } catch (Exception e) {
            return "there is no contacts app on this phone";
        }
    }

    // ---------- the calendar ----------

    private static SimpleDateFormat format(boolean utc) {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US);
        if (utc) {
            f.setTimeZone(TimeZone.getTimeZone("UTC"));
        }
        return f;
    }

    private static long millis(String local) throws Exception {
        return format(false).parse(local).getTime();
    }

    /** The calendar app with a new event filled in. "" or why not. */
    static String addEvent(Activity a, String title, String begin, String end, boolean allDay, String place, String notes) {
        try {
            Intent i = new Intent(Intent.ACTION_INSERT);
            i.setData(CalendarContract.Events.CONTENT_URI);
            i.putExtra(CalendarContract.Events.TITLE, title);
            long b = millis(begin);
            long e = millis(end);
            if (allDay) {
                // an all-day event is a day in UTC
                b = format(true).parse(begin.substring(0, 10) + " 00:00:00").getTime();
                e = format(true).parse(end.substring(0, 10) + " 00:00:00").getTime();
                if (e <= b) {
                    e = b + 86400000L;
                }
                i.putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true);
            }
            i.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, b);
            i.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, e);
            if (place.length() > 0) {
                i.putExtra(CalendarContract.Events.EVENT_LOCATION, place);
            }
            if (notes.length() > 0) {
                i.putExtra(CalendarContract.Events.DESCRIPTION, notes);
            }
            a.startActivity(i);
            return "";
        } catch (android.content.ActivityNotFoundException ex) {
            return "there is no calendar app on this phone";
        } catch (Exception ex) {
            return ex.toString();
        }
    }

    /** The events between two local times: lines of title \u0001 place \u0001 notes \u0001
     *  begin \u0001 end \u0001 1 (all day) or 0; "!" and why when not. */
    static String events(Context c, String from, String till) {
        Cursor k = null;
        try {
            Uri.Builder u = CalendarContract.Instances.CONTENT_URI.buildUpon();
            ContentUris.appendId(u, millis(from));
            ContentUris.appendId(u, millis(till));
            k = c.getContentResolver().query(u.build(),
                new String[] { CalendarContract.Instances.TITLE, CalendarContract.Instances.EVENT_LOCATION,
                    CalendarContract.Instances.DESCRIPTION, CalendarContract.Instances.BEGIN,
                    CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY },
                null, null, CalendarContract.Instances.BEGIN + " ASC");
            if (k == null) {
                return "!the calendar could not be read";
            }
            SimpleDateFormat local = format(false);
            SimpleDateFormat utc = format(true);
            StringBuilder out = new StringBuilder();
            while (k.moveToNext()) {
                boolean allDay = k.getInt(5) != 0;
                SimpleDateFormat f = allDay ? utc : local;
                out.append(clean(k.getString(0))).append('\u0001')
                    .append(clean(k.getString(1))).append('\u0001')
                    .append(clean(k.getString(2))).append('\u0001')
                    .append(f.format(new Date(k.getLong(3)))).append('\u0001')
                    .append(f.format(new Date(k.getLong(4)))).append('\u0001')
                    .append(allDay ? '1' : '0').append('\n');
            }
            return out.toString();
        } catch (SecurityException e) {
            return "!no permission for the calendar: RequestPermission(dpCalendar)";
        } catch (Exception e) {
            return "!" + e;
        } finally {
            if (k != null) {
                k.close();
            }
        }
    }
}
