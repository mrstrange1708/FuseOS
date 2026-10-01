import type { Metadata } from 'next';
import { PageShell } from '@/components/page-shell';
import { ReleaseList } from './release-list';

export const metadata: Metadata = {
  title: 'All versions · FuseOS',
  description:
    'Every FuseOS release for Mac and Android: the latest on top, and any earlier version if you need it.',
};

export default function ReleasesPage() {
  return (
    <PageShell
      eyebrow="Releases"
      title="Every version."
      intro="The latest is on top. Install the same version on your Mac and your phone; older ones are here if you need to go back."
    >
      <ReleaseList />
    </PageShell>
  );
}
