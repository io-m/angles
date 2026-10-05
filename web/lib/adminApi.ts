export type ReportSummary = {
  cardId: string;
  authorId: string;
  authorInitials: string;
  authorSuspended: boolean;
  isPublic: boolean;
  firstReportedAt: string;
  reasons: Record<string, number>;
  reportCount: number;
};

export type CardReview = ReportSummary & {
  authorEmail: string;
  firstReportedAt: string | null;
  thought: string;
  reframes: { style: string; reframe: string }[];
};

export type AuthorReview = {
  userId: string;
  email: string;
  initials: string;
  publishingSuspended: boolean;
  publicCardCount: number;
};

export class AdminApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = 'AdminApiError';
    this.status = status;
    this.code = code;
  }
}

const TOAST_KEY = 'angles-admin-toast';

export function stashToast(text: string): void {
  sessionStorage.setItem(TOAST_KEY, text);
}

export function takeToast(): string | null {
  const text = sessionStorage.getItem(TOAST_KEY);
  if (text) {
    sessionStorage.removeItem(TOAST_KEY);
  }
  return text;
}

export async function adminFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers);
  if (init?.body && !headers.has('content-type')) {
    headers.set('content-type', 'application/json');
  }
  const response = await fetch(path, {
    ...init,
    headers,
    credentials: 'include',
  });
  const text = await response.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text) as unknown;
    } catch {
      body = null;
    }
  }
  if (!response.ok) {
    const record = body && typeof body === 'object' ? (body as { error?: unknown; code?: unknown }) : {};
    const message = typeof record.error === 'string' ? record.error : 'Request failed';
    const code = typeof record.code === 'string' ? record.code : 'REQUEST_FAILED';
    throw new AdminApiError(response.status, code, message);
  }
  return body as T;
}
