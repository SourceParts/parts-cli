# Urgent — parts-cli

Project-level blockers and outstanding setup work. Address before next coordinated release.

## Homebrew tap publishing is broken

Every recent `Release` workflow run (`v0.11.2`, `v0.11.3`, `v0.12.0`) has finished with a `failure` status. Inspecting the logs shows GoReleaser successfully uploads all platform binaries + checksums to the GitHub Release, then fails on the Homebrew tap update step:

```
error checking for default branch
  projectID=SourceParts/homebrew-tap
  statusCode=401
  error=GET https://api.github.com/repos/SourceParts/homebrew-tap: 401 Bad credentials
##[error]The process '...goreleaser' failed with exit code 1
```

The release artifacts on GitHub *are* getting published correctly (install.sh `curl https://source.parts/cli/install.sh | sh` works fine). Only the Homebrew formula update is failing — which means there is no working `brew install ...` path today.

### Fix checklist

- [ ] Regenerate the `HOMEBREW_TAP_TOKEN` secret on `SourceParts/parts-cli` repo settings. The token is currently invalid (401). It must be a GitHub PAT with write access to the `SourceParts/homebrew-tap` repository.
  - Recommended: fine-grained PAT scoped to the homebrew-tap repo only, with `Contents: read/write` permission. Set an expiry that fits your renewal cadence.
- [ ] Verify the `SourceParts/homebrew-tap` repository exists, is accessible by the regenerated token, and has the expected branch (usually `main` or `master`).
- [ ] Confirm `.goreleaser.yml` `brews.repository` block matches the tap repo name and branch.
- [ ] Re-run the Release workflow against the latest tag (or push a patch tag) to verify end-to-end. Expected: a `Formula/parts.rb` file is committed to `SourceParts/homebrew-tap` automatically.

## Get on Homebrew

Once the tap publishes cleanly, the next decision is distribution reach:

- **Custom tap (current direction):** `brew tap SourceParts/tap && brew install parts`. Lower friction for us — controlled entirely by `SourceParts/homebrew-tap`, no upstream review. Users have to know to add the tap.
- **Homebrew core:** `brew install parts-cli`. Wider reach, no tap step needed. Requires submission via `homebrew/homebrew-core` PR and meeting their criteria (stable releases, license, notability). Worth pursuing once tap path is healthy and we have a few stable release cycles.

### Tap-side checklist

- [ ] `SourceParts/homebrew-tap` README documents `brew tap SourceParts/tap && brew install parts` flow.
- [ ] Tap repository has CI to validate the formula on every push (optional but reduces support load).
- [ ] Auto-formula update via GoReleaser is end-to-end verified (depends on the fixes above).

### Homebrew-core checklist (later)

- [ ] Stable v1.0 release threshold reached, with at least a few prior stable tags.
- [ ] License is OSI-approved and matches what's stated in the README.
- [ ] Open a PR to `homebrew/homebrew-core` with the formula. Be prepared to address reviewer feedback on naming, dependencies, and test blocks.

## Context

- Pre-existing problem; not caused by the v0.12.0 cc/bcc release.
- See `https://github.com/SourceParts/parts-cli/releases/tag/v0.12.0` for an example release that succeeded on binary upload but failed on tap update.
