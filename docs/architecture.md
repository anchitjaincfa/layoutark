# Architecture

LayoutArk has two trust zones.

1. The Windows scanner inventories filenames and filesystem metadata locally. It does not read Publisher file contents, follow reparse points, or use the network.
2. The static web app imports the generated manifest with FileReader and analyzes it in the browser. No server receives the manifest.

The pure TypeScript estate engine owns all derived values: triage lanes, findings, folder rollups, duplicate heuristics, and CSV escaping. The UI consumes the resulting EstateReport rather than reimplementing rules.

## Explicit non-goals

The initial release does not upload or convert Publisher files, automate Publisher, promise fidelity, keep a cloud vault, or provide accounts.
