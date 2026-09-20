-- A living Human may maintain one short plain-text testament. The death
-- snapshot copies it once; memorial records remain immutable thereafter.

ALTER TABLE humans
  DROP CONSTRAINT IF EXISTS humans_epitaph_plain_text_check;

ALTER TABLE humans
  ADD CONSTRAINT humans_epitaph_plain_text_check
  CHECK (
    epitaph IS NULL
    OR (
      char_length(epitaph) <= 240
      AND epitaph !~ '[[:cntrl:]<>]'
    )
  );

COMMENT ON COLUMN humans.epitaph IS
  'Optional living-Human testament. Plain text, at most 240 characters; copied into the immutable memorial record at death.';
