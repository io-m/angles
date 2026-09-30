import { Footer } from '@/components/Footer';
import { Hero } from '@/components/Hero';
import { HowItWorks } from '@/components/HowItWorks';
import { Membership } from '@/components/Membership';
import { Voices } from '@/components/Voices';
import { softwareApplicationJsonLd } from '@/lib/structuredData';

export default function HomePage() {
  return (
    <main>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(softwareApplicationJsonLd).replace(
            /</g,
            '\\u003c',
          ),
        }}
      />
      <Hero />
      <Voices />
      <HowItWorks />
      <Membership />
      <Footer />
    </main>
  );
}
