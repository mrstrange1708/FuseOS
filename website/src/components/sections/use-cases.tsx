import {
  IconBrandFigma,
  IconCode,
  IconKey,
  IconMapPin,
  IconMessage2,
  IconPhoto,
  IconPlaneDeparture,
  IconReceipt,
  IconShieldLock,
  IconTerminal2,
  IconVideo,
  IconWifi,
} from '@tabler/icons-react';

const ROW_A = [
  { Icon: IconShieldLock, text: 'A 2FA code from a text' },
  { Icon: IconPhoto, text: 'A screenshot into Figma' },
  { Icon: IconTerminal2, text: 'ssh deploy@10.0.4.12' },
  { Icon: IconMapPin, text: 'The address you were sent' },
  { Icon: IconWifi, text: 'The café Wi-Fi password' },
  { Icon: IconBrandFigma, text: 'A mockup to test on the phone' },
];

const ROW_B = [
  { Icon: IconPlaneDeparture, text: 'A boarding pass PDF' },
  { Icon: IconVideo, text: 'A 400 MB screen recording' },
  { Icon: IconMessage2, text: 'A long message drafted on the laptop' },
  { Icon: IconReceipt, text: 'A receipt for expenses' },
  { Icon: IconKey, text: 'An API key, once, off the clipboard' },
  { Icon: IconCode, text: 'A stack trace to read on the go' },
];

function Row({ items, reverse }: { items: typeof ROW_A; reverse?: boolean }) {
  // Two copies side by side, so the loop's seam is always off screen.
  const doubled = [...items, ...items];
  return (
    <div className="group relative flex overflow-hidden [mask-image:linear-gradient(90deg,transparent,#000_12%,#000_88%,transparent)]">
      <ul
        className="flex shrink-0 gap-3 pr-3 group-hover:[animation-play-state:paused]"
        style={{ animation: `marquee 38s linear infinite${reverse ? ' reverse' : ''}` }}
      >
        {doubled.map(({ Icon, text }, i) => (
          <li
            key={i}
            aria-hidden={i >= items.length}
            className="flex shrink-0 items-center gap-2.5 rounded-full border border-white/[0.08] bg-white/[0.03] px-4 py-2.5 text-[15px] whitespace-nowrap text-ink"
          >
            <Icon size={17} className="text-ember" />
            {text}
          </li>
        ))}
      </ul>
    </div>
  );
}

/** The small things that make up a day of moving stuff between a phone and a laptop. */
export function UseCases() {
  return (
    <section aria-labelledby="use-cases" className="bg-void py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <p className="font-mono text-xs tracking-[0.14em] text-ember uppercase">A normal Tuesday</p>
        <h2
          id="use-cases"
          className="mt-4 max-w-[20ch] font-display text-[clamp(34px,4.6vw,58px)] leading-[0.98] font-black tracking-[-0.04em]"
        >
          All the little things you used to email yourself.
        </h2>
      </div>
      <div className="mt-12 grid gap-3">
        <Row items={ROW_A} />
        <Row items={ROW_B} reverse />
      </div>
    </section>
  );
}
