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
        Angles (“we,” “us,” or “our”) is operated by <OperatorIdentity />, the
        data controller. This policy explains how Angles handles information when you use the iOS app
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
          account, restore access, and maintain monthly credit periods. When
          you buy, the app gives Apple your Angles account identifier (a random
          ID, not your name or email) with the purchase so Apple’s records can
          be matched to your account. We do not receive your full payment-card
          details.
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
        <li>check public posts before other people can see them;</li>
        <li>order Home for you (see “How Home is ordered”);</li>
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
        Before your first thought leaves your phone, the app shows a{' '}
        <strong>Before you start</strong> screen that names the AI providers and
        asks you to agree. Nothing is sent to an AI provider until you tap{' '}
        <strong>Agree and continue</strong>.
      </p>
      <p>
        Angles sends the thought you write and your answers to follow-up
        questions to a large-language-model provider. We choose the provider for
        each step on our servers: <strong>Mistral AI</strong> (France) or{' '}
        <strong>OpenAI</strong> (United States). If the first provider is unavailable,
        the same request may be sent to the other. When you post a card
        publicly, its text is also sent to one of these providers for an
        automated moderation check before anyone else can see it. Your region,
        name, email address, and account identifiers are not sent to AI
        providers.
      </p>
      <p>
        Each result is four short reframes chosen from six styles: Stoic,
        Optimistic, Humorous, Tough love, Tender, and Values. When a thought is
        about real harm to people, Humorous and Tough love are not written.
      </p>
      <p>
        Angles does not use what you write to train or improve any model. We
        send it only to generate your angles and, if you post a card, to check
        that post. We use each provider’s paid API, and those terms do not
        allow Mistral AI or OpenAI to use what you send to train or improve
        their models. A provider may keep a request for a limited time for
        abuse monitoring and legal compliance, as its terms allow. Do not use
        Angles for emergencies.
      </p>

      <h2>How Home is ordered</h2>
      <p>
        Home shows public cards in an order chosen for you. The order uses how
        recent and how hearted each post is, the life areas and moods of the
        cards you write and the angles you heart, and the people you follow. It
        does not use how long you look at a card, and it is never used for
        advertising. Author pages and your Profile are plain lists and are not
        personalized. Deleting a card or removing a heart takes it out of this
        order.
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
        <li>
          the AI providers named above, for reframe generation and the
          moderation check on public posts;
        </li>
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

      <h2>Legal bases (EEA and UK)</h2>
      <ul>
        <li>
          <strong>Contract</strong> (GDPR Article 6(1)(b)): your account, saved
          cards, subscription, credits, and the community features you choose
          to use.
        </li>
        <li>
          <strong>Explicit consent</strong> (Articles 6(1)(a) and 9(2)(a)): what
          you write can reveal information about your health or mental state.
          We process your thoughts, follow-up answers, and the mood and
          life-area details derived from them, send them to the AI providers,
          and use them to order Home, only with the consent you give on the{' '}
          <strong>Before you start</strong> screen. You can withdraw it at any
          time by deleting cards or your account; that does not affect
          processing that already happened, and Angles cannot write reframes
          without it.
        </li>
        <li>
          <strong>Legitimate interests</strong> (Article 6(1)(f)): keeping the
          service secure, preventing abuse, moderating public posts, handling
          reports and blocks, and using your hearts and follows to order Home.
        </li>
        <li>
          <strong>Legal obligation</strong> (Article 6(1)(c)): accounting and
          tax records, and answering lawful requests from authorities.
        </li>
      </ul>

      <h2>Security and international transfers</h2>
      <p>
        We use reasonable administrative and technical safeguards, but no
        service is completely secure.
      </p>
      <p>
        Some providers process information outside the European Economic Area.
        OpenAI processes it in the United States, under the EU-U.S.
        Data Privacy Framework or the European Commission’s Standard
        Contractual Clauses. Our hosting, database, and storage providers may
        also process information outside the EEA, under Standard Contractual
        Clauses or an adequacy decision. Write to us for a copy of the
        safeguards that apply.
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
        restrict, or object to processing, to withdraw consent, or to receive a
        portable copy of certain information. Write to{' '}
        <a href={`mailto:${PRIVACY_EMAIL}`}>{PRIVACY_EMAIL}</a>. You may also
        complain to{' '}
        <a href={SUPERVISORY_AUTHORITY_URL}>{SUPERVISORY_AUTHORITY_NAME}</a> or
        the authority where you live.
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
