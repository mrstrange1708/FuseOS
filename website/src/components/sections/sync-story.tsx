'use client';

import { useRef } from 'react';
import { IconBrandApple, IconFileZip, IconPhoto, IconClipboardCheck } from '@tabler/icons-react';
import { Photo, PixelPhone } from '@/components/devices';
import { FuseMark } from '@/components/fuse-mark';
import { gsap, useGSAP } from '@/lib/gsap';

const STEPS = [
  {
    Icon: IconClipboardCheck,
    kicker: 'Clipboard',
    title: "Copy on the phone. It's already on the Mac.",
    body: "Tap the tile or the notification, and the text is on your Mac's clipboard before you've looked up. Press ⌘V.",
  },
  {
    Icon: IconPhoto,
    kicker: 'Images',
    title: 'Screenshots and photos travel too.',
    body: 'Copy an image and it arrives as an image, ready to paste into Keynote, Figma or a chat.',
  },
  {
    Icon: IconFileZip,
    kicker: 'Files',
    title: 'Drop a file on the Mac. It lands on the phone.',
    body: 'Drag files into the FuseOS window, up to 1 GB each. Every file is checked with SHA-256 when it arrives, and you can cancel partway through.',
  },
] as const;

export function SyncStory() {
  const root = useRef<HTMLElement>(null);

  useGSAP(
    () => {
      const mm = gsap.matchMedia();
      mm.add('(min-width: 768px) and (prefers-reduced-motion: no-preference)', () => {
        const tl = gsap.timeline({
          defaults: { ease: 'power2.inOut' },
          scrollTrigger: {
            trigger: '.story-pin',
            start: 'top top',
            end: '+=3200',
            pin: true,
            scrub: 0.8,
          },
        });

        const travel = (reverse = false) =>
          gsap
            .timeline()
            .set('.packet', { opacity: 1, scale: 1 })
            .fromTo(
              '.trail',
              { drawSVG: reverse ? '100% 100%' : '0% 0%' },
              { drawSVG: '0% 100%', duration: 1 },
            )
            .to(
              '.packet',
              {
                motionPath: {
                  path: '.filament',
                  align: '.filament',
                  alignOrigin: [0.5, 0.5],
                  start: reverse ? 1 : 0,
                  end: reverse ? 0 : 1,
                },
                duration: 1,
                ease: 'power1.inOut',
              },
              '<',
            )
            .to('.packet', { scale: 2.2, opacity: 0, duration: 0.25 })
            .to('.trail', { drawSVG: reverse ? '0% 0%' : '100% 100%', duration: 0.4 }, '<');

        // 1 — clipboard
        tl.to('.copy-menu', { opacity: 1, y: 0, duration: 0.4 })
          .to('.phone-bubble', {
            boxShadow: '0 0 0 2px #FF7A45, 0 0 24px rgb(255 122 69 / .45)',
            duration: 0.3,
          })
          .to('.copy-menu', { opacity: 0, duration: 0.2 })
          .add(travel())
          .fromTo('.mac-paste', { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.4 }, '-=0.5')
          .to({}, { duration: 0.6 })

          // 2 — image
          .to('.cap-0', { opacity: 0, y: -20, duration: 0.4 })
          .fromTo('.cap-1', { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.4 }, '<')
          .to('.phone-chat', { opacity: 0, duration: 0.3 }, '<')
          .fromTo(
            '.phone-photo',
            { opacity: 0, scale: 0.94 },
            { opacity: 1, scale: 1, duration: 0.4 },
            '<',
          )
          .to('.mac-notes', { opacity: 0, duration: 0.3 }, '<')
          .fromTo('.mac-canvas', { opacity: 0 }, { opacity: 1, duration: 0.3 }, '<')
          .add(travel())
          .fromTo(
            '.mac-image',
            { opacity: 0, scale: 0.8, rotate: -4 },
            { opacity: 1, scale: 1, rotate: 0, duration: 0.5, ease: 'back.out(1.6)' },
            '-=0.5',
          )
          .to({}, { duration: 0.6 })

          // 3 — file, the other way
          .to('.cap-1', { opacity: 0, y: -20, duration: 0.4 })
          .fromTo('.cap-2', { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.4 }, '<')
          .to('.mac-canvas', { opacity: 0, duration: 0.3 }, '<')
          .fromTo('.mac-drop', { opacity: 0 }, { opacity: 1, duration: 0.3 }, '<')
          .fromTo(
            '.drag-file',
            { x: 120, y: 110, rotate: 12, opacity: 0 },
            { x: 0, y: 0, rotate: 0, opacity: 1, duration: 0.7, ease: 'power3.out' },
          )
          .to('.mac-drop-zone', {
            borderColor: '#FF7A45',
            backgroundColor: 'rgb(255 122 69 / .12)',
            duration: 0.2,
          })
          .to('.phone-photo', { opacity: 0, duration: 0.3 })
          .fromTo('.phone-file', { opacity: 0 }, { opacity: 1, duration: 0.3 }, '<')
          .add(travel(true))
          .fromTo(
            '.file-bar',
            { width: '0%' },
            { width: '100%', duration: 0.9, ease: 'none' },
            '-=0.9',
          )
          .to('.file-state', { opacity: 0, duration: 0.1 })
          .to('.file-done', { opacity: 1, duration: 0.2 })
          .to({}, { duration: 0.8 });
      });
    },
    { scope: root },
  );

  return (
    <section id="story" ref={root} className="relative bg-void">
      {/* Desktop: one pinned scene the scroll plays through. */}
      <div className="story-pin hidden h-screen items-center overflow-hidden md:flex">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_50%_55%,rgb(255_122_69/0.10),transparent_70%)]" />
        <div className="relative mx-auto grid w-full max-w-7xl grid-cols-[minmax(260px,340px)_1fr] items-center gap-6 px-6">
          <div className="relative h-72">
            {STEPS.map((s, i) => (
              <div
                key={s.kicker}
                className={`cap-${i} absolute inset-0 ${i === 0 ? '' : 'opacity-0'}`}
              >
                <p className="flex items-center gap-2 font-mono text-xs uppercase tracking-[0.14em] text-ember">
                  <s.Icon size={16} /> {String(i + 1).padStart(2, '0')} / 03 · {s.kicker}
                </p>
                <h3 className="mt-4 font-display text-4xl leading-[1.02] font-black tracking-[-0.03em] lg:text-5xl">
                  {s.title}
                </h3>
                <p className="mt-4 text-lg leading-relaxed text-muted">{s.body}</p>
              </div>
            ))}
          </div>

          <div className="relative mx-auto h-[560px] w-[980px] origin-center scale-[0.62] lg:scale-[0.78] xl:scale-90 2xl:scale-100">
            <svg
              viewBox="0 0 980 560"
              className="absolute inset-0 h-full w-full overflow-visible"
              aria-hidden="true"
            >
              <path
                className="filament"
                d="M 250 250 C 320 130, 340 390, 404 262"
                fill="none"
                stroke="#343b47"
                strokeWidth="2"
                strokeDasharray="3 9"
                strokeLinecap="round"
              />
              <path
                className="trail"
                d="M 250 250 C 320 130, 340 390, 404 262"
                fill="none"
                stroke="url(#trail)"
                strokeWidth="3"
                strokeLinecap="round"
                style={{ strokeDasharray: '0 9999' }}
              />
              <defs>
                <linearGradient id="trail" x1="0" x2="1">
                  <stop offset="0" stopColor="#E85D2A" />
                  <stop offset="1" stopColor="#FFB347" />
                </linearGradient>
                <radialGradient id="glow">
                  <stop offset="0" stopColor="#FFD3BC" />
                  <stop offset=".35" stopColor="#FF7A45" />
                  <stop offset="1" stopColor="#FF7A45" stopOpacity="0" />
                </radialGradient>
              </defs>
              <circle className="packet" r="16" cx="0" cy="0" fill="url(#glow)" opacity="0" />
            </svg>

            {/* phone */}
            <PixelPhone className="absolute top-0 left-0 w-[250px]">
              <div className="relative h-full">
                <div className="phone-chat absolute inset-0 flex flex-col gap-2.5 px-4 pt-5">
                  <p className="font-mono text-[10px] uppercase tracking-widest text-white/40">
                    Messages · Sam
                  </p>
                  <div className="self-start rounded-2xl rounded-bl-md bg-white/[0.07] px-3 py-2 text-[13px]">
                    Door code for tonight?
                  </div>
                  <div className="phone-bubble relative self-start rounded-2xl rounded-bl-md bg-white/[0.07] px-3 py-2 text-[13px]">
                    4471 — buzz twice, 3rd floor
                    <span className="copy-menu absolute -top-10 left-2 flex translate-y-1 gap-3 rounded-xl bg-[#2a2f3a] px-3 py-2 text-[11px] opacity-0 shadow-xl">
                      <b className="text-ember">Copy</b>{' '}
                      <span className="text-white/60">Share</span>{' '}
                      <span className="text-white/60">Select all</span>
                    </span>
                  </div>
                  <div className="self-end rounded-2xl rounded-br-md bg-ember-deep px-3 py-2 text-[13px]">
                    omw 🚲
                  </div>
                </div>
                <div className="phone-photo absolute inset-0 flex flex-col gap-3 px-4 pt-5 opacity-0">
                  <p className="font-mono text-[10px] uppercase tracking-widest text-white/40">
                    Photos
                  </p>
                  <Photo className="aspect-[3/4] w-full" />
                  <span className="self-center rounded-full bg-white/10 px-3 py-1.5 text-[11px]">
                    Copied image
                  </span>
                </div>
                <div className="phone-file absolute inset-0 flex flex-col gap-3 px-3 pt-5 opacity-0">
                  <p className="font-mono text-[10px] uppercase tracking-widest text-white/40">
                    Notifications
                  </p>
                  <div className="rounded-2xl bg-white/[0.08] p-3">
                    <p className="flex items-center gap-2 text-[11px] text-white/60">
                      <span className="grid h-5 w-5 place-items-center rounded-md bg-ember text-[9px] font-bold text-white">
                        F
                      </span>{' '}
                      FuseOS
                    </p>
                    <p className="mt-1.5 text-[13px] font-semibold">
                      <span className="file-state">Receiving file…</span>
                      <span className="file-done absolute opacity-0">File received</span>
                    </p>
                    <p className="text-[12px] text-white/60">trip-photos.zip · 48 MB</p>
                    <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
                      <div className="file-bar h-full w-0 rounded-full bg-gradient-to-r from-ember-deep to-amber" />
                    </div>
                  </div>
                </div>
              </div>
            </PixelPhone>

            {/* MacBook, front on: lid with bezel and notch, the desktop, then the base. */}
            <div className="absolute top-[88px] right-0 w-[600px]">
              <div className="relative mx-auto h-[352px] w-[540px] rounded-t-[22px] bg-[#0b0c10] p-[11px] shadow-[0_0_0_1.5px_#3a404d,0_40px_100px_-30px_rgb(0_0_0/0.9)]">
                <div className="absolute top-[11px] left-1/2 z-20 h-[14px] w-[92px] -translate-x-1/2 rounded-b-[8px] bg-[#0b0c10]" />
                <div className="relative h-full w-full overflow-hidden rounded-[6px] bg-[radial-gradient(120%_90%_at_80%_110%,#5a2712_0%,#1c202a_45%,#0c0e14_100%)]">
                  {/* menu bar */}
                  <div className="flex h-[22px] items-center justify-between bg-black/30 px-3 font-mono text-[9.5px] text-white/70 backdrop-blur">
                    <span className="flex items-center gap-3">
                      <IconBrandApple size={11} className="text-white" /> Notes{' '}
                      <span className="text-white/40">File Edit View</span>
                    </span>
                    <span className="flex items-center gap-2">
                      <FuseMark className="h-2.5 w-5 text-white" /> 9:41
                    </span>
                  </div>
                  {/* app window */}
                  <div className="absolute inset-x-5 top-[34px] bottom-4 overflow-hidden rounded-xl border border-white/10 bg-[#10131a]/95 shadow-[0_20px_50px_-20px_rgb(0_0_0/0.9)]">
                    <div className="flex items-center gap-1.5 border-b border-white/5 bg-[#161a22] px-3 py-2">
                      <i className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
                      <i className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
                      <i className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
                    </div>
                    <div className="relative h-[calc(100%-31px)]">
                      <div className="mac-notes absolute inset-0 space-y-2.5 p-5">
                        <p className="font-display text-lg font-bold">Friday</p>
                        <div className="h-2 w-2/3 rounded bg-white/10" />
                        <div className="h-2 w-5/6 rounded bg-white/10" />
                        <div className="mac-paste rounded-lg border border-dashed border-ember/60 bg-ember/10 px-3 py-2.5 text-[15px] opacity-0">
                          4471 — buzz twice, 3rd floor{' '}
                          <span className="float-right font-mono text-xs text-ember">⌘V</span>
                        </div>
                        <div className="h-2 w-1/2 rounded bg-white/10" />
                      </div>
                      <div className="mac-canvas absolute inset-0 grid place-items-center p-4 opacity-0">
                        <div className="grid h-full w-full place-items-center rounded-lg border border-white/5 bg-[#0c0e14]">
                          <Photo className="mac-image h-36 w-56 opacity-0 shadow-2xl" />
                        </div>
                      </div>
                      <div className="mac-drop absolute inset-0 p-4 opacity-0">
                        <p className="font-display text-base font-bold">Files</p>
                        <div className="mac-drop-zone mt-2 grid h-32 place-items-center rounded-xl border border-dashed border-white/20 text-center text-sm text-white/70">
                          <div className="drag-file flex flex-col items-center gap-2">
                            <IconFileZip size={40} className="text-amber" />
                            <span className="font-mono text-xs">trip-photos.zip</span>
                          </div>
                        </div>
                        <p className="mt-2 text-center text-xs text-white/50">
                          Drop files to send them to Pixel 8
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              {/* base */}
              <div className="relative h-[16px] w-full rounded-b-[14px] rounded-t-[3px] bg-[linear-gradient(180deg,#4a515e,#2a2f3a_55%,#15181f)] shadow-[0_30px_60px_-20px_rgb(0_0_0/0.9)]">
                <div className="absolute top-0 left-1/2 h-[6px] w-[96px] -translate-x-1/2 rounded-b-[8px] bg-[#1a1d25]" />
              </div>
              <p className="mt-3 text-center font-mono text-[11px] text-white/40">MacBook Air</p>
            </div>
          </div>
        </div>
      </div>

      {/* Phones and reduced motion: the same story as three plain steps. */}
      <div className="mx-auto grid max-w-xl gap-10 px-4 py-20 md:hidden">
        {STEPS.map((s, i) => (
          <div key={s.kicker}>
            <p className="flex items-center gap-2 font-mono text-xs uppercase tracking-[0.14em] text-ember">
              <s.Icon size={16} /> {String(i + 1).padStart(2, '0')} / 03 · {s.kicker}
            </p>
            <h3 className="mt-3 font-display text-3xl leading-[1.05] font-black tracking-[-0.03em]">
              {s.title}
            </h3>
            <p className="mt-3 text-muted">{s.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
