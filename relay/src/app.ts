import { timingSafeEqual } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import type { EventDispatcher } from "./events/dispatcher.js";
import { normalizeEvent } from "./events/normalize.js";
import { RingApiError, type RingClient } from "./ring/client.js";
import { verifySignature } from "./ring/signature.js";

export interface AppDeps {
  dispatcher: EventDispatcher;
  ring: RingClient;
  /** Secret for X-Signature on /webhooks/ring. Without it every webhook is rejected. */
  webhookSecret: string | undefined;
  /** Bearer token Salesforce's Named Credential must send on /api/*. Without it /api/* is closed. */
  apiToken: string | undefined;
  logger?: boolean | object;
}

declare module "fastify" {
  interface FastifyRequest {
    rawBody?: Buffer;
  }
}

export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({ logger: deps.logger ?? true, bodyLimit: 1024 * 1024 });

  // Keep the raw bytes: the HMAC is computed over the body exactly as sent.
  app.addContentTypeParser("application/json", { parseAs: "buffer" }, (req, body, done) => {
    req.rawBody = body as Buffer;
    try {
      done(null, body.length ? JSON.parse(body.toString("utf8")) : {});
    } catch {
      done(Object.assign(new Error("Invalid JSON"), { statusCode: 400 }), undefined);
    }
  });
  app.addContentTypeParser("application/sdp", { parseAs: "string" }, (_req, body, done) => done(null, body));

  app.get("/healthz", async () => ({ ok: true, pending: deps.dispatcher.pending }));

  app.post("/webhooks/ring", async (req, reply) => {
    const raw = req.rawBody;
    const signature = req.headers["x-signature"];
    if (
      !deps.webhookSecret ||
      !raw ||
      !verifySignature(deps.webhookSecret, raw, Array.isArray(signature) ? signature[0] : signature)
    ) {
      return reply.code(401).send({ error: "invalid signature" });
    }

    // Always 200 for authentic payloads, even ones we ignore, so Ring doesn't retry them.
    const source = req.headers["x-firstresponse-source"] === "emulator" ? "emulator" : "webhook";
    const event = normalizeEvent(req.body, source);
    if (!event) return { status: "ignored" };
    return { status: deps.dispatcher.accept(event), eventId: event.eventId };
  });

  app.register(async (api) => {
    api.addHook("onRequest", async (req, reply) => {
      if (!isAuthorized(req, deps.apiToken)) return reply.code(401).send({ error: "unauthorized" });
    });

    api.setErrorHandler((err, _req, reply) => {
      if (err instanceof RingApiError) {
        return reply.code(502).send({ error: "ring_api_error", status: err.status, path: err.path });
      }
      return reply.send(err);
    });

    api.get("/api/devices", async () => ({ data: await deps.ring.listDevices() }));

    api.get<{ Params: { id: string } }>("/api/devices/:id/events", async (req) => ({
      data: await deps.ring.listDeviceEvents(req.params.id),
    }));

    api.get<{ Params: { id: string } }>("/api/devices/:id/snapshot", async (req, reply) => {
      const snap = await deps.ring.getSnapshot(req.params.id);
      return reply.type(snap.contentType).send(snap.body);
    });

    // Salesforce can't reach Ring from the browser (CORS), so the Evidence card sends its
    // WebRTC offer here via Apex, and the relay negotiates with Ring server-to-server.
    api.post<{ Params: { id: string }; Body: string }>("/api/devices/:id/whep", async (req, reply) => {
      if (typeof req.body !== "string" || !req.body.startsWith("v=")) {
        return reply.code(400).send({ error: "expected an application/sdp offer" });
      }
      const { sdpAnswer } = await deps.ring.startWhepSession(req.params.id, req.body);
      return reply.type("application/sdp").send(sdpAnswer);
    });
  });

  return app;
}

function isAuthorized(req: FastifyRequest, token: string | undefined): boolean {
  if (!token) return false;
  const header = req.headers.authorization ?? "";
  const provided = Buffer.from(header.startsWith("Bearer ") ? header.slice(7) : "");
  const expected = Buffer.from(token);
  return provided.length === expected.length && timingSafeEqual(provided, expected);
}
