import type { Metadata } from 'next';
import { Suspense } from 'react';
import { PageShell } from '@/components/page-shell';
import { VerifiedMessage } from './verified-message';

export const metadata: Metadata = {
  title: 'Email confirmed · FuseOS',
  robots: { index: false, follow: false },
};

export default function VerifiedPage() {
  return (
    <PageShell eyebrow="Your account" title="Thanks for confirming.">
      <Suspense>
        <VerifiedMessage />
      </Suspense>
    </PageShell>
  );
}
