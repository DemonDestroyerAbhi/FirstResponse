import { randomUUID } from "node:crypto";

/**
 * Builds emulated Ring events for the types the Playground can't produce (sensors, webhooks,
 * multi-camera). Field names follow the documented event vocabulary; the envelope is the
 * relay's flat shape (see normalizeEvent). Demo footage must label these as emulated.
 */
export interface EmulatedEventOptions {
  eventType: string;
  deviceId: string;
  eventId?: string;
  subType?: string;
  componentId?: string;
  locationId?: string;
  occurredAt?: Date;
}

export function buildEmulatedEvent(opts: EmulatedEventOptions): Record<string, string> {
  const event: Record<string, string> = {
    id: opts.eventId ?? `emu-${randomUUID()}`,
    event_type: opts.eventType,
    device_id: opts.deviceId,
    created_at: (opts.occurredAt ?? new Date()).toISOString(),
  };
  if (opts.subType) event.sub_type = opts.subType;
  if (opts.componentId) event.component_id = opts.componentId;
  if (opts.locationId) event.location_id = opts.locationId;
  return event;
}

/** Named scenarios used in the demo script. */
export const SCENARIOS: Record<string, Omit<EmulatedEventOptions, "deviceId">[]> = {
  // 2am leak: the event that should open a Work Order with an SLA clock.
  leak: [{ eventType: "flood_detected" }],
  freeze: [{ eventType: "freeze_detected" }],
  "after-hours-intruder": [{ eventType: "motion_detected", subType: "human" }],
  "camera-offline": [{ eventType: "device_offline" }],
  tamper: [{ eventType: "tamper_detected" }],
  "fridge-warm": [{ eventType: "contact_sensor_faulted" }, { eventType: "temperature_exceeded" }],
};
