---
name: personal-finance
description: How to help with personal financial management — monitoring subscriptions and recurring expenses, tracking the monthly budget, reminding about Spanish tax deadlines, accessing banking tools, and advising when a professional is needed. Consult it whenever the owner asks about money, expenses, bills, taxes, or financial planning.
---

# Personal finance

The owner is a salaried professional in Spain. Unless he tells you otherwise,
assume Spanish tax residency, two income sources (hospital + research), and no
VAT obligations (no autónomo activity). Update this assumption if he tells you
differently.

## Subscriptions and recurring expenses

When asked to audit subscriptions, look for recurring charges in bank statements
or card exports he provides. Group them by category:

- **Tools and software**: cloud storage, productivity apps, streaming
- **Professional**: journals, databases, professional memberships
- **Services**: phone, internet, insurance premiums, gym
- **Investments / savings**: regular transfers, pension contributions

For each, flag: monthly cost, last date used (if he can tell you), and whether
it can be cancelled or downgraded. Do not suggest cancelling without asking —
just surface the list and the total.

Set a calendar reminder for a **quarterly subscription audit** if he wants one.
Three months is short enough to catch zombie subscriptions before they stack up.

## Monthly budget

If he shares income and expense data (bank export, spreadsheet, manual list),
help him structure it into:

- Fixed expenses (rent, loans, insurance, subscriptions)
- Variable essentials (groceries, transport, health)
- Discretionary (restaurants, shopping, hobbies)
- Savings and investment rate

Do not invent categories he hasn't mentioned. Ask before adding. The goal is
clarity, not a perfect budget framework — match whatever level of detail he
actually tracks.

## Spanish tax calendar

These are the key dates for a salaried resident in Spain. Remind him in advance
(at least one week before each deadline):

| Period | Deadline | What |
|--------|----------|------|
| April 2 | Campaign opens | Declaración de la Renta (IRPF) |
| June 25 | Last day with domiciliation | IRPF — bank direct debit option |
| June 30 | Campaign closes | IRPF — last day to file |
| November 20 | Second IRPF instalment | If split payment was chosen in June |

If he has income beyond salary (research grants, clinical trial fees, investment
returns, rental income, foreign income), flag that his return may require a
professional or at least manual verification — the Agencia Tributaria's
pre-filled draft (borrador) may be incomplete.

Other taxes that may apply depending on his situation:
- **Modelo 720**: declaration of foreign assets > 50,000€ (annual, March 31)
- **Patrimonio**: if net worth exceeds regional threshold (varies by CC.AA.)
- **Retenciones sobre rendimientos de capital**: withheld at source by brokers and
  banks; appears in the borrador but verify it matches your broker's certificate

## Recording invoices and financial documents

Before processing any invoice, receipt, or financial document, ask the owner
which system he uses to store them — do not assume. Common setups include:

- A dedicated folder in cloud storage (Nextcloud, Google Drive, Dropbox)
- A bookkeeping app (Freeagent, Holded, Contasimple, a spreadsheet)
- A document management system with tags/categories
- Paper + physical folder

Once you know his system, use it consistently: file documents where he expects
to find them, in the format and naming convention he already uses. If no system
exists yet, suggest one and let him decide — do not create one unilaterally.

For deductible expenses (see below), flag them explicitly at the moment of
filing so they are easy to retrieve at renta time.

## Tax deductions and allowances (desgravaciones)

Spain offers a range of deductions at national, regional (autonómica), and local
level. The applicable ones depend on the owner's specific situation — always
verify current rules with the Agencia Tributaria or a gestor, as amounts and
conditions change yearly.

### National deductions (all taxpayers)

- **Aportaciones a plan de pensiones**: up to 1,500€/year deductible from the
  general base (more if employer contributes)
- **Rendimientos del trabajo** (employed income): standard deduction applied
  automatically in the borrador
- **Donativos a entidades sin ánimo de lucro**: 80% for the first 150€, 35% or
  40% for amounts above (Law 49/2002 entities — NGOs, foundations, universities)
- **Deducciones por familia numerosa / discapacidad** if applicable
- **Inversión en empresas de nueva creación** (startups): 50% deduction on
  investment, subject to conditions

### Autónomo and professional income deductions

If the owner has any self-employed activity (honorary fees, clinical trial
payments declared as actividad económica, consulting):

- General rule: expenses must be **necessary for the activity** and
  **documented with invoice** (factura, not just ticket)
- Deductible: professional subscriptions, equipment (amortised), books and
  training, professional insurance, dedicated phone/internet proportion, home
  office if formally constituted
- A receipt (ticket) suffices for small amounts in some contexts but a proper
  factura with NIF is required for deduction claims — always prefer factura

### Autonómica and local deductions

Vary significantly by Comunidad Autónoma. In Cataluña (where the owner is based)
notable deductions include:

- **Alquiler de vivienda habitual** (tenants): if the rental contract predates
  certain dates; verify current eligibility
- **Inversión en residencia habitual**: if he purchased before 2013 (transitional
  regime)
- **Donaciones a entidades catalanas** (additional regional deduction on top of
  national)
- **Nacimiento/adopción de hijos** and family situation deductions

Check the Agència Tributària de Catalunya (ATC) website or the Agencia Tributaria
IRPF guide for Cataluña each year for the updated list — these change.

### What to track during the year

Keep a running list of potentially deductible expenses:
- Subscriptions that relate to professional activity (journals, databases,
  professional organisation fees)
- Training courses and conference fees (with factura)
- Equipment purchased for work use (prorate if also personal)
- Charitable donations (entity must provide a certificate for > 150€)

## Banking tools and access

If the owner shares bank credentials or gives you access to a banking API or
data export, document it in TOOLS.md under the bank's name. Do not store full
card numbers or PINs — only API tokens, read-only access tokens, or export
formats.

For read-only analysis tasks (categorising transactions, computing monthly
totals), ask him to export a CSV or PDF from his bank and share it. Most Spanish
banks (CaixaBank, BBVA, Santander, ING) offer transaction exports.

## When to escalate to a professional

Recommend a *gestor* or *asesor fiscal* if:
- He has freelance or autónomo income alongside salary
- He received income from abroad (grants, speaking fees, publications)
- He has rental income or sold property
- His investment returns are substantial (> 6,000€/year in gains)
- The Agencia Tributaria sends a notice (*requerimiento*) or starts a
  *comprobación limitada*

In those cases, do not try to resolve it yourself — flag it clearly and suggest
he contacts a professional before the deadline.

## Reminders

If he wants automatic reminders for tax deadlines, set them via the cron tool
at least one week before the date. Include what action is needed in the reminder
text so it is self-explanatory when it fires.
