// A Java interface implemented by Pascal (Pastel.Java's JavaImplement): a
// listener, a callback, a Runnable. Java's Proxy makes an object of the
// interface; each of its methods comes to Pascal (nativeInvoke) with its
// name and arguments, and Pascal's answer goes back.
//
// On Android it is in the app's classes.dex; on a computer Pastel.Java gives
// it to the Java VM itself (pastel.javaproxy.inc, made by tools/android-dex.sh).
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

public final class PastelProxy implements InvocationHandler {
    private final long token;

    private PastelProxy(long token) {
        this.token = token;
    }

    /** Registered by Pastel.Java (RegisterNatives). */
    static native Object nativeInvoke(long token, String method, String signature, Object[] args, boolean wantsAnswer);

    public static Object create(Class<?> iface, long token) {
        ClassLoader loader = iface.getClassLoader();
        if (loader == null) {
            loader = PastelProxy.class.getClassLoader();
        }
        return Proxy.newProxyInstance(loader, new Class<?>[] { iface }, new PastelProxy(token));
    }

    /** Java's signature of a method, "(Landroid/view/View;I)V": tells overloads of one name apart */
    static String signature(Method m) {
        StringBuilder sb = new StringBuilder("(");
        for (Class<?> p : m.getParameterTypes()) {
            type(sb, p);
        }
        sb.append(')');
        type(sb, m.getReturnType());
        return sb.toString();
    }

    private static void type(StringBuilder sb, Class<?> t) {
        while (t.isArray()) {
            sb.append('[');
            t = t.getComponentType();
        }
        if (t == void.class) sb.append('V');
        else if (t == boolean.class) sb.append('Z');
        else if (t == byte.class) sb.append('B');
        else if (t == char.class) sb.append('C');
        else if (t == short.class) sb.append('S');
        else if (t == int.class) sb.append('I');
        else if (t == long.class) sb.append('J');
        else if (t == float.class) sb.append('F');
        else if (t == double.class) sb.append('D');
        else sb.append('L').append(t.getName().replace('.', '/')).append(';');
    }

    public Object invoke(Object proxy, Method m, Object[] args) {
        String name = m.getName();
        if (m.getDeclaringClass() == Object.class) {
            // the methods every object has: answered here
            if (name.equals("hashCode")) {
                return Integer.valueOf((int) (token ^ (token >>> 32)));
            }
            if (name.equals("equals")) {
                return Boolean.valueOf(args != null && args.length == 1 && proxy == args[0]);
            }
            if (name.equals("toString")) {
                return "PastelProxy@" + Long.toHexString(token);
            }
        }
        Class<?> t = m.getReturnType();
        Object r = nativeInvoke(token, name, signature(m), args == null ? new Object[0] : args, t != void.class);
        if (r == null && t.isPrimitive() && t != void.class) {
            // Pascal answered nothing: Java's zero of that type
            if (t == boolean.class) return Boolean.FALSE;
            if (t == char.class) return Character.valueOf((char) 0);
            if (t == byte.class) return Byte.valueOf((byte) 0);
            if (t == short.class) return Short.valueOf((short) 0);
            if (t == int.class) return Integer.valueOf(0);
            if (t == long.class) return Long.valueOf(0);
            if (t == float.class) return Float.valueOf(0);
            return Double.valueOf(0);
        }
        return r;
    }
}
