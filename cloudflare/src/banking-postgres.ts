import type { PostgresRepository } from './repository.ts';
import { quoteLoan } from './banking.ts';
import { runEconomicMutation, postEconomicTransaction, postSettlementTransaction } from './settlement-barrier-postgres.ts';
import { formatCreditUnits } from './money.ts';

type CreditFacts = { borrowerEconomicId: string; walletId: string; walletBalance: bigint; reserveId: string; reserveBalance: bigint; operationsId: string; cashflow: bigint; policy: any; day: number };

async function creditFacts(tx: PostgresRepository, humanId: string): Promise<CreditFacts> {
  const clock = await readAuthoritativeGameTime(tx);
  const day = clock.gameDay;
  const owner = (await tx.query<{ economic_id: string }>(`SELECT o.economic_id
    FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
    WHERE h.id = $1 AND h.status = 'ACTIVE'`, [humanId])).rows[0];
  const policy = (await tx.query<any>(`SELECT p.* FROM bank_credit_policies p WHERE p.bank_economic_id = 'ECON-GLOBAL-BANK-001' AND p.status = 'ACTIVE' AND p.effective_from_game_day <= $1 AND (p.effective_to_game_day IS NULL OR p.effective_to_game_day >= $1) ORDER BY p.effective_from_game_day DESC LIMIT 1`, [day])).rows[0];
  const accounts = await tx.query<{ reserve_id: string; reserve_balance: string; operations_id: string; wallet_id: string; wallet_balance: string }>(`SELECT r.id::TEXT AS reserve_id, r.balance_units::TEXT AS reserve_balance, o.id::TEXT AS operations_id, w.id::TEXT AS wallet_id, w.balance_units::TEXT AS wallet_balance FROM economic_accounts r JOIN economic_accounts o ON o.owner_economic_id = r.owner_economic_id AND o.asset_id = 1 AND o.account_type = 'OPERATIONS' AND o.status = 'ACTIVE' JOIN economic_accounts w ON w.owner_economic_id = $1 AND w.asset_id = 1 AND w.account_type = 'WALLET' AND w.status = 'ACTIVE' WHERE r.owner_economic_id = 'ECON-GLOBAL-BANK-001' AND r.asset_id = 1 AND r.account_type = 'RESERVE' AND r.status = 'ACTIVE'`, [owner?.economic_id]);
  const row = accounts.rows[0];
  const cashflow = (await tx.query<{ units: string }>(`SELECT COALESCE(SUM(e.delta_units) FILTER (WHERE e.delta_units > 0), 0)::TEXT AS units FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id WHERE e.account_id = $1 AND t.game_day >= $2`, [row?.wallet_id, Math.max(1, day - 30)])).rows[0];
  if (!owner || !policy || !row) throw new Error('Bank credit policy or liquidity state is unavailable');
  return { borrowerEconomicId: owner.economic_id, walletId: row.wallet_id, walletBalance: BigInt(row.wallet_balance), reserveId: row.reserve_id, reserveBalance: BigInt(row.reserve_balance), operationsId: row.operations_id, cashflow: BigInt(cashflow?.units ?? 0), policy, day };
}

export async function listBankLoans(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ economic_id: string }>(`SELECT o.economic_id
    FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
    WHERE h.id = $1 AND h.status = 'ACTIVE'`, [humanId])).rows[0];
  if (!owner) return { loans: [], generatedFrom: 'postgres-canonical-facts' };
  const loans = await repository.query(`SELECT id, original_principal_units::TEXT, outstanding_principal_units::TEXT, accrued_interest_units::TEXT, rate_bps, term_days, origination_game_day, maturity_game_day, next_payment_game_day, status FROM bank_loans WHERE borrower_economic_id = $1 ORDER BY origination_game_day DESC, id`, [owner.economic_id]);
  return { loans: loans.rows.map((row) => {
    const principalUnits = String(row.outstanding_principal_units ?? '0');
    const interestUnits = String(row.accrued_interest_units ?? '0');
    const totalUnits = (BigInt(principalUnits) + BigInt(interestUnits)).toString();
    return { ...row, outstandingPrincipalUnits: principalUnits, accruedInterestUnits: interestUnits, totalDueUnits: totalUnits, outstandingPrincipal: formatCreditUnits(BigInt(principalUnits)), accruedInterest: formatCreditUnits(BigInt(interestUnits)), totalDue: formatCreditUnits(BigInt(totalUnits)), display: { unitCode: 'CREDIT', scale: 2 } };
  }), generatedFrom: 'postgres-canonical-facts' };
}

function quoteFromFacts(facts: CreditFacts, requestedUnits: bigint, termDays: number) {
  if (termDays > Number(facts.policy.max_term_days)) throw new Error('Requested loan term exceeds bank policy');
  return quoteLoan({ requestedUnits, termDays, collateralUnits: facts.walletBalance, guaranteedUnits: 0n, borrowerCashflowUnits: facts.cashflow, availableReserveUnits: facts.reserveBalance, baseRateBps: BigInt(facts.policy.base_rate_bps), maxLoanToCollateralBps: BigInt(facts.policy.max_loan_to_collateral_bps), maxLoanToCashflowBps: BigInt(facts.policy.max_loan_to_cashflow_bps), minimumReserveRatioBps: BigInt(facts.policy.minimum_reserve_ratio_bps) });
}

export async function getBankLoanQuote(repository: PostgresRepository, input: { humanId: string; requestedUnits: bigint; termDays: number }): Promise<Record<string, unknown>> {
  const facts = await creditFacts(repository, input.humanId);
  const quote = quoteFromFacts(facts, input.requestedUnits, input.termDays);
  const interest = (input.requestedUnits * BigInt(quote.rateBps) * BigInt(input.termDays)) / 36500n;
  return { quote: { eligible: quote.eligible, approvedUnits: quote.approvedUnits.toString(), approvedAmount: formatCreditUnits(quote.approvedUnits), requestedUnits: input.requestedUnits.toString(), requestedAmount: formatCreditUnits(input.requestedUnits), termDays: input.termDays, rateBps: quote.rateBps.toString(), estimatedInterestUnits: interest.toString(), estimatedInterest: formatCreditUnits(interest), estimatedTotalRepaymentUnits: (input.requestedUnits + interest).toString(), estimatedTotalRepayment: formatCreditUnits(input.requestedUnits + interest), maturityGameDay: facts.day + input.termDays, policyVersion: facts.policy.policy_version, reason: quote.reason, display: { unitCode: 'CREDIT', scale: 2 } }, generatedFrom: 'postgres-canonical-facts' };
}

export async function originateBankLoan(repository: PostgresRepository, input: { humanId: string; requestedUnits: bigint; termDays: number; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const existing = (await tx.query<{ id: string }>('SELECT id FROM bank_loans WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (existing) return { ok: true, alreadyProcessed: true, loanId: existing.id, correlationId: input.correlationId };
    const facts = await creditFacts(tx, input.humanId);
    const quote = quoteFromFacts(facts, input.requestedUnits, input.termDays);
    if (!quote.eligible || quote.approvedUnits < input.requestedUnits) throw new Error(`Loan is not eligible: ${quote.reason}`);
    if (facts.walletBalance < input.requestedUnits || facts.reserveBalance < input.requestedUnits) throw new Error('Cash collateral or bank reserve is insufficient');
    const locked = await tx.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [facts.walletId]);
    const reserve = await tx.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [facts.reserveId]);
    if (BigInt(locked.rows[0]?.balance_units ?? 0) < input.requestedUnits || BigInt(reserve.rows[0]?.balance_units ?? 0) < input.requestedUnits) throw new Error('Loan facts changed; retry the quote');
    const day = facts.day;
    const loanId = `LOAN-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const posted = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'BANK_LOAN_ORIGINATION',
      sourceType: 'BANK',
      sourceId: 'GLOBAL-BANK',
      rulesVersion: 'bank-credit-v1',
      entries: [
        { account_id: facts.walletId, asset_id: 1, delta_units: (-input.requestedUnits).toString() },
        { account_id: facts.operationsId, asset_id: 1, delta_units: input.requestedUnits.toString() },
        { account_id: facts.reserveId, asset_id: 1, delta_units: (-input.requestedUnits).toString() },
        { account_id: facts.walletId, asset_id: 1, delta_units: input.requestedUnits.toString() },
      ],
    }, clock);
    const maturity = day + input.termDays;
    const interest = (input.requestedUnits * BigInt(quote.rateBps) * BigInt(input.termDays)) / 36500n;
    await tx.query(`INSERT INTO bank_loans (id, borrower_economic_id, bank_economic_id, original_principal_units, outstanding_principal_units, accrued_interest_units, rate_bps, credit_limit_units, term_days, origination_game_day, maturity_game_day, next_payment_game_day, status, origination_transaction_id, correlation_id) VALUES ($1,$2,'ECON-GLOBAL-BANK-001',$3,$3,0,$4,$3,$5,$6,$7,$7,'PERFORMING',$8,$9)`, [loanId, facts.borrowerEconomicId, input.requestedUnits.toString(), quote.rateBps.toString(), input.termDays, day, maturity, posted.transactionId, input.correlationId]);
    await tx.query(`INSERT INTO bank_loan_collateral (id, loan_id, owner_economic_id, collateral_type, reference_id, valuation_units, haircut_bps, pledged_game_day, correlation_id) VALUES ($1,$2,$3,'CASH',$4,$5,0,$6,$7)`, [`COLLATERAL-${loanId}`, loanId, facts.borrowerEconomicId, facts.walletId, input.requestedUnits.toString(), day, `collateral:${input.correlationId}`]);
    await tx.query(`INSERT INTO bank_loan_schedules (id, loan_id, installment_no, due_game_day, principal_due_units, interest_due_units, correlation_id) VALUES ($1,$2,1,$3,$4,$5,$6)`, [`SCHEDULE-${loanId}`, loanId, maturity, input.requestedUnits.toString(), interest.toString(), `schedule:${input.correlationId}`]);
    return { ok: true, loanId, principalUnits: input.requestedUnits.toString(), principal: formatCreditUnits(input.requestedUnits), interestUnits: interest.toString(), interest: formatCreditUnits(interest), totalRepaymentUnits: (input.requestedUnits + interest).toString(), totalRepayment: formatCreditUnits(input.requestedUnits + interest), rateBps: quote.rateBps.toString(), maturityGameDay: maturity, display: { unitCode: 'CREDIT', scale: 2 }, correlationId: input.correlationId };
  });
}

export async function repayBankLoan(repository: PostgresRepository, input: { humanId: string; loanId: string; amountUnits?: bigint; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const existing = (await tx.query<{ id: string }>('SELECT id FROM bank_loan_payments WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (existing) return { ok: true, alreadyProcessed: true, paymentId: existing.id, correlationId: input.correlationId };
    const facts = await creditFacts(tx, input.humanId);
    const loan = (await tx.query<any>(`SELECT l.*, s.principal_due_units::TEXT AS scheduled_principal, s.interest_due_units::TEXT AS scheduled_interest, c.valuation_units::TEXT AS collateral_units FROM bank_loans l JOIN bank_loan_schedules s ON s.loan_id = l.id AND s.status IN ('DUE','PARTIAL','ARREARS') LEFT JOIN bank_loan_collateral c ON c.loan_id = l.id AND c.status = 'PLEDGED' WHERE l.id = $1 AND l.borrower_economic_id = $2 AND l.status IN ('PERFORMING','DELINQUENT') FOR UPDATE`, [input.loanId, facts.borrowerEconomicId])).rows[0];
    if (!loan) throw new Error('Repayable loan not found');
    const principal = BigInt(loan.outstanding_principal_units);
    const interestDue = BigInt(loan.accrued_interest_units) > BigInt(loan.scheduled_interest) ? BigInt(loan.accrued_interest_units) : BigInt(loan.scheduled_interest);
    const collateral = BigInt(loan.collateral_units ?? 0);
    const total = principal + interestDue;
    const payment = input.amountUnits ?? total;
    if (payment <= 0n || payment > total) throw new Error('Payment must be positive and no greater than the outstanding claim');
    const interest = payment < interestDue ? payment : interestDue;
    const principalPayment = payment - interest;
    const borrowerWallet = BigInt((await tx.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [facts.walletId])).rows[0]?.balance_units ?? 0);
    if (borrowerWallet < payment) throw new Error('Borrower cannot pay the requested loan installment');
    const entries: Array<{ account_id: string; asset_id: number; delta_units: string }> = [{ account_id: facts.walletId, asset_id: 1, delta_units: (-payment).toString() }, { account_id: facts.operationsId, asset_id: 1, delta_units: payment.toString() }];
    if (principalPayment === principal && interest === interestDue && collateral > 0n) {
      entries.push({ account_id: facts.operationsId, asset_id: 1, delta_units: (-collateral).toString() });
      entries.push({ account_id: facts.walletId, asset_id: 1, delta_units: collateral.toString() });
    }
    const posted = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'BANK_LOAN_REPAYMENT',
      sourceType: 'HOUSE',
      sourceId: input.humanId,
      rulesVersion: 'bank-credit-v1',
      entries,
    }, clock);
    const paymentId = `PAYMENT-${input.correlationId}`;
    await tx.query(`INSERT INTO bank_loan_payments (id, loan_id, amount_units, principal_units, interest_units, payment_transaction_id, game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [paymentId, input.loanId, payment.toString(), principalPayment.toString(), interest.toString(), posted.transactionId, facts.day, input.correlationId]);
    const remainingClaim = total - payment;
    await tx.query("UPDATE bank_loan_schedules SET paid_units = LEAST(principal_due_units + interest_due_units, paid_units + $1), status = CASE WHEN paid_units + $1 >= principal_due_units + interest_due_units THEN 'PAID' ELSE 'PARTIAL' END, payment_transaction_id = $2 WHERE loan_id = $3 AND status IN ('DUE','PARTIAL','ARREARS')", [payment.toString(), posted.transactionId, input.loanId]);
    if (remainingClaim === 0n) await tx.query("UPDATE bank_loan_collateral SET status = 'RELEASED', released_game_day = $1 WHERE loan_id = $2 AND status = 'PLEDGED'", [facts.day, input.loanId]);
    await tx.query("UPDATE bank_loans SET outstanding_principal_units = outstanding_principal_units - $1, accrued_interest_units = GREATEST(0, accrued_interest_units - $2), status = CASE WHEN outstanding_principal_units - $1 = 0 AND accrued_interest_units - $2 <= 0 THEN 'PAID' WHEN status = 'DELINQUENT' THEN 'DELINQUENT' ELSE 'PERFORMING' END WHERE id = $3", [principalPayment.toString(), interest.toString(), input.loanId]);
    return { ok: true, paymentId, loanId: input.loanId, principalUnits: principalPayment.toString(), principal: formatCreditUnits(principalPayment), interestUnits: interest.toString(), interest: formatCreditUnits(interest), totalUnits: payment.toString(), total: formatCreditUnits(payment), remainingUnits: remainingClaim.toString(), remaining: formatCreditUnits(remainingClaim), display: { unitCode: 'CREDIT', scale: 2 }, correlationId: input.correlationId };
  });
}

export async function addBankLoanGuarantee(repository: PostgresRepository, input: { humanId: string; loanId: string; guaranteedUnits: bigint; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const existing = (await tx.query<{ id: string }>('SELECT id FROM bank_loan_guarantees WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (existing) return { ok: true, alreadyProcessed: true, guaranteeId: existing.id, correlationId: input.correlationId };
    const facts = await creditFacts(tx, input.humanId);
    const loan = (await tx.query<{ borrower_economic_id: string; status: string }>('SELECT borrower_economic_id, status FROM bank_loans WHERE id = $1 FOR UPDATE', [input.loanId])).rows[0];
    if (!loan || loan.borrower_economic_id === facts.borrowerEconomicId || !['PERFORMING', 'DELINQUENT'].includes(loan.status) || input.guaranteedUnits <= 0n) throw new Error('Loan is not eligible for this guarantee');
    const guaranteeId = `GUARANTEE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO bank_loan_guarantees (id, loan_id, guarantor_economic_id, guaranteed_units, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)`, [guaranteeId, input.loanId, facts.borrowerEconomicId, input.guaranteedUnits.toString(), facts.day, input.correlationId]);
    return { ok: true, guaranteeId, loanId: input.loanId, guaranteedUnits: input.guaranteedUnits.toString(), correlationId: input.correlationId };
  });
}

export async function settleBankLoanRisk(tx: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const candidates = await tx.query<{ id: string }>("SELECT id FROM bank_loans WHERE status IN ('PERFORMING','DELINQUENT') AND (status = 'PERFORMING' OR delinquent_since_game_day <= $1) ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED", [gameDay]);
  let accrued = 0;
  let delinquent = 0;
  let defaulted = 0;
  for (const candidate of candidates.rows) {
    const loan = (await tx.query<any>('SELECT * FROM bank_loans WHERE id = $1 FOR UPDATE', [candidate.id])).rows[0];
    if (!loan || loan.status === 'PAID' || loan.status === 'CANCELLED') continue;
    const numerator = BigInt(loan.outstanding_principal_units) * BigInt(loan.rate_bps) + BigInt(loan.interest_accrual_remainder ?? 0);
    const dailyInterest = numerator / 36500n;
    const remainder = numerator % 36500n;
    await tx.query('UPDATE bank_loans SET accrued_interest_units = accrued_interest_units + $1, interest_accrual_remainder = $2 WHERE id = $3', [dailyInterest.toString(), remainder.toString(), loan.id]);
    accrued += 1;
    if (loan.status === 'PERFORMING' && gameDay >= Number(loan.maturity_game_day)) {
      await tx.query("UPDATE bank_loans SET status = 'DELINQUENT', delinquent_since_game_day = $1, next_payment_game_day = $1 WHERE id = $2", [gameDay, loan.id]);
      await tx.query(`INSERT INTO bank_loan_resolutions (id, loan_id, resolution_type, claim_units, priority_rank, game_day, details, correlation_id) VALUES ($1,$2,'DELINQUENCY',$3,1,$4,$5::JSONB,$6) ON CONFLICT (correlation_id) DO NOTHING`, [`RESOLVE-DELINQUENCY-${loan.id}-${gameDay}`, loan.id, (BigInt(loan.outstanding_principal_units) + BigInt(loan.accrued_interest_units) + dailyInterest).toString(), gameDay, JSON.stringify({ maturityGameDay: loan.maturity_game_day }), `delinquency:${loan.id}:${gameDay}`]);
      delinquent += 1;
    } else if (loan.status === 'DELINQUENT' && gameDay >= Number(loan.delinquent_since_game_day) + 7) {
      await tx.query("UPDATE bank_loans SET status = 'DEFAULTED', defaulted_game_day = COALESCE(defaulted_game_day, $1) WHERE id = $2", [gameDay, loan.id]);
      const collateral = (await tx.query<{ valuation_units: string }>("SELECT COALESCE(SUM(valuation_units), 0)::TEXT AS valuation_units FROM bank_loan_collateral WHERE loan_id = $1 AND status = 'PLEDGED'", [loan.id])).rows[0];
      const recovered = BigInt(collateral?.valuation_units ?? 0);
      if (recovered > 0n) {
        const bankAccounts = await tx.query<{ operations_id: string; reserve_id: string }>("SELECT o.id::TEXT AS operations_id, r.id::TEXT AS reserve_id FROM economic_accounts o JOIN economic_accounts r ON r.owner_economic_id = o.owner_economic_id AND r.asset_id = 1 AND r.account_type = 'RESERVE' AND r.status = 'ACTIVE' WHERE o.owner_economic_id = 'ECON-GLOBAL-BANK-001' AND o.asset_id = 1 AND o.account_type = 'OPERATIONS' AND o.status = 'ACTIVE'");
        const bank = bankAccounts.rows[0];
        if (!bank) throw new Error('Bank reserve accounts are unavailable for liquidation');
        await postSettlementTransaction(tx, {
          correlationId: `liquidation:${loan.id}:${gameDay}`,
          gameDay,
          kind: 'BANK_COLLATERAL_LIQUIDATION',
          sourceType: 'BANK',
          sourceId: 'GLOBAL-BANK',
          rulesVersion: 'bank-credit-v1',
          entries: [
            { account_id: bank.operations_id, asset_id: 1, delta_units: (-recovered).toString() },
            { account_id: bank.reserve_id, asset_id: 1, delta_units: recovered.toString() },
          ],
        });
        await tx.query("UPDATE bank_loan_collateral SET status = 'LIQUIDATED', released_game_day = $1 WHERE loan_id = $2 AND status = 'PLEDGED'", [gameDay, loan.id]);
      }
      await tx.query(`INSERT INTO bank_loan_resolutions (id, loan_id, resolution_type, claim_units, recovered_units, priority_rank, game_day, details, correlation_id) VALUES ($1,$2,'LIQUIDATION',$3,$4,1,$5,$6::JSONB,$7) ON CONFLICT (correlation_id) DO NOTHING`, [`RESOLVE-LIQUIDATION-${loan.id}-${gameDay}`, loan.id, (BigInt(loan.outstanding_principal_units) + BigInt(loan.accrued_interest_units) + dailyInterest).toString(), recovered.toString(), gameDay, JSON.stringify({ defaultAgeDays: 7, collateralLiquidated: recovered.toString() }), `liquidation:${loan.id}:${gameDay}`]);
      defaulted += 1;
    }
  }
  return { ok: true, gameDay, accrued, delinquent, defaulted };
}

export async function getBankRiskProjection(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const result = await repository.query<any>(`SELECT (SELECT COALESCE(SUM(balance_units),0)::TEXT FROM economic_accounts WHERE owner_economic_id = 'ECON-GLOBAL-BANK-001' AND asset_id = 1 AND account_type = 'RESERVE' AND status = 'ACTIVE') AS reserve_units, (SELECT COALESCE(SUM(principal_units + accrued_interest_units),0)::TEXT FROM bank_deposits WHERE status IN ('ACTIVE','MATURED')) AS deposit_liabilities_units, (SELECT COALESCE(SUM(outstanding_principal_units + accrued_interest_units),0)::TEXT FROM bank_loans WHERE status IN ('PERFORMING','DELINQUENT','DEFAULTED')) AS loan_claims_units, (SELECT COALESCE(SUM(outstanding_principal_units),0)::TEXT FROM bank_loans WHERE status = 'PERFORMING') AS performing_loans_units, (SELECT COUNT(*)::INTEGER FROM bank_loans WHERE status = 'DEFAULTED') AS defaulted_loan_count, (SELECT COALESCE(SUM(recovered_units),0)::TEXT FROM bank_loan_resolutions WHERE resolution_type = 'LIQUIDATION') AS liquidated_recovery_units`);
  const row = result.rows[0] ?? {};
  const reserve = BigInt(row.reserve_units ?? 0);
  const deposits = BigInt(row.deposit_liabilities_units ?? 0);
  const loans = BigInt(row.loan_claims_units ?? 0);
  return { projection: { reserveUnits: reserve.toString(), depositLiabilitiesUnits: deposits.toString(), loanClaimsUnits: loans.toString(), performingLoansUnits: String(row.performing_loans_units ?? '0'), defaultedLoanCount: Number(row.defaulted_loan_count ?? 0), liquidatedRecoveryUnits: String(row.liquidated_recovery_units ?? '0'), liquidityRatioBps: deposits > 0n ? ((reserve * 10000n) / deposits).toString() : '10000', capitalBufferUnits: (reserve + loans - deposits).toString() }, generatedFrom: 'postgres-canonical-facts' };
}
