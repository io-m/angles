import { Suspense } from 'react';

import { CardReview } from '@/components/admin/CardReview';

export default function AdminCardPage() {
  return (
    <Suspense fallback={<p className="admin-status">Loading card…</p>}>
      <CardReview />
    </Suspense>
  );
}
