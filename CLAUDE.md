# Quest Beacon

## Releases

- Every release has a changelog. `CHANGELOG.md` holds only the version being released, rewritten before each tag. The packager (`manual-changelog` in `.pkgmeta`) puts it in the GitHub release and on CurseForge.
- Brief and terse: what changed since the previous version, one line per change, as a player sees it. No AI-sounding phrasing, no filler, no Claude attribution.
- Flow: rewrite `CHANGELOG.md`, commit, `git tag X.Y.Z`, push the branch and the tag.
