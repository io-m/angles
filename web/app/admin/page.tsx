import { Suspense } from 'react';

import { ReportInbox } from '@/components/admin/ReportInbox';

export default function AdminPage() {
  return (
    <Suspense fallback={<div className="ops-content" aria-hidden="true" />}>
      <ReportInbox />
    </Suspense>
  );
}
