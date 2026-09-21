'use client';

import { useRef } from 'react';
import { EncryptedText } from '@/components/ui/encrypted-text';
import { gsap, useGSAP } from '@/lib/gsap';

const SPECS = [
  { k: 'Cipher', v: 'AES-256-GCM' },
  { k: 'Key agreement', v: 'P-256 ECDH' },
  { k: 'Session keys', v: 'HKDF-SHA256' },
  { k: 'Payloads on our server', v: '0 bytes' },
];

export function Privacy() {
  const root = useRef<HTMLElement>(null);

  useGSAP(
    () => {
      gsap.matchMedia().add('(prefers-reduced-motion: no-preference)', () => {
        const tl = gsap.timeline({
          scrollTrigger: { trigger: '.diagram', start: 'top 70%', end: 'bottom 60%', scrub: 1 },
        });
        tl.from('.ctrl-line', { drawSVG: '0%', duration: 1, stagger: 0.2 })
          .from('.node', { opacity: 0, y: 16, duration: 0.5, stagger: 0.1 }, 0)
          .from('.data-line', { drawSVG: '50% 50%', duration: 1 })
          .from('.blocked', { opacity: 0, scale: 0.4, transformOrigin: 'center', duration: 0.4 });
        gsap.to('.data-pulse', {
          motionPath: { path: '.data-line', align: '.data-line', alignOrigin: [0.5, 0.5] },
          duration: 2.4,
          ease: 'sine.inOut',
          repeat: -1,
          yoyo: true,
        });
      });
    },
    { scope: root },
  );

  return (
    <section id="privacy" ref={root} className="relative overflow-hidden bg-void py-28">
      <div className="pointer-events-none absolute -top-40 left-1/2 h-[520px] w-[900px] -translate-x-1/2 rounded-full bg-ember/[0.07] blur-[120px]" />
      <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-4 sm:px-6 lg:grid-cols-2">
        <div>
          <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">How it moves</p>
          <h2 className="mt-4 font-display text-[clamp(36px,5vw,64px)] leading-[0.98] font-black tracking-[-0.04em]">
            Nothing you copy touches our server.
          </h2>
          <p className="mt-6 max-w-[52ch] text-lg leading-relaxed text-muted">
            The server only signs you in and tells your devices where to find each other. Clips and
            files go straight from one device to the other over your own Wi-Fi, encrypted with keys
            that exist only on those two devices.
          </p>

          <div className="mt-8 rounded-2xl border border-white/[0.07] bg-[#0e1017] p-5">
            <p className="font-mono text-[11px] uppercase tracking-[0.12em] text-muted">
              What your Wi-Fi sees
            </p>
            <p className="mt-2 font-mono text-base break-all text-ember/80">
              a3f1 9c0e 5b72 d4e8 1f06 bb39 7ac2 e510 …
            </p>
            <p className="mt-4 font-mono text-[11px] uppercase tracking-[0.12em] text-muted">
              What your Mac pastes
            </p>
            <p className="mt-2 text-xl font-medium">
              <EncryptedText
                text="4471 — buzz twice, 3rd floor"
                revealDelayMs={45}
                flipDelayMs={40}
                encryptedClassName="text-muted/60 font-mono"
                revealedClassName="text-ink"
              />
            </p>
          </div>

          <dl className="mt-8 grid grid-cols-2 gap-x-8 gap-y-5">
            {SPECS.map((s) => (
              <div key={s.k} className="border-t border-white/10 pt-3">
                <dt className="font-mono text-[11px] uppercase tracking-[0.1em] text-muted">
                  {s.k}
                </dt>
                <dd className="mt-1 font-display text-xl font-bold">{s.v}</dd>
              </div>
            ))}
          </dl>
        </div>

        <div className="diagram overflow-x-auto">
          <svg
            viewBox="0 0 520 460"
            className="mx-auto w-full max-w-[520px] min-w-[420px]"
            role="img"
            aria-labelledby="dg"
          >
            <title id="dg">
              Both devices talk to the FuseOS server only to sign in and find each other. Clipboard
              and file data goes directly between them, never up to the server.
            </title>
            <defs>
              <linearGradient id="dataGrad" x1="0" x2="1">
                <stop offset="0" stopColor="#E85D2A" />
                <stop offset="1" stopColor="#FFB347" />
              </linearGradient>
            </defs>

            <path
              className="ctrl-line"
              d="M200 92 C 140 140, 110 220, 108 300"
              fill="none"
              stroke="#59616f"
              strokeWidth="1.6"
              strokeDasharray="6 6"
            />
            <path
              className="ctrl-line"
              d="M320 92 C 380 140, 410 220, 412 300"
              fill="none"
              stroke="#59616f"
              strokeWidth="1.6"
              strokeDasharray="6 6"
            />
            <text
              x="120"
              y="190"
              fill="#98a0ad"
              fontSize="11"
              fontFamily="var(--font-mono)"
              transform="rotate(-62 120 190)"
            >
              sign-in · presence
            </text>
            <text
              x="366"
              y="150"
              fill="#98a0ad"
              fontSize="11"
              fontFamily="var(--font-mono)"
              transform="rotate(62 366 150)"
            >
              sign-in · presence
            </text>

            <g className="node">
              <rect
                x="170"
                y="30"
                width="180"
                height="62"
                rx="16"
                fill="#161922"
                stroke="#343b47"
              />
              <text
                x="260"
                y="58"
                textAnchor="middle"
                fill="#eceff4"
                fontSize="14"
                fontWeight="700"
                fontFamily="var(--font-mono)"
              >
                FuseOS server
              </text>
              <text
                x="260"
                y="77"
                textAnchor="middle"
                fill="#98a0ad"
                fontSize="10.5"
                fontFamily="var(--font-mono)"
              >
                accounts · devices
              </text>
            </g>

            {/* the path data would take to the server, if it ever did */}
            <line
              x1="260"
              y1="360"
              x2="260"
              y2="110"
              stroke="#343b47"
              strokeWidth="1.5"
              strokeDasharray="2 6"
            />
            <g className="blocked">
              <circle cx="260" cy="210" r="17" fill="#0c0e14" stroke="#ff8a75" strokeWidth="1.5" />
              <path
                d="M252 202 L268 218 M268 202 L252 218"
                stroke="#ff8a75"
                strokeWidth="2.2"
                strokeLinecap="round"
              />
            </g>

            <g className="node">
              <rect
                x="28"
                y="300"
                width="160"
                height="84"
                rx="18"
                fill="#161922"
                stroke="#eceff4"
                strokeOpacity=".5"
              />
              <text
                x="108"
                y="336"
                textAnchor="middle"
                fill="#eceff4"
                fontSize="14"
                fontWeight="700"
                fontFamily="var(--font-mono)"
              >
                Pixel 8
              </text>
              <text
                x="108"
                y="356"
                textAnchor="middle"
                fill="#98a0ad"
                fontSize="10.5"
                fontFamily="var(--font-mono)"
              >
                android
              </text>
            </g>
            <g className="node">
              <rect
                x="332"
                y="300"
                width="160"
                height="84"
                rx="18"
                fill="#161922"
                stroke="#eceff4"
                strokeOpacity=".5"
              />
              <text
                x="412"
                y="336"
                textAnchor="middle"
                fill="#eceff4"
                fontSize="14"
                fontWeight="700"
                fontFamily="var(--font-mono)"
              >
                MacBook Air
              </text>
              <text
                x="412"
                y="356"
                textAnchor="middle"
                fill="#98a0ad"
                fontSize="10.5"
                fontFamily="var(--font-mono)"
              >
                macOS
              </text>
            </g>

            <path
              className="data-line"
              d="M188 342 C 240 400, 280 400, 332 342"
              fill="none"
              stroke="url(#dataGrad)"
              strokeWidth="3.5"
              strokeLinecap="round"
            />
            <circle
              className="data-pulse"
              r="7"
              fill="#FFD3BC"
              style={{ filter: 'drop-shadow(0 0 8px #FF7A45)' }}
              cx="188"
              cy="342"
            />
            <text
              x="260"
              y="425"
              textAnchor="middle"
              fill="#FF7A45"
              fontSize="12"
              fontWeight="700"
              fontFamily="var(--font-mono)"
            >
              clipboard + files · same Wi-Fi
            </text>
          </svg>
        </div>
      </div>
    </section>
  );
}
