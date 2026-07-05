# SVG diagram

A fixed, copy-and-edit SVG diagram template plus a well-formedness check, for a skill that authors a diagram where SVG reads better than ASCII art (currently `design-plan`; later `impl-recap`). This guide is the sole locus of the SVG procedure: an importing skill copies the skeleton below and issues the validation Bash call itself, rather than restating these steps.

## Template

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200" role="img" aria-label="Two-component data flow">
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path class="edge-arrow" d="M0 0 L10 5 L0 10 z"/>
    </marker>
  </defs>
  <style>
    .box   { fill: #eef2ff; stroke: #4f46e5; stroke-width: 1.5; }
    .label { font: 13px sans-serif; fill: #1e1b4b; text-anchor: middle; }
    .edge  { stroke: #4f46e5; stroke-width: 1.5; fill: none; }
    .edge-arrow { fill: #4f46e5; }
  </style>
  <rect class="box" x="20"  y="70" width="120" height="50" rx="8"/>
  <text class="label" x="80"  y="100">Source component</text>
  <rect class="box" x="260" y="70" width="120" height="50" rx="8"/>
  <text class="label" x="320" y="100">Target component</text>
  <line class="edge" x1="140" y1="95" x2="260" y2="95" marker-end="url(#arrow)"/>
  <text class="label" x="200" y="86">payload</text>
</svg>
```

Explicit `viewBox`; exactly one reusable `<marker>` arrowhead in `<defs>`; four named `<style>` classes (`box`, `label`, `edge`, `edge-arrow`); rounded-rect (`<rect rx>`) boxes with 2-4 word labels; connectors on manually chosen grid coordinates. Copy the skeleton, add or remove `<rect>`/`<text>`/`<line>` groups, and adjust coordinates by hand: no auto-layout, no renderer binary.

## Validation

After writing the `<svg>` to a file, check well-formedness as a Bash call:

- Primary: `python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' <path>` (exit 0 = well-formed).
- Fallback when `python3` is absent, a tag-balance check in Node:

```
node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const stack = [];
const tagRe = /<\/?([a-zA-Z][\w:-]*)[^>]*?(\/?)>/g;
let m;
while ((m = tagRe.exec(src))) {
  const [full, name, selfClose] = m;
  if (full.startsWith("<?") || full.startsWith("<!")) continue;
  if (selfClose === "/") continue;
  if (full.startsWith("</")) {
    if (stack.pop() !== name) { console.error("mismatched close: " + name); process.exit(1); }
  } else {
    stack.push(name);
  }
}
if (stack.length) { console.error("unclosed: " + stack.join(",")); process.exit(1); }
console.log("ok");
' <path>
```

Never use `xmllint`: it is absent on a minimal Linux box and reintroduces the dependency this procedure avoids.

`leanness:` manual grid coordinates, no auto-layout, is the deliberate ceiling; upgrade to a layout tool only if diagrams outgrow hand-placement.
