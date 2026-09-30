import type { Metadata } from 'next';
import { Navbar } from '@/components/navbar';
import { Footer } from '@/components/sections/chrome';
import { Download } from '@/components/sections/download';

export const metadata: Metadata = {
  title: 'Download FuseOS for Mac and Android',
  description:
    'Get FuseOS for your Mac and your Android phone. Free. Install one on each device and sign in with the same account.',
};

export default function DownloadPage() {
  return (
    <>
      <Navbar />
      <main className="pt-16">
        <Download />
      </main>
      <Footer />
    </>
  );
}
