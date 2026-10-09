const VOICES = [
  {
    name: 'Stoic',
    body: 'Separates what you can still hold from what you cannot.',
  },
  {
    name: 'Hopeful',
    body: 'Finds a real opening already in what you said, without dismissing how hard it is.',
  },
  {
    name: 'Witty',
    body: 'Takes the air out of the moment the way a good friend would, and never jokes at you.',
  },
  {
    name: 'Tough',
    body: 'Names the part you are avoiding and points at the next move.',
  },
  {
    name: 'Tender',
    body: 'Stays with the feeling. No fix, no task, no bright side.',
  },
  {
    name: 'Values',
    body: 'Names what the feeling is protecting, the thing you hold dear.',
  },
] as const;

export function Voices() {
  return (
    <section className="section page-shell" id="voices">
      <div className="section-heading">
        <p className="eyebrow">Six voices</p>
        <h2>Four angles, chosen for the thought.</h2>
        <p>
          Angles writes the four that fit, each a sentence or two. A thought
          about real harm to people never gets Witty or Tough. Those
          two are left out, and Tender and Values stay.
        </p>
      </div>
      <ul className="voice-grid">
        {VOICES.map((voice) => (
          <li key={voice.name}>
            <h3>{voice.name}</h3>
            <p>{voice.body}</p>
          </li>
        ))}
      </ul>
    </section>
  );
}
