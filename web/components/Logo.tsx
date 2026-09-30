import Link from 'next/link';

import { AnglesMark } from '@/components/AnglesMark';

export function Logo() {
  return (
    <Link className="brand" href="/">
      <AnglesMark className="brand-mark" />
      <span className="brand-name">Angles</span>
    </Link>
  );
}
