const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const REASONS: Record<string, string> = {
  spam: 'Spam',
  harassment: 'Harassment',
  hate: 'Hate',
  sexual: 'Sexual',
  illegal: 'Illegal',
  personal_data: 'Personal data',
  other: 'Other',
};

const STYLES: Record<string, string> = {
  stoic: 'Stoic',
  optimistic: 'Optimistic',
  humorous: 'Humorous',
  tough_love: 'Tough love',
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
