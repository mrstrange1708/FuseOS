'use client';

import { IconBrandAndroid, IconBrandApple, IconDownload } from '@tabler/icons-react';
import { useEffect, useState } from 'react';
import { GITHUB } from '@/lib/site';

type Asset = { name: string; size: number; browser_download_url: string };
type Release = {
  tag_name: string;
  name: string | null;
  html_url: string;
  published_at: string;
  prerelease: boolean;
  draft: boolean;
  assets: Asset[];
};

// Read in the visitor's browser, so a release shows up the moment GitHub publishes it, with no
// site rebuild. GitHub allows 60 unauthenticated reads an hour per visitor, plenty for a page.
const API = 'https://api.github.com/repos/mrstrange1708/FuseOS/releases?per_page=50';

const mb = (bytes: number) => `${(bytes / 1_048_576).toFixed(1)} MB`;
const date = (iso: string) =>
  new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });

function Files({ release, big }: { release: Release; big?: boolean }) {
  const files = [
    { file: 'FuseOS.dmg', label: 'Mac', Icon: IconBrandApple },
    { file: 'FuseOS.apk', label: 'Android', Icon: IconBrandAndroid },
  ].flatMap(({ file, label, Icon }) => {
    const asset = release.assets.find((a) => a.name === file);
    return asset ? [{ asset, label, Icon }] : [];
  });
  if (files.length === 0) return <p className="text-sm text-muted">Still building…</p>;
  return (
    <div className={big ? 'grid gap-3 sm:grid-cols-2' : 'flex flex-wrap gap-2'}>
      {files.map(({ asset, label, Icon }) => (
        <a
          key={asset.name}
          href={asset.browser_download_url}
          className={
            big
              ? 'flex items-center justify-center gap-2.5 rounded-2xl bg-gradient-to-b from-ember to-ember-deep px-6 py-4 font-semibold text-white transition-[filter] hover:brightness-110'
              : 'flex items-center gap-2 rounded-full border border-white/15 px-4 py-2 text-sm text-ink transition-colors hover:border-ember/60 hover:text-ember'
          }
        >
          <Icon size={big ? 19 : 16} />
          {big ? `Download for ${label}` : label}
          <span className={big ? 'font-mono text-xs opacity-80' : 'font-mono text-xs text-muted'}>
            {mb(asset.size)}
          </span>
          {!big && <IconDownload size={14} />}
        </a>
      ))}
    </div>
  );
}

export function ReleaseList() {
  const [releases, setReleases] = useState<Release[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    fetch(API, { headers: { accept: 'application/vnd.github+json' } })
      .then((res) => (res.ok ? (res.json() as Promise<Release[]>) : Promise.reject(res.status)))
      .then((all) => setReleases(all.filter((r) => !r.draft)))
      .catch(() => setFailed(true));
  }, []);

  if (failed) {
    return (
      <p className="text-muted">
        Couldn&apos;t load the list just now. Every version is also on{' '}
        <a className="text-ember underline-offset-4 hover:underline" href={`${GITHUB}/releases`}>
          GitHub
        </a>
        .
      </p>
    );
  }
  if (!releases) return <p className="text-muted">Loading versions…</p>;
  if (releases.length === 0) return <p className="text-muted">The first release is on its way.</p>;

  const latest = releases.find((r) => !r.prerelease) ?? releases[0]!;
  const rest = releases.filter((r) => r !== latest);

  return (
    <div className="grid gap-12">
      <section className="rounded-[1.75rem] border border-ember/30 bg-[#0e1017] p-8">
        <div className="flex flex-wrap items-baseline justify-between gap-3">
          <h2 className="font-display text-3xl font-black tracking-[-0.03em]">
            {latest.tag_name}{' '}
            <span className="ml-1 rounded-full bg-ember/15 px-3 py-1 align-middle font-mono text-[11px] uppercase tracking-[0.08em] text-ember-ink">
              Latest
            </span>
          </h2>
          <span className="font-mono text-sm text-muted">{date(latest.published_at)}</span>
        </div>
        <div className="mt-6">
          <Files release={latest} big />
        </div>
        <a
          className="mt-5 inline-block text-sm text-ember underline-offset-4 hover:underline"
          href={latest.html_url}
        >
          What&apos;s new in {latest.tag_name}
        </a>
      </section>

      {rest.length > 0 && (
        <section>
          <h2 className="mb-4 font-display text-xl font-extrabold">Earlier versions</h2>
          <ul className="divide-y divide-white/[0.08] rounded-2xl border border-white/[0.08]">
            {rest.map((r) => (
              <li
                key={r.tag_name}
                className="flex flex-wrap items-center justify-between gap-4 px-5 py-4"
              >
                <div>
                  <a className="font-semibold text-ink hover:text-ember" href={r.html_url}>
                    {r.tag_name}
                  </a>
                  {r.prerelease && (
                    <span className="ml-2 font-mono text-[11px] uppercase text-muted">
                      pre-release
                    </span>
                  )}
                  <p className="font-mono text-xs text-muted">{date(r.published_at)}</p>
                </div>
                <Files release={r} />
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
