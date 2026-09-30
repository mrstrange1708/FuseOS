'use client';

import { useSearchParams } from 'next/navigation';
import { useState } from 'react';
import { API } from '@/lib/site';

type State = { kind: 'idle' | 'saving' | 'done' } | { kind: 'error'; message: string };

/** The new-password form. The token comes from the emailed link; it is only ever sent back. */
export function ResetForm() {
  const token = useSearchParams().get('token') ?? '';
  const [password, setPassword] = useState('');
  const [again, setAgain] = useState('');
  const [state, setState] = useState<State>({ kind: 'idle' });

  if (!token) {
    return (
      <p className="rounded-2xl border border-white/10 bg-[#0e1017] px-5 py-4 text-muted">
        This link is missing its code. In FuseOS, type your email on the sign-in screen and tap{' '}
        <b className="text-ink">Forgot password?</b> to get a new one.
      </p>
    );
  }
  if (state.kind === 'done') {
    return (
      <div className="rounded-2xl border border-emerald-400/30 bg-emerald-400/5 px-5 py-4">
        <p className="font-semibold text-ink">Your password is changed.</p>
        <p className="mt-1 text-muted">
          Every device was signed out. Sign in to FuseOS on each with the new password.
        </p>
      </div>
    );
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (password !== again)
      return setState({ kind: 'error', message: 'The two passwords are different.' });
    setState({ kind: 'saving' });
    try {
      const response = await fetch(`${API}/auth/reset-password`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ token, newPassword: password }),
      });
      if (response.ok) return setState({ kind: 'done' });
      const body = (await response.json().catch(() => null)) as {
        error?: { message?: string };
      } | null;
      setState({ kind: 'error', message: body?.error?.message ?? 'That did not work. Try again.' });
    } catch {
      setState({
        kind: 'error',
        message: "Couldn't reach FuseOS. Check your connection and try again.",
      });
    }
  }

  const input =
    'w-full rounded-xl border border-white/10 bg-[#12141b] px-4 py-3 text-ink outline-none transition-colors focus:border-ember';
  return (
    <form onSubmit={submit} className="grid max-w-md gap-4">
      <label className="grid gap-2 text-sm text-muted">
        New password
        <input
          className={input}
          type="password"
          autoComplete="new-password"
          minLength={8}
          maxLength={200}
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </label>
      <label className="grid gap-2 text-sm text-muted">
        Type it again
        <input
          className={input}
          type="password"
          autoComplete="new-password"
          minLength={8}
          maxLength={200}
          required
          value={again}
          onChange={(e) => setAgain(e.target.value)}
        />
      </label>
      {state.kind === 'error' && <p className="text-sm text-[#ff8a80]">{state.message}</p>}
      <button
        type="submit"
        disabled={state.kind === 'saving'}
        className="mt-2 rounded-2xl bg-gradient-to-b from-ember to-ember-deep px-6 py-3.5 font-semibold text-white transition-[filter] hover:brightness-110 disabled:opacity-60"
      >
        {state.kind === 'saving' ? 'Saving…' : 'Save password'}
      </button>
    </form>
  );
}
