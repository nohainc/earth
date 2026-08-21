export type ObjectiveCategory =
  | 'enterprise'
  | 'civic'
  | 'dynasty'
  | 'technology'
  | 'finance'
  | 'civilization';

export type ObjectiveStatus = 'in_progress' | 'completed' | 'claimed';

export interface PlayerObjective {
  id: string;
  category: ObjectiveCategory;
  title: string;
  description: string;
  currentValue: number;
  targetValue: number;
  progressPercentage: number;
  metricLabel: string;
  status: ObjectiveStatus;
  rewardDescription: string;
  targetSection: string;
  iconName: string;
}

export interface ObjectivesEvaluationInput {
  human?: { credits?: unknown; standing?: unknown; legacy?: unknown; voting_weight?: unknown; age_years?: unknown };
  business?: { id?: string; business_count?: unknown; service_business_count?: unknown; valuation?: unknown; treasury?: unknown; profit?: unknown; net_income?: unknown; revenue?: unknown };
  institutions?: {
    city?: { health_capacity?: unknown; essential_services_index?: unknown; standing?: unknown };
    corporation?: { treasury?: unknown; member_count?: unknown };
  };
  governance?: { proposals_voted?: unknown; voting_weight?: unknown };
  technology?: { research_progress?: unknown; active_patents?: unknown; active_licenses?: unknown };
  dynasty?: { generation?: unknown; perks_count?: unknown; heirlooms_count?: unknown; successor_id?: string | null };
  projects?: { completed?: unknown };
  resources?: Record<string, unknown>;
  netWorth?: number;
}

const num = (v: unknown, fallback = 0): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};

/**
 * Evaluates the primary long-term strategic objectives for the player.
 * Objectives are optional, measurable, and tied to existing planetary systems.
 */
export function evaluatePlayerObjectives(input: ObjectivesEvaluationInput): PlayerObjective[] {
  const objectives: PlayerObjective[] = [];

  // 1. Build the most valuable corporation
  const corpTreasury = num(input.institutions?.corporation?.treasury, 0);
  const businessValuation = Math.max(
    num(input.business?.valuation, 0),
    corpTreasury + Math.max(0, num(input.business?.profit, 0) * 12) + 25000
  );
  const targetCorpVal = 100000;
  const corpProgress = Math.min(100, Math.round((businessValuation / targetCorpVal) * 100));
  objectives.push({
    id: 'obj-valuable-corporation',
    category: 'enterprise',
    title: 'Build the Most Valuable Corporation',
    description: 'Grow your enterprise into an industrial conglomerate with an enterprise valuation surpassing 100,000 Credits.',
    currentValue: businessValuation,
    targetValue: targetCorpVal,
    progressPercentage: corpProgress,
    metricLabel: `${businessValuation.toLocaleString()} / ${targetCorpVal.toLocaleString()} C Valuation`,
    status: corpProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Industrial Titan" · +500 Legacy Points · Corporate Tax Charter Exemption',
    targetSection: 'business',
    iconName: 'business_center',
  });

  // 4. Build a service enterprise
  const serviceBusinessCount = Math.max(0, num(input.business?.service_business_count, 0));
  const serviceTarget = 2;
  const serviceEnterpriseProgress = Math.min(100, Math.round((serviceBusinessCount / serviceTarget) * 100));
  objectives.push({
    id: 'obj-service-enterprise',
    category: 'enterprise',
    title: 'Build a Service Enterprise',
    description: 'Develop two people-powered service businesses that earn recurring revenue through expertise, contracts, and corporate networks.',
    currentValue: serviceBusinessCount,
    targetValue: serviceTarget,
    progressPercentage: serviceEnterpriseProgress,
    metricLabel: `${serviceBusinessCount} / ${serviceTarget} Service Businesses`,
    status: serviceEnterpriseProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Civic Service Architect" · +250 Legacy Points · Priority access to institutional contracts',
    targetSection: 'business',
    iconName: 'support_agent',
  });

  // 2. Build a productive food reserve
  const foodReserve = Math.max(0, num(input.resources?.food, 0));
  const targetFoodReserve = 500;
  const foodProgress = Math.min(100, Math.round((foodReserve / targetFoodReserve) * 100));
  objectives.push({
    id: 'obj-food-security',
    category: 'enterprise',
    title: 'Build a Self-Sustaining Food Reserve',
    description: 'Use productive assets and food systems to maintain a 500-unit reserve that protects your household and businesses from supply shocks.',
    currentValue: foodReserve,
    targetValue: targetFoodReserve,
    progressPercentage: foodProgress,
    metricLabel: `${Math.round(foodReserve).toLocaleString()} / ${targetFoodReserve.toLocaleString()} Food Units`,
    status: foodProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Food Systems Steward" · +200 Legacy Points · Reduced emergency supply costs',
    targetSection: 'business',
    iconName: 'restaurant',
  });

  // 3. Build a portfolio of independent operations
  const businessCount = Math.max(0, num(input.business?.business_count, input.business?.id ? 1 : 0));
  const targetBusinessCount = 3;
  const portfolioProgress = Math.min(100, Math.round((businessCount / targetBusinessCount) * 100));
  objectives.push({
    id: 'obj-enterprise-portfolio',
    category: 'enterprise',
    title: 'Build a Portfolio of Enterprises',
    description: 'Own or manage three distinct operations so your dynasty is not dependent on a single source of income or production.',
    currentValue: businessCount,
    targetValue: targetBusinessCount,
    progressPercentage: portfolioProgress,
    metricLabel: `${businessCount} / ${targetBusinessCount} Active Operations`,
    status: portfolioProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Enterprise Builder" · +300 Legacy Points · Portfolio management privileges',
    targetSection: 'business',
    iconName: 'business_center',
  });

  // 4. Become a major civic delegate
  const votingWeight = Math.max(
    num(input.governance?.voting_weight, 0),
    num(input.human?.voting_weight, 1)
  );
  const targetVotingWeight = 25;
  const civicProgress = Math.min(100, Math.round((votingWeight / targetVotingWeight) * 100));
  objectives.push({
    id: 'obj-civic-delegate',
    category: 'civic',
    title: 'Become a Major Civic Delegate',
    description: 'Amass democratic delegation and civic standing to command at least 25 voting weight across municipal referendums.',
    currentValue: votingWeight,
    targetValue: targetVotingWeight,
    progressPercentage: civicProgress,
    metricLabel: `${votingWeight.toFixed(1)} / ${targetVotingWeight.toFixed(1)} Voting Weight`,
    status: civicProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Grand Tribune" · Veto Injunction Power on City Budgets · +350 Standing',
    targetSection: 'civic',
    iconName: 'how_to_vote',
  });

  // 3. Create a dynasty with specific traits
  const dynastyGen = num(input.dynasty?.generation, 1);
  const perksCount = num(input.dynasty?.perks_count, 0) + num(input.dynasty?.heirlooms_count, 0) + (input.dynasty?.successor_id ? 1 : 0);
  const targetDynastyPerks = 3;
  const dynastyProgress = Math.min(
    100,
    Math.round(((dynastyGen - 1 + perksCount) / (targetDynastyPerks + 1)) * 100)
  );
  objectives.push({
    id: 'obj-dynasty-traits',
    category: 'dynasty',
    title: 'Create a Dynasty with Sovereign Traits',
    description: 'Advance your generational lineage to Generation 2+ and unlock at least 3 distinct dynasty traits and heirlooms.',
    currentValue: perksCount,
    targetValue: targetDynastyPerks,
    progressPercentage: dynastyProgress,
    metricLabel: `Gen ${dynastyGen} · ${perksCount} / ${targetDynastyPerks} Dynasty Traits Unlocked`,
    status: dynastyProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Eternal Patriarch" · 100% Estate Inheritance Tax Waiver · Ancestral Vault Access',
    targetSection: 'dynasty',
    iconName: 'account_balance',
  });

  // 5. Become a leading technology licensor
  const activePatents = num(input.technology?.active_patents, 0);
  const activeLicenses = num(input.technology?.active_licenses, 0);
  const techScore = activePatents * 2 + activeLicenses;
  const targetTechScore = 6;
  const techProgress = Math.min(100, Math.round((techScore / targetTechScore) * 100));
  objectives.push({
    id: 'obj-technology-licensor',
    category: 'technology',
    title: 'Become a Leading Technology Licensor',
    description: 'Grant exclusive technology patents and establish active commercial licensing contracts with other corporate enterprises.',
    currentValue: techScore,
    targetValue: targetTechScore,
    progressPercentage: techProgress,
    metricLabel: `${activePatents} Patents · ${activeLicenses} Commercial Licenses (${techScore}/${targetTechScore} Pts)`,
    status: techProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Chief Innovator" · 3.5% Global Tech Royalty Fee · Instant Research Accelerator',
    targetSection: 'technology',
    iconName: 'biotech',
  });

  // 6. Reach financial independence
  const credits = num(input.human?.credits, 0);
  const netWorth = input.netWorth ?? credits + businessValuation * 0.25;
  const targetNetWorth = 50000;
  const financeProgress = Math.min(100, Math.round((netWorth / targetNetWorth) * 100));
  objectives.push({
    id: 'obj-financial-independence',
    category: 'finance',
    title: 'Reach Financial Independence',
    description: 'Accumulate a verified personal net worth exceeding 50,000 Credits with diversified asset streams.',
    currentValue: Math.round(netWorth),
    targetValue: targetNetWorth,
    progressPercentage: financeProgress,
    metricLabel: `${Math.round(netWorth).toLocaleString()} / ${targetNetWorth.toLocaleString()} C Net Worth`,
    status: financeProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Sovereign Capitalist" · Private Banking Clearance · Priority Exchange Order Routing',
    targetSection: 'finance',
    iconName: 'account_balance_wallet',
  });

  // 7. Maintain the highest public-service score
  const cityServiceRatio = num(input.institutions?.city?.essential_services_index, 0.75) * 100;
  const standing = num(input.human?.standing, 70);
  const publicServiceScore = Math.round((cityServiceRatio + standing) / 2);
  const targetServiceScore = 90;
  const serviceProgress = Math.min(100, Math.round((publicServiceScore / targetServiceScore) * 100));
  objectives.push({
    id: 'obj-public-service-score',
    category: 'civilization',
    title: 'Maintain the Highest Public-Service Score',
    description: 'Optimize municipal health, utilities, and civic infrastructure to sustain a 90%+ Public Service & Standing rating.',
    currentValue: publicServiceScore,
    targetValue: targetServiceScore,
    progressPercentage: serviceProgress,
    metricLabel: `${publicServiceScore}% / ${targetServiceScore}% Service Rating`,
    status: serviceProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Planetary Benefactor" · Memorial Monument in Pantheon of Living Legends · +1000 Civic Trust',
    targetSection: 'city',
    iconName: 'volunteer_activism',
  });

  // Shared projects turn relationships into visible civilization-building.
  const completedProjects = Math.max(0, num(input.projects?.completed, 0));
  const projectTarget = 3;
  const projectProgress = Math.min(100, Math.round((completedProjects / projectTarget) * 100));
  objectives.push({
    id: 'obj-civic-project-builder',
    category: 'civic',
    title: 'Build With Your Community',
    description: 'Complete three shared city or corporation projects that leave a lasting improvement for the people around your dynasty.',
    currentValue: completedProjects,
    targetValue: projectTarget,
    progressPercentage: projectProgress,
    metricLabel: `${completedProjects} / ${projectTarget} Shared Projects Completed`,
    status: projectProgress >= 100 ? 'completed' : 'in_progress',
    rewardDescription: 'Title: "Commonwealth Builder" · +300 Legacy Points · Stronger institutional project influence',
    targetSection: 'activity',
    iconName: 'construction',
  });

  return objectives;
}
