---
name: research-projects
description: How to run a scientific project — a study, an analysis, a manuscript — as opposed to a code repository. Covers the project dossier, patient-data rules, manuscript versioning, circulating drafts to co-authors, journal deadlines, submission requirements and the point-by-point response to reviewers. Consult it whenever the owner mentions a study, a paper, a grant, an abstract or a revision, and before you touch any manuscript file.
---

# Running a research project

The `projects` skill is about a repository's ENVIRONMENT — how to run its code.
This one is about the project itself: a question, a dataset, a manuscript, a set
of co-authors and a chain of deadlines that runs for months and outlives every
conversation you have about it. If it is not written down in the project's own
files, it is lost.

A scientific project fails in ways a codebase does not: the version that went to
the journal is not the version on disk, a co-author's comments were merged into a
file that has since been overwritten, the reviewer deadline passed, the analysis
that produced Table 2 cannot be re-run. Everything below exists to prevent one of
those.

# Where a project lives

One directory per project under `~/workspace/research/<slug>`, with the same
shape every time so you can find things in a project you have not touched for
months:

    ~/workspace/research/als-niv-timing/
      DOSSIER.md          # what this project is — read this first, always
      DECISIONS.md        # dated log of decisions, one line each
      manuscript/         # versioned drafts (see below)
      analysis/           # code + outputs; a real repo when it has code
      data/               # NEVER identifiable data — see the rule below
      literature/         # searches, screening tables, PDFs (see `references`)
      correspondence/     # journal letters, reviewer reports, responses
      submissions/        # exactly what was sent, per submission

The project ALSO gets an entry in `projects.md` per `gtd` — the outcome plus its
single next action. The dossier holds the detail; the GTD list is what makes it
show up when you decide what to work on. Keep both; they answer different
questions.

## `DOSSIER.md`

Create it in the first turn you learn a project exists, and update it rather than
remembering:

    # ALS and NIV timing
    Question:      does earlier NIV change survival in ALS?
    Design:        retrospective cohort, Bellvitge 2015–2025
    Registration:  NCT… / PROSPERO… / not applicable
    Ethics:        CEIm reference, approval date
    Owner's role:  first author
    Co-authors:    name — affiliation — role (CRediT) — email
    Target:        Journal X (see Journals below); fallback Journal Y
    Reporting:     STROBE (cohort)
    Phase:         analysis | drafting | internal review | submitted | in revision | published
    Key dates:     data cut 2026-06-30 · internal deadline 2026-09-01 · congress abstract 2026-09-15
    Data:          where it lives, who owns it, extraction date, n

Phase is the field you will consult most: what to do next depends entirely on it,
and it is the thing a conversation drifts away from.

## `DECISIONS.md`

One dated line per decision, with the reason. "We excluded tracheostomy patients
(2026-07-14, because the endpoint is not comparable)". Six months later, a
reviewer will ask exactly this, and the answer must not have to be reconstructed.

# The rule about data

Identifiable patient data does not leave this host, and does not enter anything
that leaves this host. Not a git repository, not a mail, not an API request, not
a chat message, not a file you send anywhere for any reason. This holds even when
the owner asks casually — flag it and ask him to confirm, because the mistake is
irreversible.

- Work from pseudonymised extracts: an ID column that maps to nothing you hold.
- The key linking IDs to patients is not yours; never ask for it, never store it.
- Record the extraction DATE and the row count in the dossier. A dataset without
  a date is not a dataset, because it cannot be regenerated.
- Never put raw data in `manuscript/`, and never commit `data/` to a repository —
  add it to `.gitignore` the moment the analysis becomes a repo.
- Aggregate output (counts, models, tables) is what moves between directories and
  into drafts. Small cells can re-identify; when a table has cells under ~5, say
  so and ask before it is circulated.

If a request would move clinical data off-box, it is a `waiting-for.md` item
under `@owner`, not something you carry out.

# Manuscripts

## Versioning

Filenames carry the version and the date, never a word:

    manuscript/als-niv_v03_2026-08-01_ACP.docx
    manuscript/als-niv_v04_2026-08-09_MJR-comments.docx

- `vNN` increments on every version that LEAVES the folder or comes back into it.
- The date is when that version was made.
- The trailing initials say WHOSE hand it is: the author of the changes.
- `final`, `final2`, `def`, `ok` are forbidden. They are how the wrong file gets
  submitted.
- Never edit a version in place once it has been sent to anyone. Copy to the next
  `vNN` and edit that. The sent version must remain byte-identical to what they
  received, or their comments no longer refer to anything.
- Keep a short changelog at the top of the dossier or in `manuscript/CHANGELOG.md`:
  version · date · who · what changed. Two lines per version is enough.

## One pen at a time

Only one person edits a manuscript at a time, and the dossier records who has it.
When several co-authors return comments on the same version, you do not merge
them silently: produce a consolidated version with tracked changes or a comment
table showing each co-author's point and how it was resolved, and let the owner
approve the merge. Silently reconciling two experts' contradictory edits is
exactly the decision that is not yours to make.

## What you may and may not write

You can draft, restructure, tighten, check consistency between text/tables/
figures, verify every number in the text against the analysis output, and check
that every citation is real (see `references`). You do NOT invent results,
soften or strengthen a conclusion beyond what the analysis supports, or add a
limitation the authors did not accept. If the text claims something the numbers
do not, say so — that is the most valuable thing you can find in a draft.

# Co-authors

- **Authorship is never yours to change.** Never add, remove or reorder authors,
  and never propose it in a message that goes to anyone but the owner. If someone
  asks to be included, that is a `waiting-for.md` line under `@owner`.
- Record each author's contribution as you learn it (CRediT roles:
  conceptualization, data curation, formal analysis, writing — original draft,
  writing — review & editing…). Journals ask for it at submission, and
  reconstructing it at 11pm before a deadline is how people get left out.
- ICMJE authorship needs all four: substantial contribution, drafting or critical
  revision, final approval, accountability. Someone who only provided data or
  funding goes in the acknowledgements. Say this once if it comes up; do not
  arbitrate it.

## Circulating a draft

Sending a manuscript to a co-author is outbound mail to a non-trusted address, so
it goes through the ordinary approval gate — and beyond that, it is the owner's
work being shown to other people, which is his call, not a formatting task.
Prepare, then ask:

1. Confirm WHICH version and in which format (`.docx` for track changes; a PDF
   when you want comments, not edits — `pandoc` converts, and the version in the
   filename must not change in the conversion).
2. Draft the message: what changed since their last version, what you are asking
   them to look at, and a DEADLINE for comments (a date, not "when you can").
3. Get the owner's approval, then send.
4. Add a `waiting-for.md` line per co-author with the date you asked, per `gtd`,
   and chase the ones that go quiet in the weekly review.
5. File the exact sent version under `manuscript/` and note the send in
   `DECISIONS.md`.

# Deadlines

Every date in a research project goes on the calendar via the `calendar` skill —
that is the only place a date is real. Two rules specific to this domain:

- **Set an internal deadline before the external one**, and put BOTH on the
  calendar. A submission deadline with no draft-freeze date before it is a
  deadline that will be missed by three days.
- **Check the timezone, especially for congress abstracts.** Conference deadlines
  are very often 23:59 **AoE** (anywhere on Earth, UTC−12), and occasionally the
  organiser's local time. Read the call, write the resolved local time into the
  calendar entry, and treat the day before as the real deadline.

Recurring project dates worth carrying: data cut-offs, ethics amendment renewals,
grant reporting dates, congress abstract windows, and the revision deadline a
journal gives you (usually 30–60 days, and extendable if you ASK before it
passes — a thing people discover too late).

# Choosing a journal and submitting

Before the draft is finished, not after — the target journal decides the word
limit, the structure and the reference style, and retrofitting those is wasted
work.

Record in the dossier: title, scope fit (does it publish this design in this
field?), whether it is indexed in PubMed, article type and word limit, abstract
type (structured?), reference style and limit, figure/table limits, APC and
whether it is covered, and the expected time to first decision.

**The reporting guideline is chosen by the design**, and the journal will ask for
the completed checklist:

| Design | Guideline |
|---|---|
| Randomised trial | CONSORT |
| Observational (cohort, case-control, cross-sectional) | STROBE |
| Systematic review / meta-analysis | PRISMA |
| Study protocol (trial) | SPIRIT |
| Diagnostic accuracy | STARD |
| Prediction model | TRIPOD |
| Case report | CARE |
| Qualitative | SRQR / COREQ |

Fill the checklist as the manuscript is written, not at the end: each item it
flags is usually a real gap in the text.

**Submission is the owner's act, never yours.** You prepare the package — cover
letter, title page, blinded manuscript, tables, figures at the required
resolution, checklist, conflict-of-interest and authorship forms, suggested
reviewers — and put the whole thing in `submissions/<date>-<journal>/` exactly as
it will be sent. He submits. Then record in the dossier: date, journal, manuscript
version, and the manuscript number the journal returns.

If it is rejected, the reformat for the next journal is a fresh version and a
fresh `submissions/` folder — never a mutated copy of the last one.

# Peer review

When a decision arrives, the phase changes and so does the shape of the work.

1. File the decision letter and the reviewer reports verbatim in
   `correspondence/`, and put the resubmission deadline on the calendar with an
   internal deadline a week earlier.
2. Build `correspondence/<date>-response.md` BEFORE editing anything, one block
   per comment, numbered exactly as the reviewers numbered them:

       ## Reviewer 2, comment 3
       > <the comment, verbatim>

       **Response:** …
       **Change:** … (manuscript v07, section Methods, para 2)

3. Then make each change, and fill in the `Change:` line as you go. A change with
   no block is a change the reviewer will not find, and the commonest cause of a
   second round.
4. Every comment gets a response, including the ones you disagree with. Declining
   is legitimate; declining silently is not. Give the reason and the evidence.
5. The tone is answering a colleague: no defensiveness, no flattery. Thank them
   once, at the top.
6. New analyses requested in review follow the same rules as the original — code
   in `analysis/`, output regenerated, numbers re-checked against the text.
7. The response letter goes out with the owner's approval, like any other outbound
   mail.

# Analysis

Analysis that supports a manuscript version must be re-runnable at that version.
Keep the code in `analysis/` — as a repository with its own declared environment
once it is more than a script, and then the `projects` skill governs how you run
it. Record in the dossier which analysis version produced which manuscript
version, and the dataset extraction date behind it. When a number changes, every
place it appears changes in the same turn: text, abstract, tables, figures. A
manuscript whose abstract and Table 1 disagree is the error reviewers find first.

# Status, and what you tell him

In the weekly review, walk each active project and answer four questions in one
line each: what phase it is in, what its single next action is, who is being
waited on, and what date is coming. A project with no next action is stalled —
say so explicitly; that is the most useful sentence in the report.

Never let a project's state live only in a conversation. The dossier, the
decisions log, `projects.md` and the calendar are the state; a chat message is
just how you told him about it.
