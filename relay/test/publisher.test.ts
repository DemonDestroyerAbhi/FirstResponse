import { generateKeyPairSync, createVerify } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildJwtAssertion, SalesforcePublisher } from "../src/salesforce/publisher.js";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const cfg = {
  loginUrl: "https://login.salesforce.com",
  clientId: "client",
  username: "integration@firstresponse.dev",
  privateKey: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
  apiVersion: "62.0",
};

describe("buildJwtAssertion", () => {
  it("produces an RS256 JWT with the bearer-flow claims", () => {
    const [header, claims, signature] = buildJwtAssertion(cfg, 1000).split(".");
    expect(JSON.parse(Buffer.from(claims!, "base64url").toString())).toEqual({
      iss: "client",
      sub: "integration@firstresponse.dev",
      aud: "https://login.salesforce.com",
      exp: 1180,
    });
    const verifier = createVerify("RSA-SHA256");
    verifier.update(`${header}.${claims}`);
    expect(verifier.verify(publicKey, Buffer.from(signature!, "base64url"))).toBe(true);
  });
});

describe("SalesforcePublisher", () => {
  it("logs in once, publishes Device_Event__e, and re-authenticates on 401", async () => {
    const requests: string[] = [];
    let publishes = 0;
    const fetchFn = (async (url: string, init?: RequestInit) => {
      requests.push(url);
      if (url.endsWith("/services/oauth2/token")) {
        return Response.json({ access_token: "tok", instance_url: "https://acme.my.salesforce.com" });
      }
      publishes++;
      if (publishes === 2) return new Response("expired", { status: 401 });
      expect(JSON.parse(String(init?.body))).toMatchObject({ Event_Id__c: "e1", Event_Type__c: "flood_detected" });
      return Response.json({ success: true });
    }) as typeof fetch;

    const publisher = new SalesforcePublisher(cfg, fetchFn);
    const event = {
      eventId: "e1",
      deviceId: "d1",
      eventType: "flood_detected",
      occurredAt: "2026-10-07T02:00:00.000Z",
      source: "emulator" as const,
      raw: {},
    };
    await publisher.publish(event);
    await publisher.publish(event);

    expect(requests.filter((u) => u.endsWith("/token"))).toHaveLength(2);
    expect(requests).toContain("https://acme.my.salesforce.com/services/data/v62.0/sobjects/Device_Event__e/");
  });
});
