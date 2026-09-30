'use client';

import { useState } from 'react';
import { API } from '@/lib/site';

type Kind = 'bug' | 'idea' | 'other';
type State = { kind: 'idle' | 'sending' | 'sent' } | { kind: 'error'; message: string };

const KINDS: { value: Kind; label: string }[] = [
  { value: 'bug', label: 'Something is broken' },
  { value: 'idea', label: 'An idea' },
  { value: 'other', label: 'Something else' },
];

const field =
  'w-full rounded-xl border border-white/10 bg-[#12141b] px-4 py-3 text-ink outline-none transition-colors placeholder:text-muted/60 focus:border-ember';

/** The report form. It posts to the FuseOS server, which emails it to us. */
export function ReportForm() {
  const [kind, setKind] = useState<Kind>('bug');
  const [state, setState] = useState<State>({ kind: 'idle' });

  if (state.kind === 'sent') {
    return (
      <div className="max-w-xl rounded-2xl border border-emerald-400/30 bg-emerald-400/5 px-5 py-4">
        <p className="font-semibold text-ink">Thanks — it&apos;s with us.</p>
        <p className="mt-1 text-muted">
          We read every report. If you left your email, we&apos;ll reply there.
        </p>
      </div>
    );
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const value = (name: string) => String(form.get(name) ?? '').trim();
    setState({ kind: 'sending' });
    try {
      const response = await fetch(`${API}/feedback`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          kind,
          platform: value('platform'),
          message: value('message'),
          steps: kind === 'bug' ? value('steps') || undefined : undefined,
          appVersion: value('appVersion') || undefined,
          email: value('email') || undefined,
          website: value('website') || undefined,
        }),
      });
      if (response.ok) return setState({ kind: 'sent' });
      const body = (await response.json().catch(() => null)) as {
        error?: { message?: string };
      } | null;
      setState({ kind: 'error', message: body?.error?.message ?? 'That did not send. Try again.' });
    } catch {
      setState({
        kind: 'error',
        message: "Couldn't reach FuseOS. Check your connection and try again.",
      });
    }
  }

  return (
    <form onSubmit={submit} className="grid max-w-2xl gap-6">
      <fieldset className="grid gap-3">
        <legend className="mb-3 text-sm text-muted">What is it?</legend>
        <div className="flex flex-wrap gap-2">
          {KINDS.map((k) => (
            <button
              key={k.value}
              type="button"
              onClick={() => setKind(k.value)}
              aria-pressed={kind === k.value}
              className={
                kind === k.value
                  ? 'rounded-full border border-ember bg-ember/15 px-4 py-2 text-sm text-ink'
                  : 'rounded-full border border-white/10 px-4 py-2 text-sm text-muted hover:text-ink'
              }
            >
              {k.label}
            </button>
          ))}
        </div>
      </fieldset>

      <label className="grid gap-2 text-sm text-muted">
        Where?
        <select name="platform" defaultValue="mac" className={field}>
          <option value="mac">The Mac app</option>
          <option value="android">The Android app</option>
          <option value="both">Both / between them</option>
          <option value="website">This website</option>
        </select>
      </label>

      <label className="grid gap-2 text-sm text-muted">
        {kind === 'bug' ? 'What happened?' : 'Tell us'}
        <textarea
          name="message"
          required
          minLength={10}
          maxLength={5000}
          rows={5}
          className={field}
          placeholder={
            kind === 'bug'
              ? 'What you expected, and what happened instead.'
              : 'What would make FuseOS better for you?'
          }
        />
      </label>

      {kind === 'bug' && (
        <label className="grid gap-2 text-sm text-muted">
          How can we make it happen? (optional)
          <textarea
            name="steps"
            maxLength={5000}
            rows={3}
            className={field}
            placeholder="1. … 2. … 3. …"
          />
        </label>
      )}

      <div className="grid gap-6 sm:grid-cols-2">
        <label className="grid gap-2 text-sm text-muted">
          App version (optional)
          <input name="appVersion" maxLength={40} className={field} placeholder="e.g. 1.0.0" />
        </label>
        <label className="grid gap-2 text-sm text-muted">
          Your email, for a reply (optional)
          <input
            name="email"
            type="email"
            maxLength={200}
            className={field}
            placeholder="you@example.com"
          />
        </label>
      </div>

      {/* For bots only: people never see it, so anything in it means a bot filled the form. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-px w-px overflow-hidden">
        <label>
          Leave this empty
          <input name="website" tabIndex={-1} autoComplete="off" />
        </label>
      </div>

      <p className="text-sm text-muted">
        Please don&apos;t paste anything private. FuseOS never needs what you copied to fix a bug.
      </p>
      {state.kind === 'error' && <p className="text-sm text-[#ff8a80]">{state.message}</p>}
      <button
        type="submit"
        disabled={state.kind === 'sending'}
        className="justify-self-start rounded-2xl bg-gradient-to-b from-ember to-ember-deep px-7 py-3.5 font-semibold text-white transition-[filter] hover:brightness-110 disabled:opacity-60"
      >
        {state.kind === 'sending' ? 'Sending…' : 'Send'}
      </button>
    </form>
  );
}
