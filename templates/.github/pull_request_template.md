<!--
PRs are squash-merged, so this description becomes the commit message.
Hard-wrap it at 72 columns or fewer, as for any git commit message; that
includes .docket/pr-<slug>.md drafts and bodies written by sub-agents.
Fenced code blocks, tables and unbreakable tokens such as URLs are
exempt. Indent list continuation lines under their item so the Markdown
still renders on GitHub, and keep headings within 72. Delete this
comment and the hints below as you fill in the sections.
-->

## Why
<!-- The unmet need, bug or risk and the outcome it produces, readable
without opening a queue or the conversation. -->

## What changed
<!-- Behaviour and structure, not a file list. -->

## Markers
<!-- Exact text, one per line, at the start of the line; no bullets,
numbers or quotes, no backticks. Always one "Type: <kind>" line
(feature, fix, refactor, perf, docs, test, tooling or review), then the
queue markers that apply. Vocabulary: docket/TODO_GUIDE.md#markers. -->

## Validation
<!-- Commands actually run and their results. For behaviour changes, a
reproducible scenario with before and after. For review-finding fixes,
a human-runnable scenario: setup, actions, old failure, expected result.
State what was not checked and why. -->

## Review
<!-- Independent review by <agent> at <commit>: <verdict>. Verified:
<claims and how>. Findings: <n> (<fixed in <commit> | disposition>).
Not checked: <gaps>. -->
