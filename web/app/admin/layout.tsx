import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Operator',
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
};

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <main className="admin-page">
      <div className="page-shell">{children}</div>
    </main>
  );
}
