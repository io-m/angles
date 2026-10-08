const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const REPORT_TYPES = [
  { id: 'spam', label: 'Spam' },
  { id: 'harassment', label: 'Harassment' },
  { id: 'hate', label: 'Hate' },
  { id: 'sexual', label: 'Sexual' },
  { id: 'illegal', label: 'Illegal' },
  { id: 'personal_data', label: 'Personal data' },
  { id: 'other', label: 'Other' },
] as const;

const REASONS: Record<string, string> = Object.fromEntries(REPORT_TYPES.map((item) => [item.id, item.label]));

export type QueueFilters = {
  shelf: 'open' | 'reviewed';
  reason: string;
  visibility: 'all' | 'public' | 'private';
  suspendedOnly: boolean;
};

export function defaultFilters(): QueueFilters {
  return { shelf: 'open', reason: '', visibility: 'all', suspendedOnly: false };
}

export function readFilters(params: { get(name: string): string | null }): QueueFilters {
  const visibility = params.get('visibility');
  return {
    shelf: params.get('shelf') === 'reviewed' ? 'reviewed' : 'open',
    reason: params.get('reason') ?? '',
    visibility: visibility === 'public' || visibility === 'private' ? visibility : 'all',
    suspendedOnly: params.get('suspended') === '1',
  };
}

export function cardHref(cardId: string, filters: QueueFilters): string {
  const query = new URLSearchParams({ id: cardId, shelf: filters.shelf });
  if (filters.reason) {
    query.set('reason', filters.reason);
  }
  if (filters.visibility !== 'all') {
    query.set('visibility', filters.visibility);
  }
  if (filters.suspendedOnly) {
    query.set('suspended', '1');
  }
  return `/admin/card?${query}`;
}

export function matchesQueue(
  row: { reasons: Record<string, number>; isPublic: boolean; authorSuspended: boolean },
  filters: QueueFilters,
): boolean {
  if (filters.reason && !row.reasons[filters.reason]) {
    return false;
  }
  if (filters.visibility === 'public' && !row.isPublic) {
    return false;
  }
  if (filters.visibility === 'private' && row.isPublic) {
    return false;
  }
  if (filters.suspendedOnly && !row.authorSuspended) {
    return false;
  }
  return true;
}

const STYLES: Record<string, string> = {
  stoic: 'Stoic',
  optimistic: 'Optimistic',
  humorous: 'Humorous',
  tough_love: 'Tough love',
  tender: 'Tender',
  values: 'Values',
};

export function isUuid(value: string): boolean {
  return UUID.test(value);
}

export function reasonLine(reasons: Record<string, number>): string {
  const parts = Object.entries(reasons).map(([reason, count]) => `${REASONS[reason] ?? reason} ×${count}`);
  return parts.length > 0 ? parts.join(', ') : 'No open reports';
}

export function styleLabel(style: string): string {
  return STYLES[style] ?? style;
}

export function ageLabel(iso: string): string {
  const hours = (Date.now() - new Date(iso).getTime()) / 3_600_000;
  if (!Number.isFinite(hours) || hours < 0) {
    return 'just now';
  }
  if (hours < 1) {
    return `${Math.max(1, Math.round(hours * 60))}m ago`;
  }
  if (hours < 48) {
    return `${hours.toFixed(1)}h ago`;
  }
  return `${Math.round(hours / 24)}d ago`;
}
