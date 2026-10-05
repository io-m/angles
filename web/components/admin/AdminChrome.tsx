'use client';

import { useRouter } from 'next/navigation';
import type { ReactNode } from 'react';
import { useState } from 'react';

import { Logo } from '@/components/Logo';
import { adminFetch } from '@/lib/adminApi';

export function AdminChrome({
  title,
  email,
  children,
}: {
  title: string;
  email?: string | null;
  children: ReactNode;
}) {
  const router = useRouter();
  const [signingOut, setSigningOut] = useState(false);

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
    <>
      <header className="admin-header">
        <div>
          <Logo />
          <h1>{title}</h1>
          {email ? <p className="admin-lead">{email}</p> : null}
        </div>
        {email ? (
          <button className="button button-secondary" type="button" disabled={signingOut} onClick={() => void signOut()}>
            Sign out
          </button>
        ) : null}
      </header>
      {children}
    </>
  );
}

export function AdminToast({ message, tone }: { message: string | null; tone: 'ok' | 'err' }) {
  if (!message) {
    return null;
  }
  return (
    <p className={tone === 'err' ? 'admin-toast admin-toast-err' : 'admin-toast'} role="status">
      {message}
    </p>
  );
}
