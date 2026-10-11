# FirstResponse — context for Claude Code

Hackathon entry (Devpost "Build, Ship, Shape"). Ring device and sensor events become entitlement-checked Salesforce Service Cloud Work Orders, with SLA milestones counting from the moment the device reported the problem.

- **Deadline:** Fri 23 Oct 2026, 12:00pm PDT
- **Track:** Ring ($12k 1st / $8k 2nd). **Mini challenge:** Open Source (primary, $5k + $5k AWS credits); AWS Builder is a possible secondary, via Bedrock.
- **Customer:** facilities / AMC providers servicing multi-site retail, clinics and property portfolios. Today a leak or an offline camera becomes a phone call, a spreadsheet row and a missed SLA.
- **Origin:** a research brief ranked this idea #1 (working names "ServiceTrigger", then "Latch") out of 22 Ring and Alexa+ ideas; the runner-up was "Dispatch", an Alexa+ field-service scheduling MCP server. The user renamed it FirstResponse. The original brief and PDF are not in the repo.
- **Builder:** solo, working evenings with no laptop (GitHub Codespaces + a Salesforce Developer Edition org + the Ring Playground + an AWS Lightsail relay), based in India, with no Ring hardware.

## Hard constraints (don't break these)

- **No Field Service.** FSL and `ServiceAppointment` / `ServiceResource` / `WorkType` need licences a free DE org doesn't have. Use core `WorkOrder` (it has `EntitlementId`). Say "Service Cloud Work Orders with entitlement-driven SLA milestones", never "Field Service work orders".
- **Ring is server-to-server only.** `api.amazonvision.com` blocks browser calls via CORS. The LWC never calls Ring; it goes LWC → Apex → Named Credential → relay → Ring.
- **No "Ring" in package, app or metadata names** (Amazon trademark). That's why the platform event is `Device_Event__e`, not `Ring_Event__e`.
- **Unlocked package, no namespace.** Managed would obfuscate Apex (killing the Open Source entry) and make the namespace permanent.
- **Stage-1 gate:** the repo must actually call the Ring API at runtime (`relay/src/ring/client.ts`) and show the project working through a simulator or a real device.
- **Be honest about emulated data.** The Playground exposes only a fake Doorbell Pro, reportedly logs only `on_demand` events, and sends no webhooks; sensors and chimes are Early Access with no simulator. Open the demo on live Playground calls and label emulated segments on screen. Emulated events carry `Source__c = emulator` end to end.
- **Staging webhooks are unavailable to us:** staging needs US devices and a Ring Protection plan.

## Architecture

```
Ring event ─▶ relay/ (Node 20, TypeScript, Fastify)
               POST /webhooks/ring: verify X-Signature (sha256=<hex HMAC>), 200 within 5s,
               dedupe by event id (RecentIds), publish in background with retry (EventDispatcher)
               HistoryPoller: Playground Event History → same pipeline (no webhooks there)
               Emulator CLI: signed sensor/webhook events (npm run emulate)
        ─▶ Salesforce REST, JWT-bearer connected app → Device_Event__e (platform event)
        ─▶ DeviceEventTrigger → DeviceEventService
               rules: Event_Mapping__mdt (type, optional sub type, priority, subject template,
                      outside-business-hours-only), editable by admins without code
               idempotency: unique WorkOrder.Source_Event_Id__c, dedupe within a batch,
                      and at most one open WO per device + event type
               EntitlementResolver: Asset.Device_Id__c → asset entitlement → contract line item
                      → service contract entitlement → account-level entitlement
               WorkOrder: EntitlementId, ServiceContractId, SlaStartDate = event time
        ─▶ deviceEvidence LWC on the Work Order: snapshot + WHEP live view via EvidenceController
               (callout:FirstResponse_Relay → relay /api/devices/:id/{snapshot,whep}, bearer RELAY_API_TOKEN)
```

## Repo map

- `relay/src/ring/client.ts`: Ring API client (devices, status, history, snapshot, WHEP) with 429/5xx backoff that honours Retry-After
- `relay/src/ring/signature.ts`: HMAC sign/verify · `relay/src/ring/poller.ts`: Event History poller
- `relay/src/events/`: `normalize.ts` (accepts both flat and JSON:API envelopes), `dedupe.ts`, `dispatcher.ts`, `types.ts` (known event types)
- `relay/src/salesforce/publisher.ts`: JWT assertion, token cache, re-login on 401, `LoggingSink` when Salesforce isn't configured
- `relay/src/app.ts` (routes) · `relay/src/server.ts` (wiring) · `relay/src/config.ts` (env, see `relay/.env.example`)
- `relay/src/emulator/`: scenarios `leak`, `freeze`, `after-hours-intruder`, `camera-offline`, `tamper`, `fridge-warm`
- `force-app/main/default/`: `Device_Event__e`, `Event_Mapping__mdt` + 7 default rule records, Asset/WorkOrder fields, Apex classes and tests, trigger, `deviceEvidence` LWC, permission sets `FirstResponse_Integration` and `FirstResponse_User`
- `scripts/apex/seed-demo.apex`: demo account, asset, contract and entitlement
- `docs/setup.md` (org, entitlements, connected app, Named Credential, Lightsail), `docs/demo.md` (3-minute script), `docs/friction-log.md` (keep adding to it; worth up to a 10% judging bonus)

## Commands

```bash
cd relay && npm ci && npm test && npm run typecheck      # 18 vitest tests
RING_WEBHOOK_SECRET=demo RELAY_API_TOKEN=dev npm run dev
RING_WEBHOOK_SECRET=demo npm run emulate -- leak --device <id> --event-id evt-1 --repeat 2
npm ci && npm run prettier:verify                         # repo root: Apex/LWC formatting (prettier-plugin-apex)
sf project deploy start --target-org devhub
sf apex run test --target-org devhub --test-level RunLocalTests --wait 10
```

CI (`.github/workflows/ci.yml`) runs the relay typecheck and tests, plus the prettier check.

## State as of 11 Oct 2026

- All work is on branch `claude/adoring-babbage-kwwis5`, pushed, one build commit on top of `main`. No PR yet.
- The relay is tested: unit tests pass, and a local end-to-end run (emulated leak twice) showed one publish and one duplicate.
- **The Salesforce side has never been deployed or run.** Apex parses and is prettier-formatted, and the XML is well-formed, but no org was available. Expect fixes on first deploy. Field-level things to double-check: `WorkOrder.SlaStartDate` and `IsClosed` access, platform-event field metadata, and in-memory `Event_Mapping__mdt` construction in tests.
- `DeviceEventServiceTest.publishedEventOpensEntitledWorkOrder` deliberately uses the packaged `Flood_Detected` mapping record, because static test overrides don't reach the platform-event trigger's context.

### Departures from the brief

- The brief planned record-triggered Flow → Apex. The build uses an Apex trigger plus `Event_Mapping__mdt` for admin config. Demo step 7 shows the metadata records instead of Flow Builder, unless a platform-event Flow calling an invocable is added.
- The platform event is `Device_Event__e` (brief: `Ring_Event__e`).

### Unverified assumptions (check against the live Playground)

- The snapshot path `GET /v1/devices/{id}/media/image/download` is a guess; Playground image download has been reported to return HTTP 416. Fallback: capture a frame from the WHEP live view.
- The webhook envelope shape is unknown, so the normaliser accepts flat and JSON:API shapes.
- Whether Event History on the Playground really returns only `on_demand` events.
- Whether Lightning CSP allows the LWC's WebRTC connection to Ring's media servers.
- The zone geometry in `/configurations`, and RTSP reachability from a cloud box.
- The platform-event delivery allocation in DE/scratch orgs (check it before claiming throughput).

## Pending

**Needs the user (accounts and manual setup):**
1. Request the hackathon's $150 AWS credits. **The form closes 21 Oct.**
2. Deploy to the Developer Edition org, run the Apex tests, and fix failures (`docs/setup.md` §1–2).
3. Manual Setup: enable Entitlement Management, create milestone types, and create an active entitlement process named exactly **"FirstResponse Work Order SLA"** (type Work Order); then create the integration user, the JWT connected app (`api`, `refresh_token offline_access`, admin pre-authorised), and the `FirstResponse_Relay` External and Named Credential; and add the Device Evidence card to the Work Order page (§3–7).
4. Run the relay on Lightsail behind HTTPS (§8). Codespaces URLs die after 30 minutes idle, and forwarded ports must be set to Public.
5. Make the repo public, with the MIT licence visible in the About section.

**Code still to build:**
- A PR to the community `ring-sandbox` repo adding sensor, `component_id` and lifecycle events. **This is the Open Source mini entry.** Contribute to it rather than building another emulator, because that space is saturated.
- Optional: a Bedrock summary of the event timeline into the WorkOrder description, which also unlocks AWS Builder. Label it "AI-drafted".
- Battery and heartbeat monitoring as a WorkOrder source ("FleetPulse" fold-in): poll `battery_status.percentage` (Ring sends no battery webhook); `device_online` acts as a heartbeat, and `device_offline` lags.
- Deletion and lifecycle handling for `app_integration_removed` and `device_removed`, plus TAKE/E2EE awareness ("Revoke" fold-in), for certification credibility.
- Optional: a platform-event Flow calling an invocable wrapper of `DeviceEventService`, to match the Flow Builder demo shot.
- Kiro specs, if pursuing AWS Builder.

**Submission (Devpost):** a demo video under 3 minutes, public, in English, browser footage only (script in `docs/demo.md`); product feedback for every tool, API and SDK used; the friction log; a statement of what was built during the hackathon window; and a PR to merge this branch into `main`.

## Useful platform facts

- Ring REST: JSON:API, Bearer token, 100 TPS per partner. Playground tokens last 30 minutes.
- There are 10 webhook types (motion_detected, button_press, device_added/removed, device_online/offline, app_integration_added/removed, subscription_activated/deactivated). Webhooks carry an HMAC-SHA256 `X-Signature` and must get a 200 within 5 seconds.
- `motion_detected.sub_type` is one of `motion`, `human`, `vehicle`, `package_delivery`, `other_motion`.
- Sensor events: `flood_detected/cleared`, `freeze_detected/cleared` (fixed at 40°F / 4°C), `contact_sensor_faulted/cleared`, `tamper_detected/cleared`, temperature and humidity exceeded/cleared, `pm25_exceeded/cleared`, `co_exceeded/cleared`. Device type can't be inferred from capabilities, so a setup-time mapping is needed.
- Media carries a mandatory server-side watermark (since 8 Jun 2026). TAKE devices return encrypted video; E2EE devices are invisible to the API.
- Salesforce CLI in Codespaces: use `sf org login device`, because `login web` needs a localhost callback.
- Pitch evidence: per Triple-I's ISO/Verisk data, water damage and freezing caused 22.6% of homeowners losses in 2023, and averaged $15,400 per claim over 2019–2023. Quote Triple-I's figures, not the older $13,954.
