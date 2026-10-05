'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import { AdminShell, AdminToast } from '@/components/admin/AdminChrome';
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
  readFilters,
  type QueueFilters,
} from '@/lib/adminLabels';

const REASON_TONE: Record<string, string> = {
  spam: 'amber',
  harassment: 'red',
  hate: 'red',
  sexual: 'violet',
  illegal: 'dark',
  personal_data: 'blue',
  other: '',
};

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

function reasonEntries(reasons: Record<string, number>): Array<{ id: string; label: string; count: number }> {
  return Object.entries(reasons).map(([id, count]) => ({
    id,
    label: REPORT_TYPES.find((item) => item.id === id)?.label ?? id,
    count,
  }));
}

export function ReportInbox() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState<string | null>(null);
  const [summary, setSummary] = useState<ReportDashboard | null>(null);
  const [openReports, setOpenReports] = useState<ReportSummary[] | null>(null);
  const [reviewed, setReviewed] = useState<ReviewedSummary[] | null>(null);
  const [filters, setFilters] = useState<QueueFilters>(() => readFilters(params));
  const [query, setQuery] = useState('');
  const [searchCards, setSearchCards] = useState<SearchCard[] | null>(null);
  const [searchUsers, setSearchUsers] = useState<AuthorReview[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [toastTone, setToastTone] = useState<'ok' | 'err'>('ok');

  useEffect(() => {
    const shelf = params.get('shelf');
    setFilters((current) =>
      shelf === 'reviewed' || shelf === 'open' ? { ...current, shelf } : current,
    );
  }, [params]);

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
  const activeReason = REPORT_TYPES.find((item) => item.id === filters.reason)?.label;

  return (
    <>
      <AdminShell
        email={email}
        openCount={summary?.openCount}
        reviewedCount={summary?.reviewedCount}
        title="Reports"
        subtitle={
          filters.shelf === 'reviewed'
            ? 'Latest decisions, newest first.'
            : activeReason
              ? `Open reports filed as ${activeReason}.`
              : 'Open reports, oldest first.'
        }
      >
        <ul className="ops-stats">
          <li>
            <button
              className="ops-stat"
              type="button"
              aria-pressed={filters.shelf === 'open' && filters.visibility === 'all' && !filters.suspendedOnly && !filters.reason}
              onClick={() => setFilters(defaultFilters())}
            >
              <span className="ops-stat-value">{summary?.openCount ?? '—'}</span>
              <span className="ops-stat-label">Open reports</span>
            </button>
          </li>
          <li>
            <button
              className="ops-stat"
              type="button"
              aria-pressed={filters.shelf === 'open' && filters.visibility === 'private'}
              onClick={() => patch({ shelf: 'open', visibility: 'private', suspendedOnly: false })}
            >
              <span className="ops-stat-value">{summary?.privateCount ?? '—'}</span>
              <span className="ops-stat-label">Already private</span>
            </button>
          </li>
          <li>
            <button
              className="ops-stat"
              type="button"
              aria-pressed={filters.suspendedOnly}
              onClick={() => patch({ shelf: 'open', suspendedOnly: !filters.suspendedOnly, visibility: 'all' })}
            >
              <span className="ops-stat-value">{summary?.suspendedAuthorCount ?? '—'}</span>
              <span className="ops-stat-label">Suspended authors</span>
            </button>
          </li>
          <li>
            <button
              className="ops-stat"
              type="button"
              aria-pressed={filters.shelf === 'reviewed'}
              onClick={() => patch({ shelf: 'reviewed', reason: '', visibility: 'all', suspendedOnly: false })}
            >
              <span className="ops-stat-value">{summary?.reviewedCount ?? '—'}</span>
              <span className="ops-stat-label">Reviewed</span>
            </button>
          </li>
        </ul>

        <ul className="ops-reasons">
          {REPORT_TYPES.map((type) => (
            <li key={type.id}>
              <button
                className="ops-reason"
                type="button"
                aria-pressed={filters.reason === type.id && filters.shelf === 'open'}
                onClick={() =>
                  patch({
                    shelf: 'open',
                    reason: filters.reason === type.id ? '' : type.id,
                  })
                }
              >
                <span className="ops-reason-name">{type.label}</span>
                <span className="ops-reason-count">{summary?.reasons[type.id] ?? 0}</span>
              </button>
            </li>
          ))}
        </ul>

        <div className="ops-toolbar">
          <form
            className="ops-search"
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
          <div className="ops-segment" role="group" aria-label="Shelf">
            <button
              className="ops-chip"
              type="button"
              aria-pressed={filters.shelf === 'open'}
              onClick={() => patch({ shelf: 'open' })}
            >
              Open
            </button>
            <button
              className="ops-chip"
              type="button"
              aria-pressed={filters.shelf === 'reviewed'}
              onClick={() => patch({ shelf: 'reviewed' })}
            >
              Reviewed
            </button>
          </div>
          <button
            className="ops-pill-btn"
            type="button"
            aria-pressed={filters.visibility === 'public'}
            onClick={() => patch({ visibility: filters.visibility === 'public' ? 'all' : 'public' })}
          >
            Public
          </button>
          <button
            className="ops-pill-btn"
            type="button"
            aria-pressed={filters.visibility === 'private'}
            onClick={() => patch({ visibility: filters.visibility === 'private' ? 'all' : 'private' })}
          >
            Private
          </button>
          <button
            className="ops-pill-btn"
            type="button"
            aria-pressed={filters.suspendedOnly}
            onClick={() => patch({ suspendedOnly: !filters.suspendedOnly })}
          >
            Suspended
          </button>
        </div>

        {error ? (
          <p className="ops-banner" data-tone="error">
            {error}
          </p>
        ) : null}
        {searching ? <p className="ops-banner">Searching…</p> : null}

        {showingSearch ? (
          <ul className="ops-queue">
            {searchUsers?.map((user) => (
              <li className="ops-row" key={user.userId}>
                <div className="ops-row-link">
                  <p className="ops-excerpt">
                    {user.initials} · {user.email}
                  </p>
                  <div className="ops-pills">
                    <span className="ops-pill">{user.publicCardCount} public</span>
                    {user.publishingSuspended ? (
                      <span className="ops-pill" data-tone="red">
                        Suspended
                      </span>
                    ) : null}
                  </div>
                </div>
                <div className="ops-row-side">
                  <button className="ops-mini-btn" type="button" onClick={() => setQuery(user.email)}>
                    Their cards
                  </button>
                </div>
              </li>
            ))}
            {searchCards?.map((card) => (
              <QueueRow
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
              <li className="ops-empty">Nothing matches.</li>
            ) : null}
          </ul>
        ) : (
          <ul className="ops-queue">
            {openReports === null && !error ? (
              <>
                <li className="ops-skeleton" aria-hidden="true" />
                <li className="ops-skeleton" aria-hidden="true" />
                <li className="ops-skeleton" aria-hidden="true" />
              </>
            ) : null}
            {openReports && rows.length === 0 ? (
              <li className="ops-empty">
                {filters.shelf === 'open' && summary?.openCount === 0 ? 'No open reports.' : 'Nothing matches these filters.'}
              </li>
            ) : null}
            {rows.map((row) => (
              <QueueRow key={row.cardId} row={row} href={cardHref(row.cardId, filters)} onCopy={() => void copyId(row.cardId)} />
            ))}
          </ul>
        )}
      </AdminShell>
      <AdminToast message={toast} tone={toastTone} />
    </>
  );
}

function QueueRow({ row, href, onCopy }: { row: QueueRow; href: string; onCopy: () => void }) {
  return (
    <li className="ops-row">
      <Link className="ops-row-link" href={href}>
        <p className="ops-excerpt">{row.thoughtExcerpt}</p>
        <p className="ops-row-meta">
          {row.authorInitials} · {row.extra} · {row.when}
        </p>
        <div className="ops-pills">
          {reasonEntries(row.reasons).map((reason) => (
            <span key={reason.id} className="ops-pill" data-tone={REASON_TONE[reason.id] || undefined}>
              {reason.label} ×{reason.count}
            </span>
          ))}
          <span className="ops-pill">{row.isPublic ? 'Public' : 'Private'}</span>
          {row.authorSuspended ? (
            <span className="ops-pill" data-tone="red">
              Suspended
            </span>
          ) : null}
        </div>
      </Link>
      <div className="ops-row-side">
        <span className="ops-chevron" aria-hidden="true">
          ›
        </span>
        <button
          className="ops-mini-btn"
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onCopy();
          }}
        >
          Copy id
        </button>
      </div>
    </li>
  );
}
