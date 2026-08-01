---
name: investment-es
description: Spain-specific investment skill — account types, Spanish tax treatment of returns (base del ahorro, IRPF), broker access, rebalancing, year-end checklist, and when to escalate. Consult it whenever the owner asks about investing, a broker, a fund, a portfolio, or the tax impact of selling.
---

# Investment (Spain)

> **Scope**: this skill covers the Spanish investment and tax framework (IRPF base
> del ahorro, Modelo 720, Spanish-domiciled products). It is not applicable to
> other jurisdictions.

Check TOOLS.md for the owner's specific broker accounts, credentials, and any
notes about his current portfolio. This skill covers the general framework.

## Investment vehicles available in Spain

### Cuenta de valores (taxable brokerage account)
Standard account at any broker. No tax deferral — every dividend, interest, and
realised gain is taxable in the year it occurs. Most flexible: any asset class,
any broker.

### Fondos de inversión (UCITS investment funds)
Unique Spanish tax advantage: **traspasos are tax-free**. Moving money between
funds does not trigger a taxable event — tax is deferred until actual withdrawal.
This makes rebalancing via traspasos far more tax-efficient than selling and
rebuying. For long-term indexed investing, funds often beat ETFs in Spain purely
on tax grounds.

### ETFs in Spain
The traspaso exemption does **not** apply to ETFs. Switching between ETFs in a
taxable account is a taxable event. Tax-efficient globally, but less so for a
Spanish resident unless the TER difference versus equivalent funds is substantial.

### Plan de pensiones
Tax deduction at contribution time — reduces the general IRPF base up to the
annual limit (currently **1,500€ personal + employer contributions up to 8,500€**).
Withdrawals are taxed as earned income (not capital gains), so the bet is on
having lower income at withdrawal time than at contribution time.
Illiquid until retirement, with narrow exceptions (disability, long-term
unemployment, contributions older than 10 years for those made since 2015).
Key actions: contribute before Dec 31 each year to capture the deduction; plan
the withdrawal year carefully to minimise the tax rate.

### PIAS (Plan Individual de Ahorro Sistemático)
Insurance-wrapped savings product. Tax-free conversion to an annuity after 5
years. Complex and relatively niche; mention only if the owner asks.

## Tax treatment of investment returns (IRPF)

Investment returns — dividends, interest, and realised capital gains on shares,
ETFs, and funds — go into the **base imponible del ahorro**, taxed at:

| Gain/income | Rate (2024) |
|-------------|-------------|
| First 6,000€ | 19% |
| 6,001–50,000€ | 21% |
| 50,001–200,000€ | 23% |
| 200,001–300,000€ | 27% |
| > 300,000€ | 28% |

Rates change with each Ley de Presupuestos. Verify current rates before
advising on any significant transaction.

Plan de pensiones withdrawals are **not** in the ahorro base — they are taxed
as earned income at the general marginal rate.

**Loss offsetting**: capital losses offset capital gains. Losses can offset
dividends/interest up to 25% of positive returns. Unused losses carry forward
4 years — they are a tax asset worth tracking.

**Retención at source**: Spanish brokers typically withhold 19% on dividends and
gains. Many foreign brokers (e.g. DeGiro, Interactive Brokers) do not withhold
for Spanish clients — the owner must self-report those in the declaración de
la renta. Check TOOLS.md to know which brokers apply and whether they withhold.

**Cost basis**: Spain uses FIFO for shares and weighted average for funds. Make
sure broker reporting aligns, or adjust manually when computing gains.

## Working with a broker

When the owner shares portfolio data or gives access to a broker:
1. Document it in TOOLS.md: broker name, account type, access method (export
   format, API, manual CSV), and whether it withholds Spanish tax at source.
2. For tax reporting: request the annual tax report (informe fiscal / tax
   certificate) — usually available in the broker's platform in January.
3. If the broker is foreign (non-Spanish), check: Does it withhold? If dividends
   come from third countries, is there foreign withholding that can be credited
   in the Spanish return (conveniodedoble imposición)?

**Year-end checklist (December)**:
- Review unrealised losses — selling before Dec 31 to realise losses can offset
  gains from earlier in the year, or carry forward to the next 4 years
- Top up any plan de pensiones to the personal annual limit before Dec 31
  (contributions after Dec 31 count toward the following year)
- Verify the broker's records match your own tracking (shares held, dividends
  received, cost basis per position)

**At renta campaign (April–June)**:
- Gather annual tax reports from all brokers
- Cross-check dividends and gains/losses against the borrador (Agencia Tributaria
  pre-fill is often incomplete for foreign broker accounts)
- Include foreign withheld tax as a deduction or credit where applicable

## Traspaso de fondos vs selling ETFs — the key Spanish tax advantage

The **traspaso** is a transfer between investment funds (fondos de inversión UCITS)
that does not trigger a taxable event in Spain. The investor switches from one fund
to another without paying capital gains tax — tax is deferred until the final
redemption (reembolso).

**Why this matters for long-term indexing:**
- Rebalancing a portfolio of index funds can be done with zero tax drag
- Switching from accumulation fund to a cheaper share class, or from one provider
  to another, is free from a fiscal standpoint
- Compounding works on the full pre-tax amount for as long as the position is held

**The ETF trap**: ETFs traded on a stock exchange — even identical UCITS ETFs —
do not qualify for the traspaso regime. Selling an ETF to buy another (even the
same index, different provider) is a taxable event. For a Spanish resident with
meaningful accumulated gains, switching ETFs can be expensive.

**Practical rule**: for long-term indexed portfolio, favour fondos de inversión
over ETFs when the product is available, unless the TER difference is large enough
to outweigh the tax cost of periodic rebalancing. For tactical or short-term
positions, or when no equivalent fund exists, ETFs are fine.

## Cryptocurrencies (fiscalidad en España)

Spain taxes crypto gains as **capital gains in the base del ahorro** (same rates
as shares/funds: 19–28%). Key points:

- **Taxable events**: selling for fiat, exchanging one crypto for another,
  spending crypto on goods or services, receiving crypto as payment
- **Non-taxable**: buying crypto with fiat, transferring between your own wallets
- **Cost basis**: FIFO per currency; losses can offset gains in the same year and
  carry forward 4 years
- **Staking and DeFi yields**: treated as earned income (rendimientos del trabajo
  or del capital mobiliario depending on structure) — taxed at the general rate,
  not the ahorro rate. This distinction matters significantly for the marginal rate.

**Reporting obligations (from 2024):**
- **Modelo 172**: annual declaration of crypto held at Spanish providers (exchanges
  with Spanish licence). Filed in January for the prior year.
- **Modelo 173**: annual declaration of operations (buy/sell/exchange) at Spanish
  providers. Same window as 172.
- **Modelo 721**: foreign crypto assets (held at non-Spanish exchanges) exceeding
  50,000€ — analogous to Modelo 720 for financial assets. Annual, March deadline.
- Operations appear in the IRPF return (Modelo 100) in the capital gains section;
  the Modelos 172/173/721 are informational filings, not tax payment forms.

If the owner holds any crypto, flag the obligation to file the informational models
and ensure gains/losses are included in the renta. Foreign exchange holdings above
50,000€ trigger Modelo 721 — do not overlook it.

## Deposit and investment protection

**Fondo de Garantía de Depósitos (FGD)**: protects up to **100,000€ per depositor
per institution** for cash deposits (current accounts, savings accounts, fixed-term
deposits) at Spanish banks. Joint accounts count at 100,000€ per holder.

**Fondo de Garantía de Inversiones (FOGAIN)**: protects securities accounts
(valores) up to **100,000€ per investor per institution** in the event of broker
insolvency — covers the securities themselves, not market losses.

For foreign brokers (DeGiro, IBKR):
- DeGiro is Dutch; covered by the Dutch DGS (up to 100k€ in cash) and the Dutch
  SIPC-equivalent (20k€ for securities). Securities are held in a separate
  custodial structure (SPV) which reduces — but does not eliminate — insolvency risk.
- IBKR US entity: covered by SIPC (up to $500k, including $250k cash); EU entity
  varies by registration.
- Always verify the specific entity and its coverage before depositing large amounts.

Practical implication: if total investable assets at a single institution approach
100,000€, consider spreading across entities to stay within guarantee limits.

## When to involve a professional

Recommend a *gestor* or tax adviser if:
- The owner is about to sell a large position and wants to time it across fiscal
  years to manage the marginal rate
- He receives foreign dividends with unclear treaty treatment
- Foreign assets at foreign brokers exceed 50,000€ (Modelo 720 obligation,
  deadline March 31 annually)
- He is considering rescuing a plan de pensiones and wants to model the income
  tax hit across different drawdown strategies
- The portfolio is large enough that adviser cost is outweighed by tax savings
  (rough rule: above ~100,000€ in taxable accounts)
