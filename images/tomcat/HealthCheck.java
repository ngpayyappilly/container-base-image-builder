import java.net.HttpURLConnection;
import java.net.URI;

/**
 * Self-check for shell-less images (no curl): exit 0 iff the URL answers 200.
 *   java -cp /opt/tomcat/bin/healthcheck.jar HealthCheck [url]
 * Default URL is the HealthCheckValve configured in server.xml.
 */
public class HealthCheck {
    public static void main(String[] args) {
        String url = args.length > 0 ? args[0] : "http://127.0.0.1:8080/healthz";
        try {
            HttpURLConnection c = (HttpURLConnection) URI.create(url).toURL().openConnection();
            c.setConnectTimeout(2000);
            c.setReadTimeout(2000);
            System.exit(c.getResponseCode() == 200 ? 0 : 1);
        } catch (Exception e) {
            System.exit(1);
        }
    }
}
