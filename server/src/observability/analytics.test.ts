import { describe, it, expect } from 'vitest';
import { assertNoPayload, capture } from './analytics.js';

describe('analytics payload guard', () => {
  it('throws when a forbidden payload key is present', () => {
    expect(() => assertNoPayload({ text: 'my secret clipboard' })).toThrow(/forbidden/);
    expect(() => capture('user-1', 'clip_synced', { content: 'secret' })).toThrow(/forbidden/);
  });

  it('is case-insensitive about forbidden keys', () => {
    expect(() => assertNoPayload({ Clipboard: 'x' })).toThrow(/forbidden/);
    expect(() => assertNoPayload({ FILEDATA: 'x' })).toThrow(/forbidden/);
  });

  it('allows safe metadata', () => {
    expect(() => assertNoPayload({ sizeBytes: 12, platform: 'android', ok: true })).not.toThrow();
    expect(() => capture('user-1', 'clip_synced', { sizeBytes: 12 })).not.toThrow();
  });
});
