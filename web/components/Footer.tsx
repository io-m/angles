import Link from 'next/link';

import { Logo } from '@/components/Logo';
import { COMPANY_ORIGIN } from '@/lib/legalOperator';

export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-inner page-shell">
        <Logo />
        <div className="footer-meta">
          <span>© {new Date().getFullYear()} Angles</span>
          <nav aria-label="Legal" className="footer-links">
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="/support">Support</Link>
            <a href={COMPANY_ORIGIN}>Bithavn</a>
          </nav>
        </div>
      </div>
    </footer>
  );
}
