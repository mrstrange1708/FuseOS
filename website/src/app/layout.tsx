import type { Metadata } from 'next';
import { Instrument_Sans, JetBrains_Mono, Schibsted_Grotesk } from 'next/font/google';
import './globals.css';
import { Analytics } from '@/components/analytics';
import { SmoothScroll } from '@/components/smooth-scroll';

const display = Schibsted_Grotesk({
  variable: '--font-schibsted',
  subsets: ['latin'],
  weight: ['500', '700', '800', '900'],
});

const body = Instrument_Sans({
  variable: '--font-instrument',
  subsets: ['latin'],
});

const mono = JetBrains_Mono({
  variable: '--font-jetbrains',
  subsets: ['latin'],
});

const description =
  'Copy on your Android phone, paste on your Mac. Files, notifications, calls and your screen, over your Wi-Fi — end-to-end encrypted, so not even our server can read them.';

export const metadata: Metadata = {
  metadataBase: new URL('https://fuseos.theshaik.dev'),
  title: 'FuseOS — your Android phone and your Mac, as one',
  description,
  // The preview a link shows in WhatsApp, X, LinkedIn and Slack.
  openGraph: {
    type: 'website',
    siteName: 'FuseOS',
    title: 'FuseOS — your Android phone and your Mac, as one',
    description,
    images: [
      {
        url: '/fuseos-film.jpg',
        width: 1600,
        height: 900,
        alt: 'FuseOS on a Mac and an Android phone',
      },
    ],
  },
  twitter: { card: 'summary_large_image' },
};

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable} ${mono.variable} antialiased`}>
      <body className="grain min-h-full">
        <SmoothScroll />
        <Analytics />
        {children}
      </body>
    </html>
  );
}
