# Social posting strategy (running)

> This is the **drafting playbook** every caption-writing skill should consult before writing copy. The structural rules here come from reading X's open-source feed algorithm; the per-platform notes for IG / LinkedIn / Pinterest are well-documented patterns from each platform's own creator docs, not source code.
>
> Account routing (which handle posts what) lives in `CLAUDE.local.md` — that's PII. This doc covers structural strategy only.

## Last reviewed: 2026-05-15 — against [`xai-org/x-algorithm`](https://github.com/xai-org/x-algorithm) May 15 release

xAI commits to updating the open repo every 4 weeks. To refresh:

```bash
cd /tmp && rm -rf x-algorithm && git clone --depth=1 https://github.com/xai-org/x-algorithm.git
```

Files worth re-reading on each refresh:

| Path | Why |
|---|---|
| `home-mixer/scorers/weighted_scorer.rs` | The literal score formula. Watch for added/removed signals. |
| `home-mixer/scorers/author_diversity_scorer.rs` | Per-viewer-session repeat-author decay. |
| `home-mixer/scorers/oon_scorer.rs` | Out-of-network penalty (followers compound). |
| `home-mixer/filters/vf_filter.rs` | The hard-drop visibility filter — actual shadowban path. |
| `grox/classifiers/content/banger_initial_screen.py` | Quality / slop / minor-content classifier. |
| `phoenix/README.md` | Two-tower retrieval + transformer ranking architecture. |

**What's NOT in the repo and never will be:** the actual numeric weight values (`params.rs` is intentionally excluded), the full Phoenix model checkpoint (only a mini shipped), and the `xai_visibility_filtering` crate that defines what counts as a Drop. We see the *shape*, not the *numbers*.

---

## X — what the For You algorithm literally rewards

The `WeightedScorer` (`home-mixer/scorers/weighted_scorer.rs:49-67`) computes:

```
Final = Σ (weight_i × P(action_i))
```

Across **19 engagement signals**:

| Signal | Sign | Notes |
|---|---|---|
| favorite | + | classic like |
| **reply** | + | own weight, distinct from RT/quote — reply-bait is a real, separate lever |
| retweet | + | |
| photo_expand | + | tap-to-zoom on attached image |
| click | + | link click |
| profile_click | + | got someone curious about you |
| **vqv** (video quality view) | + | **only fires when `video_duration_ms > MIN_VIDEO_DURATION_MS`** — short clips skip this bonus |
| share | + | generic share |
| **share_via_dm** | + | highest-intent share — most effort, most weight |
| share_via_copy_link | + | |
| **dwell (binary)** | + | did they stop scrolling? |
| **dwell_time (continuous)** | + | how long? **dwell is counted TWICE** |
| quote | + | |
| quoted_click | + | |
| follow_author | + | post caused a follow |
| not_interested | **−** | |
| block_author | **−** | |
| mute_author | **−** | |
| report | **−** | |

Three downstream rerankers run after the weighted sum:

1. **`AuthorDiversityScorer`** — per-viewer-session: each subsequent appearance of the same author in a single feed response gets `score *= (1 - floor) · decay^N + floor` (where N is the position among that author's appearances). Multiple of your posts CAN surface to one viewer, but each is attenuated.
2. **`OONScorer`** — if the candidate is out-of-network for this viewer, `score *= OON_WEIGHT_FACTOR` (<1). Followers structurally compound; cold reach is taxed.
3. **`VFFilter`** — hard binary kill. A `SafetyResult::Drop` from the (private) `xai_visibility_filtering` crate removes the post from the candidate set entirely. No gradient. This is the actual "shadowban" mechanism; soft-shadowban impressions are more likely just the cumulative effect of OON penalty + author-diversity decay + low banger score, not a hidden tier.

Plus: `grox/classifiers/content/banger_initial_screen.py` is a Grok-VLM classifier that tags every post with `quality_score`, `slop_score`, `has_minor_score`, `taxonomy_categories`, `tags`. **Slop is a real classifier output**, not an emergent property — low-effort AI-flavored content is named and tracked.

---

## Drafting checklist — apply to every post

Derived from the weights and rerankers above. Skills should walk this list before finalizing a caption draft.

1. **End with a reply-bait question.** Reply has its own weight, distinct from RT/quote. "Which one would you pick?" / "Am I wrong?" / "What did I miss?" are the cheapest, highest-leverage tweaks.
2. **Write for dwell.** Length that *holds attention* compounds — dwell is counted twice (binary + continuous). Don't pad; be substantive. Lists, numbered tips, mini-stories all dwell well.
3. **Make it DM-shareable.** The `share_via_dm` signal is the highest-effort share. Framings: "send this to the friend who…", "save this for the next time you…", "tag someone who needs to see this".
4. **Use media that earns its own signal.** Text-in-image earns `photo_expand` (people zoom in); videos longer than `MIN_VIDEO_DURATION_MS` earn `vqv`. Use `pad_ios_video.sh` output (≥30s, 1080×1920 h264) — short loops skip the video bonus entirely.
5. **Bait `profile_click`.** Strong opening that hints at expertise → people click your profile to read more from you. Bio CTA matters because of this.
6. **Avoid the negative weights.** Polarizing-for-clicks isn't free — `not_interested`, `mute`, `block`, `report` are *summed* into the score with negative weights, and the offset formula in `weighted_scorer.rs:83-91` pushes net-negative posts below zero (not just slightly down). Provocation that alienates costs more than mild posts gain.
7. **Don't post >1× per audience-overlap window.** Author diversity decays your subsequent posts per viewer session. Quality > quantity is mathematically baked in. Posting 2–3× a day across timezone-staggered audiences (different viewer cohorts) dodges this.
8. **Build in-network first.** Every follower removes the OON multiplier for that viewer's feed. The first 1K followers compound disproportionately because each one is a structural lift on every future post they see. Warming (mutual-follow signals, niche-adjacent engagement) is the cheap path.
9. **Avoid slop signals.** The Grox VLM tags low-effort AI content. Native-look, specific, lived-experience captions read very differently from generic-template content. If the caption could plausibly be auto-generated for any post, rewrite it.
10. **Don't trip VF.** Hard drop is binary — borderline policy content gets removed entirely, not down-ranked. Stay clear of the line.

---

## Per-platform application

The 10 rules above are X-derived but mostly port. Per-platform deltas:

### X
- **Caption ≤ 280 chars** — front-load the hook in the first ~80 chars (above-the-fold in feed), save the reply-bait question for the end.
- **Threads** — tweet 1 is its own scored unit and carries most of the reach. Make it a complete idea, not a "1/" teaser. Subsequent tweets extend dwell but each is scored independently.
- **Video** — `pad_ios_video.sh` output (≥30s, 1080×1920 h264 + AAC) reliably qualifies for `vqv`. The padded blurred-bg variant looks native, not bot-cropped.
- **Auto-attached link cards** consume the media slot. For caption-+-image posts, drop the URL or expect the card to crowd out the image preview for some viewers.

### Instagram
- Top signals (per Meta's own creator docs): **comments, saves, sends (DMs)**. Same shape as X — questions drive comments, "save this for later" framings drive saves, "send this to" drives DMs.
- **Reels watchtime > everything else.** First 1s is the entire hook. A static title card costs you in the first second.
- **Carousel completion matters.** Slide 1 = promise, last slide = payoff. Designs where people *want* to swipe to slide 5 score better.
- No public author-diversity scorer like X's, but the feed model has its own freshness signal. Once-a-day per audience is the conventional sweet spot.

### LinkedIn
- Top signals: **dwell time, comments, first-hour velocity**. External-link posts are visibly deranked — put URLs in the first comment instead of the post body, or write a no-link post that drives DMs / profile clicks.
- **Long-form is rewarded natively** — 1200–1900 chars when the content deserves it. Whitespace + short paragraphs make it scannable.
- Reply to every comment in the first hour. First-hour engagement velocity is the algorithm's strongest "this is hot" signal on LinkedIn.

### Pinterest
- Different beast: **it's a search engine**, not a feed. Optimize for query match.
- **Pin title = the search query you want to rank for.** "AI Bible Study App for iPhone" beats "Check out our new feature".
- **Description = long-tail keyword body**, 200–500 chars. Natural prose, not keyword stuffing.
- **Fresh pins win** — new image + new description for the *same* destination URL is treated as a new pin and gets a fresh distribution shot. Don't just repin.
- The algorithm rewards click-throughs to the destination, not in-platform engagement. Title + first-image hook should sell the click.

### TikTok / YouTube Shorts
- Both deferred (no video pipeline yet). This section reserved for when we have content.

### Reddit
- Anti-pattern for this whole playbook. Per-sub culture, 10:1 self-promo policing, no cross-post fan-out. Use the `/reddit-post` stub only for hand-crafted, sub-specific posts after karma is built. The drafting checklist above does NOT apply — Reddit punishes anything that smells like a template.

---

## How skills should use this doc

A caption-drafting skill (anything that *generates* copy, not just accepts it as input) should:

1. Before drafting, re-read this doc — specifically the "Drafting checklist" and the relevant "Per-platform application" subsection.
2. Walk the checklist explicitly in its thinking before producing draft text.
3. When showing drafts to the user for approval, note which checklist items the draft hits (reply-bait? DM-share framing? video that qualifies for VQV?).

Skills that just *take* a caption as a parameter (`x-post`, `instagram-post`, `linkedin-post`, `pinterest-post`, the warm skills) don't need to consult this doc — the caller already wrote the caption.
