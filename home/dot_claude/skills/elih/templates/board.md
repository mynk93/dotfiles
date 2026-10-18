# Board

## Today's flow and what breaks

```svg
<svg viewBox="0 0 760 296" role="img" aria-label="Today every write goes through the part that breaks">
  <defs><marker id="today-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M240 64 V112" marker-end="url(#today-arrow)"/>
  <path class="dg-edge" d="M240 152 V216" marker-end="url(#today-arrow)"/>
  <text class="dg-label" x="248" y="92">calls</text>
  <text class="dg-label" x="248" y="188">writes</text>
  <g><rect class="dg-node" x="152" y="24" width="176" height="40" rx="8"/><text class="dg-name" x="240" y="48">Today's entry point</text></g>
  <g><rect class="dg-legacy" x="152" y="112" width="176" height="40" rx="8"/><text class="dg-name" x="240" y="136">The part that breaks</text></g>
  <g><path class="dg-ext" d="M152 224 A88 8 0 0 1 328 224 V264 A88 8 0 0 1 152 264 Z"/><path class="dg-ext dg-rim" d="M152 224 A88 8 0 0 0 328 224"/><text class="dg-name" x="240" y="248">The store</text></g>
</svg>
<figcaption>Today every write goes through the part that breaks.</figcaption>
```

One or two sentences on what fails today.

## Pass 1: First chunk

```svg
<svg viewBox="0 0 760 296" role="img" aria-label="The first chunk takes over writes while the old path stays until it is retired">
  <defs><marker id="pass1-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M240 64 V112" marker-end="url(#pass1-arrow)"/>
  <path class="dg-edge" d="M240 152 V216" marker-end="url(#pass1-arrow)"/>
  <path class="dg-edge" d="M328 44 H512 V112" marker-end="url(#pass1-arrow)"/>
  <path class="dg-edge" d="M512 168 V244 H328" marker-end="url(#pass1-arrow)"/>
  <text class="dg-label" x="248" y="92">calls</text>
  <text class="dg-label" x="248" y="188">writes</text>
  <text class="dg-label" x="420" y="36" text-anchor="middle">calls</text>
  <text class="dg-label" x="520" y="210">writes</text>
  <g><rect class="dg-node" x="152" y="24" width="176" height="40" rx="8"/><text class="dg-name" x="240" y="48">Today's entry point</text></g>
  <g><rect class="dg-legacy" x="152" y="112" width="176" height="40" rx="8"/><text class="dg-name" x="240" y="136">The part that breaks</text></g>
  <g><path class="dg-ext" d="M152 224 A88 8 0 0 1 328 224 V264 A88 8 0 0 1 152 264 Z"/><path class="dg-ext dg-rim" d="M152 224 A88 8 0 0 0 328 224"/><text class="dg-name" x="240" y="248">The store</text></g>
  <g><rect class="dg-new" x="424" y="112" width="176" height="56" rx="8"/><text class="dg-name" x="512" y="136">First chunk</text><text class="dg-sub" x="512" y="152">what it adds</text></g>
</svg>
<figcaption>The first chunk takes over writes; the old path stays until it is retired.</figcaption>
```

## Context: who talks to whom

```svg
<svg viewBox="0 0 760 136" role="img" aria-label="The new deployable sits inside our system, between the existing service and the external one">
  <defs><marker id="ctx-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <rect class="dg-group" x="32" y="24" width="432" height="88" rx="14"/><text class="dg-lane" x="46" y="44">Our system</text>
  <path class="dg-edge" d="M192 76 H304" marker-end="url(#ctx-arrow)"/>
  <path class="dg-edge" d="M448 76 H576" marker-end="url(#ctx-arrow)"/>
  <text class="dg-label" x="248" y="68" text-anchor="middle">sends events</text>
  <text class="dg-label" x="512" y="68" text-anchor="middle">asks for data</text>
  <g><rect class="dg-node" x="48" y="56" width="144" height="40" rx="8"/><text class="dg-name" x="120" y="80">Existing service</text></g>
  <g><rect class="dg-new" x="304" y="56" width="144" height="40" rx="8"/><text class="dg-name" x="376" y="80">New deployable</text></g>
  <g><rect class="dg-ext" x="576" y="56" width="144" height="40" rx="8"/><text class="dg-name" x="648" y="80">External service</text></g>
</svg>
<figcaption>The new deployable sits inside our system, between the existing service and the external one.</figcaption>
```
