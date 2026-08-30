-- Migration 020: Migrate event_outbox.payload and proposals.target_value_json to Nano Markup TEXT

alter table event_outbox
  alter column payload type text using payload::text;

alter table proposals
  alter column target_value_json type text using target_value_json::text;
