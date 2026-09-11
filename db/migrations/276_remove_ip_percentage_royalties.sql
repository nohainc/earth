-- Technology & Research V2 Plan 23: fixed-fee IP contracts only.
--
-- Percentage royalties are intentionally not part of the initial IP V2
-- contract.  License economics are represented by the immutable
-- technology_license_contracts.upfront_fee_units and daily_fee_units fields.
-- Keep the legacy table's non-royalty columns temporarily for expiry
-- compatibility, but remove the percentage field so it cannot be mistaken for
-- an authoritative V2 term.

DO $$
BEGIN
  IF to_regclass('public.technology_licenses') IS NOT NULL THEN
    ALTER TABLE technology_licenses
      DROP COLUMN IF EXISTS royalty_rate;
  END IF;
END
$$;
