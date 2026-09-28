import { Navbar } from '@/components/navbar';
import { Download } from '@/components/sections/download';
import { Faq, Footer } from '@/components/sections/chrome';
import { Features } from '@/components/sections/features';
import { Film } from '@/components/sections/film';
import { Continuity } from '@/components/sections/continuity';
import { Hero } from '@/components/sections/hero';
import { MacbookSection } from '@/components/sections/macbook';
import { NotchStage } from '@/components/sections/notch';
import { MenuBarDemo } from '@/components/sections/menubar-demo';
import { UseCases } from '@/components/sections/use-cases';
import { Privacy } from '@/components/sections/privacy';
import { SyncStory } from '@/components/sections/sync-story';

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <Film />
        <SyncStory />
        <NotchStage />
        <MenuBarDemo />
        <MacbookSection />
        <Features />
        <Continuity />
        <UseCases />
        <Privacy />
        <Download />
        <Faq />
      </main>
      <Footer />
    </>
  );
}
