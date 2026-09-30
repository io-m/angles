import Link from 'next/link';

import { Logo } from '@/components/Logo';

export default function NotFound() {
  return (
    <main className="legal-page">
      <header>
        <Logo />
        <h1>Page not found.</h1>
        <p>That page is not on this site.</p>
      </header>
      <Link className="button button-primary" href="/">
        Back to Angles
      </Link>
    </main>
  );
}
