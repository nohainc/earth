/** Canonical API contract.
 *
 * Route handlers remain free to use whatever internal implementation they
 * need, but every public endpoint has one owner and one authorization class.
 * Keep this list deliberately boring: it is also consumed by certification
 * tests and tooling that checks for accidental route duplication.
 */
export const API_ROUTE_OWNERS = [
  'AuthRoutes', 'SystemRoutes', 'HouseRoutes', 'BuildingRoutes',
  'ResearchRoutes', 'MarketRoutes', 'FinanceRoutes', 'InstitutionRoutes',
  'GovernanceRoutes', 'CommunityRoutes', 'ReadModelRoutes',
] as const;

export const API_AUTH_CLASSES = [
  'PUBLIC', 'AUTHENTICATED', 'HOUSE_SELF', 'HUMAN_SELF',
  'INSTITUTION_MEMBER', 'INSTITUTION_ROLE', 'INTERNAL_ADMIN',
] as const;

export type ApiRouteOwner = typeof API_ROUTE_OWNERS[number];
export type ApiAuthClass = typeof API_AUTH_CLASSES[number];
export type ApiRouteStatus = 'ACTIVE' | 'DEPRECATED' | 'REMOVED';

export type ApiRouteContract = {
  method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  /** A normalized path. Dynamic identifiers use `{id}` or `{kind}`. */
  path: string;
  owner: ApiRouteOwner;
  auth: ApiAuthClass;
  service: string;
  status: ApiRouteStatus;
};

export const API_ROUTES: readonly ApiRouteContract[] = [
  { method: 'GET', path: '/api/live', owner: 'SystemRoutes', auth: 'PUBLIC', service: 'liveness', status: 'ACTIVE' },
  { method: 'GET', path: '/api/ready', owner: 'SystemRoutes', auth: 'PUBLIC', service: 'readiness', status: 'ACTIVE' },
  { method: 'GET', path: '/api/health', owner: 'SystemRoutes', auth: 'PUBLIC', service: 'health', status: 'ACTIVE' },
  { method: 'GET', path: '/internal/audit', owner: 'ReadModelRoutes', auth: 'INTERNAL_ADMIN', service: 'auditWorld', status: 'ACTIVE' },
  { method: 'POST', path: '/api/auth/register', owner: 'AuthRoutes', auth: 'PUBLIC', service: 'registerAccount', status: 'ACTIVE' },
  { method: 'POST', path: '/api/auth/login', owner: 'AuthRoutes', auth: 'PUBLIC', service: 'login', status: 'ACTIVE' },
  { method: 'POST', path: '/api/auth/logout', owner: 'AuthRoutes', auth: 'AUTHENTICATED', service: 'logout', status: 'ACTIVE' },
  { method: 'GET', path: '/api/auth/me', owner: 'AuthRoutes', auth: 'AUTHENTICATED', service: 'getSessionAccount', status: 'ACTIVE' },
  { method: 'PATCH', path: '/api/auth/profile', owner: 'AuthRoutes', auth: 'HUMAN_SELF', service: 'updateProfile', status: 'ACTIVE' },
  { method: 'GET', path: '/api/house', owner: 'HouseRoutes', auth: 'HOUSE_SELF', service: 'getHouseOverview', status: 'ACTIVE' },
  { method: 'POST', path: '/api/house/{action}', owner: 'HouseRoutes', auth: 'HOUSE_SELF', service: 'houseService', status: 'ACTIVE' },
  { method: 'GET', path: '/api/buildings/catalog', owner: 'ReadModelRoutes', auth: 'PUBLIC', service: 'buildingCatalog', status: 'ACTIVE' },
  { method: 'POST', path: '/api/real-estate/purchase', owner: 'BuildingRoutes', auth: 'HOUSE_SELF', service: 'purchaseBuilding', status: 'ACTIVE' },
  { method: 'POST', path: '/api/real-estate/upgrade', owner: 'BuildingRoutes', auth: 'HOUSE_SELF', service: 'upgradeBuilding', status: 'ACTIVE' },
  { method: 'POST', path: '/api/real-estate/{action}', owner: 'BuildingRoutes', auth: 'HOUSE_SELF', service: 'buildingService', status: 'ACTIVE' },
  { method: 'GET', path: '/api/market/instruments', owner: 'MarketRoutes', auth: 'PUBLIC', service: 'listInstruments', status: 'ACTIVE' },
  { method: 'GET', path: '/api/market/{instrument}/{view}', owner: 'MarketRoutes', auth: 'PUBLIC', service: 'marketReadModel', status: 'ACTIVE' },
  { method: 'GET', path: '/api/market/orders/my', owner: 'MarketRoutes', auth: 'HOUSE_SELF', service: 'listOrders', status: 'ACTIVE' },
  { method: 'POST', path: '/api/market/orders', owner: 'MarketRoutes', auth: 'HOUSE_SELF', service: 'submitOrder', status: 'ACTIVE' },
  { method: 'DELETE', path: '/api/market/orders/{id}', owner: 'MarketRoutes', auth: 'HOUSE_SELF', service: 'cancelOrder', status: 'ACTIVE' },
  { method: 'GET', path: '/api/finance/me', owner: 'FinanceRoutes', auth: 'HOUSE_SELF', service: 'getFinance', status: 'ACTIVE' },
  { method: 'GET', path: '/api/finance/{view}', owner: 'FinanceRoutes', auth: 'HOUSE_SELF', service: 'financeReadModel', status: 'ACTIVE' },
  { method: 'GET', path: '/api/cities', owner: 'InstitutionRoutes', auth: 'AUTHENTICATED', service: 'listCities', status: 'ACTIVE' },
  { method: 'POST', path: '/api/cities', owner: 'InstitutionRoutes', auth: 'HUMAN_SELF', service: 'createCity', status: 'ACTIVE' },
  { method: 'GET', path: '/api/corporations', owner: 'InstitutionRoutes', auth: 'AUTHENTICATED', service: 'listCorporations', status: 'ACTIVE' },
  { method: 'POST', path: '/api/corporations', owner: 'InstitutionRoutes', auth: 'HUMAN_SELF', service: 'createCorporation', status: 'ACTIVE' },
  { method: 'GET', path: '/api/institutions/{id}/budget/{view}', owner: 'InstitutionRoutes', auth: 'INSTITUTION_MEMBER', service: 'budgetReadModel', status: 'ACTIVE' },
  { method: 'POST', path: '/api/governance/proposals', owner: 'GovernanceRoutes', auth: 'HUMAN_SELF', service: 'createProposal', status: 'ACTIVE' },
  { method: 'POST', path: '/api/governance/rules', owner: 'GovernanceRoutes', auth: 'INSTITUTION_ROLE', service: 'amendRules', status: 'ACTIVE' },
  { method: 'GET', path: '/api/governance/{view}', owner: 'GovernanceRoutes', auth: 'AUTHENTICATED', service: 'governanceReadModel', status: 'ACTIVE' },
  { method: 'GET', path: '/api/research/{view}', owner: 'ResearchRoutes', auth: 'HOUSE_SELF', service: 'researchReadModel', status: 'ACTIVE' },
  { method: 'POST', path: '/api/research/{action}', owner: 'ResearchRoutes', auth: 'HOUSE_SELF', service: 'researchService', status: 'ACTIVE' },
  { method: 'GET', path: '/api/research/buildings', owner: 'ResearchRoutes', auth: 'HOUSE_SELF', service: 'listBuildingResearch', status: 'ACTIVE' },
  { method: 'POST', path: '/api/research/buildings', owner: 'ResearchRoutes', auth: 'HOUSE_SELF', service: 'startBuildingResearch', status: 'ACTIVE' },
  { method: 'POST', path: '/api/research/contribute', owner: 'ResearchRoutes', auth: 'HOUSE_SELF', service: 'contributeResearch', status: 'ACTIVE' },
  { method: 'GET', path: '/api/communities', owner: 'CommunityRoutes', auth: 'AUTHENTICATED', service: 'listCommunities', status: 'ACTIVE' },
  { method: 'POST', path: '/api/communities', owner: 'CommunityRoutes', auth: 'HUMAN_SELF', service: 'createCommunity', status: 'ACTIVE' },
  { method: 'GET', path: '/api/{readModel}', owner: 'ReadModelRoutes', auth: 'AUTHENTICATED', service: 'readModel', status: 'ACTIVE' },
];

export function routeKey(route: Pick<ApiRouteContract, 'method' | 'path'>): string {
  return `${route.method} ${route.path}`;
}

export function validateApiRegistry(routes: readonly ApiRouteContract[] = API_ROUTES): string[] {
  const failures: string[] = [];
  const keys = new Set<string>();
  for (const route of routes) {
    const key = routeKey(route);
    if (keys.has(key)) failures.push(`duplicate route ${key}`);
    keys.add(key);
    if (!API_ROUTE_OWNERS.includes(route.owner)) failures.push(`${key} has unknown owner ${route.owner}`);
    if (!API_AUTH_CLASSES.includes(route.auth)) failures.push(`${key} has unknown auth class ${route.auth}`);
    if (!route.service?.trim()) failures.push(`${key} has no service`);
    if (!route.status) failures.push(`${key} has no status`);
  }
  return failures;
}
