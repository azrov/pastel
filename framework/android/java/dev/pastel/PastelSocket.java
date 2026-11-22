// A TCP connection, TLS or not, for Pascal's protocols other than HTTP
// (Pastel.Http's NetConnect: WebSockets, e-mail): OpenSSL is not on phones,
// so Android's own TLS does it. Bytes go to and from Pascal as ISO-8859-1
// strings (one char per byte).
//
// Part of the Pastel project, MIT License.
package dev.pastel;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.security.cert.X509Certificate;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

public final class PastelSocket {
    private static final String BYTES = "ISO-8859-1";

    private Socket socket;
    private InputStream in;
    private OutputStream out;
    private final String host;
    private final int port;
    private final boolean verify;

    private PastelSocket(String host, int port, boolean verify) {
        this.host = host;
        this.port = port;
        this.verify = verify;
    }

    public static PastelSocket open(String host, int port, boolean tls, boolean verify, int timeout) throws IOException {
        PastelSocket p = new PastelSocket(host, port, verify);
        Socket s = new Socket();
        s.connect(new InetSocketAddress(host, port), timeout);
        s.setSoTimeout(timeout);
        p.use(s);
        if (tls) {
            p.startTls();
        }
        return p;
    }

    private void use(Socket s) throws IOException {
        socket = s;
        in = s.getInputStream();
        out = s.getOutputStream();
    }

    private SSLSocketFactory factory() throws IOException {
        if (verify) {
            return (SSLSocketFactory) SSLSocketFactory.getDefault();
        }
        // tests only: any certificate
        try {
            TrustManager any = new X509TrustManager() {
                public void checkClientTrusted(X509Certificate[] c, String a) { }
                public void checkServerTrusted(X509Certificate[] c, String a) { }
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            };
            SSLContext ctx = SSLContext.getInstance("TLS");
            ctx.init(null, new TrustManager[] { any }, null);
            return ctx.getSocketFactory();
        } catch (Exception e) {
            throw new IOException(e.toString());
        }
    }

    /** the plain connection becomes TLS (also SMTP's STARTTLS) */
    public void startTls() throws IOException {
        SSLSocket t = (SSLSocket) factory().createSocket(socket, host, port, true);
        // the certificate must be for this host: TLS checks it (Android 7 and newer, Java)...
        boolean checked = false;
        if (verify) {
            try {
                SSLParameters p = t.getSSLParameters();
                // by reflection: Android 7's method, not in the android.jar Pastel is built with
                SSLParameters.class.getMethod("setEndpointIdentificationAlgorithm", String.class).invoke(p, "HTTPS");
                t.setSSLParameters(p);
                checked = true;
            } catch (Throwable e) {
                // older Android: below
            }
        }
        try {
            t.startHandshake();
        } catch (IOException e) {
            t.close();
            throw new IOException("certificate of \"" + host + "\" is not trusted, or TLS failed: " + e.getMessage());
        }
        // ...or Android's own check of the name
        if (verify && !checked && !HttpsURLConnection.getDefaultHostnameVerifier().verify(host, t.getSession())) {
            t.close();
            throw new IOException("certificate of \"" + host + "\" is not trusted: it is for another name");
        }
        use(t);
    }

    public void setReadTimeout(int ms) throws IOException {
        socket.setSoTimeout(ms);
    }

    /** up to max bytes; "" when nothing came in time; null at the end */
    public String read(int max) throws IOException {
        byte[] b = new byte[max];
        try {
            int n = in.read(b);
            if (n < 0) {
                return null;
            }
            return new String(b, 0, n, BYTES);
        } catch (SocketTimeoutException e) {
            return "";
        } catch (IOException e) {
            if (socket.isClosed()) {
                return null;
            }
            throw e;
        }
    }

    public void write(String data) throws IOException {
        out.write(data.getBytes(BYTES));
        out.flush();
    }

    public void close() {
        try {
            socket.close();
        } catch (IOException e) {
            // closed already
        }
    }
}
