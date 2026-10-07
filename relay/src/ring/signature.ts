import { createHmac, timingSafeEqual } from "node:crypto";

const PREFIX = "sha256=";

/** Computes the X-Signature value Ring sends: "sha256=" + hex HMAC-SHA256 of the raw body. */
export function signPayload(secret: string, rawBody: Buffer | string): string {
  return PREFIX + createHmac("sha256", secret).update(rawBody).digest("hex");
}

/** Constant-time check of an X-Signature header against the raw request body. */
export function verifySignature(secret: string, rawBody: Buffer, header: string | undefined): boolean {
  if (!header) return false;
  const provided = header.trim().toLowerCase();
  const hex = provided.startsWith(PREFIX) ? provided.slice(PREFIX.length) : provided;
  if (!/^[0-9a-f]{64}$/.test(hex)) return false;

  const expected = createHmac("sha256", secret).update(rawBody).digest();
  return timingSafeEqual(expected, Buffer.from(hex, "hex"));
}
