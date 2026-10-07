import { describe, expect, it } from "vitest";
import { RecentIds } from "../src/events/dedupe.js";
import { EventDispatcher, type EventSink } from "../src/events/dispatcher.js";
import type { DeviceEvent } from "../src/events/types.js";

const silent = { info() {}, warn() {}, error() {} };
const event = (id: string): DeviceEvent => ({
  eventId: id,
  deviceId: "d1",
  eventType: "flood_detected",
  occurredAt: new Date().toISOString(),
  source: "emulator",
  raw: {},
});

describe("RecentIds", () => {
  it("expires ids after the TTL", () => {
    let now = 0;
    const ids = new RecentIds(1000, 10, () => now);
    expect(ids.add("a")).toBe(true);
    expect(ids.add("a")).toBe(false);
    now = 1001;
    expect(ids.add("a")).toBe(true);
  });

  it("caps its size", () => {
    const ids = new RecentIds(60_000, 2);
    ids.add("a");
    ids.add("b");
    ids.add("c");
    expect(ids.size).toBe(2);
    expect(ids.add("a")).toBe(true);
  });
});

describe("EventDispatcher", () => {
  it("publishes once per event id", async () => {
    const published: string[] = [];
    const sink: EventSink = { publish: async (e) => void published.push(e.eventId) };
    const dispatcher = new EventDispatcher(sink, silent);

    expect(dispatcher.accept(event("e1"))).toBe("queued");
    expect(dispatcher.accept(event("e1"))).toBe("duplicate");
    expect(dispatcher.accept(event("e2"))).toBe("queued");
    await dispatcher.idle();

    expect(published).toEqual(["e1", "e2"]);
  });

  it("retries, then lets a redelivery through after giving up", async () => {
    let calls = 0;
    const sink: EventSink = {
      publish: async () => {
        calls++;
        throw new Error("down");
      },
    };
    const dispatcher = new EventDispatcher(sink, silent, new RecentIds(), [1, 1]);

    dispatcher.accept(event("e1"));
    await dispatcher.idle();
    expect(calls).toBe(3);
    expect(dispatcher.accept(event("e1"))).toBe("queued");
    await dispatcher.idle();
  });
});
