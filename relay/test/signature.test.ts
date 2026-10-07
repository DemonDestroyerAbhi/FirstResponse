import { describe, expect, it } from "vitest";
import { signPayload, verifySignature } from "../src/ring/signature.js";

describe("webhook signature", () => {
  const secret = "s3cret";
  const body = Buffer.from('{"id":"e1"}');

  it("accepts a correct sha256= signature", () => {
    expect(verifySignature(secret, body, signPayload(secret, body))).toBe(true);
  });

  it("accepts a bare hex signature", () => {
    expect(verifySignature(secret, body, signPayload(secret, body).slice(7))).toBe(true);
  });

  it("rejects a wrong secret, a tampered body, and garbage", () => {
    expect(verifySignature(secret, body, signPayload("other", body))).toBe(false);
    expect(verifySignature(secret, Buffer.from('{"id":"e2"}'), signPayload(secret, body))).toBe(false);
    expect(verifySignature(secret, body, "sha256=nothex")).toBe(false);
    expect(verifySignature(secret, body, undefined)).toBe(false);
  });
});
