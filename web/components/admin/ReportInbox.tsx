'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import { AdminChrome, AdminToast } from '@/components/admin/AdminChrome';
import {
  AdminApiError,
  adminFetch,
  takeToast,
  type AuthorReview,
  type ReportDashboard,
  type ReportSummary,
  type ReviewedSummary,
  type SearchCard,
} from '@/lib/adminApi';
import {
  REPORT_TYPES,
  ageLabel,
  cardHref,
  defaultFilters,
  isUuid,
  matchesQueue,
  reasonLine,
  type QueueFilters,
} from '@/lib/adminLabels';

type QueueRow = {
  cardId: string;
  thoughtExcerpt: string;
  reasons: Record<string, number>;
  isPublic: boolean;
  authorSuspended: boolean;
  authorInitials: string;
  when: string;
  extra?: string;
};

export function ReportInbox() {
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);
  const [summary, setSummary] = useState<ReportDashboard | null>(null);
  const [openReports, setOpenReports] = useState<ReportSummary[] | null>(null);
  const [reviewed, setReviewed] = useState<ReviewedSummary[] | null>(null);
  const [filters, setFilters] = useState<QueueFilters>(defaultFilters);
  const [query, setQuery] = useState('');
  const [searchCards, setSearchCards] = useState<SearchCard[] | null>(null);
  const [searchUsers, setSearchUsers] = useState<AuthorReview[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [toastTone, setToastTone] = useState<'ok' | 'err'>('ok');

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
        const [counts, open] = await Promise.all([
          adminFetch<ReportDashboard>('/api/admin/reports/summary'),
          adminFetch<{ reports: ReportSummary[] }>('/api/admin/reports'),
        ]);
        if (!cancelled) {
          setSummary(counts);
          setOpenReports(open.reports);
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
    if (filters.shelf !== 'reviewed' || reviewed !== null) {
      return;
    }
    let cancelled = false;
    adminFetch<{ reports: ReviewedSummary[] }>('/api/admin/reports/reviewed')
      .then((body) => {
        if (!cancelled) {
          setReviewed(body.reports);
        }
      })
      .catch((caught: unknown) => {
        if (!cancelled) {
          setError(caught instanceof Error ? caught.message : 'Could not load reviewed reports');
        }
      });
    return () => {
      cancelled = true;
    };
  }, [filters.shelf, reviewed]);

  useEffect(() => {
    if (!toast) {
      return;
    }
    const timer = window.setTimeout(() => setToast(null), 4000);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < 2 && !isUuid(trimmed)) {
      setSearchCards(null);
      setSearchUsers(null);
      setSearching(false);
      return;
    }
    setSearching(true);
    let cancelled = false;
    const timer = window.setTimeout(() => {
      adminFetch<{ cards: SearchCard[]; users: AuthorReview[] }>(
        `/api/admin/search?q=${encodeURIComponent(trimmed)}`,
      )
        .then((body) => {
          if (cancelled) {
            return;
          }
          if (isUuid(trimmed) && body.cards.length === 1 && body.users.length === 0) {
            const match = body.cards[0];
            if (match) {
              router.push(cardHref(match.cardId, filters));
            }
            return;
          }
          setSearchCards(body.cards);
          setSearchUsers(body.users);
        })
        .catch((caught: unknown) => {
          if (cancelled) {
            return;
          }
          setToastTone('err');
          setToast(caught instanceof Error ? caught.message : 'Search failed');
        })
        .finally(() => {
          if (!cancelled) {
            setSearching(false);
          }
        });
    }, 250);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [filters, query, router]);

  const rows = useMemo(() => {
    const source: QueueRow[] =
      filters.shelf === 'reviewed'
        ? (reviewed ?? []).map((report) => ({
            cardId: report.cardId,
            thoughtExcerpt: report.thoughtExcerpt,
            reasons: report.reasons,
            isPublic: report.isPublic,
            authorSuspended: report.authorSuspended,
            authorInitials: report.authorInitials,
            when: ageLabel(report.reviewedAt),
            extra: report.resolution === 'hidden' ? 'Hidden' : 'Kept',
          }))
        : (openReports ?? []).map((report) => ({
            cardId: report.cardId,
            thoughtExcerpt: report.thoughtExcerpt,
            reasons: report.reasons,
            isPublic: report.isPublic,
            authorSuspended: report.authorSuspended,
            authorInitials: report.authorInitials,
            when: ageLabel(report.firstReportedAt),
            extra: `${report.reportCount} open`,
          }));
    return source.filter((row) => matchesQueue(row, filters));
  }, [filters, openReports, reviewed]);

  function patch(next: Partial<QueueFilters>): void {
    setQuery('');
    setFilters((current) => ({ ...current, ...next }));
  }

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

  const showingSearch = searchCards !== null;

  return (
    <>
      <AdminChrome title="Reports" email={email}>
        <ul className="admin-stats">
          <li>
            <button
              className="admin-stat"
              type="button"
              aria-pressed={filters.shelf === 'open' && filters.visibility === 'all' && !filters.suspendedOnly && !filters.reason}
              onClick={() => setFilters(defaultFilters())}
            >
              <strong>{summary?.openCount ?? '—'}</strong>
              <span>Open</span>
            </button>
          </li>
          <li>
            <button
              className="admin-stat"
              type="button"
              aria-pressed={filters.shelf === 'open' && filters.visibility === 'private'}
              onClick={() => patch({ shelf: 'open', visibility: 'private', suspendedOnly: false })}
            >
              <strong>{summary?.privateCount ?? '—'}</strong>
              <span>Already private</span>
            </button>
          </li>
          <li>
            <button
              className="admin-stat"
              type="button"
              aria-pressed={filters.suspendedOnly}
              onClick={() => patch({ shelf: 'open', suspendedOnly: !filters.suspendedOnly, visibility: 'all' })}
            >
              <strong>{summary?.suspendedAuthorCount ?? '—'}</strong>
              <span>Suspended authors</span>
            </button>
          </li>
          <li>
            <button
              className="admin-stat"
              type="button"
              aria-pressed={filters.shelf === 'reviewed'}
              onClick={() => patch({ shelf: 'reviewed', reason: '', visibility: 'all', suspendedOnly: false })}
            >
              <strong>{summary?.reviewedCount ?? '—'}</strong>
              <span>Reviewed</span>
            </button>
          </li>
        </ul>

        <ul className="admin-reasons">
          {REPORT_TYPES.map((type) => (
            <li key={type.id}>
              <button
                className="admin-reason"
                type="button"
                aria-pressed={filters.reason === type.id && filters.shelf === 'open'}
                onClick={() =>
                  patch({
                    shelf: 'open',
                    reason: filters.reason === type.id ? '' : type.id,
                  })
                }
              >
                <strong>{summary?.reasons[type.id] ?? 0}</strong>
                <span>{type.label}</span>
              </button>
            </li>
          ))}
        </ul>

        <div className="admin-toolbar">
          <form
            className="admin-search"
            onSubmit={(event) => {
              event.preventDefault();
            }}
          >
            <input
              aria-label="Search reports"
              value={query}
              placeholder="Search thought, email, or id"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              onChange={(event) => setQuery(event.target.value)}
            />
          </form>
          <button
            className="admin-chip"
            type="button"
            aria-pressed={filters.shelf === 'open'}
            onClick={() => patch({ shelf: 'open' })}
          >
            Open
          </button>
          <button
            className="admin-chip"
            type="button"
            aria-pressed={filters.shelf === 'reviewed'}
            onClick={() => patch({ shelf: 'reviewed' })}
          >
            Reviewed
          </button>
          <button
            className="admin-chip"
            type="button"
            aria-pressed={filters.visibility === 'public'}
            onClick={() => patch({ visibility: filters.visibility === 'public' ? 'all' : 'public' })}
          >
            Public
          </button>
          <button
            className="admin-chip"
            type="button"
            aria-pressed={filters.visibility === 'private'}
            onClick={() => patch({ visibility: filters.visibility === 'private' ? 'all' : 'private' })}
          >
            Private
          </button>
          <button
            className="admin-chip"
            type="button"
            aria-pressed={filters.suspendedOnly}
            onClick={() => patch({ suspendedOnly: !filters.suspendedOnly })}
          >
            Suspended
          </button>
        </div>

        {error ? <p className="admin-status">{error}</p> : null}
        {searching ? <p className="admin-status">Searching…</p> : null}

        {showingSearch ? (
          <div className="admin-list">
            {searchUsers?.map((user) => (
              <article className="admin-card" key={user.userId}>
                <p className="admin-excerpt">
                  {user.initials} · {user.email}
                </p>
                <div className="admin-badges">
                  <span className="admin-badge">{user.publicCardCount} public</span>
                  {user.publishingSuspended ? <span className="admin-badge admin-badge-alert">Suspended</span> : null}
                </div>
                <button className="button button-secondary" type="button" onClick={() => setQuery(user.email)}>
                  Show their cards
                </button>
              </article>
            ))}
            {searchCards?.map((card) => (
              <QueueCard
                key={card.cardId}
                row={{
                  cardId: card.cardId,
                  thoughtExcerpt: card.thoughtExcerpt,
                  reasons: card.reasons,
                  isPublic: card.isPublic,
                  authorSuspended: card.authorSuspended,
                  authorInitials: card.authorInitials,
                  when: card.authorEmail,
                  extra: `${card.reportCount} open`,
                }}
                href={cardHref(card.cardId, filters)}
                onCopy={() => void copyId(card.cardId)}
              />
            ))}
            {searchCards?.length === 0 && searchUsers?.length === 0 ? (
              <p className="admin-status">Nothing matches.</p>
            ) : null}
          </div>
        ) : (
          <div className="admin-list">
            {openReports === null && !error ? <p className="admin-status">Loading reports…</p> : null}
            {openReports && rows.length === 0 ? (
              <p className="admin-status">{filters.shelf === 'open' && summary?.openCount === 0 ? 'No open reports.' : 'Nothing matches.'}</p>
            ) : null}
            {rows.map((row) => (
              <QueueCard key={row.cardId} row={row} href={cardHref(row.cardId, filters)} onCopy={() => void copyId(row.cardId)} />
            ))}
          </div>
        )}
      </AdminChrome>
      <AdminToast message={toast} tone={toastTone} />
    </>
  );
}

function QueueCard({ row, href, onCopy }: { row: QueueRow; href: string; onCopy: () => void }) {
  return (
    <article className="admin-card admin-row">
      <Link className="admin-row-link" href={href}>
        <p className="admin-excerpt">{row.thoughtExcerpt}</p>
        <p className="admin-meta">
          {row.authorInitials} · {row.extra} · {row.when}
        </p>
        <div className="admin-badges">
          <span className="admin-badge">{reasonLine(row.reasons)}</span>
          <span className="admin-badge">{row.isPublic ? 'Public' : 'Private'}</span>
          {row.authorSuspended ? <span className="admin-badge admin-badge-alert">Suspended</span> : null}
        </div>
      </Link>
      <button className="admin-quiet" type="button" onClick={onCopy}>
        Copy id
      </button>
    </article>
  );
}
