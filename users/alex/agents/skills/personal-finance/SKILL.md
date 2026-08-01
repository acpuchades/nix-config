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
