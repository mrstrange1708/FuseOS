/**
 * True for a Postgres unique-violation (SQLSTATE 23505). Drizzle wraps driver
 * errors in a `DrizzleQueryError`, so the real `PostgresError` (with `.code`) is
 * on `.cause` — check both.
 */
export function isUniqueViolation(error: unknown): boolean {
  const hasCode23505 = (value: unknown): boolean =>
    typeof value === 'object' &&
    value !== null &&
    'code' in value &&
    (value as { code?: unknown }).code === '23505';
  return hasCode23505(error) || hasCode23505((error as { cause?: unknown })?.cause);
}
