export function isExactSchemaCompatible(
  migrationVersion: number | null | undefined,
  missingObjects: readonly string[] = [],
  expectedVersion: number,
): boolean {
  return migrationVersion === expectedVersion && missingObjects.length === 0;
}
