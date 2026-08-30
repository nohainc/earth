import pg from 'pg';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const client = new pg.Client({ connectionString });

await client.connect();
try {
  const humans = await client.query('SELECT h.id, h.display_name, ac.email FROM humans h LEFT JOIN auth_credentials ac ON ac.human_id = h.id ORDER BY h.id');
  for (const h of humans.rows) {
    const res = await client.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 ORDER BY resource', [h.id]);
    const ab = await client.query("SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [h.id]);
    console.log(`User: ${h.display_name} (${h.id}, ${h.email || 'no-email'}) - Credits: ${ab.rows[0]?.balance ?? '0'}`);
    console.log('  Resources:', res.rows.map(r => `${r.resource}: ${r.amount}`).join(', '));
  }
} finally {
  await client.end();
}
