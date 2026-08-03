# Independent implementation

YTKACE is implemented as an independent iOS tweak. Its runtime, settings, download manager, media players, networking, UI controllers and build tooling are maintained in this repository.

Private YouTube class and selector names are treated as compatibility facts. Implementations are written against observed YouTube behavior and are guarded so missing classes disable only the affected feature.

Release rules:

- Do not include third-party tweak binaries, resources or localization tables.
- Do not include activation, analytics, telemetry, anti-debugging or updater code.
- Use system symbols or documented project-owned assets.
- Record the origin and license of every bundled third-party component.
- Run the provenance audit before publishing an artifact.

See [Asset Provenance](ASSET_PROVENANCE.md) and [Third-Party Notices](../THIRD_PARTY_NOTICES.md).
