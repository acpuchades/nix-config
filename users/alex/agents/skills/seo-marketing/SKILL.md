---
name: seo-marketing
description: How to do search-visibility and digital-marketing work on ANY site, page or channel — establish the goal and the audience before touching anything, audit the SERVED output rather than the source, the per-page and site-wide checks, how to work honestly when there is no analytics data, what is legitimate promotion and what is never done, and the fact that you do not publish, send, post or spend. Consult it before writing or reviewing any page, metadata, newsletter, landing page or campaign copy, and whenever the owner asks about search, visibility, traffic, keywords, metadata, link previews, structured data, email marketing, ads or analytics.
---

# Search visibility and digital marketing

This applies to whatever property is in front of you — his professional site, a
project's documentation, a study's landing page, a mailing list, a profile on
someone else's platform. Nothing here is tied to one repository: the property
sets the specifics, and this skill is the method and the limits.

# Ask what the goal is before you touch anything

Traffic is not a goal. It is a proxy that is wrong more often than it is right,
and optimising it is how a good property gets worse. Establish, in one sentence,
who should arrive and what should happen when they do:

| Property | What success actually is |
|---|---|
| A researcher's or professional's site | someone looking for HIS work — by name, by a paper, by a question he wrote about — lands on the right page, and a shared link renders correctly |
| Project or documentation | a user with a problem reaches the answer without reading three wrong pages |
| A study or recruitment page | the right participants reach the form; the wrong ones are filtered out before it |
| A service or product page | a qualified enquiry, not a visit |

If you cannot state the goal, you cannot tell an improvement from a change. Ask.

The two failure modes are opposite ones: doing nothing (a truncated snippet, no
link preview, a page missing from the sitemap) and doing too much (prose written
for a crawler, a page per synonym, claims made to attract clicks). The first is a
bug and you fix it. The second damages standing, and that is not recoverable by
editing a file.

# The property's own conventions are the authority

If the site lives in a repository, read its `README`, its `CLAUDE.md` and its
docs BEFORE you change anything — front-matter fields and their length rules, how
keywords/taxonomies are derived, how translations are paired, how images are
picked up, what the build and deploy pipeline does.

**Where those docs disagree with what you believe, THEY win** — say so and stop,
rather than "fixing" the property to match your assumption. Several conventions
in any mature repo exist because the obvious thing was tried and was wrong. Do
not restate their rules into another file (a second copy drifts), and never edit
a documented convention as if it were an optimisation.

# You can only claim what you can observe

- **With no analytics and no Search Console**, you have NO way to see rankings,
  impressions, clicks or traffic, and no way to tell whether a change helped. Say
  what is true instead: what the served output contains, and which documented
  convention a page does or does not follow.
- **With data available**, read it and label it — the tool, the metric, the date
  window. A change and a movement in the same week is not causation: algorithm
  updates, seasonality, a link from elsewhere and a competitor's change all move
  the same number.
- **Never invent numbers.** No keyword volume, no difficulty score, no traffic
  estimate, no conversion lift, no "this will improve rankings". Those come from
  tools you do not have. If a number is load-bearing for a decision, name the tool
  that would produce it and let him fetch it. An invented number about his
  visibility is exactly as bad as an invented citation.
- The same applies to competitors: describe what a page demonstrably contains,
  never what it "ranks for".

# Audit what is SERVED, never the source

The markdown, the template and the front matter are not what a crawler sees.
Config, the theme and any local overrides sit between a field and the emitted
tag — which is the whole reason a page can look correct in source and ship a
snippet chopped mid-sentence. Get the real output first:

| Setup | How to see what is served |
|---|---|
| Static generator in a repo | run its documented build (`hugo --minify`, `make build`, `npm run build`) and read the output directory |
| A live host you are allowed to reach | fetch it with the sanctioned wrapper (`request-trusted-url`), not raw curl — see the `policy` skill |
| A JS-rendered app | the source HTML is not enough; it has to be the browser, and only for allowlisted hosts |

Your fetch and browse paths are host-allowlisted. If a property is not reachable
from here, **say so** — audit the source if that is all you have, and label it as
such. Never let "I read the templates" be reported as "I checked the output".

Dev servers are for iterating, not auditing: they rewrite the output directory
behind you. Stop one when you are done, and re-read the repo's own warnings about
what its build regenerates before you start it.

## Per page

| Check | What wrong looks like |
|---|---|
| One `<title>`, unique across the site | two pages competing for the same query |
| `<meta name="description">` present, ≤160 chars | a snippet cut mid-sentence — usually a missing description silently falling back to a long summary |
| `<link rel="canonical">` is the URL you intended | a translated or aliased path canonicalising to the wrong one |
| `hreflang` alternates, in BOTH directions | a translated pair whose folder names differ and was never linked — it appears as a page with no alternates at all |
| `og:title` / `og:description` / `og:image` + the twitter card | a bare grey box when the link is shared |
| The `og:image` is the image you MEANT | a theme falling back to the site-wide social image is still an og:image — the miss is invisible unless you look at WHICH one |
| One `<h1>`, headings in order, no skipped level | but check the repo first: list/home heading overrides are often deliberate |
| Every `<img>` has meaningful `alt` | a figure invisible to a screen reader and to image search |
| The JSON-LD parses, and describes THIS page | stale author/organisation data copied from config |
| The page is in `sitemap.xml`, or is deliberately excluded | taxonomy terms and print/export outputs are usually excluded on purpose |
| `robots.txt` does not block it and no `noindex` slipped in | |
| No draft/unpublished page reachable in the output | |
| Its links resolve — no 404, no redirect chain | |

## Site-wide

- One canonical host and scheme (www vs apex, trailing slash), everything else
  301-redirected to it, and no redirect chains.
- `sitemap.xml` current, and referenced from `robots.txt`.
- `robots.txt` blocks nothing the renderer needs (CSS/JS) and nothing indexable.
- A missing page returns a real 404, not a 200 with "not found" in the body.
- No duplicate content generated by query parameters, pagination or print views.
- Weight and speed: images sized and compressed, no multi-megabyte hero, fonts
  not blocking. You can measure bytes and request counts locally; you cannot
  measure field Core Web Vitals without RUM data, so do not quote them.
- Mobile viewport set, and the page usable at 375px wide.
- Feeds valid, and the locale/language declared correctly.

A page that fails a check is a finding. A page that passes them all is done —
there is no further optimisation to perform on it.

# Before a page is published

Alongside whatever the property's own docs require:

1. **Title** says what the piece IS, in the words a reader would use. Not a
   keyword string, not a question nobody asks aloud.
2. **Description** written for a human reading a search result, ≤160 characters,
   standing alone — it is also the link-preview text.
3. **Summary/excerpt** written in full for the feed, the search index and the list
   card. Write the summary first, then compress it into the description.
4. **Tags/taxonomy** curated, not sprayed. They are the keywords AND they build
   term pages: reuse the existing ones, and remember a tag used once is a dead
   page.
5. **Translations paired** on both sides when the versions live at different
   paths, so neither competes with the other.
6. **Internal links** to the related material, and to the series when there is one.
7. **External links** point at stable identifiers — a DOI, a permalink, an
   archived URL — not a landing page that will move.
8. **Published only when he says it publishes.**

# Keywords and content without a keyword tool

- Start from the audience's own vocabulary, not a generator: the words in his
  writing, in the questions people actually send him, in the existing tags, and —
  if a Search Console exists — in the queries it already reports.
- One page, one subject. Two pages on the same subject compete with each other.
- Match the intent: someone looking for a definition, a tool, a paper and a
  person want four different page shapes.
- Write the thing first; the metadata DESCRIBES it. Prose written backwards from a
  term reads exactly like what it is.
- Answer the question in the first paragraph. Everything that delays the answer
  costs you the reader you wanted.

# The rest of the channels

The order is **audience → message → channel → measurement**. Picking the channel
first is the standard mistake, and it is why most campaigns cannot be evaluated.

| Channel | Good for | The rule that does not bend |
|---|---|---|
| Owned site / blog | durable, indexable, yours | volume is not a goal; one good page beats ten |
| Newsletter / email | the most direct reach there is | consent only, working unsubscribe on every send |
| Social / professional networks | discovery and identity, on rented land | no bought followers, no engagement pods |
| Talks, community, press | the highest credibility per unit of effort | never overstate what the work shows |
| Paid ads | the only one that spends money | not yours to run — see the limits below |

**Identity graph first.** For a person-brand, the highest-value work is usually
the least clever: profiles that exist, are current, and cross-link consistently
(ORCID, Scholar, Scopus, ResearchGate, GitHub, LinkedIn, the site itself), with
publications carrying DOIs. That is what makes a name resolve to the right person
across the web. Do it before anything else.

**Email.** Deliverability is technical before it is creative: SPF, DKIM and DMARC
aligned for the sending domain, a warmed domain, list hygiene (bounces and
complaints removed), plain honest subject lines. A one-off personal mail is not a
campaign; a send to a list is never unprompted.

**Landing pages.** One page, one action. The ask visible without scrolling, the
form asking only for what is genuinely needed, fast on a phone. Measure the
action, not the visit.

**UTM tags.** A consistent lowercase scheme, on EXTERNAL links only — putting
them on internal links destroys the attribution you added them for.

# Analytics, tracking and consent

- Prefer privacy-respecting, self-hostable analytics to anything that ships
  visitor data to an ad network.
- In the EU, non-essential cookies and trackers need PRIOR consent; a banner that
  assumes it is not consent. Adding tracking is a legal-surface change and the
  owner's call — never a side effect of a visibility pass.
- Identifiable or health-related data never goes into a URL, an analytics event,
  a pixel or an ad-platform audience. Not hashed, not "anonymised".

# What is legitimate, and what is never done

Legitimate, and worth doing:

- Accurate, complete metadata on every page (everything above).
- Structured data that is CORRECT, and an identity graph kept consistent.
- Internal linking that reflects how the ideas actually connect.
- Translations properly paired and served to the right reader.
- Fixing genuinely broken things: a dead link, a missing alt, a page absent from
  the sitemap, a description that never got written.
- Making the content itself better, and earning links by being worth citing.

Never, whatever the reason and whoever asks:

- Keyword stuffing, or rewriting prose to hit a term. If a sentence would be
  worse for a reader, it does not go in.
- Pages made to rank rather than to say something: doorway pages, near-duplicates
  per synonym, "ultimate guide" filler.
- AI-generated posts published as his voice. Volume is not a goal and it costs
  credibility that is not bought back.
- Machine-translating instead of translating.
- Cloaking, link schemes, paid links, PBNs, comment and forum link drops,
  expired-domain tricks.
- Fake reviews, testimonials, endorsements or engagement; bought followers.
- Unsolicited bulk email, scraped or purchased address lists, misleading subject
  lines, a missing or broken unsubscribe.
- Dark patterns: invented scarcity and countdowns, pre-ticked consent, hidden
  costs, a subscription that is hard to leave.
- Impersonation, or using a person's or an institution's name or logo in a way
  that implies an endorsement that was not given.
- Any claim about health, treatment or outcomes pitched harder than the evidence
  supports in order to attract attention. On a clinician's or a researcher's
  property this is a professional-conduct problem, not a marketing decision, and
  it is the line that ends a career rather than the one that costs a ranking.
- Anything you would have to hide from the search engine, the platform, the
  recipient, or from him.

If he asks for something on that list, say plainly which line it crosses and
offer the legitimate version of the same goal. There almost always is one.

# What is not yours

- **You do not publish.** A commit, a push and a deploy go through the ordinary
  approval gate, and a deploy target read from a gitignored env file is a publish,
  not a build.
- **You do not send.** Mail to anyone outside the trusted addresses is an
  approval (see the `policy` skill), and a list send is never unprompted.
- **You do not post.** No social or platform account is yours to write from.
- **You do not spend.** Never create, fund, bid on or edit an advertising
  campaign, and never touch billing.
- **Site-wide config, themes, DNS and mail records are his call.** They carry
  documented reasons and have to be re-diffed when a pin lifts. Propose the
  change; do not make it as a side effect of an audit.
- **PII stays out** of pages, feeds, analytics events and mailing lists — and
  never touch a repo's PII pipeline, which has a guard for a reason.
- **His prose is a proposal, not an edit.** Metadata you may fix; what he wrote,
  you show him.

# How to report an audit

Group by finding, most consequential first, and give four things for each: the
page or channel, what the served output ACTUALLY contains, which rule or
documented convention it breaks, and the one-line fix. Then let him choose what
to apply.

Do not sweep a change across thirty files silently, and do not mix a mechanical
fix (a missing alt) with an editorial one (a rewritten title) in the same batch —
he will wave the first through and want to read the second.

Hand off rather than improvise: `policy` for every approval gate and outbound
wrapper, `references` whenever a page cites literature (no identifier goes into a
page until it has resolved against a real API response), and the property's own
repo docs for anything about how that property is built.
