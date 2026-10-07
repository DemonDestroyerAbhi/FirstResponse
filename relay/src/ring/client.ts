/**
 * Server-side client for the Ring partner API (api.amazonvision.com, JSON:API, Bearer auth).
 *
 * Ring blocks browser calls to this host via CORS, so every call goes through the relay;
 * Salesforce (Apex / LWC) only ever talks to the relay.
 *
 * Endpoint paths marked "verify" come from developer reports rather than a confirmed
 * response and should be checked against the Playground before the demo.
 */

export interface RingDevice {
  id: string;
  type: string;
  attributes: Record<string, unknown>;
  relationships?: Record<string, unknown>;
}

export interface RingHistoryEvent {
  id: string;
  type: string;
  attributes: Record<string, unknown>;
}

export class RingApiError extends Error {
  constructor(
    readonly status: number,
    readonly path: string,
    readonly body: string,
  ) {
    super(`Ring API ${status} on ${path}: ${body.slice(0, 200)}`);
  }
}

export type FetchFn = typeof fetch;

export interface RingClientOptions {
  apiBase: string;
  /** Returns the current access token (Playground tokens expire after 30 minutes). */
  getToken: () => string | undefined | Promise<string | undefined>;
  fetchFn?: FetchFn;
  /** Max retries on 429 / 5xx. */
  maxRetries?: number;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export class RingClient {
  private readonly fetchFn: FetchFn;
  private readonly maxRetries: number;

  constructor(private readonly opts: RingClientOptions) {
    this.fetchFn = opts.fetchFn ?? fetch;
    this.maxRetries = opts.maxRetries ?? 3;
  }

  /** GET /v1/devices with status, capabilities, location and configurations included. */
  async listDevices(): Promise<RingDevice[]> {
    const res = await this.request("/v1/devices?include=status,capabilities,location,configurations");
    const body = (await res.json()) as { data?: RingDevice[] };
    return body.data ?? [];
  }

  /** GET /v1/devices/{id}/status — battery_status.percentage lives here (Ring sends no battery webhook). */
  async getDeviceStatus(deviceId: string): Promise<Record<string, unknown>> {
    const res = await this.request(`/v1/devices/${encodeURIComponent(deviceId)}/status`);
    return (await res.json()) as Record<string, unknown>;
  }

  /** GET /v1/history/devices/{id}/events. Device-level only; there is no component filter. */
  async listDeviceEvents(deviceId: string): Promise<RingHistoryEvent[]> {
    const res = await this.request(`/v1/history/devices/${encodeURIComponent(deviceId)}/events`);
    const body = (await res.json()) as { data?: RingHistoryEvent[] };
    return body.data ?? [];
  }

  /**
   * Latest snapshot as JPEG/PNG bytes. Verify: Playground image download has been reported
   * to return HTTP 416; fall back to a frame captured from the WHEP live view.
   */
  async getSnapshot(deviceId: string): Promise<{ contentType: string; body: Buffer }> {
    const res = await this.request(`/v1/devices/${encodeURIComponent(deviceId)}/media/image/download`, {
      headers: { accept: "image/jpeg, image/png" },
    });
    return {
      contentType: res.headers.get("content-type") ?? "image/jpeg",
      body: Buffer.from(await res.arrayBuffer()),
    };
  }

  /**
   * Starts a WHEP live-view session: POSTs an SDP offer and returns the SDP answer plus the
   * session resource URL (used to tear the session down).
   */
  async startWhepSession(deviceId: string, sdpOffer: string): Promise<{ sdpAnswer: string; location?: string }> {
    const res = await this.request(`/v1/devices/${encodeURIComponent(deviceId)}/media/streaming/whep/sessions`, {
      method: "POST",
      headers: { "content-type": "application/sdp", accept: "application/sdp" },
      body: sdpOffer,
    });
    return { sdpAnswer: await res.text(), location: res.headers.get("location") ?? undefined };
  }

  private async request(path: string, init: RequestInit = {}): Promise<Response> {
    const token = await this.opts.getToken();
    if (!token) throw new Error("RING_ACCESS_TOKEN is not set");

    for (let attempt = 0; ; attempt++) {
      const res = await this.fetchFn(`${this.opts.apiBase}${path}`, {
        ...init,
        headers: {
          accept: "application/vnd.api+json, application/json",
          ...init.headers,
          authorization: `Bearer ${token}`,
        },
      });
      if (res.ok) return res;

      const retryable = res.status === 429 || res.status >= 500;
      if (!retryable || attempt >= this.maxRetries) {
        throw new RingApiError(res.status, path, await res.text());
      }
      // Partner budget is 100 TPS; honour Retry-After, otherwise back off exponentially.
      const retryAfter = Number(res.headers.get("retry-after"));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 250 * 2 ** attempt);
    }
  }
}
