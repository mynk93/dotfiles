# Board

## Today's flow and what breaks

```svg
<svg viewBox="0 0 800 328" role="img" aria-label="Today: the entry point calls the part that breaks, which writes to the store">
  <defs><marker id="today-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M264 68 V132" marker-end="url(#today-arrow)"/>
  <path class="dg-edge" d="M264 176 V260" marker-end="url(#today-arrow)"/>
  <g><rect class="dg-node" x="176" y="24" width="176" height="44" rx="10"/><text class="dg-name" x="264" y="51">Today's entry point</text></g>
  <g><rect class="dg-legacy" x="176" y="132" width="176" height="44" rx="10"/><text class="dg-name" x="264" y="159">The part that breaks</text></g>
  <g><rect class="dg-ext" x="176" y="260" width="176" height="44" rx="10"/><text class="dg-name" x="264" y="287">The store</text></g>
</svg>
<p class="diagram-legend"><span><i class="k-node"></i>Unchanged</span><span><i class="k-legacy"></i>Legacy</span><span><i class="k-ext"></i>Store</span></p>
```

One or two sentences on what fails today.

## Pass 1: First chunk

```svg
<svg viewBox="0 0 800 328" role="img" aria-label="Pass 1: the first chunk sits beside the part that breaks and writes to the same store">
  <defs><marker id="pass1-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M264 68 V132" marker-end="url(#pass1-arrow)"/>
  <path class="dg-edge" d="M264 176 V260" marker-end="url(#pass1-arrow)"/>
  <path class="dg-edge" d="M352 46 H536 V132" marker-end="url(#pass1-arrow)"/>
  <path class="dg-edge" d="M536 196 V282 H352" marker-end="url(#pass1-arrow)"/>
  <g><rect class="dg-node" x="176" y="24" width="176" height="44" rx="10"/><text class="dg-name" x="264" y="51">Today's entry point</text></g>
  <g><rect class="dg-legacy" x="176" y="132" width="176" height="44" rx="10"/><text class="dg-name" x="264" y="159">The part that breaks</text></g>
  <g><rect class="dg-ext" x="176" y="260" width="176" height="44" rx="10"/><text class="dg-name" x="264" y="287">The store</text></g>
  <g><rect class="dg-new" x="448" y="132" width="176" height="64" rx="10"/><text class="dg-name" x="536" y="159">FIRST CHUNK</text><text class="dg-sub" x="536" y="178">what it adds</text></g>
</svg>
<p class="diagram-legend"><span><i class="k-new"></i>New in this pass</span><span><i class="k-node"></i>Unchanged</span><span><i class="k-legacy"></i>Legacy</span><span><i class="k-ext"></i>Store</span></p>
```

## Context: who talks to whom

```svg
<svg viewBox="0 0 800 92" role="img" aria-label="The existing service calls the new deployable, which calls an external service">
  <defs><marker id="ctx-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M232 46 H328" marker-end="url(#ctx-arrow)"/>
  <path class="dg-edge" d="M472 46 H568" marker-end="url(#ctx-arrow)"/>
  <g><rect class="dg-node" x="88" y="24" width="144" height="44" rx="10"/><text class="dg-name" x="160" y="51">Existing service</text></g>
  <g><rect class="dg-new" x="328" y="24" width="144" height="44" rx="10"/><text class="dg-name" x="400" y="51">New deployable</text></g>
  <g><rect class="dg-ext" x="568" y="24" width="144" height="44" rx="10"/><text class="dg-name" x="640" y="51">External service</text></g>
  <g class="dg-badge"><circle cx="280" cy="46" r="10"/><text x="280" y="50">1</text></g>
  <g class="dg-badge"><circle cx="520" cy="46" r="10"/><text x="520" y="50">2</text></g>
</svg>
<p class="diagram-legend"><span><i class="k-node"></i>Existing</span><span><i class="k-new"></i>New</span><span><i class="k-ext"></i>External</span></p>
```

| # | From → to | What happens |
|---|---|---|
| <span class="num">1</span> | Existing service → new deployable | what it sends |
| <span class="num">2</span> | New deployable → external service | what it asks for |
