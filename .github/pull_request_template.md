## Summary

<!-- What changed and why? Link the issue or decision record when applicable. -->

## Verification

- [ ] `npm run check`
- [ ] `npm test`
- [ ] `flutter analyze` (when Flutter code changes)
- [ ] `flutter test` (when Flutter code changes)
- [ ] Production smoke/deploy verification (for release changes)

## Data and release safety

- [ ] No secrets, credentials, or personal data are included.
- [ ] PostgreSQL migrations are backward-compatible or include a rollout note.
- [ ] The change preserves server-authoritative outcomes and core invariants.
- [ ] Documentation and schema manifest are updated when needed.
