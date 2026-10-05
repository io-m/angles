'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';

import { AdminChrome } from '@/components/admin/AdminChrome';
import { AdminApiError, adminFetch } from '@/lib/adminApi';

export function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    adminFetch<{ email: string }>('/api/admin/session')
      .then(() => {
        if (!cancelled) {
          router.replace('/admin');
        }
      })
      .catch(() => {
        // A missing session is the login page.
      });
    return () => {
      cancelled = true;
    };
  }, [router]);

  async function submit(event: FormEvent): Promise<void> {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await adminFetch('/api/admin/login/request', {
        method: 'POST',
        body: JSON.stringify({ email }),
      });
      setSent(true);
    } catch (caught) {
      setError(caught instanceof AdminApiError ? caught.message : 'Could not send the link');
    } finally {
      setBusy(false);
    }
  }

  return (
    <AdminChrome title="Sign in">
      {sent ? (
        <p className="admin-copy">Check that inbox for a sign-in link. It expires in 15 minutes and works once.</p>
      ) : (
        <form className="admin-stack" onSubmit={(event) => void submit(event)}>
          <label className="admin-field" htmlFor="operator-email">
            Email
            <input
              id="operator-email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>
          <p className="admin-status">We will email a link if this address can review reports.</p>
          {error ? <p className="admin-status">{error}</p> : null}
          <button className="button button-primary" type="submit" disabled={busy}>
            Email me a link
          </button>
        </form>
      )}
    </AdminChrome>
  );
}
