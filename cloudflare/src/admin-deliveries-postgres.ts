export interface EmailDeliveryRecord {
  id: string;
  correlationId: string;
  humanId: string;
  recipientMasked: string;
  action: string;
  status: 'accepted' | 'failed';
  providerMessageId: string | null;
  errorCode: string | null;
  errorMessage: string | null;
  createdAt: string;
}

export interface EmailDeliveriesResponse {
  ok: boolean;
  bindingConfigured: boolean;
  metrics: {
    totalAccepted: number;
    totalFailed: number;
    lastDeliveryAt: string | null;
    successRatePct: number;
  };
  deliveries: EmailDeliveryRecord[];
}

export async function getEmailDeliveriesPostgres(
  client: any,
  options: { limit?: number; bindingConfigured?: boolean } = {},
): Promise<EmailDeliveriesResponse> {
  const limit = Math.min(Math.max(1, options.limit ?? 50), 200);
  const bindingConfigured = options.bindingConfigured ?? false;

  const deliveriesQuery = await client.query(
    `SELECT
      id,
      correlation_id AS "correlationId",
      human_id AS "humanId",
      recipient_masked AS "recipientMasked",
      action,
      status,
      provider_message_id AS "providerMessageId",
      error_code AS "errorCode",
      error_message AS "errorMessage",
      created_at AS "createdAt"
    FROM auth_email_deliveries
    ORDER BY created_at DESC
    LIMIT $1`,
    [limit],
  ).catch(() => ({ rows: [] }));

  const metricsQuery = await client.query(
    `SELECT
      COUNT(*) FILTER (WHERE status = 'accepted')::integer AS accepted,
      COUNT(*) FILTER (WHERE status = 'failed')::integer AS failed,
      MAX(created_at) AS last_delivery
    FROM auth_email_deliveries`,
  ).catch(() => ({ rows: [{ accepted: 0, failed: 0, last_delivery: null }] }));

  const metricsRow = metricsQuery.rows[0] ?? { accepted: 0, failed: 0, last_delivery: null };
  const totalAccepted = Number(metricsRow.accepted ?? 0);
  const totalFailed = Number(metricsRow.failed ?? 0);
  const total = totalAccepted + totalFailed;
  const successRatePct = total > 0 ? Number(((totalAccepted / total) * 100).toFixed(2)) : 100.0;

  return {
    ok: true,
    bindingConfigured,
    metrics: {
      totalAccepted,
      totalFailed,
      lastDeliveryAt: metricsRow.last_delivery ? new Date(metricsRow.last_delivery).toISOString() : null,
      successRatePct,
    },
    deliveries: (deliveriesQuery.rows || []).map((row: any) => ({
      id: String(row.id),
      correlationId: String(row.correlationId),
      humanId: String(row.humanId),
      recipientMasked: String(row.recipientMasked),
      action: String(row.action),
      status: row.status === 'accepted' ? 'accepted' : 'failed',
      providerMessageId: row.providerMessageId ? String(row.providerMessageId) : null,
      errorCode: row.errorCode ? String(row.errorCode) : null,
      errorMessage: row.errorMessage ? String(row.errorMessage) : null,
      createdAt: row.createdAt ? new Date(row.createdAt).toISOString() : new Date().toISOString(),
    })),
  };
}
