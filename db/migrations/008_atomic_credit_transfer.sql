-- Narrow financial primitive: keep balance mutation and its audit entry atomic.
-- Gameplay policy (who may pay, how much tax applies, and which rule version is
-- selected) remains in TypeScript. This function only protects the contested
-- database mutation once the policy has already been decided.
create or replace function earth_transfer_credits(
  p_ledger_id uuid,
  p_game_day bigint,
  p_debit_account text,
  p_credit_account text,
  p_amount numeric(20,2),
  p_reason_type text,
  p_reason_id text,
  p_rule_version text,
  p_correlation_id text
)
returns table (
  status text,
  ledger_id uuid,
  amount numeric(20,2),
  already_processed boolean
)
language plpgsql
as $$
declare
  account_count integer;
begin
  if p_debit_account is null or p_credit_account is null or p_debit_account = p_credit_account then
    raise exception 'Credit transfer requires two different accounts';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Credit transfer amount must be positive';
  end if;

  if p_reason_type is null or length(trim(p_reason_type)) = 0 then
    raise exception 'Credit transfer reason type is required';
  end if;

  if p_correlation_id is null or length(trim(p_correlation_id)) = 0 then
    raise exception 'Credit transfer correlation ID is required';
  end if;

  -- Serialize calls using the same business idempotency key. This protects
  -- callers before a future migration adds a global unique index, and does not
  -- hold a lock beyond the surrounding transaction.
  perform pg_advisory_xact_lock(hashtextextended(p_reason_type || ':' || p_correlation_id, 0));

  if exists (
    select 1
    from ledger_entries
    where reason_type = p_reason_type
      and correlation_id::text = p_correlation_id
  ) then
    return query
      select 'already_processed'::text, le.id, le.amount, true
      from ledger_entries le
      where le.reason_type = p_reason_type
        and le.correlation_id::text = p_correlation_id
      order by le.created_at asc, le.id asc
      limit 1;
    return;
  end if;

  select count(*)::integer
    into account_count
  from account_balances
  where account_id in (p_debit_account, p_credit_account)
    and currency = 'CREDIT';

  if account_count <> 2 then
    raise exception 'Credit transfer account not found';
  end if;

  -- Lock in a deterministic order to reduce deadlock risk when two transfers
  -- touch the same pair of accounts in opposite directions.
  perform account_id
  from account_balances
  where account_id in (p_debit_account, p_credit_account)
    and currency = 'CREDIT'
  order by account_id
  for update;

  update account_balances
  set balance = balance - p_amount
  where account_id = p_debit_account
    and currency = 'CREDIT'
    and balance >= p_amount;

  if not found then
    raise exception 'Insufficient Credits';
  end if;

  update account_balances
  set balance = balance + p_amount
  where account_id = p_credit_account
    and currency = 'CREDIT';

  insert into ledger_entries (
    id, game_day, debit_account, credit_account, amount, currency,
    reason_type, reason_id, rule_version, correlation_id
  ) values (
    p_ledger_id, p_game_day, p_debit_account, p_credit_account, p_amount,
    'CREDIT', p_reason_type, p_reason_id, p_rule_version, p_correlation_id
  );

  return query select 'applied'::text, p_ledger_id, p_amount, false;
end;
$$;
