# FiveM Banking Resource

A feature-packed, standalone banking system for FiveM servers that now includes a slick NUI tablet, interactive ATMs/tellers, timed wires, scheduled payments, shared accounts, taxes/fees, robbery hooks, and admin/auditing tooling on top of the original cash/bank functionality.

## Highlights

- **Immersive UI:** Open the in-game tablet (F6 or `/bankmenu`) or walk up to the configured ATMs/tellers to manage accounts via NUI instead of chat spam.
- **ATM gameplay:** Service fees and withdraw limits, robbery/hacking hooks (`H` near an ATM), contextual biometric/PIN checks, and events (`banking:atmUsage`) for other scripts.
- **Economic depth:** Timed wire transfers, scheduled payments, donation goals, crowdfunding, configurable taxes, transaction cooldowns/limits, offline transfers, fractional currency support, and server-tier overrides.
- **Accounts everywhere:** Personal cash/bank/crypto wallets, shared business accounts, ATM treasury, scheduled autopay, savings interest (even while offline), overdraft/loan systems, favorites, achievements, and tiered perks.
- **Staff tooling:** `/bankgive`, `/bankset`, `/bankfine`, `/banktier`, `/bankdashboard`, `/bankaudit`, transaction webhooks/backups, webhook-ready alerts for high value moves, and Discord-ready payloads.
- **Developer friendly:** Events/exports for rewarding/charging players, automatic paycheck event, rent helper, crime payout splitter, overrides, and ATM usage broadcasts.

## Installation

1. Copy `resources/banking` into your server resources directory.
2. Ensure the resource in `server.cfg`:
   ```cfg
   ensure banking
   ```
3. Make sure `resources/banking/data` is writable; account data lives in `data/accounts.json`.

The resource ships with a minimal web UI (`html/`) referenced by the manifest—no additional setup required.

## Player commands

| Command | Description |
| --- | --- |
| `/bankbalance` | Show current cash/bank totals. |
| `/bankdeposit <amount|all>` | Deposit cash to bank (applies taxes). |
| `/bankwithdraw <amount|all>` | Withdraw with tier/ATM fees, biometric checks, overdraft support. |
| `/banktransfer <target> <amount>` | Instant transfer via player id, IBAN, or saved favorite (PIN gating for high values). |
| `/bankwire <iban> <amount>` | Schedule a delayed wire transfer. |
| `/bankschedule list/add/remove ...` | Recurring payments to other identifiers. |
| `/bankshared create/deposit/withdraw` | Create and use faction/business accounts. |
| `/bankhistory [page] [filter]` | Paginated, filterable history viewer. |
| `/banktop [bank|cash|wealth|gains]` | Leaderboards. |
| `/bankhelp` | Quick reference of the above. |
| `/bankloan` / `/bankrepay` | Payday-style loan system with auto interest. |
| `/bankinvest <bonds|stocks> <amount>` | Record passive investments. |
| `/bankstats` | Lifetime earnings/spendings summary. |
| `/bankfavorite <name> <target>` | Save IBAN/player shortcuts for transfers. |
| `/bankrequest` / `/bankapprove` | Player-to-player fund requests. |
| `/bankdonate <goal> <amount>` | Push toward configurable server goals. |
| `/bankshare <id> <seconds>` | Temporarily link balances with another player. |
| `/banklock` | Toggle personal account lock. |
| `/bankpin <current> [new]` | Verify or change your PIN for large transfers. |
| `/bankmenu` (or F6) | Open the NUI tablet anywhere. |

## Admin / management commands

- `/bankgive <id> <amount>` — Grant/remove bank money (ACE: `command.bankgive`).
- `/bankset <id> <amount>` — Force a player bank balance (ACE: `command.bankset`).
- `/bankfine <id> <amount>` — Deduct fines with webhook logging (ACE: `command.bankfine`).
- `/banktier <id> <tier>` — Assign VIP tiers defined in `Config.serviceTiers` (ACE: `command.banktier`).
- `/bankdashboard` — Aggregate cash/bank totals (ACE: `command.bankdashboard`).
- `/bankaudit <identifier>` — Push full balance/history payloads to the configured webhook (ACE: `command.bankaudit`).
- `bankreload` — Console-only JSON reload.

## Exports & helpers

```lua
local cash, bank, crypto = exports['banking']:GetBalance(playerId)
exports['banking']:AddCash(playerId, 500)
exports['banking']:AddBank(playerId, -250, 'ticket fee')
exports['banking']:TransferBank(sourceId, targetId, 1000)
exports['banking']:DistributeCrimePayout(playerId, 5000, 0.6) -- split between cash/bank
exports['banking']:WithdrawForRent(playerId, 1500)
exports['banking']:SetAccountOverride(identifier, 'pinThreshold', 2000)
```

### Events

- `banking:balanceUpdated (playerSrc, cash, bank, reason)` — Fired on every sync.
- `banking:transaction (identifier, action, amount, metadata)` — Emitted for all transactions.
- `banking:atmUsage (playerSrc, coords)` — Raised when a player uses the UI at an ATM/teller.
- `banking:paycheck (amount)` — Client event you can trigger to auto-deposit wages.
- `banking:atmRobbery` (client→server) — Provided for robbery/hacking scripts; server re-broadcasts alerts via `Config.atm.robbery.alertEvent`.

## Configuration overview

Nearly every system has knobs inside `server/main.lua`'s `Config` table:

- `localization` — Language + strings.
- `startingBalances` / `currencies` — Default cash/bank/crypto values.
- `atm` — Interact distance, withdraw limits, service fees, robbery rewards, teller ped coordinates.
- `wires`, `scheduledPayments`, `sharedAccounts` — Limits and intervals for automation features.
- `taxes`, `savings`, `loans`, `overdraft`, `donations`, `achievements`, `serviceTiers` — Economic tuning.
- `cooldowns`, `limits`, `notifications`, `webhooks`, `backup` — Anti-abuse + auditing hooks.

Adjust the values to match your server economy, add/remove ATMs, teller NPCs, donation goals, etc. The JSON datastore (`data/accounts.json`) automatically preserves balances, scheduled payments, offline transfers, and donation progress.

## UI & interactions

- F6 (or `/bankmenu`) opens the tablet anywhere.
- E near the provided ATM coordinates opens the UI with ATM context (fees, biometric gates).
- H near an ATM triggers the robbery mini-hook (server fires `Config.atm.robbery.alertEvent`).
- E near the spawned teller ped opens the banker UI with no fees.

The NUI is intentionally lightweight so you can re-skin it if desired; the HTML/JS files live in `resources/banking/html/` and can be customized freely.

## Data & backups

Accounts, shared ledgers, donation progress, and queued offline transfers are stored in `data/accounts.json`. Autosaves happen periodically, on player drop, and on resource stop; optional webhook backups (`Config.webhooks.backup`) can mirror the file externally to prevent data loss.
