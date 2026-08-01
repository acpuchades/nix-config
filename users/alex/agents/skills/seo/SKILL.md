---
name: seo
description: How to do search-visibility work on the owner's site — audit the BUILT html rather than the markdown, the per-page checks before anything is published, what is legitimate on a researcher's professional site and what is never done there, and the fact that you cannot measure results so you must not claim them. Consult it before writing or reviewing any page for acpuchades-site, and whenever the owner asks about search, visibility, metadata, link previews or structured data.
---

# Search visibility

This is a working researcher's professional site, not a content property. The
goal is narrow and it is not traffic: that someone looking for HIS work — by
name, by a paper, by a question he has written about — finds the right page, and
that a link to it renders correctly when shared. Nothing here is worth a
sentence that reads as written for a crawler. Clinicians and researchers are the
audience, and they can tell.

So the two failure modes to avoid are opposite ones: doing nothing (a page with a
truncated snippet, no link preview, missing from the sitemap) and doing too much
(keyword-stuffed prose, pages spun up per synonym, claims made to attract
clicks). The first is a bug. The second damages his professional standing, which
is not recoverable by editing a file.

# The repo's own `CLAUDE.md` is the authority

`acpuchades-site/CLAUDE.md` documents this site's conventions in detail — the
`description:` vs `summary:` split and their length rules, why keywords are
derived from `tags:` and never hand-written, `translationKey` for translated
pages whose slugs differ, how feature images are auto-detected, the theme
overrides and the CV/PII pipeline.

**Read it before you touch the repository, and defer to it.** Where anything you
believe disagrees with that file, IT wins — say so and stop, rather than
"fixing" the site to match your assumption. Do not restate its rules into other
files, and never edit a documented convention as if it were an SEO improvement:
several of them exist because the obvious thing was tried and was wrong.

# You cannot measure this, so do not claim it

There is no Search Console and no analytics on this site — the analytics blocks
in `params.toml` are empty. You therefore have NO way to observe rankings,
impressions, clicks or traffic, and no way to tell whether any change helped.

Say what is true: what the built output contains, and which documented convention
a page does or does not follow. Never write "this will improve rankings", never
estimate traffic, never rank keywords by difficulty or volume — those numbers
would be invented, and invented numbers about his professional visibility are
exactly as bad as an invented citation.

# Audit the BUILT site, never the markdown

The markdown is not what search engines see. Config, the theme and six local
theme overrides all intervene between a front-matter field and the emitted tag —
which is the whole reason a page can look correct in source and ship a snippet
chopped mid-sentence. So: build first, then read `public/`.

    hugo --minify           # or `make build`, which also runs the CV pipeline

`make serve` is for iterating. Read the deploy/PII warning in the repo's
CLAUDE.md before you start it, and stop it when you are done — the dev server
rewrites `public/` behind your back, and one of the things it puts back is
PII-bearing.

## What to check, per page

For each page, look at the actual emitted HTML and confirm:

| Check | What wrong looks like |
|---|---|
| One `<title>`, unique across the site | two pages competing for the same query |
| `<meta name="description">` present, ≤160 chars | a snippet Google cuts mid-sentence — usually a missing `description:` silently falling back to the long `summary:` |
| `<link rel="canonical">` is the URL you intended | the ES translated slug vs the English section path |
| `hreflang` alternates, both directions | a translated pair whose folder names differ and has no `translationKey` — it shows up as a page with NO alternates |
| `og:title` / `og:description` / `og:image`, and the twitter card | a bare grey box when the link is shared |
| The `og:image` is the image you MEANT | the theme falls back to the site-wide social image when a bundle has no image matching its expected filename pattern — so the page still HAS an og:image and the miss is invisible unless you look at which one |
| One `<h1>`, headings in order with no skipped level | the homepage/list heading overrides are deliberate — re-read CLAUDE.md before "fixing" one |
| Every `<img>` has meaningful `alt` | a figure that is invisible to a screen reader and to image search |
| The JSON-LD block parses, and describes THIS page | stale author/schema data from config |
| The page is in `sitemap.xml` — or is deliberately excluded | taxonomy/term kinds and the CV print outputs are excluded ON PURPOSE |
| `robots.txt` does not block it, and no `noindex` slipped in | |
| No `draft: true` page reachable in `public/` | |

A page that fails one of these is a finding. A page that passes them all is done —
there is no further optimisation to perform on it.

# Before a page is published

Alongside whatever the repo's CLAUDE.md requires:

1. `title` says what the piece IS, in the words a reader would use. Not a keyword
   string, not a question nobody asks aloud.
2. `description` written for a human reading a search result, ≤160 characters,
   and it must stand alone — it is also the link-preview text.
3. `summary` written in full for the RSS feed, the search index and the list card.
   Write the summary first, then compress it into the description.
4. `tags` curated, not sprayed. They ARE the keywords, and they build the `/tags/`
   term pages. Reuse existing tags — read `/tags/` before inventing one; a tag
   used once is a dead page.
5. `translationKey` set on BOTH sides when the EN and ES bundles have different
   folder names.
6. Internal links to the related posts, and to the series when there is one.
7. External links point at DOIs, not at a publisher landing page that will move.
8. `draft: false` only when the owner says it publishes.

# What is legitimate here, and what is not

Legitimate, and worth doing:

- Accurate, complete metadata on every page (everything above).
- Structured data that is CORRECT. On a researcher's site the identity graph is
  worth more than any on-page trick: ORCID, Scopus, Scholar, ResearchGate and
  GitHub are already in the config, and publications carry DOIs. Keeping those
  consistent is what makes his name resolve to the right person across the web —
  the highest-value thing in this whole skill.
- Internal linking that reflects how the ideas actually connect.
- Making sure the ES and EN versions are properly paired, so neither competes
  with the other and each is served to the right reader.
- Fixing genuinely broken things: a dead link, a missing alt, a page absent from
  the sitemap, a description that never got written.

Never, on this site, whatever the reason:

- Keyword stuffing, or rewriting prose to hit a term. If a sentence would be
  worse for a reader, it does not go in.
- A page created to rank rather than to say something. No doorway pages, no
  near-duplicate pages per synonym, no "ultimate guide" filler.
- AI-generated posts. Everything published here is his professional voice on his
  own field; volume is not a goal and would cost him credibility.
- Machine-translating the Spanish from the English. The repo's convention is that
  Spanish is a translation, not a copy.
- Any claim about ALS, treatments or outcomes stated more strongly than the
  evidence supports in order to attract attention. This is a clinician's site;
  that is a professional-conduct problem, not a marketing decision.
- Cloaking, link schemes, paid links, comment-link placement, or anything else
  you would have to hide from the search engine or from him.

# What is not yours

- **You do not publish.** Publishing is a commit and a push, and the push goes
  through the ordinary approval gate; the self-hosted runner deploys from there.
  Never run `make deploy` — it targets a host from a gitignored `.env` and it is
  a publish, not a build.
- **Site-wide config and the theme overrides are the owner's call.** They carry
  reasons documented in CLAUDE.md and they have to be re-diffed when the theme
  pin lifts. Propose the change; do not make it as a side effect of an SEO pass.
- **Never touch the CV pipeline or anything under `data/cv/`.** It carries PII and
  it has a guard for a reason.
- A rewrite of his prose is a proposal, not an edit. Metadata you may fix; what
  he wrote, you show him.

# How to report an audit

Group by finding, most consequential first, and for each one give four things:
the page, what the built output ACTUALLY contains, which documented convention it
breaks, and the one-line fix. Then let him choose what to apply.

Do not sweep a change across thirty files silently, and do not mix a mechanical
fix (a missing alt) with an editorial one (a rewritten title) in the same batch —
he will want to wave the first through and read the second.
