import { describe, expect, it } from 'vitest';
import { isUniqueViolation } from './errors.js';

/** Shapes a driver/Drizzle error closely enough for the SQLSTATE check. */
function pgError(code: string): Error {
  return Object.assign(new Error('duplicate key value violates unique constraint'), { code });
}

describe('isUniqueViolation', () => {
  it('detects SQLSTATE 23505 on the error itself', () => {
    expect(isUniqueViolation(pgError('23505'))).toBe(true);
  });

  it('detects it on the cause, where Drizzle wraps the driver error', () => {
    const wrapped = Object.assign(new Error('Failed query'), { cause: pgError('23505') });
    expect(isUniqueViolation(wrapped)).toBe(true);
  });

  it.each([
    ['a foreign-key violation', pgError('23503')],
    ['a check violation', pgError('23514')],
    ['a plain error', new Error('boom')],
    ['a wrapped non-unique error', Object.assign(new Error('x'), { cause: pgError('23503') })],
    ['null', null],
    ['undefined', undefined],
    ['a bare string', '23505'],
    ['a number code', Object.assign(new Error('x'), { code: 23505 })],
  ])('is false for %s', (_label, value) => {
    expect(isUniqueViolation(value)).toBe(false);
  });
});
