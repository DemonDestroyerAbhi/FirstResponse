import { describe, expect, it } from "vitest";
import { normalizeEvent } from "../src/events/normalize.js";

describe("normalizeEvent", () => {
  it("reads the flat shape", () => {
    const event = normalizeEvent(
      { id: "e1", event_type: "flood_detected", device_id: "d1", created_at: "2026-10-07T02:00:00Z" },
      "emulator",
    );
    expect(event).toMatchObject({
      eventId: "e1",
      eventType: "flood_detected",
      deviceId: "d1",
      occurredAt: "2026-10-07T02:00:00.000Z",
      source: "emulator",
    });
  });

  it("reads the JSON:API shape", () => {
    const event = normalizeEvent(
      {
        data: {
          id: "e2",
          type: "events",
          attributes: { event_type: "motion_detected", sub_type: "human", component_id: 2 },
          relationships: { device: { data: { id: "d9" } }, location: { data: { id: "loc1" } } },
        },
      },
      "webhook",
    );
    expect(event).toMatchObject({
      eventId: "e2",
      eventType: "motion_detected",
      subType: "human",
      componentId: "2",
      deviceId: "d9",
      locationId: "loc1",
    });
  });

  it("ignores unknown types and incomplete payloads", () => {
    expect(normalizeEvent({ id: "e3", event_type: "made_up", device_id: "d1" }, "webhook")).toBeUndefined();
    expect(normalizeEvent({ id: "e3", event_type: "flood_detected" }, "webhook")).toBeUndefined();
    expect(normalizeEvent("nope", "webhook")).toBeUndefined();
  });
});
