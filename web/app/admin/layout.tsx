import type { Metadata } from 'next';
import type { ReactNode } from 'react';

import './admin.css';

export const metadata: Metadata = {
  title: 'Operator',
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
};

export default function AdminLayout({ children }: { children: ReactNode }) {
  return <div className="ops-root">{children}</div>;
}
