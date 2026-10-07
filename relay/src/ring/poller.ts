import type { EventDispatcher, Logger } from "../events/dispatcher.js";
import { normalizeEvent } from "../events/normalize.js";
import type { RingClient } from "./client.js";

/**
 * Polls Event History for every device and feeds new events to the dispatcher.
 *
 * The Playground sends no webhooks, so this is how live Ring data reaches Salesforce during
 * the demo. The dispatcher's dedupe makes repeated polls of the same history harmless.
 */
export class HistoryPoller {
  private timer: NodeJS.Timeout | undefined;
  private running = false;

  constructor(
    private readonly ring: RingClient,
    private readonly dispatcher: EventDispatcher,
    private readonly log: Logger,
    private readonly intervalMs: number,
  ) {}

  start(): void {
    if (this.timer || this.intervalMs <= 0) return;
    this.timer = setInterval(() => void this.pollOnce(), this.intervalMs);
    void this.pollOnce();
  }

  stop(): void {
    clearInterval(this.timer);
    this.timer = undefined;
  }

  /** Returns how many new events were queued. */
  async pollOnce(): Promise<number> {
    if (this.running) return 0;
    this.running = true;
    let queued = 0;
    try {
      for (const device of await this.ring.listDevices()) {
        for (const item of await this.ring.listDeviceEvents(device.id)) {
          const event = normalizeEvent({ device_id: device.id, ...item, ...item.attributes }, "history");
          if (event && this.dispatcher.accept(event) === "queued") queued++;
        }
      }
    } catch (err) {
      this.log.warn({ err: String(err) }, "history poll failed");
    } finally {
      this.running = false;
    }
    return queued;
  }
}
