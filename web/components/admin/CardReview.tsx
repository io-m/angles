'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';

import { AdminChrome, AdminToast } from '@/components/admin/AdminChrome';
import {
  AdminApiError,
  adminFetch,
  stashToast,
  type AuthorReview,
  type CardReview as CardReviewBody,
} from '@/lib/adminApi';
import { isUuid, reasonLine, styleLabel } from '@/lib/adminLabels';

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
  const [email, setEmail] = useState<string | null>(null);
  const [card, setCard] = useState<CardReviewBody | null>(null);
  const [author, setAuthor] = useState<AuthorReview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [toastTone, setToastTone] = useState<'ok' | 'err'>('ok');
  const [confirm, setConfirm] = useState<ConfirmKind | null>(null);
  const [busy, setBusy] = useState(false);

  const showError = useCallback((caught: unknown): void => {
    setToastTone('err');
    setToast(caught instanceof Error ? caught.message : 'Something went wrong');
  }, []);

  const load = useCallback(async (isCurrent: () => boolean): Promise<void> => {
    if (!isUuid(cardId)) {
      setCard(null);
      setAuthor(null);
      setError(cardId ? 'That card id is not valid.' : 'Open a card from the inbox.');
      return;
    }
    const [session, nextCard] = await Promise.all([
      adminFetch<{ email: string }>('/api/admin/session'),
      adminFetch<CardReviewBody>(`/api/admin/reports/${cardId}`),
    ]);
    if (!isCurrent()) {
      return;
    }
    setEmail(session.email);
    setCard(nextCard);
    const nextAuthor = await adminFetch<AuthorReview>(`/api/admin/users/${nextCard.authorId}`);
    if (!isCurrent()) {
      return;
    }
    setAuthor(nextAuthor);
    setError(null);
  }, [cardId]);

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

  async function copyId(): Promise<void> {
    try {
      await navigator.clipboard.writeText(cardId);
      setToastTone('ok');
      setToast('Card id copied.');
    } catch {
      showError(new Error('Could not copy the card id.'));
    }
  }

  async function run(action: () => Promise<void>, success: string): Promise<void> {
    setBusy(true);
    setConfirm(null);
    try {
      await action();
      setToastTone('ok');
      setToast(success);
      await load(() => true);
    } catch (caught) {
      showError(caught);
    } finally {
      setBusy(false);
    }
  }

  async function removeCard(): Promise<void> {
    setBusy(true);
    setConfirm(null);
    try {
      await adminFetch(`/api/admin/reports/${cardId}/delete`, { method: 'POST' });
      stashToast('Card deleted.');
      router.replace('/admin');
    } catch (caught) {
      showError(caught);
      setBusy(false);
    }
  }

  return (
    <>
      <AdminChrome title="Card" email={email}>
        <p>
          <Link href="/admin">Back to reports</Link>
        </p>
        {error ? <p className="admin-status">{error}</p> : null}
        {!card && !error ? <p className="admin-status">Loading card…</p> : null}
        {card ? (
          <article className="admin-stack">
            <section className="admin-card">
              <div className="admin-id-row">
                <p className="admin-id">{card.cardId}</p>
                <button className="button button-secondary" type="button" onClick={() => void copyId()}>
                  Copy
                </button>
              </div>
              <div className="admin-badges">
                <span className="admin-badge">{card.isPublic ? 'Public' : 'Private'}</span>
                <span className="admin-badge">
                  {card.reportCount} open · {reasonLine(card.reasons)}
                </span>
                {card.authorSuspended ? <span className="admin-badge admin-badge-alert">Suspended</span> : null}
              </div>
              <div className="admin-section">
                <h2>Thought</h2>
                <p className="admin-copy">{card.thought}</p>
              </div>
              {card.reframes.map((item) => (
                <div className="admin-section" key={item.style}>
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
                          void run(
                            () => adminFetch(`/api/admin/reports/${card.cardId}/hide`, { method: 'POST' }),
                            'Card hidden.',
                          );
                        } else if (confirm === 'delete') {
                          void removeCard();
                        } else {
                          void run(
                            () => adminFetch(`/api/admin/users/${card.authorId}/suspend`, { method: 'POST' }),
                            'Publishing suspended.',
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
                      void run(
                        () => adminFetch(`/api/admin/reports/${card.cardId}/keep`, { method: 'POST' }),
                        'Reports dismissed.',
                      )
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
              <p className="admin-id">{card.authorId}</p>
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
            </section>
          </article>
        ) : null}
      </AdminChrome>
      <AdminToast message={toast} tone={toastTone} />
    </>
  );
}
