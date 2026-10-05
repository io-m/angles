'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';

import { AdminChrome, AdminToast } from '@/components/admin/AdminChrome';
import { AdminApiError, adminFetch, takeToast, type ReportSummary } from '@/lib/adminApi';
import { ageLabel, isUuid, reasonLine } from '@/lib/adminLabels';

export function ReportInbox() {
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);
  const [reports, setReports] = useState<ReportSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [toastTone, setToastTone] = useState<'ok' | 'err'>('ok');
  const [lookup, setLookup] = useState('');

  useEffect(() => {
    const stored = takeToast();
    if (stored) {
      setToast(stored);
    }
    let cancelled = false;
    adminFetch<{ email: string }>('/api/admin/session')
      .then(async (session) => {
        if (cancelled) {
          return;
        }
        setEmail(session.email);
        const body = await adminFetch<{ reports: ReportSummary[] }>('/api/admin/reports');
        if (!cancelled) {
          setReports(body.reports);
        }
      })
      .catch((caught: unknown) => {
        if (cancelled) {
          return;
        }
        if (caught instanceof AdminApiError && caught.status === 401) {
          router.replace('/admin/login');
          return;
        }
        setError(caught instanceof Error ? caught.message : 'Could not load reports');
      });
    return () => {
      cancelled = true;
    };
  }, [router]);

  useEffect(() => {
    if (!toast) {
      return;
    }
    const timer = window.setTimeout(() => setToast(null), 4000);
    return () => window.clearTimeout(timer);
  }, [toast]);

  async function copyId(cardId: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(cardId);
      setToastTone('ok');
      setToast('Card id copied.');
    } catch {
      setToastTone('err');
      setToast('Could not copy the card id.');
    }
  }

  function openLookup(event: FormEvent): void {
    event.preventDefault();
    const id = lookup.trim();
    if (!isUuid(id)) {
      setToastTone('err');
      setToast('Enter a card id.');
      return;
    }
    router.push(`/admin/card?id=${id}`);
  }

  return (
    <>
      <AdminChrome title="Reports" email={email}>
        <form className="admin-field" onSubmit={openLookup}>
          <label htmlFor="card-lookup">Open a card</label>
          <div className="admin-id-row">
            <input
              id="card-lookup"
              value={lookup}
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              placeholder="Card id"
              onChange={(event) => setLookup(event.target.value)}
            />
            <button className="button button-secondary" type="submit">
              Open
            </button>
          </div>
        </form>

        {error ? <p className="admin-status">{error}</p> : null}
        {reports === null && !error ? <p className="admin-status">Loading reports…</p> : null}
        {reports?.length === 0 ? <p className="admin-status">No open reports.</p> : null}
        {reports && reports.length > 0 ? (
          <div className="admin-list">
            {reports.map((report) => (
              <article className="admin-card" key={report.cardId}>
                <div className="admin-id-row">
                  <p className="admin-id">{report.cardId}</p>
                  <button className="button button-secondary" type="button" onClick={() => void copyId(report.cardId)}>
                    Copy
                  </button>
                </div>
                <p className="admin-meta">
                  {report.reportCount} open · {reasonLine(report.reasons)} · {ageLabel(report.firstReportedAt)}
                </p>
                <p className="admin-meta">
                  {report.authorInitials} · {report.authorId}
                </p>
                <div className="admin-badges">
                  <span className="admin-badge">{report.isPublic ? 'Public' : 'Private'}</span>
                  {report.authorSuspended ? <span className="admin-badge admin-badge-alert">Suspended</span> : null}
                </div>
                <Link className="button button-primary" href={`/admin/card?id=${report.cardId}`}>
                  Review
                </Link>
              </article>
            ))}
          </div>
        ) : null}
      </AdminChrome>
      <AdminToast message={toast} tone={toastTone} />
    </>
  );
}
