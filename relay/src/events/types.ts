/** Where an event entered the relay. */
export type EventSource = "webhook" | "history" | "emulator";

/**
 * Relay-internal event shape. This is what gets published to Salesforce as Device_Event__e;
 * the Salesforce side decides (via Event_Mapping__mdt) whether it becomes a Work Order.
 */
export interface DeviceEvent {
  /** Idempotency key: Ring's event id. */
  eventId: string;
  deviceId: string;
  eventType: string;
  /** e.g. motion_detected sub_type: motion | human | vehicle | package_delivery | other_motion */
  subType?: string;
  /** Multi-camera devices report which lens fired. */
  componentId?: string;
  locationId?: string;
  /** ISO-8601. */
  occurredAt: string;
  source: EventSource;
  raw: unknown;
}

/** Event types the relay recognises. Anything else is acknowledged and dropped. */
export const KNOWN_EVENT_TYPES = new Set([
  // Webhook types documented as GA
  "motion_detected",
  "button_press",
  "device_added",
  "device_removed",
  "device_online",
  "device_offline",
  "app_integration_added",
  "app_integration_removed",
  "subscription_activated",
  "subscription_deactivated",
  // Sensor events (Early Access; produced by the emulator until a real source exists)
  "flood_detected",
  "flood_cleared",
  "freeze_detected",
  "freeze_cleared",
  "contact_sensor_faulted",
  "contact_sensor_cleared",
  "tamper_detected",
  "tamper_cleared",
  "temperature_exceeded",
  "temperature_cleared",
  "humidity_exceeded",
  "humidity_cleared",
  "pm25_exceeded",
  "pm25_cleared",
  "co_exceeded",
  "co_cleared",
  // Event History on the Playground only returns these
  "on_demand",
]);
