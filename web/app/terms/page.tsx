import type { Metadata } from 'next';
import Link from 'next/link';

import { LegalPageShell } from '@/components/legal/LegalPageShell';
import {
  OperatorIdentity,
  OperatorPostal,
} from '@/components/legal/OperatorIdentity';
import {
  APPLE_STANDARD_EULA_URL,
  LEGAL_EFFECTIVE_DATE,
  MINIMUM_AGE,
  PRIVACY_PATH,
  SUPPORT_EMAIL,
} from '@/lib/legalOperator';

const description =
  'Terms of service for Angles, an iPhone app that turns a stuck thought into short reframes. Accounts, public cards, subscriptions, and acceptable use.';

export const metadata: Metadata = {
  title: 'Terms of service',
  description,
  alternates: { canonical: '/terms' },
  openGraph: { description },
  twitter: { description },
};

export default function TermsPage() {
  return (
    <LegalPageShell title="Terms of service" updated={LEGAL_EFFECTIVE_DATE}>
      <p>
        These Terms of Service (“Terms”) govern your use of Angles, operated by{' '}
        <OperatorIdentity /> (“Angles,” “we,” “us,” or “our”). By using Angles,
        you agree to these Terms and the{' '}
        <Link href={PRIVACY_PATH}>Privacy Policy</Link>. If you do not agree, do not
        use the service.
      </p>

      <h2>Eligibility and accounts</h2>
      <p>
        You must be at least {MINIMUM_AGE}, or the higher minimum age required
        where you live, and legally able to agree to these Terms. You sign in
        with Apple and are responsible for activity under your account and for
        protecting access to your device and Apple account. Provide accurate
        information and do not transfer or share your Angles account.
      </p>

      <h2>The service</h2>
      <p>
        Angles accepts a thought and uses AI providers to generate reframes in
        several styles. You can save cards privately or choose to post them
        publicly, view public cards, favorite angles, follow people, and use
        blocks and reports.
      </p>
      <p>
        Before your first thought is sent, the app asks you to agree to these
        Terms and the Privacy Policy and to allow what you write to be sent to
        our AI providers. Tapping <strong>Agree and continue</strong> records
        that agreement.
      </p>
      <p>
        The service may change, experience interruptions, or produce incomplete,
        inaccurate, offensive, or unsuitable output. You are responsible for
        evaluating and deciding whether to use any output.
      </p>

      <h2>Not medical or crisis care</h2>
      <p>
        Angles is a self-reflection tool. It is not therapy, medical or
        mental-health advice, diagnosis, treatment, emergency monitoring, or a
        substitute for a qualified professional. Angles does not create a
        clinician-patient relationship. If you may harm yourself or someone
        else, contact local emergency services or a qualified crisis service
        immediately.
      </p>

      <h2>Your content and privacy choices</h2>
      <p>
        You retain ownership of content you submit. You grant us a limited,
        worldwide license to host, process, reproduce, adapt, and display it
        only as needed to operate, secure, improve, and enforce the service.
      </p>
      <p>
        Saved cards are private unless you choose to post them. When you make a
        card public, you grant us a license to display and distribute that
        card, its reframes, and associated author information through Angles.
        You can later make it private or delete it, but other users may already
        have seen or captured it.
      </p>
      <p>
        Do not submit content you lack permission to use, confidential
        information you are not authorized to disclose, or another person’s
        personal data without a lawful basis.
      </p>

      <h2>Acceptable use</h2>
      <p>You may not:</p>
      <ul>
        <li>break the law or violate another person’s rights;</li>
        <li>
          threaten, harass, exploit, impersonate, or promote hatred or
          violence;
        </li>
        <li>post sexual exploitation material or other illegal content;</li>
        <li>
          reveal private personal information, spam, manipulate engagement, or
          evade blocks;
        </li>
        <li>
          probe, scrape, reverse engineer, overload, disrupt, or bypass
          security, moderation, access, or usage limits;
        </li>
        <li>use automated access except where we expressly authorize it; or</li>
        <li>
          represent AI output as professional advice or guaranteed fact.
        </li>
      </ul>

      <h2>Community moderation</h2>
      <p>
        Angles has zero tolerance for objectionable content and abusive users.
        Do not post content that is hateful, harassing, sexual, violent,
        threatening, or otherwise objectionable, and do not abuse other people.
        Every card you post is checked automatically before anyone else can see
        it. We review reported content within 24 hours, remove content that
        breaks these Terms, and remove the accounts of users who post it.
      </p>
      <p>
        We may also review reports and use automated or human moderation to reject,
        limit, make private, remove, or preserve content; restrict features;
        suspend or terminate accounts; and cooperate with authorities where
        appropriate. Blocking changes what you see but does not guarantee that
        another person cannot encounter public content elsewhere. We do not
        guarantee that all objectionable content will be detected or removed
        immediately.
      </p>

      <h2>Subscriptions, billing, and cancellation</h2>
      <p>
        Paid membership is sold through Apple’s App Store. The price, billing
        period, included features, and any trial are shown before purchase.
        Payment is charged to your Apple ID. Subscriptions renew automatically
        unless canceled at least 24 hours before the current period ends,
        subject to Apple’s rules. Apple handles billing, refunds, renewal, and
        cancellation.
      </p>
      <p>
        Cancel through your Apple subscription settings. Cancellation stops
        future renewal but normally leaves access through the paid period.
        Deleting your Angles account or app does not cancel your Apple
        subscription. Restore Purchases can restore an eligible entitlement
        associated with your Apple account.
      </p>

      <h2>Monthly credits and usage limits</h2>
      <p>
        Angles may allocate monthly AI-use credits or other usage limits to a
        subscription. Any allowance displayed in the app or purchase description
        is part of that subscription period. Credits:
      </p>
      <ul>
        <li>
          are a limited license to use eligible Angles features, not money or
          stored value;
        </li>
        <li>
          are personal, nontransferable, nonrefundable, and have no cash value;
        </li>
        <li>
          cannot be sold, gifted, exchanged, or moved between accounts;
        </li>
        <li>
          expire at the end of the applicable monthly billing or allowance
          period and do not roll over; and
        </li>
        <li>
          may be consumed at different rates by different models or operations,
          as disclosed in the app.
        </li>
      </ul>
      <p>
        We do not sell separate credit packs. Each monthly membership period
        currently includes 600 credits. Each ready result uses one credit, while
        continue, safety, and failed operations use no user credits. We may
        also enforce reasonable technical or fair-use limits to protect the
        service. A provider outage or safety refusal may prevent a request
        without guaranteeing a replacement output.
      </p>

      <h2>Intellectual property</h2>
      <p>
        Angles, its software, design, branding, and service content other than
        user content are owned by us or our licensors. These Terms grant you a
        personal, limited, revocable, nonexclusive, nontransferable license to
        use the app for its intended purpose. No other rights are granted.
      </p>

      <h2>Apple App Store</h2>
      <p>
        If you downloaded Angles from Apple’s App Store, Apple’s{' '}
        <a href={APPLE_STANDARD_EULA_URL}>
          Standard Licensed Application End User License Agreement
        </a>{' '}
        also applies to your use of the app. Where it conflicts with these Terms
        about the license to the app itself, the Apple agreement controls.
        Apple is not responsible for Angles or its content and has no
        obligation to provide support for it.
      </p>

      <h2>Third-party services</h2>
      <p>
        Angles relies on Apple, AI providers, hosting, storage, and other
        service providers. Their terms may also apply. We are not responsible
        for third-party services outside our control.
      </p>

      <h2>Suspension and termination</h2>
      <p>
        You may stop using Angles at any time and may delete your account in
        Settings. We may suspend or terminate access for violations, safety or
        legal risk, fraud, nonpayment, abuse, or service discontinuation.
        Sections that by their nature should survive termination will survive.
      </p>

      <h2>Disclaimers</h2>
      <p>
        To the maximum extent allowed by law, Angles is provided “as is” and
        “as available.” We disclaim implied warranties, including
        merchantability, fitness for a particular purpose, and noninfringement.
        We do not warrant uninterrupted operation, preservation of content, or
        that AI output is accurate, safe, or suitable.
      </p>

      <h2>Limitation of liability</h2>
      <p>
        To the maximum extent allowed by law, Angles and its operator,
        affiliates, and providers will not be liable for indirect, incidental,
        special, consequential, exemplary, or punitive damages, lost profits,
        lost data, or decisions made from AI output. Our aggregate liability
        arising from the service will not exceed the greater of the amount you
        paid for Angles in the 12 months before the claim or USD $100. Some
        jurisdictions do not allow all limitations, so they apply only to the
        extent permitted.
      </p>

      <h2>Indemnity</h2>
      <p>
        Where permitted by law, you will indemnify and hold us harmless from
        claims arising from your unlawful use, your public content, or your
        violation of these Terms or another person’s rights.
      </p>

      <h2>Governing law and disputes</h2>
      <p>
        These Terms are governed by the laws of Denmark, without regard to
        conflict-of-law rules, and without affecting any mandatory consumer
        protections that apply where you live. Courts in Denmark have
        jurisdiction, without limiting your right, if you are a consumer in the
        EU, to bring proceedings in the courts of your country of residence.
      </p>

      <h2>Changes</h2>
      <p>
        We may update these Terms. We will update the date above and provide
        notice when required. Continuing to use Angles after an update takes
        effect means you accept the updated Terms.
      </p>

      <h2>Contact</h2>
      <p>
        Support: <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        <br />
        Postal address: <OperatorPostal />
      </p>
    </LegalPageShell>
  );
}
