/**
 * Remembers recently seen event ids so retried webhooks and overlapping history polls don't
 * publish twice. This is only the first line of defence: Salesforce enforces idempotency
 * with a unique external id on WorkOrder, which survives relay restarts.
 */
export class RecentIds {
  private readonly seen = new Map<string, number>();

  constructor(
    private readonly ttlMs = 24 * 60 * 60 * 1000,
    private readonly maxSize = 50_000,
    private readonly now: () => number = Date.now,
  ) {}

  /** Returns true the first time an id is seen within the TTL, false for repeats. */
  add(id: string): boolean {
    const t = this.now();
    const expiresAt = this.seen.get(id);
    if (expiresAt !== undefined && expiresAt > t) return false;

    this.seen.delete(id);
    this.seen.set(id, t + this.ttlMs);
    this.evict(t);
    return true;
  }

  /** Forget an id, e.g. when publishing failed and the event should be accepted again. */
  remove(id: string): void {
    this.seen.delete(id);
  }

  get size(): number {
    return this.seen.size;
  }

  private evict(t: number): void {
    // Map iterates in insertion order, so the oldest entries come first.
    for (const [id, expiresAt] of this.seen) {
      if (this.seen.size <= this.maxSize && expiresAt > t) break;
      this.seen.delete(id);
    }
  }
}
