import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { EventDispatcher } from "./events/dispatcher.js";
import { RingClient } from "./ring/client.js";
import { HistoryPoller } from "./ring/poller.js";
import { LoggingSink, SalesforcePublisher } from "./salesforce/publisher.js";

const config = loadConfig();

const ring = new RingClient({
  apiBase: config.ring.apiBase,
  // Read on every call so a fresh Playground token can be swapped in via the environment.
  getToken: () => process.env.RING_ACCESS_TOKEN?.trim() || config.ring.accessToken,
});

// Fastify's logger isn't available until the app exists, so the sink and dispatcher log
// through a proxy that forwards to it.
let appLog: import("fastify").FastifyBaseLogger | undefined;
const log = {
  info: (obj: object, msg?: string) => appLog?.info(obj, msg),
  warn: (obj: object, msg?: string) => appLog?.warn(obj, msg),
  error: (obj: object, msg?: string) => appLog?.error(obj, msg),
};

const sink = config.salesforce ? new SalesforcePublisher(config.salesforce) : new LoggingSink(log);
const dispatcher = new EventDispatcher(sink, log);

const app = buildApp({
  dispatcher,
  ring,
  webhookSecret: config.ring.webhookSecret,
  apiToken: config.relayApiToken,
});
appLog = app.log;

const poller = new HistoryPoller(ring, dispatcher, log, config.ring.pollIntervalSeconds * 1000);

if (!config.salesforce) app.log.warn("Salesforce not configured: events will be logged, not published");
if (!config.ring.webhookSecret) app.log.warn("RING_WEBHOOK_SECRET not set: all webhooks will be rejected");
if (!config.relayApiToken) app.log.warn("RELAY_API_TOKEN not set: /api/* is closed");

await app.listen({ port: config.port, host: "0.0.0.0" });
poller.start();

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, async () => {
    poller.stop();
    await app.close();
    await dispatcher.idle();
    process.exit(0);
  });
}
