import { Navbar } from '@/components/navbar';
import { Download } from '@/components/sections/download';
import { Faq, Footer } from '@/components/sections/chrome';
import { Features } from '@/components/sections/features';
import { Hero } from '@/components/sections/hero';
import { MacbookSection } from '@/components/sections/macbook';
import { Privacy } from '@/components/sections/privacy';
import { SyncStory } from '@/components/sections/sync-story';

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <SyncStory />
        <MacbookSection />
        <Features />
        <Privacy />
        <Download />
        <Faq />
      </main>
      <Footer />
    </>
  );
}
