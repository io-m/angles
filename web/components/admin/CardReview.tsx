'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';

import { AdminShell, AdminToast } from '@/components/admin/AdminChrome';
import { REPORT_TYPES } from '@/lib/adminLabels';
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
import { cardHref, isUuid, matchesQueue, readFilters, styleLabel, type QueueFilters } from '@/lib/adminLabels';

type ConfirmKind = 'hide' | 'publish' | 'delete' | 'suspend';

const CONFIRM: Record<ConfirmKind, { title: string; label: string }> = {
  hide: {
    title: 'Hide this card? It becomes private, the author is told it broke the rules, and they cannot publish it again until an operator does.',
    label: 'Hide card',
  },
  publish: {
    title: 'Make this card public again? It returns to Home, and the author can change it after that.',
    label: 'Make public',
  },
  delete: {
    title: 'Delete this card? This cannot be undone.',
    label: 'Delete card',
  },
  suspend: {
    title: 'Suspend publishing? Every card from this account goes private until you unsuspend them.',
    label: 'Suspend',
  },
};

const REASON_TONE: Record<string, string> = {
  spam: 'amber',
  harassment: 'red',
  hate: 'red',
  sexual: 'violet',
  illegal: 'dark',
  personal_data: 'blue',
  other: '',
};

function reasonLabel(id: string): string {
  return REPORT_TYPES.find((item) => item.id === id)?.label ?? id;
}

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
  const suspended = Boolean(author?.publishingSuspended || card?.authorSuspended);

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
    <>
      <AdminShell
        email={email}
        title={card?.thought ?? 'Review'}
        subtitle={position ? `Report ${position} in this queue.` : 'Report detail.'}
        actions={
          nextId ? (
            <Link className="ops-btn ops-btn-secondary" style={{ flex: '0 0 auto', textDecoration: 'none', display: 'inline-flex', alignItems: 'center' }} href={cardHref(nextId, filters)}>
              Next →
            </Link>
          ) : undefined
        }
      >
        <div className="ops-toolbar" style={{ marginBottom: 16 }}>
          <Link className="ops-back" href="/admin">
            ← Back to reports
          </Link>
          {position ? <span className="ops-position">{position}</span> : null}
        </div>

        {error ? (
          <p className="ops-banner" data-tone="error">
            {error}
          </p>
        ) : null}
        {!card && !error ? (
          <>
            <div className="ops-skeleton" aria-hidden="true" />
            <div className="ops-skeleton" aria-hidden="true" />
          </>
        ) : null}

        {card ? (
          <div className="ops-review-grid">
            <section className="ops-card" aria-label="Reported card">
              <div className="ops-card-head">
                <div className="ops-pills">
                  <span className="ops-pill">{card.isPublic ? 'Public' : 'Private'}</span>
                  {Object.entries(card.reasons).map(([id, count]) => (
                    <span key={id} className="ops-pill" data-tone={REASON_TONE[id] || undefined}>
                      {reasonLabel(id)} ×{count}
                    </span>
                  ))}
                  {card.authorSuspended ? (
                    <span className="ops-pill" data-tone="red">
                      Author suspended
                    </span>
                  ) : null}
                </div>
                <p className="ops-mono">
                  {card.cardId}{' '}
                  <button
                    className="ops-mini-btn"
                    type="button"
                    onClick={() => void copyId()}
                    style={{ marginLeft: 6 }}
                  >
                    Copy
                  </button>
                </p>
              </div>

              <p className="ops-thought">{card.thought}</p>

              {card.reframes.map((item) => (
                <div className="ops-answer" key={item.style}>
                  <h2>{styleLabel(item.style)}</h2>
                  <p>{item.reframe}</p>
                </div>
              ))}

              {confirm ? (
                <div className="ops-confirm" role="dialog" aria-labelledby="confirm-title">
                  <p id="confirm-title">
                    <strong>{CONFIRM[confirm].label}.</strong> {CONFIRM[confirm].title}
                  </p>
                  <div className="ops-confirm-actions">
                    <button className="ops-btn ops-btn-secondary" type="button" disabled={busy} onClick={() => setConfirm(null)}>
                      Cancel
                    </button>
                    <button
                      className={confirm === 'publish' ? 'ops-btn ops-btn-primary' : 'ops-btn ops-btn-danger'}
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        if (confirm === 'hide') {
                          void run(() => adminFetch(`/api/admin/reports/${card.cardId}/hide`, { method: 'POST' }), 'Card hidden.', true);
                        } else if (confirm === 'publish') {
                          void run(
                            () => adminFetch(`/api/admin/reports/${card.cardId}/publish`, { method: 'POST' }),
                            'Card is public again.',
                            false,
                          );
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
                <div className="ops-actionbar">
                  <button
                    className="ops-btn ops-btn-primary"
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void run(() => adminFetch(`/api/admin/reports/${card.cardId}/keep`, { method: 'POST' }), 'Reports dismissed.', true)
                    }
                  >
                    Keep
                  </button>
                  <button className="ops-btn ops-btn-secondary" type="button" disabled={busy} onClick={() => setConfirm('hide')}>
                    Hide
                  </button>
                  {card.isPublic ? null : (
                    <button className="ops-btn ops-btn-primary" type="button" disabled={busy} onClick={() => setConfirm('publish')}>
                      Make public
                    </button>
                  )}
                  <button className="ops-btn ops-btn-danger" type="button" disabled={busy} onClick={() => setConfirm('delete')}>
                    Delete
                  </button>
                </div>
              )}
            </section>

            <aside className="ops-card" aria-label="Author">
              <h2 className="ops-rail-title">Author</h2>
              <p className="ops-author">
                {author?.initials ?? card.authorInitials} · {author?.email ?? card.authorEmail}
              </p>
              <div className="ops-pills">
                {suspended ? (
                  <span className="ops-pill" data-tone="red">
                    Suspended
                  </span>
                ) : (
                  <span className="ops-pill" data-tone="green">
                    Can publish
                  </span>
                )}
                {author ? <span className="ops-pill">{author.publicCardCount} public</span> : null}
              </div>
              {suspended ? (
                <button
                  className="ops-btn ops-btn-secondary"
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
                <button
                  className="ops-btn ops-btn-secondary"
                  type="button"
                  disabled={busy || confirm !== null}
                  onClick={() => setConfirm('suspend')}
                >
                  Suspend publishing
                </button>
              )}
              {others.length > 0 ? (
                <div>
                  <h2 className="ops-rail-title" style={{ marginBottom: 6 }}>
                    Other public cards
                  </h2>
                  <ul className="ops-others">
                    {others.map((item) => (
                      <li key={item.cardId}>
                        <Link href={cardHref(item.cardId, filters)}>{item.thoughtExcerpt}</Link>
                      </li>
                    ))}
                  </ul>
                </div>
              ) : null}
            </aside>
          </div>
        ) : null}
      </AdminShell>
      <AdminToast message={toast} tone={toastTone} />
    </>
  );
}
