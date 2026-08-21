export type OpportunitySignal = 'market' | 'production' | 'business' | 'governance' | 'community';

export type Opportunity = {
  id: string;
  signal: OpportunitySignal;
  title: string;
  detail: string;
  priority: 'high' | 'medium' | 'low';
  subject: string;
};

type MarketSignal = { product: string; supply: unknown; demand: unknown; price: unknown };
type MachineSignal = { id: string; name: string; output_resource: string; condition: unknown; utilization: unknown };
type ProposalSignal = { id: string; title: string; status: string; closes_at?: unknown };
type CommunitySignal = { id: string; name: string; status: string };
type BusinessSignal = { id: string; name?: string; sector?: string; status?: string };

const numeric = (value: unknown): number => Number(value ?? 0);
const label = (value: string): string => value.charAt(0).toUpperCase() + value.slice(1);

/**
 * Ranks attention-worthy signals for the first-session command center.
 * This is a presentation rule only: it never changes prices, production, or
 * any authoritative economic outcome.
 */
export function rankOpportunities(input: {
  market: MarketSignal[];
  machines: MachineSignal[];
  businesses?: BusinessSignal[];
  proposals: ProposalSignal[];
  communities: CommunitySignal[];
}): Opportunity[] {
  const opportunities: Array<Opportunity & { score: number }> = [];
  for (const product of input.market) {
    const supply = numeric(product.supply);
    const demand = numeric(product.demand);
    if (demand <= supply) continue;
    const pressure = demand / Math.max(1, supply);
    opportunities.push({
      id: `market-${product.product}`,
      signal: 'market',
      title: `${label(product.product)} demand is ahead`,
      detail: `${Math.round(demand)} demand against ${Math.round(supply)} available · ${numeric(product.price).toFixed(2)} C reference price`,
      priority: pressure >= 1.5 ? 'high' : 'medium',
      subject: product.product,
      score: pressure,
    });
  }

  const scarceProducts = new Set(opportunities.filter((item) => item.signal === 'market').map((item) => item.subject));
  for (const machine of input.machines) {
    if (!scarceProducts.has(machine.output_resource) || numeric(machine.condition) <= 0) continue;
    opportunities.push({
      id: `production-${machine.id}`,
      signal: 'production',
      title: `${machine.name} can answer demand`,
      detail: `Its ${label(machine.output_resource)} output matches a live market shortage · condition ${Math.round(numeric(machine.condition))}%`,
      priority: numeric(machine.condition) < 40 ? 'high' : 'medium',
      subject: machine.id,
      score: 2 + numeric(machine.condition) / 100,
    });
  }

  const serviceSectors = new Set(['it-services', 'consulting', 'logistics', 'healthcare', 'education']);
  for (const business of input.businesses ?? []) {
    if (business.status && business.status !== 'active') continue;
    if (!serviceSectors.has(String(business.sector))) continue;
    const sectorName = label(String(business.sector).replaceAll('-', ' '));
    opportunities.push({
      id: `service-${business.id}`,
      signal: 'business',
      title: `${business.name ?? 'Service business'} needs client work`,
      detail: `${sectorName} capacity earns more when it is matched with a recurring service contract.`,
      priority: 'medium',
      subject: business.id,
      score: 1.8,
    });
  }

  const proposal = input.proposals.find((item) => item.status === 'open');
  if (proposal) {
    opportunities.push({
      id: `governance-${proposal.id}`,
      signal: 'governance',
      title: 'A rule is waiting for your judgment',
      detail: proposal.title,
      priority: 'medium',
      subject: proposal.id,
      score: 1.5,
    });
  }

  const community = input.communities.find((item) => item.status === 'active');
  if (community) {
    opportunities.push({
      id: `community-${community.id}`,
      signal: 'community',
      title: 'A Community is open to new Humans',
      detail: `${community.name} is available for membership and future city formation.`,
      priority: 'low',
      subject: community.id,
      score: 1,
    });
  }

  return opportunities
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, 5)
    .map(({ score: _score, ...opportunity }) => opportunity);
}
