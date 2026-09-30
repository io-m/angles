import type { Metadata } from 'next';
import Link from 'next/link';

import { LegalPageShell } from '@/components/legal/LegalPageShell';
import {
  OperatorIdentity,
  OperatorPostal,
} from '@/components/legal/OperatorIdentity';
import {
  LEGAL_EFFECTIVE_DATE,
  MINIMUM_AGE,
  PRIVACY_EMAIL,
  SUPERVISORY_AUTHORITY_NAME,
  SUPERVISORY_AUTHORITY_URL,
  SUPPORT_EMAIL,
  TERMS_PATH,
} from '@/lib/legalOperator';

const description =
  'How Angles handles your account, thoughts, cards, community activity, and subscription. Operated by Bithavn in Denmark.';

export const metadata: Metadata = {
  title: 'Privacy policy',
  description,
  alternates: { canonical: '/privacy' },
  openGraph: { description },
  twitter: { description },
};

export default function PrivacyPage() {
  return (
    <LegalPageShell title="Privacy policy" updated={LEGAL_EFFECTIVE_DATE}>
      <p>
        Angles (“we,” “us,” or “our”) is operated by <OperatorIdentity />. This
        policy explains how Angles handles information when you use the iOS app
        and its services. The terms of service are at{' '}
        <Link href={TERMS_PATH}>useangles.app/terms</Link>.
      </p>
      <p>
        <strong>Privacy contact:</strong>{' '}
        <a href={`mailto:${PRIVACY_EMAIL}`}>{PRIVACY_EMAIL}</a>
        <br />
        <strong>Postal address:</strong> <OperatorPostal />
      </p>
      <p>
        You may also complain to{' '}
        <a href={SUPERVISORY_AUTHORITY_URL}>{SUPERVISORY_AUTHORITY_NAME}</a>,
        the Danish data protection authority.
      </p>

      <h2>Information we handle</h2>
      <ul>
        <li>
          <strong>Apple sign-in and account information.</strong> We receive an
          Apple account identifier and, when Apple provides them, your name and
          relay or account email address. We store account and session
          identifiers, your chosen display name or initials, and
          authentication and session records.
        </li>
        <li>
          <strong>Thoughts and reframes.</strong> We process the text you
          submit, follow-up answers, generated reframes (in English and, when
          you write in another language, in that language), the AI model used,
          language, tags, category, mood, intensity, timeframe, safety
          classification, and related card metadata. Do not submit information
          you do not want processed.
        </li>
        <li>
          <strong>Cards and community activity.</strong> Saved cards are
          private unless you choose to post them publicly. Public cards can be
          seen by other users. We process favorites, follows, blocks, and
          reports needed to provide and moderate the community.
        </li>
        <li>
          <strong>Profile photos.</strong> If you choose a photo, we upload and
          store a JPEG avatar. Avatars are displayed with your public cards
          and profile activity.
        </li>
        <li>
          <strong>Subscription and purchase information.</strong> Apple
          processes payment. We receive and verify signed product, entitlement,
          renewal and expiration, transaction, refund and revocation, and
          purchase-status information needed to bind membership to your Angles
          account, restore access, and maintain monthly credit periods. We do
          not receive your full payment-card details.
        </li>
        <li>
          <strong>Usage and metering information.</strong> We maintain
          account-linked monthly credit balances, request identifiers and
          text-free request fingerprints, operation status, the AI model used,
          rate and tariff versions, and abuse-limit counters. For each actual
          AI-provider attempt, including failed attempts, we record available
          or estimated token counts, provider request identifiers, success or
          failure status, and calculated company cost. The metering and
          provider-cost records do not contain your thought or generated
          reframe text. So that a lost connection does not charge you twice, we
          keep the finished response to each request for one hour, encrypted
          under a key that only your device holds and that we do not store. We
          cannot read it, and it is deleted after that hour or with your
          account.
        </li>
        <li>
          <strong>Region.</strong> When you compose, your device’s region
          setting (for example “US”) is sent so we can show the right crisis
          contacts if you need them. It is not sent to AI providers.
        </li>
        <li>
          <strong>Technical and security information.</strong> Our
          authentication and hosting systems may process IP address, user
          agent, request timing, errors, and similar security or operational
          records. We do not log the text of your thoughts in application logs.
        </li>
      </ul>

      <h2>How we use information</h2>
      <p>We use this information to:</p>
      <ul>
        <li>authenticate accounts and keep sessions secure;</li>
        <li>
          generate reframes, save and display cards, and provide community
          features;
        </li>
        <li>
          provide, verify, restore, and support subscriptions and monthly
          credits;
        </li>
        <li>
          enforce privacy choices, blocks, reports, safety rules, and our
          Terms;
        </li>
        <li>prevent abuse, troubleshoot failures, and maintain the service; and</li>
        <li>comply with law and protect users, the public, and the service.</li>
      </ul>

      <h2>AI processing</h2>
      <p>
        Angles sends the thought text and conversation context needed to
        generate a response to the configured large-language-model provider. We
        choose the provider for each step on our servers. It may be Mistral AI,
        Google Gemini, or DeepSeek, and if the first provider is unavailable
        the same request may be sent to another of them. Those providers
        process the content on our behalf or under the service configuration
        and terms applicable to our account.
      </p>
      <p>
        Do not use Angles for emergency or highly sensitive information.
        Provider retention, regional processing, and model-improvement controls
        can vary by provider and configuration.
      </p>

      <h2>Private and public content</h2>
      <p>
        Cards are stored privately unless you choose to post them. A public
        card, its generated English reframes, author initials or avatar, and
        date may be visible to other users. A reframe in your own language is
        shown only to you. Making a card private removes it from public
        surfaces. Other users may have previously seen or captured public
        content.
      </p>
      <p>
        Favorites of another person’s card remain available only while that
        card remains public. Follows are visible through the app’s social
        features. Blocking removes the affected public content and follow or
        save relationships between those accounts from their in-app experiences
        and records the block. Reports include the reported card, reporter,
        selected reason, and time so we can review and enforce community rules.
        Reporting removes that card from the reporter’s experience. Repeated
        reports can automatically make a card private.
      </p>

      <h2>Sharing and service providers</h2>
      <p>We disclose information only as needed to operate Angles, including to:</p>
      <ul>
        <li>
          Apple for Sign in with Apple, StoreKit subscriptions, and App Store
          services;
        </li>
        <li>configured AI providers for reframe generation;</li>
        <li>
          hosting, database, object-storage, authentication, and infrastructure
          providers;
        </li>
        <li>
          professional advisers, authorities, or counterparties when required
          by law, safety, fraud prevention, or a business transaction.
        </li>
      </ul>
      <p>
        We do not sell personal information. Angles does not use third-party
        advertising, cross-app tracking, or tracking for targeted advertising.
        This marketing website is static. It does not use cookies, analytics,
        or accounts. If you email us, we keep that message only as long as
        needed to reply and run the service.
      </p>

      <h2>Retention and deletion</h2>
      <p>
        We keep account data and saved cards while your account is active and
        as needed to provide the service. Operational, security, report, and
        legal records may be kept for a reasonable period where necessary to
        prevent abuse, resolve disputes, or comply with law.
      </p>
      <p>
        You can delete individual cards in the app. You can delete your account
        in Settings. That deletes your Angles account, cards, social
        relationships, blocks, reports tied to your account, sessions, and
        stored avatar from active systems. Backups and provider records may
        persist for a limited period according to provider backup, security,
        and legal-retention schedules. Account deletion does not cancel an
        Apple subscription. Manage or cancel it through Apple.
      </p>

      <h2>Security and international processing</h2>
      <p>
        We use reasonable administrative and technical safeguards, but no
        service is completely secure. Angles and its providers may process
        information in countries other than your own, subject to applicable
        legal safeguards.
      </p>

      <h2>Children</h2>
      <p>
        Angles is not directed to children under {MINIMUM_AGE}, or the higher
        minimum age required where they live. We do not knowingly collect
        personal information from children below that age. Contact us if you
        believe a child has provided information.
      </p>

      <h2>Mental-health notice</h2>
      <p>
        Angles is a reflection and reframing tool, not medical care, therapy,
        diagnosis, crisis support, or professional advice. It may produce
        inaccurate or unsuitable output. If you may harm yourself or someone
        else, contact local emergency services or a qualified crisis service
        immediately.
      </p>

      <h2>Your choices and rights</h2>
      <p>
        You can make cards private, delete cards, remove an avatar, unfollow or
        block people, and delete your account in Settings. Depending on your
        location, you may also have rights to access, correct, delete,
        restrict, or object to processing, or to receive a portable copy of
        certain information. Write to{' '}
        <a href={`mailto:${PRIVACY_EMAIL}`}>{PRIVACY_EMAIL}</a>.
      </p>

      <h2>Changes</h2>
      <p>
        We may update this policy as Angles changes. We will update the date
        above and provide additional notice when required.
      </p>

      <h2>Contact</h2>
      <p>
        Privacy requests:{' '}
        <a href={`mailto:${PRIVACY_EMAIL}`}>{PRIVACY_EMAIL}</a>
        <br />
        Support: <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        <br />
        Postal address: <OperatorPostal />
      </p>
    </LegalPageShell>
  );
}
