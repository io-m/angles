const VOICES = [
  {
    name: 'Stoic',
    body: 'Separates what you can still hold from what you cannot.',
  },
  {
    name: 'Optimistic',
    body: 'Finds a real opening already in what you said, without dismissing how hard it is.',
  },
  {
    name: 'Humorous',
    body: 'Takes the air out of the moment the way a good friend would, and never jokes at you.',
  },
  {
    name: 'Tough love',
    body: 'Names the part you are avoiding and points at the next move.',
  },
] as const;

export function Voices() {
  return (
    <section className="section page-shell" id="voices">
      <div className="section-heading">
        <p className="eyebrow">Four voices</p>
        <h2>The same thought, seen four ways.</h2>
        <p>
          Each line is a sentence or two, written for the thought you actually
          typed. When a voice would land wrong — a joke on grief, toughness
          when you are already crushed — that angle is left out.
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
