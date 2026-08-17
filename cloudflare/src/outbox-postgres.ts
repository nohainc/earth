import type { PostgresRepository } from './repository';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';

export type OutboxEvent = {
  id: string;
  event_key: string;
  topic: string;
  aggregate_type: string;
  aggregate_id: string;
  payload: Record<string, unknown>;
  attempts: number;
};

export type OutboxMetrics = {
  pendingCount: number;
  retryCount: number;
  staleLocksCount: number;
  deadLetterCount: number;
  oldestPendingAgeSeconds: number | null;
  lastSuccessfulDeliveryAt: string | null;
};

export async function enqueueOutbox(
  repository: PostgresRepository,
  input: { eventKey: string; topic: string; aggregateType: string; aggregateId: string; payload: Record<string, unknown> },
): Promise<void> {
  await repository.query(
    `INSERT INTO event_outbox (id, event_key, topic, aggregate_type, aggregate_id, payload)
     VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (event_key) DO NOTHING`,
    [crypto.randomUUID(), input.eventKey, input.topic, input.aggregateType, input.aggregateId, toNanoMarkup(input.payload)],
  );
}

export async function getOutboxMetrics(repository: PostgresRepository): Promise<OutboxMetrics> {
  const [metrics, lastDelivery] = await Promise.all([
    repository.query<{
      pending_count: string;
      retry_count: string;
      stale_locks_count: string;
      dead_letter_count: string;
      oldest_pending_age: string | null;
    }>(`
      SELECT
        COUNT(*) FILTER (WHERE processed_at IS NULL)::text AS pending_count,
        COUNT(*) FILTER (WHERE processed_at IS NULL AND attempts > 0)::text AS retry_count,
        COUNT(*) FILTER (WHERE processed_at IS NULL AND locked_at IS NOT NULL AND locked_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes')::text AS stale_locks_count,
        COUNT(*) FILTER (WHERE last_error LIKE 'DEAD_LETTER%')::text AS dead_letter_count,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MIN(created_at) FILTER (WHERE processed_at IS NULL)))::text AS oldest_pending_age
      FROM event_outbox
    `),
    repository.query<{ last_delivery: string }>(`
      SELECT MAX(processed_at)::text AS last_delivery FROM event_outbox WHERE processed_at IS NOT NULL
    `),
  ]);

  const row = metrics.rows[0];
  return {
    pendingCount: Number(row?.pending_count ?? 0),
    retryCount: Number(row?.retry_count ?? 0),
    staleLocksCount: Number(row?.stale_locks_count ?? 0),
    deadLetterCount: Number(row?.dead_letter_count ?? 0),
    oldestPendingAgeSeconds: row?.oldest_pending_age != null ? Number(row.oldest_pending_age) : null,
    lastSuccessfulDeliveryAt: lastDelivery.rows[0]?.last_delivery ?? null,
  };
}

export async function deliverOutbox(
  repository: PostgresRepository,
  publish: (event: OutboxEvent) => Promise<void>,
  limit = 50,
  maxAttempts = 5,
): Promise<number> {
  const claimed = await repository.transaction(async (tx) => {
    // Reclaim stale locks older than 5 minutes
    await tx.query(
      `UPDATE event_outbox
       SET locked_at = NULL
       WHERE processed_at IS NULL AND locked_at IS NOT NULL AND locked_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes'`,
    );

    const result = await tx.query<OutboxEvent>(
      `SELECT id, event_key, topic, aggregate_type, aggregate_id, payload, attempts
       FROM event_outbox
       WHERE processed_at IS NULL
         AND available_at <= CURRENT_TIMESTAMP
         AND (locked_at IS NULL OR locked_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes')
       ORDER BY created_at ASC, id ASC
       LIMIT $1 FOR UPDATE SKIP LOCKED`,
      [limit],
    );
    for (const event of result.rows) {
      if (typeof event.payload === 'string') {
        try {
          event.payload = fromNanoMarkup<Record<string, unknown>>(event.payload);
        } catch {
          try { event.payload = JSON.parse(event.payload); } catch { event.payload = {}; }
        }
      }
      await tx.query(
        'UPDATE event_outbox SET locked_at = CURRENT_TIMESTAMP, attempts = attempts + 1 WHERE id = $1',
        [event.id],
      );
    }
    return result.rows;
  });

  let delivered = 0;
  for (const event of claimed) {
    try {
      await publish(event);
      await repository.query(
        'UPDATE event_outbox SET processed_at = CURRENT_TIMESTAMP, locked_at = NULL, last_error = NULL WHERE id = $1 AND processed_at IS NULL',
        [event.id],
      );
      delivered += 1;
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 500) : 'Outbox delivery failed';
      if (event.attempts >= maxAttempts) {
        // Quarantine in dead-letter state to prevent blocking newer events
        await repository.query(
          `UPDATE event_outbox SET locked_at = NULL, processed_at = CURRENT_TIMESTAMP, last_error = $2 WHERE id = $1 AND processed_at IS NULL`,
          [event.id, `DEAD_LETTER: ${message}`],
        );
      } else {
        await repository.query(
          `UPDATE event_outbox SET locked_at = NULL, available_at = CURRENT_TIMESTAMP + INTERVAL '30 seconds', last_error = $2 WHERE id = $1 AND processed_at IS NULL`,
          [event.id, message],
        );
      }
    }
  }
  return delivered;
}
