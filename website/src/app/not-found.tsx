import { PageShell } from '@/components/page-shell';

export default function NotFound() {
  return (
    <PageShell
      eyebrow="404"
      title="Nothing here."
      intro="That page doesn't exist, or it moved. These are the ones people usually look for:"
    >
      <ul className="grid gap-3 sm:grid-cols-2">
        {[
          { href: '/', label: 'Home', note: 'What FuseOS does' },
          { href: '/download', label: 'Download', note: 'Mac and Android' },
          { href: '/help', label: 'Help', note: 'Setup and fixes' },
          { href: '/privacy', label: 'Privacy', note: 'What we keep, and what we never see' },
        ].map((l) => (
          <li key={l.href}>
            <a
              href={l.href}
              className="block rounded-2xl border border-white/[0.08] bg-[#0e1017] px-5 py-4 transition-colors hover:border-ember/50"
            >
              <span className="block font-semibold text-ink">{l.label}</span>
              <span className="text-sm text-muted">{l.note}</span>
            </a>
          </li>
        ))}
      </ul>
    </PageShell>
  );
}
