import { useId } from 'react';

/**
 * The two-layer mark from the compose screen (`InspireMark` in the app).
 * Layer scale and translation match that layout on the 1024 icon canvas.
 */

const BACK_PATH =
  'M678.563 161.906H244.75L342.547 331.203H776.359L678.563 161.906ZM367.125 377.438L296.656 499.469L150.047 753.328H345.641L394.453 668.766L515.625 459.078L562.547 377.438H367.125ZM314.703 375.719L244.406 253.859L97.7969 0L0 169.297L48.8125 253.859L169.813 463.547L216.906 545.016L314.703 375.719Z';

const FRONT_PATH =
  'M463.375 0L392.906 116.875L348.391 190.953H543.812L611.703 78.2031L658.797 0H463.375ZM222.75 404.766L86.4531 402.188L0 400.641L97.7969 569.938L229.453 572.344L320.547 574.062L222.75 404.766ZM568.562 575.953L634.563 695.234L676.328 770.859L774.125 601.562L710.359 486.406L666.359 406.484L568.562 575.953Z';

export function AnglesMark({ className }: { className?: string }) {
  const id = useId().replace(/:/g, '');
  const back = `${id}-back`;
  const front = `${id}-front`;

  return (
    <svg
      aria-hidden="true"
      className={className}
      viewBox="0 0 1024 1024"
    >
      <defs>
        <linearGradient id={back} x1="0.1" x2="0.78" y1="0" y2="1">
          <stop offset="0" stopColor="rgb(255, 182, 0)" />
          <stop offset="1" stopColor="rgb(247, 115, 9)" />
        </linearGradient>
        <linearGradient id={front} x1="0.13" x2="1" y1="0" y2="1">
          <stop offset="0" stopColor="rgb(255, 201, 94)" stopOpacity="0.9" />
          <stop offset="1" stopColor="rgb(255, 147, 0)" />
        </linearGradient>
      </defs>
      <g transform="translate(557 525) scale(0.9) translate(-388.5 -377)">
        <path d={BACK_PATH} fill={`url(#${back})`} />
      </g>
      <g transform="translate(462.34 506.63) scale(0.9) translate(-387.5 -385.5)">
        <path d={FRONT_PATH} fill={`url(#${front})`} />
      </g>
    </svg>
  );
}
