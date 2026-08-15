-- Prolonged insolvency ends in an auditable dissolution, matching the game lifecycle.
alter table financial_states drop constraint if exists financial_states_status_check;
alter table financial_states add constraint financial_states_status_check check (status in ('active','distressed','insolvent','bankrupt','dissolved'));
