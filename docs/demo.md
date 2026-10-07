# Demo script (under 3 minutes, browser footage only)

Open on a **live** Playground call. Label every emulated segment on screen.

| Time | Shot | What to run / show |
|---|---|---|
| 0:00 | Problem card | "Leak at 2 am. SLA breached by 9 am." |
| 0:15 | Ring Playground | Generate a token, run the device list in the API explorer. |
| 0:30 | Relay console | `curl -H "Authorization: Bearer $RELAY_API_TOKEN" $RELAY/api/devices`: a live `GET /v1/devices`. |
| 0:45 | **[Emulated]** leak | `npm run emulate -- leak --device <id> --event-id demo-leak-1 --url $RELAY`. The Work Order appears in Salesforce with the entitlement attached and the First Response milestone counting down from the event time. |
| 1:30 | **[Emulated]** duplicate | Run the same command again: the relay answers `duplicate` and no second Work Order appears. Then send a new event id: still one Work Order, because one is already open for that device and event type. |
| 1:50 | Evidence card | On the Work Order, click **Live view** (Playground live view via WHEP), then **Snapshot**. |
| 2:20 | Admin config | Setup → Custom Metadata → Event Mappings: change the priority, or turn on after-hours-only for a rule, with no code. |
| 2:40 | Open source | The `ring-sandbox` PR link and one friction-log highlight. |
