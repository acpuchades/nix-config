---
name: references
description: How to run a literature search and manage references — building a reproducible query, which database to ask for what, chasing citations forward and backward from seed papers, screening and appraising what comes back, working down the legal ladder to a full text, and reading from and adding to the owner's Zotero library without duplicates. Consult it whenever you are asked to find, check, summarise or cite published work, before you put ANY reference in a document, and before you touch Zotero.
---

# Literature and references

The owner is a clinical researcher; most of what he asks for here ends up in a
manuscript, a protocol or a clinical decision. So this skill has one rule above
all others, and it is not negotiable:

**A reference you have not verified does not exist.** Never write a PMID, a DOI,
a title, a journal, a year or an author list from memory or from inference —
every identifier goes in a document only after you have RESOLVED it against a
real API response in this session. Inventing a plausible citation is the single
most damaging thing you can do in this domain: it is invisible in review, it
survives into print, and it is attributed to him.

The corollary: never cite what you have not read at least the abstract of, and
say plainly which ones you read in full and which only in abstract.

# 0. Before you search

Write the question down in one sentence, in PICO shape when it is clinical:

> In adults with ALS (P), does early NIV (I) versus standard timing (C) change
> survival (O)?

Then decide, before the first query, what would count as an ANSWER: which study
designs, which years, which populations, which languages, and how many papers is
enough. Write those inclusion/exclusion criteria into the project's notes BEFORE
screening. Criteria invented while reading are criteria fitted to the results.

If the request is vague ("what's new in ALS biomarkers"), do not guess the scope —
propose one and ask him to confirm it, or deliver a first pass explicitly framed
as a scoping search.

# 1. Where to ask, and for what

All of these are read-only, keyless (unless noted) and on the trusted-site list,
so they run through `request-trusted-url` without approval:

| Need | Endpoint |
|---|---|
| The clinical literature, with MeSH indexing | `eutils.ncbi.nlm.nih.gov` (PubMed E-utilities) |
| The same plus preprints and open full text | `www.ebi.ac.uk` (Europe PMC REST) |
| Metadata for a known DOI | `api.crossref.org` |
| Citations, related works, an author's output | `api.openalex.org`, `api.semanticscholar.org` |
| A legal open-access PDF for a DOI | `api.unpaywall.org` (needs `?email=`) |
| Trials: registered, recruiting, results | `clinicaltrials.gov` (API v2) |
| Preprints in physics/stats/CS | `export.arxiv.org` |
| Drug names, interactions, labels | `rxnav.nlm.nih.gov`, `api.fda.gov` |
| The owner's own library | `check-zotero` (a wrapper, not a URL — see below) |

**PubMed is the default for a clinical question**, because MeSH is what makes a
search reproducible. Europe PMC is the second pass: it indexes preprints and
gives you open full text, so it finds things PubMed will not. OpenAlex and
Semantic Scholar are for FOLLOWING the graph — who cited this, what else did this
group publish — not for the primary search.

**UpToDate is reachable only through the BROWSER.** It is a subscription site
behind an interactive login, so `request-trusted-url` cannot read it — a GET with
no cookies returns the login page and nothing else. Navigate to
`https://www.uptodate.com/…` with the browser tool and sign in with the
credentials the owner gave you, which live in `~/workspace/TOOLS.md` under
`## UpToDate` like any other credential (record them the moment he hands them
over; never paste them anywhere but that login form). Expect to log in again in a
new session — the browser profile does not necessarily keep the cookie.

If the login redirects somewhere the browser refuses to follow, that is the SSRF
allowlist blocking an institutional identity provider that is not on it: say
which host it bounced to and ask the owner to add it. Do not work around it.

Treat what you find there as what it is: a tertiary, synthesised source.
Excellent for orientation, for standard-of-care questions and for finding the
primary references it cites — but it is NOT a citation in a paper. When UpToDate
gives you the answer, follow its references to the primary studies and cite
those, after verifying them like any other reference.

## The shape of the calls

    request-trusted-url "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax=100&term=<query>"
    request-trusted-url "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id=<pmid,pmid,…>"
    request-trusted-url "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&rettype=abstract&id=<pmid,…>"
    request-trusted-url "https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=<query>&format=json&pageSize=100"
    request-trusted-url "https://api.crossref.org/works/<doi>"
    request-trusted-url "https://api.unpaywall.org/v2/<doi>?email=<owner-address>"

URL-encode the query (spaces, quotes, brackets, `&`), write the whole URL in
double quotes, and go through `request-trusted-url` — never `curl`. `esearch`
gives you PMIDs; `esummary` gives you the metadata to screen; `efetch` gives you
the abstract and the publication types. Save each raw response into the project
folder rather than re-fetching: the API is rate-limited and you will want the
exact bytes you screened from.

# 2. Building the query

A good query is one that someone else can re-run and get the same set. Build it
in explicit blocks, one concept per block, ORed inside and ANDed between:

    ("Amyotrophic Lateral Sclerosis"[Mesh] OR "amyotrophic lateral sclerosis"[tiab] OR ALS[tiab])
    AND ("Noninvasive Ventilation"[Mesh] OR NIV[tiab] OR "non-invasive ventilation"[tiab])
    AND ("2015"[dp] : "3000"[dp])

- Pair every MeSH term with free-text `[tiab]` synonyms — MeSH indexing lags, so
  MeSH alone misses everything published in the last months.
- `[Mesh]` explodes narrower terms by default; that is usually what you want.
- Add filters as terms, not as assumptions: `AND humans[mh]`,
  `AND randomizedcontrolledtrial[pt]`, `AND english[la]`.
- Do not silently drop a concept because it returned too little. Report the
  narrowing and let him decide.

**Record the search**, in the project folder, as a small block you can paste into
a methods section later:

    Database: PubMed (E-utilities esearch)
    Run: 2026-08-01
    Query: <the exact string, verbatim>
    Results: 214

Without the date and the verbatim string the search is not reproducible, and an
irreproducible search cannot go into a paper.

# 3. Citation chasing

A boolean query only finds what uses the vocabulary you happened to think of. If
one group writes "non-invasive ventilation", another "NPPV" and a third describes
it without naming it in the title or abstract, your MeSH+`[tiab]` search loses
them, and loses them silently. Citation links do not depend on vocabulary: two
papers about the same thing tend to cite each other. So a search is not finished
when the query is finished.

Do it in both directions, from two or three SEED papers you already know are good:

- **Backward** — what a paper cites. Takes you to the foundational work.
- **Forward** — what cites it. Takes you to what came after: replications,
  critiques, larger cohorts, the guideline that absorbed it.

    # forward — who cites it
    request-trusted-url "https://api.openalex.org/works?filter=cites:<openalex-id>&per-page=100"
    request-trusted-url "https://www.ebi.ac.uk/europepmc/webservices/rest/MED/<pmid>/citations?format=json"
    request-trusted-url "https://api.semanticscholar.org/graph/v1/paper/DOI:<doi>/citations?fields=title,year,externalIds"

    # backward — what it cites
    request-trusted-url "https://api.openalex.org/works/doi:<doi>"        # referenced_works
    request-trusted-url "https://www.ebi.ac.uk/europepmc/webservices/rest/MED/<pmid>/references?format=json"
    request-trusted-url "https://api.crossref.org/works/<doi>"            # reference, when the publisher deposited it

    # the neighbourhood
    request-trusted-url "https://api.openalex.org/works/doi:<doi>"        # related_works

Add whatever is relevant to the seed set and go round again, until a round turns
up nothing new — saturation, usually after two or three rounds. Then stop and say
you stopped there.

**Record it like any other search**: the seed papers, both directions, the date,
how many rounds, and where it saturated. In a systematic review this is the
supplementary search method PRISMA-S asks you to report, so an unrecorded round of
chasing is a round that cannot be written up.

**Google Scholar is not part of this.** It has no API, its terms forbid automated
access, and it blocks bots with CAPTCHAs — and solving those to scrape it would be
spending the owner's captcha credit to defeat a site's anti-bot defences, which
you do not do. Everything anyone actually wants Scholar for is above: its "cited
by" is OpenAlex and Semantic Scholar, its `[PDF]` links are Unpaywall, and its
coverage of preprints is Europe PMC.

# 4. Screening and appraisal

Two passes, and never collapse them into one:

1. **Title/abstract** against the criteria you wrote in step 0. Produce a table:
   PMID · year · design · population · n · what it reports · include/exclude ·
   reason for exclusion. Excluded rows STAY in the table with their reason —
   that is what a PRISMA flow is made of.
2. **Full text** for what survived, and only then a judgement.

What to look at, in roughly this order:

- **Design, and whether it can answer the question.** An observational study
  cannot establish efficacy, however large. Note the design explicitly for each
  paper; "a study showed" is not a finding.
- **Population** — does it match the owner's? ALS cohorts differ enormously by
  site of onset, diagnostic criteria and time from onset.
- **n, and the primary endpoint** — the one declared, not the one highlighted in
  the abstract. Check whether the trial was registered and whether the primary
  endpoint changed (`clinicaltrials.gov` API v2 by NCT number).
- **Effect size with its confidence interval**, never a bare p-value.
- **Funding and conflicts.**
- **Is it retracted or corrected?** `efetch` returns publication types and
  comment/correction links: look for `Retracted Publication`, `Retraction of
  Publication`, `Expression of Concern`. Do this for anything you are about to
  cite — a retracted citation is worse than a missing one.
- **Where it was published.** An unfamiliar journal with an APC and a two-week
  turnaround deserves scepticism; check whether it is indexed in PubMed at all.

Preprints are legitimate to report and must ALWAYS be labelled as preprints —
not peer reviewed. Check whether the preprint has since been published (Europe
PMC links them) and prefer the published version.

# 5. Getting the full text

Work down this ladder and stop at the first rung that works. Most of it is free
and legal; the paywall is the last rung, not the first.

1. **Europe PMC open access** —
   `/europepmc/webservices/rest/<source>/<id>/fullTextXML`. Machine-readable full
   text, the best case.
2. **PubMed Central**, when the record has a PMCID.
3. **Unpaywall** for a legal OA copy: `api.unpaywall.org/v2/<doi>?email=…`. Read
   `best_oa_location`, but read `oa_locations` TOO — the author-accepted
   manuscript often sits in an institutional or subject repository even when the
   publisher's version is closed, and that entry is the one people miss. It is the
   same content, minus the publisher's typesetting; label it as the accepted
   manuscript when you quote page numbers, because they will not match.
4. **The preprint version**, always labelled as a preprint, and check first
   whether it has since been published (Europe PMC links the two).
5. **The institutional subscription.** He has access through the hospital and the
   university; you generally do not, unless he has given you credentials for a
   library portal and the host is on the browser allowlist. If it is, use it like
   any other logged-in site (see UpToDate above). If it is not, this rung is his.
6. **Ask the corresponding author for a reprint.** Legal, ordinary and
   surprisingly effective — most authors answer within days and are pleased to be
   asked. The address is in the paper's metadata. Draft a short message: who is
   asking and from where, the exact citation, and one line on why. It is outbound
   mail to a stranger, so it goes through the ordinary approval gate — prepare it,
   put it to the owner, and file a `waiting-for.md` line with the date when it
   goes out.
7. **Interlibrary loan** through the hospital library. Slow but it works for
   anything; raise it as an option rather than doing it, since it goes through his
   library account.

If none of them works, say so plainly with the DOI and which rungs you tried.
"I could not get the full text" is a perfectly good answer.

**Never route around a paywall.** Sci-Hub and its mirrors are not an option, are
not on the allowlist, and are not to be suggested: they redistribute copyrighted
articles without the publisher's authorization, which is not the same thing as an
open-access source however convenient it looks. A stolen PDF is not a result, and
it is his name on the work it would end up in.

# 6. Zotero

His library is the reference system of record, and `check-zotero` / `zotero-add`
are your ONLY way into it. There is nothing to configure and no credential for
you to hold: the wrappers read his API key themselves and send it as a header.

That is deliberate. Never put an API key in a URL, never try to reach
`api.zotero.org` with `request-trusted-url` (it is not a trusted site, and the
request will be refused), and do not record a Zotero credential in `TOOLS.md`. A
key you type into a command is a key that ends up in your transcript, your memory
index and one slip away from a chat message.

## Reading

    check-zotero doi 10.1000/xyz                 # the deduplication check
    check-zotero search "als niv timing" --limit 10
    check-zotero search "biomarker" --collection ABCD2345
    check-zotero collections                     # the 8-char keys --collection takes
    check-zotero item ABCD1234 --json            # everything about one item

The default output is one line per item — item key, type, year, first author,
title, DOI — which is what you need to judge "is this already here?". Use
`--json` when you need the full record, for example to build a citation.

## Always deduplicate BEFORE adding

    check-zotero doi 10.1000/xyz

`zotero-add` does not do this for you. A duplicated reference is a silent error
that surfaces as two entries in a bibliography weeks later. If it is already
there, say so and use the existing item key. Search by DOI first; if the item has
no DOI, search the title.

## Adding

Use `zotero-add`. It takes a JSON ARRAY of Zotero items — from a file or stdin —
and creates them in his library. It runs without approval because it can only
ever create: the endpoint is fixed, and it refuses any item carrying `key` or
`version`, so it cannot modify or delete a reference that is already there.

    zotero-add --dry-run refs.json                  # validate, print, send nothing
    zotero-add --collection ABCD2345 refs.json      # create, filed in a collection

Each item is an `itemType` plus that type's fields:

    [
      {
        "itemType": "journalArticle",
        "title": "…",
        "creators": [{"creatorType": "author", "firstName": "A", "lastName": "B"}],
        "publicationTitle": "…", "volume": "12", "pages": "1-9",
        "date": "2025-03", "DOI": "10.1000/xyz",
        "extra": "PMID: 12345678"
      }
    ]

The working sequence, and none of the steps are optional:

1. **Search the library first** with `check-zotero doi <doi>`. `zotero-add`
   does NOT deduplicate, and a duplicate is invisible until it shows up twice in
   a bibliography weeks later.
2. **Take every field from an API response** — Crossref for a DOI, `esummary`
   for a PMID — never from a PDF's front page and never from memory. Put the PMID
   in `extra` as `PMID: …`; it is how his library links back to PubMed.
3. **`--dry-run` first** whenever the batch is more than two or three items, and
   read what it prints.
4. **Then send**, and report what was created. The command exits non-zero if any
   item was rejected: fix and re-send only the rejected ones, or you will create
   duplicates of the ones that already landed.

Keep batches small and reviewable rather than dumping a whole search into his
library. A reference he did not want is his to delete, and you cannot delete it
for him.

## Conventions inside the library

Follow the structure that is already there — read the collections before you
propose one. When you do add, put each reference in the collection for its
project, and tag it with the project slug so a search can recover the working set
later. Never restructure or rename his collections; never delete an item.

# 7. Putting references into a document

Before any reference leaves your workspace in a manuscript, a report or a mail:

1. Every DOI resolves through Crossref, every PMID through `esummary`.
2. Author list, year, journal, volume/pages come FROM that response.
3. Nothing is retracted (step 4).
4. Every claim in the text points to a paper that actually says it — check the
   sentence against the abstract you have, not against what the paper is
   generally about.
5. The reference style matches the target journal (see the `research-projects`
   skill), and the numbering matches the citation order in the text.

If you cannot verify one, remove it and say which one and why. A short verified
bibliography is worth more than a long plausible one.

# 8. What you report

Give him the search as a decision-ready object, not a pile of links:

- The question as you understood it, and the criteria you applied.
- The exact query, database and date, with the number of hits.
- A table of what you included, with design, n, and the one-line finding.
- What you excluded and why, in aggregate.
- What you could NOT get (paywalled, unreachable, ambiguous).
- Your reading of what it means — clearly separated from what the papers say.

File the whole thing in the project folder per the `research-projects` skill,
and put any follow-up (get a PDF, ask a co-author, re-run with wider dates) on
`next-actions.md` per `gtd`. A search that lives only in a chat message is a
search that will be run again from scratch in a month.
