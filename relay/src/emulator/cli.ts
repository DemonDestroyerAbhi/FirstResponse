import { parseArgs } from "node:util";
import { signPayload } from "../ring/signature.js";
import { buildEmulatedEvent, SCENARIOS, type EmulatedEventOptions } from "./events.js";

const USAGE = `Usage:
  npm run emulate -- <scenario|event_type> --device <device_id> [options]

Scenarios: ${Object.keys(SCENARIOS).join(", ")}

Options:
  --device       Ring device id (must match Asset.Device_Id__c in Salesforce)
  --event-id     Fixed event id; send the same id twice to demo idempotency
  --sub-type     e.g. human, vehicle, package_delivery
  --component    component_id for multi-camera devices
  --repeat       Send each event N times (default 1)
  --url          Relay base URL (default http://localhost:3000)

Signs each request with RING_WEBHOOK_SECRET, exactly as Ring would.`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    device: { type: "string" },
    "event-id": { type: "string" },
    "sub-type": { type: "string" },
    component: { type: "string" },
    repeat: { type: "string", default: "1" },
    url: { type: "string", default: process.env.RELAY_URL ?? "http://localhost:3000" },
    help: { type: "boolean", short: "h" },
  },
});

const name = positionals[0];
const secret = process.env.RING_WEBHOOK_SECRET;
if (values.help || !name || !values.device) {
  console.log(USAGE);
  process.exit(values.help ? 0 : 1);
}
if (!secret) {
  console.error("RING_WEBHOOK_SECRET must be set");
  process.exit(1);
}

const steps: Omit<EmulatedEventOptions, "deviceId">[] = SCENARIOS[name] ?? [{ eventType: name }];
const repeat = Math.max(1, Number(values.repeat) || 1);

for (const step of steps) {
  const event = buildEmulatedEvent({
    ...step,
    deviceId: values.device,
    eventId: values["event-id"] ?? step.eventId,
    subType: values["sub-type"] ?? step.subType,
    componentId: values.component ?? step.componentId,
  });
  const body = JSON.stringify(event);

  for (let i = 0; i < repeat; i++) {
    const res = await fetch(`${values.url}/webhooks/ring`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-signature": signPayload(secret, body),
        "x-firstresponse-source": "emulator",
      },
      body,
    });
    console.log(`[emulated] ${event.event_type} ${event.id} -> ${res.status} ${await res.text()}`);
  }
}
