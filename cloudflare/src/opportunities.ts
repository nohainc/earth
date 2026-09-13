export type OpportunitySignal = 'market' | 'production' | 'governance' | 'community';

export type Opportunity = {
  id: string;
  signal: OpportunitySignal;
  title: string;
  detail: string;
  priority: 'high' | 'medium' | 'low';
  subject: string;
};

type MarketSignal = { product: string; supply: unknown; demand: unknown; price: unknown };
type ProposalSignal = { id: string; title: string; status: string; closes_at?: unknown };
type CommunitySignal = { id: string; name: string; status: string };

const numeric = (value: unknown): number => Number(value ?? 0);
const label = (value: string): string => value.charAt(0).toUpperCase() + value.slice(1);

/**
 * Ranks attention-worthy signals for the first-session command center.
 * This is a presentation rule only: it never changes prices, production, or
 * any authoritative economic outcome.
 */
export function rankOpportunities(input: {
  market: MarketSignal[];
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
