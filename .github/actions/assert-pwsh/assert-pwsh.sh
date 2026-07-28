#!/usr/bin/env bash
#
# Fails fast with an actionable message if `pwsh` is not on PATH.
#
# The bootstrap check for every workflow in this family whose steps run
# with `shell: pwsh`, and the reason it is bash is structural: a runner
# missing the interpreter cannot run ANY PowerShell composite - including
# the preflights whose whole job is to report a missing prerequisite. What
# the operator sees instead is a bare `pwsh: command not found` from
# whichever composite executed first, naming no cause. This script exists
# to turn that into a sentence.
#
# On self-hosted, PowerShell is expected to be baked into the runner image
# (how the pool is provisioned is the runner operator's concern, external
# to any workflow here), so the message points at the image rather than
# suggesting an ad hoc install on the runner.

set -euo pipefail

if ! command -v pwsh >/dev/null 2>&1; then
    # Written as a workflow error annotation so the cause appears in the
    # job summary rather than only in the log.
    echo "::error::PowerShell (pwsh) not found on runner. This workflow's" \
         "composite actions run with 'shell: pwsh', so the job cannot" \
         "proceed. On self-hosted, pwsh is expected to be baked into the" \
         "runner image; update the runner image rather than installing ad" \
         "hoc on the runner."
    exit 1
fi

# Report the version the way the sibling asserts do, so a job log records
# which interpreter the run actually used. Captured into a variable first
# rather than interpolated inline: under `set -e` that makes a pwsh which
# is present but cannot START (a missing native library - libicu is the
# usual culprit) fail here, where the message is about PowerShell, rather
# than a step later where it is not.
version="$(pwsh --version)"
echo "PowerShell version: ${version}"
