import { createSign } from "node:crypto";
import type { SalesforceConfig } from "../config.js";
import type { EventSink } from "../events/dispatcher.js";
import type { DeviceEvent } from "../events/types.js";
import type { FetchFn } from "../ring/client.js";

interface AccessToken {
  accessToken: string;
  instanceUrl: string;
}

/** Long Text Area limit on Device_Event__e.Payload__c. */
const PAYLOAD_LIMIT = 32_000;

const base64url = (input: Buffer | string) => Buffer.from(input).toString("base64url");

/** Builds the signed assertion for the OAuth 2.0 JWT bearer flow. */
export function buildJwtAssertion(cfg: SalesforceConfig, nowSeconds = Math.floor(Date.now() / 1000)): string {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(
    JSON.stringify({ iss: cfg.clientId, sub: cfg.username, aud: cfg.loginUrl, exp: nowSeconds + 180 }),
  );
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${claims}`);
  return `${header}.${claims}.${base64url(signer.sign(cfg.privateKey))}`;
}

/** Maps a DeviceEvent to Device_Event__e fields. */
export function toPlatformEvent(event: DeviceEvent): Record<string, string | null> {
  let payload = JSON.stringify(event.raw);
  if (payload.length > PAYLOAD_LIMIT) payload = payload.slice(0, PAYLOAD_LIMIT);
  return {
    Event_Id__c: event.eventId,
    Device_Id__c: event.deviceId,
    Event_Type__c: event.eventType,
    Sub_Type__c: event.subType ?? null,
    Component_Id__c: event.componentId ?? null,
    Location_Id__c: event.locationId ?? null,
    Occurred_At__c: event.occurredAt,
    Source__c: event.source,
    Payload__c: payload,
  };
}

/** Publishes events to Salesforce as Device_Event__e using a JWT-bearer connected app. */
export class SalesforcePublisher implements EventSink {
  private token: AccessToken | undefined;
  private readonly fetchFn: FetchFn;

  constructor(
    private readonly cfg: SalesforceConfig,
    fetchFn?: FetchFn,
  ) {
    this.fetchFn = fetchFn ?? fetch;
  }

  async publish(event: DeviceEvent): Promise<void> {
    const body = JSON.stringify(toPlatformEvent(event));
    let res = await this.post(body);
    if (res.status === 401) {
      // Session expired or revoked: get a fresh token once.
      this.token = undefined;
      res = await this.post(body);
    }
    if (!res.ok) throw new Error(`Salesforce publish failed ${res.status}: ${(await res.text()).slice(0, 300)}`);

    const result = (await res.json()) as { success?: boolean; errors?: unknown[] };
    if (result.success === false) throw new Error(`Salesforce rejected event: ${JSON.stringify(result.errors)}`);
  }

  private async post(body: string): Promise<Response> {
    const { accessToken, instanceUrl } = await this.getToken();
    return this.fetchFn(`${instanceUrl}/services/data/v${this.cfg.apiVersion}/sobjects/Device_Event__e/`, {
      method: "POST",
      headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body,
    });
  }

  private async getToken(): Promise<AccessToken> {
    if (this.token) return this.token;

    const res = await this.fetchFn(`${this.cfg.loginUrl}/services/oauth2/token`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: buildJwtAssertion(this.cfg),
      }),
    });
    if (!res.ok) throw new Error(`Salesforce JWT login failed ${res.status}: ${(await res.text()).slice(0, 300)}`);

    const json = (await res.json()) as { access_token: string; instance_url: string };
    this.token = { accessToken: json.access_token, instanceUrl: json.instance_url };
    return this.token;
  }
}

/** Used when Salesforce isn't configured, so the relay can still be exercised locally. */
export class LoggingSink implements EventSink {
  constructor(private readonly log: { info(obj: object, msg?: string): void }) {}

  async publish(event: DeviceEvent): Promise<void> {
    this.log.info({ platformEvent: toPlatformEvent(event) }, "Salesforce not configured; would publish Device_Event__e");
  }
}
