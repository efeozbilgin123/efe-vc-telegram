package org.portal.voice;

import org.geysermc.event.subscribe.Subscribe;
import org.geysermc.geyser.api.GeyserApi;
import org.geysermc.geyser.api.connection.GeyserConnection;
import org.geysermc.geyser.api.event.lifecycle.GeyserPostInitializeEvent;
import org.geysermc.geyser.api.event.lifecycle.GeyserShutdownEvent;
import org.geysermc.geyser.api.extension.Extension;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Optional Geyser-side position adapter for the local Portal Voice companion.
 * Intended for one local Bedrock client per Portal engine, not shared servers.
 */
public final class GeyserBridgeExtension implements Extension {
    private ScheduledExecutorService scheduler;
    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofMillis(500)).build();
    private String secret = "";

    @Subscribe
    public void onReady(GeyserPostInitializeEvent event) {
        try {
            Path folder = dataFolder();
            Files.createDirectories(folder);
            Path conf = folder.resolve("bridge.properties");
            if (!Files.exists(conf)) {
                Files.writeString(conf,
                    "# Copy Local Bridge Key from the running Portal Voice client.\n" +
                    "bridgeKey=\n");
            }
            Properties props = new Properties();
            try (var input = Files.newInputStream(conf)) {
                props.load(input);
            }
            secret = props.getProperty("bridgeKey", "").trim();
            if (secret.isEmpty()) {
                logger().warning("Portal Voice bridgeKey is empty. Update " + conf +
                    " and restart Geyser.");
                return;
            }
            scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
                Thread t = new Thread(r, "portal-voice-position");
                t.setDaemon(true);
                return t;
            });
            scheduler.scheduleWithFixedDelay(this::updatePosition,
                0, 850, TimeUnit.MILLISECONDS);
            logger().info("Portal Voice position bridge started (local only).");
        } catch (Exception ex) {
            logger().warning("Portal Voice bridge initialization failed: " + ex);
        }
    }

    private void updatePosition() {
        try {
            List<? extends GeyserConnection> connections = GeyserApi.api().onlineConnections();
            // Never publish another local player's location in multi-client mode.
            if (connections.size() != 1) return;
            GeyserConnection session = connections.get(0);
            var player = session.entities().playerEntity();
            if (player == null) return;
            var pos = player.position();
            float x = pos.getX(), y = pos.getY(), z = pos.getZ();
            if (!Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z)) return;

            // Dimension is not currently surfaced directly by public GeyserConnection
            // API. Use the known GeyserSession getter; fail CLOSED on incompatibility.
            String dimension = (String) session.getClass()
                .getMethod("getDimension").invoke(session);
            if (dimension == null || !dimension.matches("[a-z0-9_.-]+:[a-z0-9_./-]+"))
                return;

            String json = "{\"x\":" + x + ",\"y\":" + y + ",\"z\":" + z
                + ",\"dimension\":\"" + dimension + "\"}";
            HttpRequest request = HttpRequest.newBuilder(
                URI.create("http://127.0.0.1:43128/position"))
                .timeout(Duration.ofMillis(500))
                .header("Content-Type", "application/json")
                .header("X-Portal-Key", secret)
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();
            http.send(request, HttpResponse.BodyHandlers.discarding());
        } catch (Exception ignored) {
            // Voice client can be closed while the proxy remains running.
        }
    }

    @Subscribe
    public void onShutdown(GeyserShutdownEvent event) {
        if (scheduler != null) scheduler.shutdownNow();
    }
}
