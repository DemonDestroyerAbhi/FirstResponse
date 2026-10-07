# Setup

Everything here runs in a browser: GitHub Codespaces for the CLI, a free Salesforce Developer Edition org, the Ring Playground, and a $5 AWS Lightsail instance for the relay.

## 1. Codespace and Salesforce CLI

```bash
npm i -g @salesforce/cli
sf org login device --set-default-dev-hub --alias devhub
```

Use device login: `sf org login web` needs a localhost OAuth callback that doesn't exist in a Codespace.

Turn on Dev Hub in the Developer Edition org first (Setup → Dev Hub → Enable). Keep the Developer Edition org as the stable demo target, because scratch orgs expire.

## 2. Deploy the package source

```bash
sf project deploy start --target-org devhub
sf apex run test --target-org devhub --test-level RunLocalTests --wait 10
```

Or try it in a scratch org first:

```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias fr --duration-days 7
sf project deploy start --target-org fr
```

Assign the **FirstResponse User** permission set to yourself and anyone who works Work Orders.

## 3. Entitlements and milestones (manual, in Setup)

1. **Entitlement Settings**: enable Entitlement Management (on a scratch org, the definition file already does this).
2. **Milestones**: create milestone types, for example `First Response` and `Resolution`.
3. **Entitlement Processes**: create a process named **FirstResponse Work Order SLA** with type **Work Order**.
   - Add `First Response` with criteria such as `Work Order: Priority equals Critical`, 1 hour; and `Priority equals High`, 4 hours.
   - Add `Resolution` with a longer window.
   - Activate the process.
4. Add the **Milestones** related list (or the Milestone Tracker) to the Work Order page layout.

`DeviceEventService` sets `SlaStartDate` to the time the device reported the event, so a leak at 2:00 am is late at 3:00 am even if the record was opened later.

## 4. Demo data

Edit `DEVICE_ID` in `scripts/apex/seed-demo.apex` to the device id from the Playground device list (or the id you'll pass to the emulator), then run:

```bash
sf apex run --file scripts/apex/seed-demo.apex --target-org devhub
```

## 5. Integration user and connected app (relay → Salesforce)

The relay publishes `Device_Event__e` with the OAuth 2.0 JWT bearer flow.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout firstresponse.key -out firstresponse.crt -subj "/CN=FirstResponse relay"
```

1. Create a dedicated integration user (Salesforce Integration licence or a standard user) and assign the **FirstResponse Integration** permission set.
2. Setup → App Manager → New Connected App:
   - Enable OAuth, callback `http://localhost` (unused), **Use digital signatures** → upload `firstresponse.crt`.
   - Scopes: `api`, `refresh_token offline_access`.
3. Manage → Edit Policies → **Admin approved users are pre-authorized**, then add the integration user's profile or permission set.
4. Put the consumer key and username in the relay's environment (`SF_CLIENT_ID`, `SF_USERNAME`) and the private key in `SF_PRIVATE_KEY` (newlines as `\n`) or `SF_PRIVATE_KEY_PATH`. Never commit the key.

Optional: platform event triggers run as the Automated Process user. To have Work Orders created by a named user instead, deploy a `PlatformEventSubscriberConfig` for `DeviceEventTrigger`.

## 6. Named Credential (Salesforce → relay)

The Device Evidence card calls the relay through `callout:FirstResponse_Relay`.

1. Setup → Named Credentials → **External Credentials** → New: label `FirstResponse Relay`, name `FirstResponse_Relay`, authentication protocol **Custom**.
   - Add a principal (for example `Relay`) with an authentication parameter `Token` = the relay's `RELAY_API_TOKEN`.
   - Add a custom header `Authorization` with value `{!'Bearer ' & $Credential.FirstResponse_Relay.Token}`.
2. **Named Credentials** → New: name `FirstResponse_Relay`, URL = the relay's public URL (for example `https://relay.example.com`), external credential `FirstResponse Relay`, and turn on **Allow formulas in HTTP header**.
3. In the **FirstResponse User** permission set, add **External Credential Principal Access** for the `Relay` principal.

## 7. Work Order page

Lightning App Builder → Work Order record page → drag **Device Evidence** onto the page → Save and activate.

## 8. Relay on Lightsail

Codespaces stops after 30 minutes idle and its forwarded URL dies with it, so run the relay on Lightsail for anything you record.

```bash
# On a Lightsail Node 20 instance (browser SSH)
git clone https://github.com/DemonDestroyerAbhi/FirstResponse.git
cd FirstResponse/relay
npm ci && npm run build
cp .env.example .env   # fill in, then:
set -a; . ./.env; set +a
node dist/server.js
```

Put it behind HTTPS (for example a Lightsail load balancer or Caddy) before pointing the Named Credential at it. If you test from a Codespace instead, forward port 3000 and set its visibility to **Public**, or incoming webhook POSTs get a 401 from the Codespaces proxy.

## 9. Ring Playground

Generate a token in the Playground (it lasts 30 minutes), set `RING_ACCESS_TOKEN`, and restart the relay or re-export the variable. `GET /api/devices` with the relay token should now return the simulated doorbell. Set `RING_POLL_INTERVAL_SECONDS=15` to feed Event History into the pipeline.

## 10. Package versions

The package is **Unlocked with no namespace**: Apex stays readable (needed for the Open Source entry), and installs are versioned and repeatable. Don't put "Ring" in the package or app name; it's an Amazon trademark.

```bash
sf package create --name FirstResponse --package-type Unlocked --path force-app --no-namespace \
  --description "Device events to entitlement-checked Service Cloud work orders" --target-dev-hub devhub
sf package version create --package FirstResponse --installation-key-bypass --code-coverage --wait 30
```
