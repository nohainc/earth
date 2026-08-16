export type BusinessFinancialStatus = 'active' | 'distressed' | 'insolvent' | 'bankrupt';

export function classifyBusinessFinancialStatus(input: {
  profit: unknown;
  condition: unknown;
  currentStatus: string;
  sinceGameDay: number | null;
  gameDay: number;
}): BusinessFinancialStatus {
  if (input.currentStatus === 'bankrupt') return 'bankrupt';
  if (input.currentStatus === 'dissolved') return 'bankrupt';
  const profit = Number(input.profit);
  const condition = Number(input.condition);
  const unhealthy = !Number.isFinite(profit) || profit < 0 || !Number.isFinite(condition) || condition <= 0;
  if (!unhealthy) return 'active';
  const since = input.sinceGameDay ?? input.gameDay;
  return input.gameDay - since >= 7 ? 'insolvent' : 'distressed';
}
