# FirstResponse

**Ring device and sensor events become entitlement-checked Service Cloud Work Orders, with SLA milestones counting from the moment the device reported the problem.**

Facilities and AMC providers servicing multi-site retail, clinics and property portfolios still learn about a leak or an offline camera through a phone call and a spreadsheet row, often after the SLA has already been missed. FirstResponse connects the device straight to the system of record: the event finds the asset, the asset finds its service contract and entitlement, and a Work Order opens with the entitlement process's milestones already running.

> Service Cloud Work Orders with entitlement-driven SLA milestones. Not Field Service: no FSL package or licences are needed, so it runs on a free Developer Edition org.

## How it works

```
Ring event ──▶ relay (Node 20 / TypeScript / Fastify)
                 │  verify X-Signature (HMAC-SHA256), ack immediately, dedupe by event id
                 │  (Playground: poll Event History instead, since it sends no webhooks)
                 ▼
          Platform Event  Device_Event__e         (JWT-bearer connected app)
                 ▼
          DeviceEventTrigger ─▶ DeviceEventService
                 │  Event_Mapping__mdt: which events open a work order, priority, subject,
                 │                      after-hours-only rules (admin-editable, no code)
                 │  EntitlementResolver: Asset(Device_Id__c) ─▶ Service Contract ─▶ Entitlement
                 │  idempotency: unique WorkOrder.Source_Event_Id__c + one open WO per device/event type
                 ▼
          WorkOrder  (EntitlementId set, SlaStartDate = event time ─▶ milestones start)
                 ▼
          "Device Evidence" LWC on the Work Order: snapshot + WHEP live view, via Apex ─▶ relay ─▶ Ring
```

Ring blocks browser calls to `api.amazonvision.com` with CORS, so every Ring call goes server-to-server through the relay. The browser only carries the WebRTC media itself.

## Repository layout

| Path | What's there |
|---|---|
| `relay/` | Ring client (`src/ring/client.ts`), webhook signature check, event normalisation, dedupe, Salesforce publisher, Event History poller, emulator CLI, tests |
| `force-app/` | Unlocked package: `Device_Event__e`, `Event_Mapping__mdt` with default rules, Asset/WorkOrder fields, Apex service, resolver and tests, `deviceEvidence` LWC, permission sets |
| `scripts/apex/seed-demo.apex` | Demo account, asset, service contract and entitlement |
| `docs/setup.md` | Org, connected app, Named Credential and relay setup |
| `docs/demo.md` | The demo script, under 3 minutes |
| `docs/friction-log.md` | Platform friction, recorded as we go |

## Quick start: relay only

```bash
cd relay
npm install
cp .env.example .env          # set RING_WEBHOOK_SECRET and RELAY_API_TOKEN at minimum
npm test
RING_WEBHOOK_SECRET=demo RELAY_API_TOKEN=dev npm run dev
```

In another terminal, fire an emulated leak twice with the same event id. The first is queued, the second is reported as a duplicate:

```bash
cd relay
RING_WEBHOOK_SECRET=demo npm run emulate -- leak --device playground-doorbell-1 --event-id evt-42 --repeat 2
```

Without Salesforce credentials the relay logs the `Device_Event__e` it would have published. Add a Ring Playground token (`RING_ACCESS_TOKEN`) and the `/api/devices` route returns your live device list. Set `RING_POLL_INTERVAL_SECONDS` to feed Playground Event History into the pipeline.

## Full setup

See [docs/setup.md](docs/setup.md): Developer Edition org, entitlement process, JWT connected app, Named Credential, deploying the package, and running the relay on Lightsail.

## Relay API

| Route | Auth | Purpose |
|---|---|---|
| `POST /webhooks/ring` | `X-Signature: sha256=<hex HMAC of body>` | Ring webhooks (and the emulator). Always acks fast; publishing happens in the background. |
| `GET /api/devices` | `Authorization: Bearer $RELAY_API_TOKEN` | Live `GET /v1/devices` from Ring |
| `GET /api/devices/:id/events` | Bearer | Event History for a device |
| `GET /api/devices/:id/snapshot` | Bearer | Latest snapshot image |
| `POST /api/devices/:id/whep` | Bearer | SDP offer in, Ring's WHEP SDP answer out |
| `GET /healthz` | none | Liveness and queue depth |

## Being honest about emulated data

The Ring Playground exposes a simulated doorbell and live view, but it doesn't simulate sensors, and developers report that it sends no webhooks. FirstResponse therefore:

- makes **live** Playground calls for the device list, Event History, snapshot and live view;
- uses a **documented-schema emulator** (`npm run emulate`) for sensor and webhook events, which signs requests exactly as Ring does and tags them `Source__c = emulator` all the way into the Work Order description.

Emulated segments are labelled as such in the demo. The reasons are in the friction log.

## Status

This is the first cut. Things not verified against a live org or the Playground yet:

- the Apex hasn't been deployed or run in an org yet (it parses and is formatted, and its tests are written);
- `GET /v1/devices/{id}/media/image/download` (snapshot path) and the webhook envelope shape;
- whether WebRTC from the LWC to Ring's media servers is allowed by Lightning's CSP.

Planned next: an optional Bedrock summary of the event timeline in the Work Order description, a `ring-sandbox` PR adding sensor, `component_id` and lifecycle events, and battery/heartbeat monitoring as a Work Order source.

## License

[MIT](LICENSE)
