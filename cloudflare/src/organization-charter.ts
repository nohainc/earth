export type OrganizationCharter = {
  membershipModel: 'OPEN' | 'REQUEST' | 'INVITE_ONLY';
  ownershipModel: 'ORGANIZATION' | 'HOUSE_COLLECTIVE' | 'PUBLIC';
  votingMethod: 'ONE_HOUSE_ONE_VOTE' | 'DELEGATED' | 'SHARE_WEIGHTED' | 'QUADRATIC_VOICE';
  authorityLimits: { canOwnAssets: boolean; canGovernTerritory: boolean };
  surplusPolicy: 'RETAIN_AND_DISTRIBUTE' | 'MEMBER_DIVIDEND' | 'REINVEST_RESEARCH' | 'PUBLIC_SERVICES';
  capabilities: string[];
  dissolutionPolicy: 'GOVERNANCE_VOTE' | 'UNANIMOUS_MEMBER_VOTE' | 'EARTH_REVIEW';
};

const allowedCapabilities = new Set(['ECONOMIC_OWNER', 'GOVERNANCE', 'TERRITORY_GOVERNOR', 'RESEARCH', 'BANKING', 'PUBLIC_PROJECTS']);

export function validateOrganizationCharter(value: unknown): OrganizationCharter {
  const charter = value as Partial<OrganizationCharter>;
  if (!['OPEN', 'REQUEST', 'INVITE_ONLY'].includes(String(charter.membershipModel))) throw new Error('Invalid charter membership model');
  if (!['ORGANIZATION', 'HOUSE_COLLECTIVE', 'PUBLIC'].includes(String(charter.ownershipModel))) throw new Error('Invalid charter ownership model');
  if (!['ONE_HOUSE_ONE_VOTE', 'DELEGATED', 'SHARE_WEIGHTED', 'QUADRATIC_VOICE'].includes(String(charter.votingMethod))) throw new Error('Unsupported charter voting method');
  if (!charter.authorityLimits || typeof charter.authorityLimits.canOwnAssets !== 'boolean' || typeof charter.authorityLimits.canGovernTerritory !== 'boolean') throw new Error('Invalid charter authority limits');
  if (!['RETAIN_AND_DISTRIBUTE', 'MEMBER_DIVIDEND', 'REINVEST_RESEARCH', 'PUBLIC_SERVICES'].includes(String(charter.surplusPolicy))) throw new Error('Invalid charter surplus policy');
  const capabilities = [...new Set((charter.capabilities ?? []).map((capability) => String(capability).toUpperCase()))];
  if (!capabilities.length || capabilities.some((capability) => !allowedCapabilities.has(capability)) || !capabilities.includes('GOVERNANCE')) throw new Error('Charter must declare valid Governance capability');
  if (charter.ownershipModel === 'PUBLIC' && !capabilities.includes('PUBLIC_PROJECTS')) throw new Error('Public ownership requires PUBLIC_PROJECTS capability');
  if (charter.authorityLimits.canGovernTerritory && !capabilities.includes('TERRITORY_GOVERNOR')) throw new Error('Territory authority requires TERRITORY_GOVERNOR capability');
  if (charter.ownershipModel === 'HOUSE_COLLECTIVE' && charter.authorityLimits.canGovernTerritory) throw new Error('House collective cannot govern Territory');
  if (charter.surplusPolicy === 'REINVEST_RESEARCH' && !capabilities.includes('RESEARCH')) throw new Error('Research surplus requires RESEARCH capability');
  if (!['GOVERNANCE_VOTE', 'UNANIMOUS_MEMBER_VOTE', 'EARTH_REVIEW'].includes(String(charter.dissolutionPolicy))) throw new Error('Invalid charter dissolution policy');
  return { ...charter, capabilities } as OrganizationCharter;
}

export function charterPreset(archetype: string): OrganizationCharter {
  const presets: Record<string, OrganizationCharter> = {
    CORPORATION: { membershipModel: 'OPEN', ownershipModel: 'ORGANIZATION', votingMethod: 'ONE_HOUSE_ONE_VOTE', authorityLimits: { canOwnAssets: true, canGovernTerritory: true }, surplusPolicy: 'RETAIN_AND_DISTRIBUTE', capabilities: ['ECONOMIC_OWNER', 'GOVERNANCE', 'TERRITORY_GOVERNOR'], dissolutionPolicy: 'GOVERNANCE_VOTE' },
    COOPERATIVE: { membershipModel: 'REQUEST', ownershipModel: 'HOUSE_COLLECTIVE', votingMethod: 'ONE_HOUSE_ONE_VOTE', authorityLimits: { canOwnAssets: true, canGovernTerritory: false }, surplusPolicy: 'MEMBER_DIVIDEND', capabilities: ['ECONOMIC_OWNER', 'GOVERNANCE'], dissolutionPolicy: 'UNANIMOUS_MEMBER_VOTE' },
    RESEARCH: { membershipModel: 'INVITE_ONLY', ownershipModel: 'ORGANIZATION', votingMethod: 'ONE_HOUSE_ONE_VOTE', authorityLimits: { canOwnAssets: true, canGovernTerritory: false }, surplusPolicy: 'REINVEST_RESEARCH', capabilities: ['ECONOMIC_OWNER', 'GOVERNANCE', 'RESEARCH'], dissolutionPolicy: 'GOVERNANCE_VOTE' },
    PUBLIC_BODY: { membershipModel: 'OPEN', ownershipModel: 'PUBLIC', votingMethod: 'ONE_HOUSE_ONE_VOTE', authorityLimits: { canOwnAssets: true, canGovernTerritory: true }, surplusPolicy: 'PUBLIC_SERVICES', capabilities: ['GOVERNANCE', 'TERRITORY_GOVERNOR', 'PUBLIC_PROJECTS'], dissolutionPolicy: 'EARTH_REVIEW' },
  };
  return presets[archetype.toUpperCase()] ?? presets.COOPERATIVE;
}

export function charterTemplateId(archetype: string): string {
  const normalized = archetype.toUpperCase();
  if (normalized === 'CORPORATION') return 'CHARTER-COMPANY-V1';
  if (normalized === 'RESEARCH') return 'CHARTER-RESEARCH-V1';
  if (normalized === 'PUBLIC_BODY') return 'CHARTER-TERRITORIAL-V1';
  return 'CHARTER-COOPERATIVE-V1';
}
