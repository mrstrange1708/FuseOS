import type { Metadata } from 'next';
import { Suspense } from 'react';
import { PageShell } from '@/components/page-shell';
import { ResetForm } from './reset-form';

export const metadata: Metadata = {
  title: 'Choose a new password · FuseOS',
  // The link carries a one-time token: keep this page out of search and out of referrers.
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
};

export default function ResetPage() {
  return (
    <PageShell
      eyebrow="Your account"
      title="Choose a new password."
      intro="At least 8 characters. Every device signs out afterwards, for your security."
    >
      <Suspense>
        <ResetForm />
      </Suspense>
    </PageShell>
  );
}
