import type { PostgresRepository } from './repository';

type OutboxEvent = {
  id: string;
  event_key: string;
  topic: string;
  aggregate_type: string;
  aggregate_id: string;
  payload: Record<string, unknown>;
  attempts: number;
};

export async function enqueueOutbox(
  repository: PostgresRepository,
  input: { eventKey: string; topic: string; aggregateType: string; aggregateId: string; payload: Record<string, unknown> },
): Promise<void> {
  await repository.query(
    `INSERT INTO event_outbox (id, event_key, topic, aggregate_type, aggregate_id, payload)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb) ON CONFLICT (event_key) DO NOTHING`,
    [crypto.randomUUID(), input.eventKey, input.topic, input.aggregateType, input.aggregateId, JSON.stringify(input.payload)],
  );
}

export async function deliverOutbox(
  repository: PostgresRepository,
  publish: (event: OutboxEvent) => Promise<void>,
  limit = 50,
): Promise<number> {
  const claimed = await repository.transaction(async (tx) => {
    const result = await tx.query<OutboxEvent>(
      `SELECT id, event_key, topic, aggregate_type, aggregate_id, payload, attempts
       FROM event_outbox
       WHERE processed_at IS NULL AND available_at <= CURRENT_TIMESTAMP
         AND (locked_at IS NULL OR locked_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes')
       ORDER BY created_at
       LIMIT $1 FOR UPDATE SKIP LOCKED`,
      [limit],
    );
    for (const event of result.rows) {
      await tx.query('UPDATE event_outbox SET locked_at = CURRENT_TIMESTAMP, attempts = attempts + 1 WHERE id = $1', [event.id]);
    }
    return result.rows;
  });

  let delivered = 0;
  for (const event of claimed) {
    try {
      await publish(event);
      await repository.query('UPDATE event_outbox SET processed_at = CURRENT_TIMESTAMP, locked_at = NULL, last_error = NULL WHERE id = $1 AND processed_at IS NULL', [event.id]);
      delivered += 1;
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 500) : 'Outbox delivery failed';
      await repository.query('UPDATE event_outbox SET locked_at = NULL, available_at = CURRENT_TIMESTAMP + INTERVAL \'30 seconds\', last_error = $2 WHERE id = $1 AND processed_at IS NULL', [event.id, message]);
    }
  }
  return delivered;
}
