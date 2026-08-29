# Schema reference

Generated reference for core operational tables; consult the numbered migrations for constraints and full history.

| Table | Purpose | Key columns |
| --- | --- | --- |
| humans | Player characters | id UUID, life_status TEXT, standing NUMERIC, legacy NUMERIC |
| accounts | Credit account registry | account_id TEXT, owner_id UUID, currency TEXT |
| account_balances | Current balance projection | account_id TEXT, balance NUMERIC, currency TEXT |
| ledger_entries | Immutable credit movements | id UUID, debit_account TEXT, credit_account TEXT, amount NUMERIC, correlation_id TEXT |
| world_state | Singleton game clock and indices | id TEXT, game_day INTEGER, game_minute INTEGER |
| world_rules | Configurable world thresholds | key TEXT, value TEXT |
| businesses | Player enterprises | id TEXT, owner_id UUID, sector TEXT, status TEXT |
| business_employees | Workforce assignments | business_id TEXT, human_id UUID, wage NUMERIC, status TEXT |
| business_financials | Business financial projection | business_id TEXT, revenue NUMERIC, operating_costs NUMERIC, profit NUMERIC |
| market_orders | Submitted market orders | id TEXT, commodity TEXT, side TEXT, quantity NUMERIC, price NUMERIC |
| market_trades | Executed market fills | id TEXT, order_id TEXT, quantity NUMERIC, price NUMERIC |
| institutions | Cities and corporations | id TEXT, kind TEXT, status TEXT |
| memberships | Human institutional membership | human_id UUID, city_id TEXT, corporation_id TEXT |
| proposals | Governance proposals | id TEXT, institution_id TEXT, status TEXT, closes_game_day INTEGER |
| ballots | Governance votes | proposal_id TEXT, human_id UUID, choice TEXT, weight NUMERIC |
| notifications | Player notifications | id TEXT, human_id UUID, notification_type TEXT, read_at TIMESTAMPTZ |
| event_outbox | Reliable side-effect dispatch | id UUID, topic TEXT, payload JSONB, status TEXT |
| ai_assistants | Player advisory assistants | id TEXT, owner_id UUID, tier TEXT, policy TEXT |
| ai_recommendation_feedback | Player feedback on advice | id UUID, human_id UUID, recommendation_type TEXT, action TEXT |
| scheduler_tick_logs | Scheduler engine observability | id UUID, game_day INTEGER, engine TEXT, status TEXT, duration_ms INTEGER |
