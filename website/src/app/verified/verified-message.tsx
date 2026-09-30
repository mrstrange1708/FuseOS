'use client';

import { useSearchParams } from 'next/navigation';

/** What the confirmation link did: `?error=expired` when the server refused it. */
export function VerifiedMessage() {
  const expired = useSearchParams().get('error') !== null;
  return expired ? (
    <div className="max-w-xl rounded-2xl border border-white/10 bg-[#0e1017] px-5 py-4 text-muted">
      <p className="font-semibold text-ink">That link has expired or was already used.</p>
      <p className="mt-1">
        Confirmation links work for one hour. If your email isn&apos;t confirmed yet, sign up again
        or{' '}
        <a className="text-ember" href="/help#account">
          see Help
        </a>
        .
      </p>
    </div>
  ) : (
    <div className="max-w-xl rounded-2xl border border-emerald-400/30 bg-emerald-400/5 px-5 py-4">
      <p className="font-semibold text-ink">Your email is confirmed.</p>
      <p className="mt-1 text-muted">
        You&apos;re all set. Sign in on your Mac and your phone with this account and they&apos;ll
        link themselves.{' '}
        <a className="text-ember" href="/download">
          Get the apps →
        </a>
      </p>
    </div>
  );
}
