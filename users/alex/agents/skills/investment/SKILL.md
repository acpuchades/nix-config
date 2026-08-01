---
name: investment
description: How to help with investment decisions and portfolio management in Spain — types of accounts and products, Spanish tax treatment of investment returns, tracking positions, periodic rebalancing, and what to watch out for. Consult it whenever the owner asks about investing, a broker, a fund, a portfolio, or the tax impact of selling.
---

# Investment

## Investment vehicles available in Spain

### Cuenta de valores (taxable brokerage account)
Standard account at a broker. No tax deferral — every dividend, interest, and
realised gain is taxable in the year it occurs. Most flexible: any asset class,
any broker.

### Fondos de inversión (UCITS investment funds)
Unique Spanish feature: **traspasos are tax-free**. You can move money between
funds without triggering a taxable event. Tax is deferred until you actually
withdraw. This makes fund-of-funds strategies and rebalancing via traspasos
significantly more tax-efficient than ETFs in a taxable account.

### ETFs in Spain
Tax-efficient globally but not in Spain: ETF switches are taxable events. The
traspaso exemption does NOT apply to ETFs. For a Spanish resident building a
long-term portfolio, funds often beat ETFs purely on tax grounds unless the ETF
TER is dramatically lower.

### Plan de pensiones
Tax deduction at contribution time (reduces IRPF base). Annual contribution
limit: **1,500€ personal + employer contributions up to 8,500€**. Withdrawals
are taxed as earned income (not capital gains) — which is disadvantageous.
Illiquid until retirement (with exceptions: disability, long-term unemployment,
> 10 years for contributions made since 2015). Only useful if: the owner
expects lower income in retirement than now (likely for most professionals), and
can absorb the illiquidity.

### PIAS (Plan Individual de Ahorro Sistemático)
Insurance product, not a pension. Tax-free conversion to an annuity after 5
years if used for that purpose. Complex; mention only if he asks about it.

## Tax treatment of investment returns (IRPF)

Investment returns go into the **base imponible del ahorro**, taxed at:

| Gain/income | Rate (2024) |
|-------------|-------------|
| First 6,000€ | 19% |
| 6,001–50,000€ | 21% |
| 50,001–200,000€ | 23% |
| 200,001–300,000€ | 27% |
| > 300,000€ | 28% |

Rates change with each Finance Law (Ley de Presupuestos). Verify current rates
before advising on a large transaction.

**What goes here**: dividends, interest, realised capital gains (sale of shares,
ETFs, funds). **What doesn't**: plan de pensiones withdrawals (earned income),
annual premiums on life insurance (insurance rules apply).

**Loss offsetting**: capital losses can offset capital gains. Losses from funds
can offset dividends up to 25% of positive returns. Unused losses carry forward
4 years. Keep track of losses — they are an asset.

**Retención**: brokers typically withhold 19% at source. This appears on the tax
return and offsets the final liability. Foreign brokers may not withhold; the
owner must self-report.

## Tracking positions

If the owner shares portfolio data (broker export, CSV, manual list), help him
track:
- Current allocation (% per asset class or geography)
- Unrealised gains/losses per position
- Dividend history (for yield calculation)
- Cost basis (weighted average price — how Spanish law calculates it for FIFO
  purposes: Spain uses FIFO for shares, weighted average for funds)

Document any broker access tokens or export formats in TOOLS.md under the
broker name.

## Periodic rebalancing

If he has a target allocation, suggest a rebalancing review annually or after
>5% drift. For taxable accounts, prefer rebalancing by directing new
contributions rather than selling (avoids taxable events). For funds, use
traspasos where possible.

## The owner's current setup

### MyInvestor — plan de pensiones
The owner holds a plan de pensiones at MyInvestor. Key things to track:
- Annual contribution limit: **1,500€ personal** (deducts from IRPF general base)
- MyInvestor also offers low-cost indexed funds (Amundi, Vanguard equivalents)
  — if he wants to use traspasos for rebalancing, he can do it all within
  MyInvestor without changing brokers
- The plan de pensiones annual statement (extracto) comes in January; useful
  for verifying the IRPF deduction matches contributions made the prior year
- Withdrawal strategy matters: if he rescues the pension in a year with low
  income (sabbatical, retirement), the tax hit is much lower

### DeGiro — taxable brokerage (cuenta de valores)
The owner has assets at DeGiro. Important specifics:
- **DeGiro does NOT withhold Spanish tax** at source — he must self-report all
  dividends and capital gains in the declaración de la renta
- DeGiro provides an **Informe Anual / Annual Tax Report** each January (available
  in the platform under Documents). This is the primary input for the tax return
- **Dutch withholding**: for ETFs domiciled in Ireland (most Vanguard/iShares EU
  ETFs) there is typically no Dutch withholding. For Dutch-domiciled assets,
  15% is withheld; it can be recovered via double-taxation treaty (but requires
  filing with the Dutch tax authority, which is rarely worth the effort for small
  amounts)
- Cost basis: DeGiro uses FIFO for shares. Spanish law also uses FIFO for
  shares (not weighted average). Match these when calculating gains
- If total foreign assets at DeGiro exceed 50,000€, **Modelo 720** must be filed
  by March 31 each year

### What to do at year-end (December)
1. Review unrealised losses at DeGiro — if any position is down, consider
   whether selling before Dec 31 to realise the loss is worthwhile (offsets
   gains or carries forward)
2. Verify MyInvestor plan de pensiones contributions — top up to 1,500€ if
   not yet reached, before Dec 31
3. DeGiro annual report will arrive in January — save it for the renta campaign

## What other brokers are common among Spanish investors

- **Indexa Capital**: robo-advisor, automatic rebalancing, low TER; good
  alternative if he wants a hands-off approach
- **Interactive Brokers**: broad asset access, complex but powerful; same
  self-reporting requirement as DeGiro
- **Banco tradicional** (CaixaBank, BBVA, Santander): high-fee funds, avoid
  for indexed investing

## When to involve a professional

Recommend a *gestor* or tax adviser if:
- He is about to sell a large position and wants to time the tax impact across
  fiscal years
- He receives foreign dividends and is unsure about double-taxation treaties
- He holds foreign accounts or assets > 50,000€ (Modelo 720 obligation)
- He is considering a plan de pensiones rescue and wants to model the tax hit
- The portfolio is large enough that the saving from professional advice
  exceeds its cost (rough rule: above 100,000€ in taxable accounts, a
  one-hour session with a tax adviser pays for itself)
