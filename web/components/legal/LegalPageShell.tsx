import Link from 'next/link';
import type { ReactNode } from 'react';

import { Logo } from '@/components/Logo';
import { COMPANY_ORIGIN } from '@/lib/legalOperator';

export function LegalPageShell({
  title,
  updated,
  children,
}: {
  title: string;
  updated: string;
  children: ReactNode;
}) {
  return (
    <main className="legal-page">
      <header>
        <Logo />
        <h1>{title}</h1>
        <p>Last updated: {updated}</p>
      </header>
      {children}
      <nav aria-label="Legal" className="legal-footer-nav">
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
        <Link href="/support">Support</Link>
        <a href={COMPANY_ORIGIN}>Bithavn</a>
      </nav>
    </main>
  );
}
