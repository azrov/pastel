// Firebase gives push messages and new tokens here (see PastelPush).
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

public class PastelPushService extends FirebaseMessagingService {
    @Override
    public void onNewToken(String token) {
        PastelPush.add("token\t" + token);
    }

    @Override
    public void onMessageReceived(RemoteMessage m) {
        String title = "";
        String body = "";
        RemoteMessage.Notification n = m.getNotification();
        if (n != null) {
            title = n.getTitle() == null ? "" : n.getTitle();
            body = n.getBody() == null ? "" : n.getBody();
        }
        Map<String, String> data = m.getData();
        if (title.length() == 0 && data.containsKey("title")) {
            title = data.get("title");
        }
        if (body.length() == 0 && data.containsKey("body")) {
            body = data.get("body");
        }
        PastelPush.message(title, body, data, false);
        // the app not on the screen: the user sees it as a notification (Firebase shows only its own kind)
        if (!PastelActivity.onScreen && n == null && (title.length() > 0 || body.length() > 0)) {
            PastelNotifications.post(this, "push-" + (m.getMessageId() == null ? "" : m.getMessageId()), title, body);
        }
    }
}
