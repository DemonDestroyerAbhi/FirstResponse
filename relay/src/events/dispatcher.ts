import { RecentIds } from "./dedupe.js";
import type { DeviceEvent } from "./types.js";

export interface EventSink {
  publish(event: DeviceEvent): Promise<void>;
}

export interface Logger {
  info(obj: object, msg?: string): void;
  warn(obj: object, msg?: string): void;
  error(obj: object, msg?: string): void;
}

export type AcceptResult = "queued" | "duplicate";

/**
 * Accepts events, drops duplicates, and publishes them in the background so the webhook
 * handler can acknowledge Ring within its 5-second window.
 *
 * The queue is in memory: a relay crash loses events that haven't been published yet.
 * That's acceptable for the demo; production would put a durable queue (e.g. SQS) here.
 */
export class EventDispatcher {
  private readonly queue: DeviceEvent[] = [];
  private draining: Promise<void> | undefined;

  constructor(
    private readonly sink: EventSink,
    private readonly log: Logger,
    private readonly recent = new RecentIds(),
    private readonly retryDelaysMs = [500, 2_000, 8_000],
  ) {}

  accept(event: DeviceEvent): AcceptResult {
    if (!this.recent.add(event.eventId)) return "duplicate";
    this.queue.push(event);
    this.draining ??= this.drain().finally(() => {
      this.draining = undefined;
    });
    return "queued";
  }

  /** Resolves once everything queued so far has been handled. */
  async idle(): Promise<void> {
    while (this.draining) await this.draining;
  }

  get pending(): number {
    return this.queue.length;
  }

  private async drain(): Promise<void> {
    for (let event = this.queue.shift(); event; event = this.queue.shift()) {
      await this.publishWithRetry(event);
    }
  }

  private async publishWithRetry(event: DeviceEvent): Promise<void> {
    for (let attempt = 0; ; attempt++) {
      try {
        await this.sink.publish(event);
        this.log.info({ eventId: event.eventId, eventType: event.eventType, deviceId: event.deviceId }, "event published");
        return;
      } catch (err) {
        const delay = this.retryDelaysMs[attempt];
        if (delay === undefined) {
          // Let a later redelivery of the same event through.
          this.recent.remove(event.eventId);
          this.log.error({ eventId: event.eventId, err: String(err) }, "event dropped after retries");
          return;
        }
        this.log.warn({ eventId: event.eventId, attempt, err: String(err) }, "publish failed, retrying");
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
}
