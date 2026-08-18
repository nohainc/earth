import test from 'node:test';
import assert from 'node:assert/strict';
import { maskEmail } from '../cloudflare/src/auth-session.ts';
import { getEmailDeliveriesPostgres } from '../cloudflare/src/admin-deliveries-postgres.ts';

test('maskEmail obfuscates usernames while preserving domain structure', () => {
  assert.equal(maskEmail('alice@earthuc.com'), 'a***e@earthuc.com');
  assert.equal(maskEmail('bo@earthuc.com'), 'b*@earthuc.com');
  assert.equal(maskEmail('c@earthuc.com'), 'c*@earthuc.com');
  assert.equal(maskEmail('invalid-email'), '***@***');
});

test('getEmailDeliveriesPostgres aggregates delivery metrics and records', async () => {
  const mockClient = {
    query: async (sql, params) => {
      if (sql.includes('COUNT(*) FILTER')) {
        return {
          rows: [
            {
              accepted: 42,
              failed: 3,
              last_delivery: new Date('2026-08-18T12:00:00Z'),
            },
          ],
        };
      }
      return {
        rows: [
          {
            id: 'DEL-001',
            correlationId: 'corr-xyz-123',
            humanId: 'H-0044',
            recipientMasked: 'c***e@earthuc.com',
            action: 'reset_password',
            status: 'accepted',
            providerMessageId: 'msg-98765',
            errorCode: null,
            errorMessage: null,
            createdAt: new Date('2026-08-18T12:00:00Z'),
          },
          {
            id: 'DEL-002',
            correlationId: 'corr-xyz-124',
            humanId: 'H-0045',
            recipientMasked: 'b***b@earthuc.com',
            action: 'verify_email',
            status: 'failed',
            providerMessageId: null,
            errorCode: 'MAILBOX_FULL',
            errorMessage: 'Recipient mailbox full',
            createdAt: new Date('2026-08-18T11:45:00Z'),
          },
        ],
      };
    },
  };

  const result = await getEmailDeliveriesPostgres(mockClient, { limit: 10, bindingConfigured: true });

  assert.equal(result.ok, true);
  assert.equal(result.bindingConfigured, true);
  assert.equal(result.metrics.totalAccepted, 42);
  assert.equal(result.metrics.totalFailed, 3);
  assert.equal(result.metrics.successRatePct, 93.33);
  assert.equal(result.deliveries.length, 2);
  assert.equal(result.deliveries[0].correlationId, 'corr-xyz-123');
  assert.equal(result.deliveries[0].status, 'accepted');
  assert.equal(result.deliveries[1].status, 'failed');
  assert.equal(result.deliveries[1].errorCode, 'MAILBOX_FULL');
});
