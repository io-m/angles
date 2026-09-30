import type { Metadata } from 'next';
import Link from 'next/link';

import { LegalPageShell } from '@/components/legal/LegalPageShell';
import { OperatorPostal } from '@/components/legal/OperatorIdentity';
import {
  LEGAL_EFFECTIVE_DATE,
  PRIVACY_PATH,
  SUPPORT_EMAIL,
  TERMS_PATH,
} from '@/lib/legalOperator';

const description =
  'Get help with Angles: restore purchases, delete your account, and how to reach support. Angles is not crisis care.';

export const metadata: Metadata = {
  title: 'Support',
  description,
  alternates: { canonical: '/support' },
  openGraph: { description },
  twitter: { description },
};

export default function SupportPage() {
  return (
    <LegalPageShell title="Support" updated={LEGAL_EFFECTIVE_DATE}>
      <p>
        Angles uses Sign in with Apple. There is no separate password and no
        in-app chat. Email is the way to reach us.
      </p>
      <p>
        Support: <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        <br />
        Postal address: <OperatorPostal />
      </p>

      <h2>Restore purchases</h2>
      <p>
        Your subscription is attached to your Apple ID and to the Angles
        account you were signed into when you bought it. After a reinstall, or
        on another iPhone signed into the same Apple ID, restore from the
        paywall’s information sheet, or from Profile → Settings → Subscription
        → Restore purchases. The phone needs a network connection so Apple and
        Angles can confirm the purchase.
      </p>
      <p>
        Subscriptions renew until you cancel them in your Apple ID subscription
        settings. We cannot cancel an App Store subscription for you. Deleting
        the Angles account or the app does not cancel it.
      </p>

      <h2>Delete your account</h2>
      <p>
        Profile → Settings → Delete account removes the Angles account, your
        cards, social relationships, and stored avatar from active systems
        after the server confirms. It does not cancel the Apple subscription.
      </p>

      <h2>Not crisis care</h2>
      <p>
        Angles is a reflection tool. It is not therapy, medical advice, or a
        crisis line. If you may harm yourself or someone else, contact local
        emergency services or a qualified crisis service. The app can show a
        regional crisis contact when a thought is flagged for safety. That
        line is not a substitute for emergency help, and writing to{' '}
        {SUPPORT_EMAIL} is not monitored as a crisis service.
      </p>

      <h2>Policies</h2>
      <p>
        <Link href={PRIVACY_PATH}>Privacy policy</Link>
        <br />
        <Link href={TERMS_PATH}>Terms of service</Link>
      </p>
    </LegalPageShell>
  );
}
