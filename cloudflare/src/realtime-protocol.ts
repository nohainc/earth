export type RealtimeInvalidation = {
  version: 1;
  type: 'refresh_required';
  topics: string[];
  gameDay: number | null;
  gameMinute: number | null;
  eventKey: string;
  payload?: Record<string, unknown>;
  at: string;
};

const TOPICS = new Set([
  'world', 'market', 'house', 'finance', 'buildings', 'research',
  'governance', 'notifications', 'institutions', 'communities',
]);

function topicFor(event: { topic?: string; aggregate_type?: string }): string {
  const candidates = [event.topic, event.aggregate_type]
    .filter(Boolean)
    .map((value) => String(value).toLowerCase().replace(/[^a-z]+/g, '_'));
  for (const candidate of candidates) {
    for (const topic of TOPICS) {
      if (candidate === topic || candidate.startsWith(`${topic}_`) || candidate.includes(topic)) return topic;
    }
  }
  return 'world';
}

function safeNumber(value: unknown): number | null {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 ? number : null;
}

export function mapToRealtimeInvalidation(event: {
  topic?: string;
  aggregate_type?: string;
  event_key?: string;
  payload?: Record<string, unknown>;
}): RealtimeInvalidation {
  const topic = topicFor(event);
  const payload = event.payload ?? {};
  const eventName = String(event.topic ?? event.aggregate_type ?? 'changed')
    .toLowerCase().split(/[.:/_-]+/).filter((part) => /^[a-z]+$/.test(part)).pop() ?? 'changed';
  // Outbox payloads are private by default. Only the deliberately public,
  // participant-scoped market outcome contract is forwarded to clients.
  const publicPayload = payload.kind === 'MARKET_ORDER_OUTCOME' ? payload : undefined;
  return {
    version: 1,
    type: 'refresh_required',
    topics: [topic],
    gameDay: safeNumber(payload.gameDay ?? payload.game_day),
    gameMinute: safeNumber(payload.gameMinute ?? payload.game_minute),
    eventKey: publicPayload ? (event.event_key ?? `${topic}.${eventName}`) : `${topic}.${eventName}`,
    ...(publicPayload ? { payload: publicPayload } : {}),
    at: new Date().toISOString(),
  };
}
