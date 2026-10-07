# Friction log

Platform friction hit while building FirstResponse, recorded as it happens. Each entry: what we tried, what happened, what we did about it, and what would have helped.

| Date | Area | What happened | Workaround | Suggestion |
|---|---|---|---|---|
| 2026-10-07 | Ring Playground | Developer reports say the Playground logs only `on_demand` events and sends no webhooks. To be confirmed in week 1. | Event History poller in the relay, plus a signed, documented-schema emulator for webhook and sensor events. | A Playground "send test webhook" button per event type. |
| 2026-10-07 | Ring sensors | Sensors and chimes are Early Access with no confirmed simulator, but they're the events facilities teams care about most (flood, freeze, tamper). | Emulator events, tagged `Source__c = emulator` end to end. | Simulated sensors in the Playground. |
| 2026-10-07 | Ring API / CORS | `api.amazonvision.com` blocks browser calls, so a Lightning component can't call Ring directly. | All Ring calls go through the relay; the LWC uses Apex → Named Credential → relay. | Call this out on the getting-started page. |
| 2026-10-07 | Ring webhooks | Webhook envelope schema isn't visible without a staging account, and staging needs US devices and a Ring Protection plan. | Normaliser accepts both a flat shape and a JSON:API shape. | Publish example payloads for every webhook type. |
| 2026-10-07 | Salesforce CLI in Codespaces | `sf org login web` needs a localhost callback that a Codespace doesn't have. | `sf org login device`. | — |
| 2026-10-07 | Codespaces | Forwarded ports are private by default, so incoming webhooks get a 401, and the URL dies after 30 minutes idle. | Port set to Public for testing; the relay runs on Lightsail for the demo. | — |
