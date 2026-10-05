'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { AdminChrome } from '@/components/admin/AdminChrome';
import { adminFetch } from '@/lib/adminApi';

export function VerifyLogin() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash;
    const token = new URLSearchParams(hash).get('t');
    window.history.replaceState(null, '', '/admin/login/verify');
    if (!token) {
      setError('This sign-in link is missing.');
      return;
    }
    let cancelled = false;
    adminFetch('/api/admin/login/verify', {
      method: 'POST',
      body: JSON.stringify({ token }),
    })
      .then(() => {
        if (!cancelled) {
          router.replace('/admin');
        }
      })
      .catch((caught: unknown) => {
        if (!cancelled) {
          setError(caught instanceof Error ? caught.message : 'This sign-in link did not work.');
        }
      });
    return () => {
      cancelled = true;
    };
  }, [router]);

  return (
    <AdminChrome title="Sign in">
      {error ? (
        <>
          <p className="ops-banner" data-tone="error">{error}</p>
          <p>
            <Link className="ops-back" href="/admin/login">Request a new link</Link>
          </p>
        </>
      ) : (
        <p className="ops-hint">Signing in…</p>
      )}
    </AdminChrome>
  );
}
