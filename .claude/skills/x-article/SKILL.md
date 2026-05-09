---
name: x-article
description: Draft a long-form X Article (formatted essay with headings, bold, lists, images) and write it to articles/<slug>.md as a paste-ready file. Does NOT auto-publish — the X composer's rich-text editor races with keyboard typing on markdown shortcuts and contextually hides toolbar buttons, so reliable auto-fill is impractical. The user pastes paragraph-by-paragraph into x.com/compose/articles, applying the toolbar buttons by hand. Use when the user says "draft an X article", "write a long-form post for X", or runs /x-article.
disable-model-invocation: true
argument-hint: [account] [slug] [source]
allowed-tools: Bash(*) Read(*) Write(*) Edit(*) Glob(*) Grep(*)
---

# Draft an X Article (paste-ready helper)

Account handle: `$0` (no `@`). Recorded in the run log so you remember which account this is for.
Slug: `$1` (kebab-case — e.g. `my-product-launch`). Used for the output filename.
Source: `$2` (path to a repo, file, or `-` to draft from in-conversation context).

Output: `articles/<slug>.md` in this repo (the directory is gitignored — see `.gitignore`).

## Why this skill is a draft-helper, not a publisher

We tried full automation against the X Article composer (`x.com/compose/articles`) on 2026-05-07. The composer is a Lexical-based contenteditable with two distinct fragility classes:

1. **Markdown shortcut races with typing.** The composer auto-converts `## ` (with trailing space) to a Subheading block. But `agent-browser keyboard type` sends characters faster than the React state can settle, so the auto-format consumes some chars and the rest fall through after the conversion. Typing `## Test heading` produced a Subheading block containing only "eT".
2. **Toolbar buttons are contextual.** `btn-bold`, `btn-italic`, `btn-strikethrough`, `btn-blockquote`, `btn-ul`, `btn-ol`, `btn-link` only render when the cursor is in certain block contexts. After typing into a body block, they disappear from the DOM entirely. So you cannot reliably click them programmatically across a whole article.

Both classes could be worked around (Cmd+B selection-then-toggle, etc.) but the result is brittle — every layout change risks silent breakage. **Cheaper and more reliable**: generate a clean paste-ready markdown file, hand it to the user, let them drive the composer with the toolbar.

If X ever ships a markdown-import endpoint or an Articles API, swap this skill for a real publisher. Until then, this is the right shape.

## Step 1: Sanity checks

```!
test -n "$0" || { echo "ACCOUNT MISSING — usage: /x-article <handle> <slug> <source>"; exit 1; }
test -n "$1" || { echo "SLUG MISSING"; exit 1; }
test -n "$2" || { echo "SOURCE MISSING (path or '-')"; exit 1; }
mkdir -p articles
echo "drafting articles/$1.md for @$0 from source: $2"
```

## Step 2: Read the source

If `$2` is a path:
- Directory → read README.md, AGENTS.md / CLAUDE.md, and any `docs/` index files. Look at `git log --reverse --format="%ai %s"` to anchor the timeline if you'll mention how long it took to build. Inventory `docs/screenshots/` for image candidates.
- File → read the file directly.

If `$2` is `-`, work from the in-conversation context (the user has briefed you).

## Step 3: Draft the article

Author in the user's voice (first person, conversational, no LLM tells). Hard rules:

- **No em-dashes.** Use periods, colons, or commas instead. Em-dashes are a known Claude tell. (See `feedback_no_em_dashes.md`.)
- **No "It's not X — it's Y" rhetorical pattern.** Another classic LLM tell.
- **Concrete numbers > generic adjectives.** "320 commits in 45 days" beats "I built it quickly."
- **Bold leads on feature paragraphs.** Reader-skimming pattern from X's own Articles guide.
- **One idea per paragraph.** Short paragraphs (2–4 lines).
- **Subheadings every 3–5 paragraphs.**
- **Strong close.** A summarizing thought, a question, or a call to action. Don't fade out.

Target length: 1200–1800 words. Anything longer needs a real reason.

## Step 4: Pick images

From `<source>/docs/screenshots/` (if a code repo) or wherever the user keeps imagery:
- **Cover image** — the broadest "this is what you get" hero shot. The X help text is emphatic that the header image drives reader pickup.
- **3–5 inline images** — one per major section of the article. Place after the lead paragraph of the section, not before it (otherwise the image arrives before the reader knows what it shows).

Use absolute paths in the markdown so the user can drag them straight into the composer.

## Step 5: Write `articles/<slug>.md`

Use this exact structure so the user knows what goes where:

```
# TITLE (paste into the "Add a title" field)

<title>

# COVER IMAGE (upload first; becomes the article header)

<absolute path to cover>

# BODY (paste paragraph by paragraph; apply Subheading style on lines marked [SUBHEADING])

<lead paragraphs...>

[SUBHEADING] <section heading>

<section paragraphs>

[BLOCKQUOTE] <quote text>

<more paragraphs>

[INLINE IMAGE] <absolute path>

<...>
```

Markers (always all-caps, in square brackets, on their own line):
- `[SUBHEADING]` — apply Subheading style via the `Body` dropdown
- `[BLOCKQUOTE]` — apply blockquote via the `btn-blockquote` button (toggle off after Enter)
- `[INLINE IMAGE]` — drag the file from Finder OR click `Insert > Add Media`, point at the absolute path

Bold leads stay as `**Bold lead.**` markdown — the user will retype the bolded portion using Cmd+B in the composer (faster than fighting with paste behavior).

## Step 6: Verify

```!
echo "em-dashes: $(grep -c '—' articles/$1.md || echo 0)"
echo "words: $(wc -w < articles/$1.md)"
echo "first 60 lines:"
head -60 articles/$1.md
```

If em-dash count is non-zero, sweep them out and re-verify before reporting.

## Step 7: Report

Tell the user:
- Output path (`articles/<slug>.md`).
- Word count.
- Confirmation that em-dash count is zero.
- A 3–5 line "how to paste" cheat sheet:
  1. Go to `x.com/compose/articles` and click `Write`.
  2. Paste the title into "Add a title".
  3. Drag the cover image (path: `<...>`) into the body.
  4. Paste each paragraph in turn. On `[SUBHEADING]` lines, use the `Body` dropdown to set Subheading. On `[BLOCKQUOTE]` lines, click the blockquote button. At `[INLINE IMAGE]` markers, drop the file from Finder.
  5. When done, click `Publish` (top right).

**Do not attempt to publish for the user.** This skill ends with the file written and the cheat sheet displayed.

## Failure modes & gotchas

- **The composer at `/compose/article` (singular) is the long-form post composer (~25k char tweet), not Articles.** Don't confuse the two when researching. The Articles entry point is `/compose/articles` (plural) → click `Write`.
- **Articles requires X Premium on the target account.** If the user reports getting redirected to a sign-up page, that's the cause.
- **The user's voice gets diluted by features-tour mode.** A tour of every tab makes the article feel like a brochure. Keep the thesis (why this exists, what changes when you have it) front-and-center, then weave the tour through it.
- **Source code is a sketchy ground truth for marketing copy.** Verify each concrete claim against the README or commit messages. The README is what the user is willing to commit to publicly; internal AGENTS.md guidance may be aspirational.
