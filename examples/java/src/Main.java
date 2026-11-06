import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

public class Main {
    public static void main(String[] args) throws Exception {
        // No curl in a distroless image: the app checks itself for HEALTHCHECK.
        if (args.length > 0 && args[0].equals("healthcheck")) {
            var req = HttpRequest.newBuilder(URI.create("http://127.0.0.1:8080/healthz"))
                    .timeout(Duration.ofSeconds(2)).build();
            int status = HttpClient.newHttpClient().send(req, HttpResponse.BodyHandlers.discarding()).statusCode();
            System.exit(status == 200 ? 0 : 1);
        }
        var server = HttpServer.create(new InetSocketAddress(8080), 0);
        server.createContext("/healthz", ex -> reply(ex, "ok\n"));
        server.createContext("/", ex -> reply(ex, "hello from java " + Runtime.version()
                + ", user=" + System.getProperty("user.name") + "\n"));
        server.start();
    }

    private static void reply(com.sun.net.httpserver.HttpExchange ex, String body) throws java.io.IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.sendResponseHeaders(200, bytes.length);
        try (var os = ex.getResponseBody()) { os.write(bytes); }
    }
}
