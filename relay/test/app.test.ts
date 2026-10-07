import { afterEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { EventDispatcher, type EventSink } from "../src/events/dispatcher.js";
import type { DeviceEvent } from "../src/events/types.js";
import { RingClient } from "../src/ring/client.js";
import { signPayload } from "../src/ring/signature.js";

const SECRET = "whsec";
const TOKEN = "relay-token";
const silent = { info() {}, warn() {}, error() {} };

function setup(fetchFn?: typeof fetch) {
  const published: DeviceEvent[] = [];
  const sink: EventSink = { publish: async (e) => void published.push(e) };
  const dispatcher = new EventDispatcher(sink, silent);
  const ring = new RingClient({ apiBase: "https://ring.test", getToken: () => "ring-token", fetchFn });
  const app = buildApp({ dispatcher, ring, webhookSecret: SECRET, apiToken: TOKEN, logger: false });
  return { app, dispatcher, published };
}

let current: ReturnType<typeof setup> | undefined;
afterEach(async () => {
  await current?.app.close();
  current = undefined;
});

const post = (app: ReturnType<typeof setup>["app"], payload: object, signature?: string) => {
  const body = JSON.stringify(payload);
  return app.inject({
    method: "POST",
    url: "/webhooks/ring",
    headers: { "content-type": "application/json", "x-signature": signature ?? signPayload(SECRET, body) },
    payload: body,
  });
};

describe("POST /webhooks/ring", () => {
  const leak = { id: "evt-1", event_type: "flood_detected", device_id: "dev-1" };

  it("queues a signed event and publishes it once", async () => {
    current = setup();
    const first = await post(current.app, leak);
    const second = await post(current.app, leak);
    await current.dispatcher.idle();

    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ status: "queued", eventId: "evt-1" });
    expect(second.json()).toEqual({ status: "duplicate", eventId: "evt-1" });
    expect(current.published.map((e) => e.eventId)).toEqual(["evt-1"]);
  });

  it("rejects a bad signature", async () => {
    current = setup();
    const res = await post(current.app, leak, "sha256=" + "0".repeat(64));
    expect(res.statusCode).toBe(401);
    expect(current.published).toHaveLength(0);
  });

  it("acknowledges but ignores unknown event types", async () => {
    current = setup();
    const res = await post(current.app, { id: "x", event_type: "unknown", device_id: "d" });
    expect(res.json()).toEqual({ status: "ignored" });
  });
});

describe("/api routes", () => {
  it("require the relay token", async () => {
    current = setup();
    const res = await current.app.inject({ method: "GET", url: "/api/devices" });
    expect(res.statusCode).toBe(401);
  });

  it("proxy the Ring device list server-to-server", async () => {
    const calls: { url: string; auth: string | null }[] = [];
    const fetchFn = (async (url: string, init?: RequestInit) => {
      calls.push({ url, auth: new Headers(init?.headers).get("authorization") });
      return new Response(JSON.stringify({ data: [{ id: "dev-1", type: "devices", attributes: {} }] }), {
        status: 200,
      });
    }) as typeof fetch;
    current = setup(fetchFn);

    const res = await current.app.inject({
      method: "GET",
      url: "/api/devices",
      headers: { authorization: `Bearer ${TOKEN}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().data[0].id).toBe("dev-1");
    expect(calls[0]?.url).toBe("https://ring.test/v1/devices?include=status,capabilities,location,configurations");
    expect(calls[0]?.auth).toBe("Bearer ring-token");
  });

  it("maps Ring API errors to 502", async () => {
    current = setup((async () => new Response("nope", { status: 403 })) as typeof fetch);
    const res = await current.app.inject({
      method: "GET",
      url: "/api/devices",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(res.statusCode).toBe(502);
    expect(res.json()).toMatchObject({ error: "ring_api_error", status: 403 });
  });
});
