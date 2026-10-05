'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';

import { AdminChrome, AdminToast } from '@/components/admin/AdminChrome';
import {
  AdminApiError,
  adminFetch,
  stashToast,
  type AuthorPublicCard,
  type AuthorReview,
  type CardReview as CardReviewBody,
  type ReportSummary,
  type ReviewedSummary,
} from '@/lib/adminApi';
import { cardHref, isUuid, matchesQueue, readFilters, reasonLine, styleLabel, type QueueFilters } from '@/lib/adminLabels';

type ConfirmKind = 'hide' | 'delete' | 'suspend';

const CONFIRM: Record<ConfirmKind, { title: string; label: string }> = {
  hide: {
    title: 'Hide this card? It becomes private and cannot be published again.',
    label: 'Hide',
  },
  delete: {
    title: 'Delete this card? This cannot be undone.',
    label: 'Delete',
  },
  suspend: {
    title: 'Suspend publishing? Every card from this account becomes private until you unsuspend them.',
    label: 'Suspend',
  },
};

export function CardReview() {
  const router = useRouter();
  const params = useSearchParams();
  const cardId = params.get('id')?.trim() ?? '';
  const shelf: QueueFilters['shelf'] = params.get('shelf') === 'reviewed' ? 'reviewed' : 'open';
  const reason = params.get('reason') ?? '';
  const visibilityParam = params.get('visibility');
  const visibility: QueueFilters['visibility'] =
    visibilityParam === 'public' || visibilityParam === 'private' ? visibilityParam : 'all';
  const suspendedOnly = params.get('suspended') === '1';
  const filters = readFilters(params);
  const [email, setEmail] = useState<string | null>(null);
  const [card, setCard] = useState<CardReviewBody | null>(null);
  const [author, setAuthor] = useState<AuthorReview | null>(null);
  const [others, setOthers] = useState<AuthorPublicCard[]>([]);
  const [queue, setQueue] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [toastTone, setToastTone] = useState<'ok' | 'err'>('ok');
  const [confirm, setConfirm] = useState<ConfirmKind | null>(null);
  const [busy, setBusy] = useState(false);

  const showError = useCallback((caught: unknown): void => {
    setToastTone('err');
    setToast(caught instanceof Error ? caught.message : 'Something went wrong');
  }, []);

  const load = useCallback(
    async (isCurrent: () => boolean): Promise<void> => {
      if (!isUuid(cardId)) {
        setCard(null);
        setAuthor(null);
        setError(cardId ? 'That card id is not valid.' : 'Open a card from the overview.');
        return;
      }
      const activeFilters: QueueFilters = { shelf, reason, visibility, suspendedOnly };
      const queuePath = shelf === 'reviewed' ? '/api/admin/reports/reviewed' : '/api/admin/reports';
      const [session, nextCard, listed] = await Promise.all([
        adminFetch<{ email: string }>('/api/admin/session'),
        adminFetch<CardReviewBody>(`/api/admin/reports/${cardId}`),
        adminFetch<{ reports: Array<ReportSummary | ReviewedSummary> }>(queuePath),
      ]);
      if (!isCurrent()) {
        return;
      }
      setEmail(session.email);
      setCard(nextCard);
      setQueue(listed.reports.filter((row) => matchesQueue(row, activeFilters)).map((row) => row.cardId));
      const [nextAuthor, publicCards] = await Promise.all([
        adminFetch<AuthorReview>(`/api/admin/users/${nextCard.authorId}`),
        adminFetch<{ cards: AuthorPublicCard[] }>(`/api/admin/users/${nextCard.authorId}/cards`),
      ]);
      if (!isCurrent()) {
        return;
      }
      setAuthor(nextAuthor);
      setOthers(publicCards.cards.filter((item) => item.cardId !== cardId));
      setError(null);
    },
    [cardId, reason, shelf, suspendedOnly, visibility],
  );

  useEffect(() => {
    let cancelled = false;
    load(() => !cancelled).catch((caught: unknown) => {
      if (cancelled) {
        return;
      }
      if (caught instanceof AdminApiError && caught.status === 401) {
        router.replace('/admin/login');
        return;
      }
      setError(caught instanceof Error ? caught.message : 'Could not load this card');
    });
    return () => {
      cancelled = true;
    };
  }, [load, router]);

  useEffect(() => {
    if (!toast) {
      return;
    }
    const timer = window.setTimeout(() => setToast(null), 4000);
    return () => window.clearTimeout(timer);
  }, [toast]);

  const index = queue.indexOf(cardId);
  const nextId = index >= 0 ? (queue[index + 1] ?? null) : null;
  const position = index >= 0 ? `${index + 1} of ${queue.length}` : null;

  function finish(message: string): void {
    stashToast(message);
    router.replace(nextId ? cardHref(nextId, filters) : '/admin');
  }

  async function copyId(): Promise<void> {
    try {
      await navigator.clipboard.writeText(cardId);
      setToastTone('ok');
      setToast('Card id copied.');
    } catch {
      showError(new Error('Could not copy the card id.'));
    }
  }

  async function run(action: () => Promise<void>, success: string, advance: boolean): Promise<void> {
    setBusy(true);
    setConfirm(null);
    try {
      await action();
      if (advance) {
        finish(success);
        return;
      }
      setToastTone('ok');
      setToast(success);
      await load(() => true);
    } catch (caught) {
      showError(caught);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="admin-review">
      <AdminChrome title={card?.thought ?? 'Review'} email={email}>
        <div className="admin-toolbar">
          <Link href="/admin">Back to reports</Link>
          {position ? <span className="admin-meta">{position}</span> : null}
          {nextId ? (
            <Link className="button button-secondary" href={cardHref(nextId, filters)}>
              Next
            </Link>
          ) : null}
        </div>
        {error ? <p className="admin-status">{error}</p> : null}
        {!card && !error ? <p className="admin-status">Loading card…</p> : null}
        {card ? (
          <article className="admin-stack">
            <section className="admin-card">
              <div className="admin-id-row">
                <p className="admin-id">{card.cardId}</p>
                <button className="admin-quiet" type="button" onClick={() => void copyId()}>
                  Copy id
                </button>
              </div>
              <div className="admin-badges">
                <span className="admin-badge">{card.isPublic ? 'Public' : 'Private'}</span>
                <span className="admin-badge">
                  {card.reportCount} open · {reasonLine(card.reasons)}
                </span>
                {card.authorSuspended ? <span className="admin-badge admin-badge-alert">Suspended</span> : null}
              </div>
              {card.reframes.map((item) => (
                <div className="admin-answer-block" key={item.style}>
                  <h2>{styleLabel(item.style)}</h2>
                  <p className="admin-answer">{item.reframe}</p>
                </div>
              ))}
              {confirm ? (
                <div className="admin-confirm" role="dialog" aria-labelledby="confirm-title">
                  <p id="confirm-title">{CONFIRM[confirm].title}</p>
                  <div className="admin-actions">
                    <button className="button button-secondary" type="button" disabled={busy} onClick={() => setConfirm(null)}>
                      Cancel
                    </button>
                    <button
                      className="button button-danger"
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        if (confirm === 'hide') {
                          void run(() => adminFetch(`/api/admin/reports/${card.cardId}/hide`, { method: 'POST' }), 'Card hidden.', true);
                        } else if (confirm === 'delete') {
                          void run(
                            async () => {
                              await adminFetch(`/api/admin/reports/${card.cardId}/delete`, { method: 'POST' });
                            },
                            'Card deleted.',
                            true,
                          );
                        } else {
                          void run(
                            () => adminFetch(`/api/admin/users/${card.authorId}/suspend`, { method: 'POST' }),
                            'Publishing suspended.',
                            false,
                          );
                        }
                      }}
                    >
                      {CONFIRM[confirm].label}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="admin-actions">
                  <button
                    className="button button-primary"
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void run(() => adminFetch(`/api/admin/reports/${card.cardId}/keep`, { method: 'POST' }), 'Reports dismissed.', true)
                    }
                  >
                    Keep
                  </button>
                  <button className="button button-secondary" type="button" disabled={busy} onClick={() => setConfirm('hide')}>
                    Hide
                  </button>
                  <button className="button button-danger" type="button" disabled={busy} onClick={() => setConfirm('delete')}>
                    Delete
                  </button>
                </div>
              )}
            </section>

            <section className="admin-card" id="author">
              <h2 className="eyebrow">Author</h2>
              <p className="admin-meta">
                {author?.initials ?? card.authorInitials} · {author?.email ?? card.authorEmail}
              </p>
              <div className="admin-badges">
                {author?.publishingSuspended || card.authorSuspended ? (
                  <span className="admin-badge admin-badge-alert">Publishing suspended</span>
                ) : (
                  <span className="admin-badge">Can publish</span>
                )}
                {author ? <span className="admin-badge">{author.publicCardCount} public</span> : null}
              </div>
              {author?.publishingSuspended || card.authorSuspended ? (
                <button
                  className="button button-secondary"
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(
                      () => adminFetch(`/api/admin/users/${card.authorId}/unsuspend`, { method: 'POST' }),
                      'Publishing restored.',
                      false,
                    )
                  }
                >
                  Unsuspend
                </button>
              ) : (
                <button className="button button-danger" type="button" disabled={busy || confirm !== null} onClick={() => setConfirm('suspend')}>
                  Suspend publishing
                </button>
              )}
              {others.length > 0 ? (
                <div className="admin-list">
                  {others.map((item) => (
                    <Link className="admin-row-link" key={item.cardId} href={cardHref(item.cardId, filters)}>
                      <p className="admin-excerpt">{item.thoughtExcerpt}</p>
                    </Link>
                  ))}
                </div>
              ) : null}
            </section>
          </article>
        ) : null}
      </AdminChrome>
      <AdminToast message={toast} tone={toastTone} />
    </div>
  );
}
