const STEPS = [
  {
    title: 'Write it',
    body: 'One negative thought. If Angles needs a little more, it asks one short follow-up. You can answer or say more.',
  },
  {
    title: 'Read the takes',
    body: 'You can ask for a new answer on any one style. The lines stay short enough to read in a breath.',
  },
  {
    title: 'Keep or post',
    body: 'Saved cards stay in a private library. Posting one also puts it on Home, where other people can read it, heart the angle that helped, and follow the author.',
  },
] as const;

export function HowItWorks() {
  return (
    <section className="section page-shell" id="how">
      <div className="section-heading">
        <p className="eyebrow">How it works</p>
        <h2>Private by default.</h2>
        <p>
          Home opens on For you, with a tab for each style. You can narrow it
          by life area and mood. A card you did not post never appears there.
        </p>
      </div>
      <ol className="steps">
        {STEPS.map((step, index) => (
          <li key={step.title}>
            <span>{index + 1}</span>
            <h3>{step.title}</h3>
            <p>{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
