// TalkBack and other accessibility services: Pascal draws the window itself, so
// this view tells Android what is on it - the controls Pascal sends (their
// place, kind, text, state) as virtual views - and passes the service's
// actions (click, focus) back to Pascal.
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import android.content.Context;
import android.graphics.Rect;
import android.os.Bundle;
import android.view.View;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeProvider;

import java.util.ArrayList;
import java.util.HashMap;

final class PastelAccess extends View {
    interface Actions {
        void action(int id, int action);
    }

    static final class Node {
        int id, parent;
        Rect bounds = new Rect();
        String role = "", text = "", hint = "";
        boolean enabled = true, checked, checkable, focused, editable, clickable, scrollable;
        ArrayList<Integer> children = new ArrayList<Integer>();
    }

    private final HashMap<Integer, Node> nodes = new HashMap<Integer, Node>();
    private final ArrayList<Integer> top = new ArrayList<Integer>();
    private final Actions actions;
    private int accessibilityFocus = -1;

    PastelAccess(Context c, Actions a) {
        super(c);
        actions = a;
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
    }

    static boolean on(Context c) {
        AccessibilityManager am = (AccessibilityManager) c.getSystemService(Context.ACCESSIBILITY_SERVICE);
        return am != null && am.isEnabled() && am.isTouchExplorationEnabled();
    }

    /** lines "id\tparent\tx\ty\tw\th\trole\ttext\thint\tflags" (flags: e enabled, c checkable, k checked, f focused, t editable, l clickable, s scrollable) */
    void update(String tree) {
        nodes.clear();
        top.clear();
        int[] at = new int[2];
        getRootView().getLocationOnScreen(at);     // Pascal's places are in the window's pixels
        for (String line : tree.split("\n")) {
            String[] p = line.split("\t", -1);
            if (p.length < 10) {
                continue;
            }
            Node n = new Node();
            n.id = Integer.parseInt(p[0]);
            n.parent = Integer.parseInt(p[1]);
            int x = Integer.parseInt(p[2]) + at[0];
            int y = Integer.parseInt(p[3]) + at[1];
            n.bounds.set(x, y, x + Integer.parseInt(p[4]), y + Integer.parseInt(p[5]));
            n.role = p[6];
            n.text = p[7];
            n.hint = p[8];
            String f = p[9];
            n.enabled = f.indexOf('e') >= 0;
            n.checkable = f.indexOf('c') >= 0;
            n.checked = f.indexOf('k') >= 0;
            n.focused = f.indexOf('f') >= 0;
            n.editable = f.indexOf('t') >= 0;
            n.clickable = f.indexOf('l') >= 0;
            n.scrollable = f.indexOf('s') >= 0;
            nodes.put(n.id, n);
        }
        for (Node n : nodes.values()) {
            Node p = nodes.get(n.parent);
            if (p != null) {
                p.children.add(n.id);
            } else {
                top.add(n.id);
            }
        }
        sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED);
    }

    private static String className(String role) {
        if (role.length() == 0) {
            return "android.view.View";
        }
        return role.indexOf('.') >= 0 ? role : "android.widget." + role;
    }

    @Override
    public AccessibilityNodeProvider getAccessibilityNodeProvider() {
        return new AccessibilityNodeProvider() {
            @Override
            public AccessibilityNodeInfo createAccessibilityNodeInfo(int id) {
                if (id == View.NO_ID) {
                    AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(PastelAccess.this);
                    onInitializeAccessibilityNodeInfo(info);
                    for (int c : top) {
                        info.addChild(PastelAccess.this, c);
                    }
                    return info;
                }
                Node n = nodes.get(id);
                if (n == null) {
                    return null;
                }
                AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(PastelAccess.this, id);
                info.setPackageName(getContext().getPackageName());
                info.setClassName(className(n.role));
                info.setBoundsInScreen(n.bounds);
                int[] at = new int[2];
                getLocationOnScreen(at);
                Rect local = new Rect(n.bounds);
                local.offset(-at[0], -at[1]);
                info.setBoundsInParent(local);
                if (nodes.containsKey(n.parent)) {
                    info.setParent(PastelAccess.this, n.parent);
                } else {
                    info.setParent(PastelAccess.this);
                }
                if (n.text.length() > 0) {
                    info.setText(n.text);
                }
                if (n.hint.length() > 0) {
                    info.setContentDescription(n.text.length() > 0 ? null : n.hint);
                }
                info.setEnabled(n.enabled);
                info.setCheckable(n.checkable);
                info.setChecked(n.checked);
                info.setFocusable(n.clickable || n.editable);
                info.setFocused(n.focused);
                info.setEditable(n.editable);
                info.setClickable(n.clickable);
                info.setScrollable(n.scrollable);
                info.setVisibleToUser(true);
                info.setAccessibilityFocused(accessibilityFocus == id);
                if (n.clickable || n.editable) {
                    info.addAction(AccessibilityNodeInfo.ACTION_CLICK);
                    info.addAction(AccessibilityNodeInfo.ACTION_FOCUS);
                }
                if (n.scrollable) {
                    info.addAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD);
                    info.addAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
                }
                info.addAction(accessibilityFocus == id ? AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS
                    : AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS);
                for (int c : n.children) {
                    info.addChild(PastelAccess.this, c);
                }
                return info;
            }

            @Override
            public boolean performAction(int id, int action, Bundle args) {
                if (id == View.NO_ID) {
                    return performAccessibilityAction(action, args);
                }
                if (!nodes.containsKey(id)) {
                    return false;
                }
                switch (action) {
                    case AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS:
                        accessibilityFocus = id;
                        invalidate();
                        sendEvent(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED);
                        return true;
                    case AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS:
                        if (accessibilityFocus == id) {
                            accessibilityFocus = -1;
                        }
                        sendEvent(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED);
                        return true;
                    case AccessibilityNodeInfo.ACTION_CLICK:
                    case AccessibilityNodeInfo.ACTION_FOCUS:
                    case AccessibilityNodeInfo.ACTION_SCROLL_FORWARD:
                    case AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD:
                        actions.action(id, action);
                        if (action == AccessibilityNodeInfo.ACTION_CLICK) {
                            sendEvent(id, AccessibilityEvent.TYPE_VIEW_CLICKED);
                        }
                        return true;
                    default:
                        return false;
                }
            }
        };
    }

    private void sendEvent(int id, int type) {
        if (getParent() == null) {
            return;
        }
        AccessibilityEvent e = AccessibilityEvent.obtain(type);
        e.setPackageName(getContext().getPackageName());
        e.setSource(this, id);
        Node n = nodes.get(id);
        if (n != null) {
            e.setClassName(className(n.role));
            e.getText().add(n.text.length() > 0 ? n.text : n.hint);
        }
        getParent().requestSendAccessibilityEvent(this, e);
    }
}
