import type { Metadata } from 'next';
import { PageShell } from '@/components/page-shell';
import { ReportForm } from './report-form';

export const metadata: Metadata = {
  title: 'Report a bug · FuseOS',
  description: 'Tell us what broke, or what would make FuseOS better.',
};

export default function ReportPage() {
  return (
    <PageShell
      eyebrow="Report a bug"
      title="Something broke? Tell us."
      intro="Bugs, ideas, anything. It comes straight to us, and we read every one."
    >
      <ReportForm />
    </PageShell>
  );
}
