/**
 * Narrow domain boundaries for new mechanics.
 *
 * These types intentionally do not model every existing service. They provide
 * explicit vocabulary at the edges of new domain work so an overloaded
 * entityType cannot silently become authority, actor, payer, owner, location,
 * or state holder.
 */
export type AuthorityScope = 'EARTH' | 'CORPORATION';

export type EconomicPrincipalType =
  | 'EARTH'
  | 'CORPORATION'
  | 'HOUSE'
  | 'BANK'
  | 'SYSTEM';

export type ActorType = 'HUMAN' | 'SYSTEM';

export type MechanicResponsibility = {
  policyAuthority: AuthorityScope | 'none';
  decisionAuthority: AuthorityScope | 'none';
  actor: ActorType;
  economicPrincipal: EconomicPrincipalType | 'none';
  payer: EconomicPrincipalType | 'none';
  economicOwner: EconomicPrincipalType | 'none';
  location: 'TERRITORY' | 'none';
  stateHolder: string;
  beneficiaries: string[];
  authorizationSource: string;
  settlementPhase: string;
};

export function assertMechanicResponsibility(record: MechanicResponsibility): void {
  if (!record.stateHolder.trim()) throw new Error('Mechanic state holder is required');
  if (!record.authorizationSource.trim()) throw new Error('Mechanic authorization source is required');
  if (!record.settlementPhase.trim()) throw new Error('Mechanic settlement phase is required');
}
