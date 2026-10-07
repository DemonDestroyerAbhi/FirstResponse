import { KNOWN_EVENT_TYPES, type DeviceEvent, type EventSource } from "./types.js";

/**
 * Turns an incoming payload into a DeviceEvent.
 *
 * The exact webhook envelope isn't confirmed (the Playground sends no webhooks), so this
 * accepts both a flat shape and a JSON:API shape:
 *
 *   { "id", "event_type", "device_id", "sub_type"?, "component_id"?, "location_id"?, "created_at" }
 *   { "data": { "id", "type", "attributes": { ...same fields... },
 *               "relationships": { "device": { "data": { "id" } } } } }
 *
 * Returns undefined when the payload can't be identified or the type isn't one we handle.
 */
export function normalizeEvent(payload: unknown, source: EventSource): DeviceEvent | undefined {
  if (!isObject(payload)) return undefined;

  const data = isObject(payload.data) ? payload.data : payload;
  const attrs = isObject(data.attributes) ? data.attributes : {};
  const field = (...keys: string[]): string | undefined => {
    for (const key of keys) {
      for (const obj of [attrs, data, payload]) {
        const value = obj[key];
        if (typeof value === "string" && value) return value;
        if (typeof value === "number") return String(value);
      }
    }
    return undefined;
  };

  const eventId = field("event_id", "id");
  const eventType = field("event_type", "kind", "type");
  const deviceId = field("device_id") ?? relationshipId(data, "device");
  if (!eventId || !eventType || !deviceId) return undefined;
  if (!KNOWN_EVENT_TYPES.has(eventType)) return undefined;

  const occurred = field("occurred_at", "created_at", "timestamp");
  const occurredAt = occurred && !Number.isNaN(Date.parse(occurred)) ? new Date(occurred).toISOString() : new Date().toISOString();

  return {
    eventId,
    deviceId,
    eventType,
    subType: field("sub_type"),
    componentId: field("component_id"),
    locationId: field("location_id") ?? relationshipId(data, "location"),
    occurredAt,
    source,
    raw: payload,
  };
}

function relationshipId(data: Record<string, unknown>, name: string): string | undefined {
  const rels = data.relationships;
  if (!isObject(rels)) return undefined;
  const rel = rels[name];
  if (!isObject(rel) || !isObject(rel.data)) return undefined;
  const id = rel.data.id;
  return typeof id === "string" || typeof id === "number" ? String(id) : undefined;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
