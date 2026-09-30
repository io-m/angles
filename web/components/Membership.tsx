import { SUPPORT_EMAIL } from '@/lib/legalOperator';

export function Membership() {
  return (
    <section className="membership page-shell" id="membership">
      <p className="eyebrow">The app</p>
      <h2>Sign in with Apple. One free taste, then a subscription.</h2>
      <p>
        Angles is not on the App Store yet. When it is, you will sign in with
        Apple, try one thought, and then choose a membership. Questions go to{' '}
        <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
      </p>
      <p className="membership-note">
        Angles is a reflection tool, not therapy or crisis care. If you may
        harm yourself or someone else, contact local emergency services.
      </p>
    </section>
  );
}
