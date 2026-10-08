import { Logo } from '@/components/Logo';
import { SUPPORT_EMAIL } from '@/lib/legalOperator';

export function Hero() {
  return (
    <>
      <nav className="nav page-shell" aria-label="Main navigation">
        <Logo />
        <div className="nav-links">
          <a href="#voices">Voices</a>
          <a href="#how">How it works</a>
          <a href={`mailto:${SUPPORT_EMAIL}`}>Contact</a>
        </div>
      </nav>

      <section className="hero page-shell">
        <p className="eyebrow">For iPhone</p>
        <h1>One stuck thought. Four short angles.</h1>
        <p className="hero-lead">Keep it private, or share it.</p>
        <p className="hero-copy">
          Write the thought down. If it needs a little more context, Angles
          asks one short follow-up. Then you get four brief takes, chosen from
          six voices.
        </p>
        <div className="hero-actions">
          <a className="button button-primary" href="#voices">
            See the voices
          </a>
          <a className="button button-secondary" href="#how">
            How it works
          </a>
        </div>
      </section>
    </>
  );
}
