'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import type { ReactNode } from 'react';
import { useState } from 'react';

import { adminFetch } from '@/lib/adminApi';

export function AdminShell({
  email,
  openCount,
  reviewedCount,
  title,
  subtitle,
  actions,
  children,
}: {
  email: string | null;
  openCount?: number;
  reviewedCount?: number;
  title: ReactNode;
  subtitle?: string;
  actions?: ReactNode;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [signingOut, setSigningOut] = useState(false);
  const onCard = pathname.startsWith('/admin/card');

  async function signOut(): Promise<void> {
    setSigningOut(true);
    try {
      await adminFetch('/api/admin/logout', { method: 'POST' });
    } catch {
      // The cookie clear is best-effort. The login page is the next stop either way.
    }
    router.replace('/admin/login');
  }

  return (
    <div className="ops-shell">
      <aside className="ops-sidebar" aria-label="Operator navigation">
        <Link className="ops-brand" href="/admin">
          <span className="ops-brand-mark" aria-hidden="true">
            A
          </span>
          <span>
            <span className="ops-brand-name">Angles</span>
            <span className="ops-brand-sub">Operator</span>
          </span>
        </Link>
        <nav className="ops-nav">
          <Link className="ops-nav-link" href="/admin" aria-current={pathname === '/admin' ? 'page' : undefined}>
            Open queue
            {typeof openCount === 'number' ? <span className="ops-nav-count">{openCount}</span> : null}
          </Link>
          <Link
            className="ops-nav-link"
            href="/admin?shelf=reviewed"
            aria-current={pathname === '/admin' && false ? 'page' : undefined}
          >
            Reviewed
            {typeof reviewedCount === 'number' ? <span className="ops-nav-count">{reviewedCount}</span> : null}
          </Link>
          <Link className="ops-nav-link" href="/admin/card" aria-current={onCard ? 'page' : undefined}>
            Review card
          </Link>
        </nav>
        <div className="ops-side-footer">
          {email ? <p className="ops-side-email">{email}</p> : null}
          {email ? (
            <button className="ops-nav-link" type="button" disabled={signingOut} onClick={() => void signOut()}>
              Sign out
            </button>
          ) : null}
        </div>
      </aside>

      <div className="ops-main">
        <div className="ops-topbar">
          <Link className="ops-topbar-brand" href="/admin" style={{ color: 'inherit', textDecoration: 'none' }}>
            <span className="ops-brand-mark" aria-hidden="true">
              A
            </span>
            Operator
          </Link>
          {email ? (
            <button
              className="ops-mini-btn"
              type="button"
              disabled={signingOut}
              onClick={() => void signOut()}
              style={{ background: 'transparent', borderColor: 'rgba(255,255,255,0.25)', color: '#fff' }}
            >
              Sign out
            </button>
          ) : null}
        </div>

        <main className="ops-content">
          <div className="ops-page-head">
            <div>
              <h1 className={typeof title === 'string' && title.length > 80 ? 'ops-review-title' : undefined}>{title}</h1>
              {subtitle ? <p className="ops-page-sub">{subtitle}</p> : null}
            </div>
            {actions}
          </div>
          {children}
        </main>
      </div>
    </div>
  );
}

export function AdminAuthShell({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="ops-auth">
      <div className="ops-auth-card">
        <div>
          <div className="ops-brand" style={{ padding: 0, border: 0, color: '#14181f' }}>
            <span className="ops-brand-mark" aria-hidden="true">
              A
            </span>
            <span>
              <span className="ops-brand-name">Angles</span>
              <span className="ops-brand-sub" style={{ color: '#5b6472' }}>
                Operator
              </span>
            </span>
          </div>
          <h1 style={{ marginTop: 12 }}>{title}</h1>
        </div>
        {children}
      </div>
    </div>
  );
}

/** Kept for the login pages. New pages use AdminShell directly. */
export function AdminChrome({
  title,
  children,
}: {
  title: string;
  email?: string | null;
  children: ReactNode;
}) {
  return <AdminAuthShell title={title}>{children}</AdminAuthShell>;
}

export function AdminToast({ message, tone }: { message: string | null; tone: 'ok' | 'err' }) {
  if (!message) {
    return null;
  }
  return (
    <p className="ops-toast" data-tone={tone === 'err' ? 'error' : undefined} role="status">
      {message}
    </p>
  );
}
