import type { Metadata } from 'next';
import { Instrument_Sans, JetBrains_Mono, Schibsted_Grotesk } from 'next/font/google';
import './globals.css';
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

export const metadata: Metadata = {
  title: 'FuseOS — your Android phone and your Mac, as one',
  description:
    'Copy on your Android phone, paste on your Mac. Files and the share sheet, both ways, straight over your Wi-Fi. Nothing you copy touches a server.',
};

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable} ${mono.variable} antialiased`}>
      <body className="grain min-h-full">
        <SmoothScroll />
        {children}
      </body>
    </html>
  );
}
