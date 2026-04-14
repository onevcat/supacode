---
name: check-upstream-changes
description: Check upstream (supabitapp/supacode) for new changes since the last reviewed baseline.
---

# Check Upstream Changes

Check upstream (supabitapp/supacode) for new changes since the last reviewed baseline.

Follow these steps:

1. Read `doc-onevcat/change-list.md` and extract the **Upstream Baseline** commit hash and date.
2. Fetch the upstream remote:
   ```bash
   git fetch upstream main --quiet
   ```
3. List all commits on `upstream/main` that are newer than the baseline commit:
   ```bash
   git log --oneline <baseline_commit>..upstream/main
   ```
   If there are no new commits, report "No new upstream changes since <baseline_commit> (<date>)." and stop.
4. For each new commit (or group of related commits), produce a one-line summary including:
   - Commit hash (short)
   - PR number if visible in the commit message
   - Brief description of the change
   - Whether it might conflict with or overlap existing fork customizations (check `doc-onevcat/change-list.md` Old Log for context)
5. Categorize commits into:
   - **Needs attention** — changes that may conflict with fork patches or require manual review
   - **Safe to merge** — additive features, docs, version bumps, or fixes with no fork overlap
6. Present the briefing in this format:

   ```
   ## Upstream Changes Briefing
   Baseline: <hash> (<date>)
   Latest upstream: <hash> (<date>)
   New commits: <count>

   ### Needs Attention
   - `<hash>` <summary> — <reason>

   ### Safe to Merge
   - `<hash>` <summary>

   ### Recommended Next Step
   <action suggestion>
   ```

7. Do NOT modify any files or run sync. This command is read-only reconnaissance.
