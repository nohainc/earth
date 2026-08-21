const independentSectors = new Set(['maintenance', 'machines', 'components']);
const serviceSectors = new Set(['it-services', 'consulting', 'logistics', 'healthcare', 'education']);

export function businessSectorAccess(sector: string, hasCity: boolean, hasCorporation: boolean): { allowed: boolean; reason?: string } {
  if (!hasCity && !independentSectors.has(sector)) return { allowed: false, reason: 'This business sector requires an active city affiliation' };
  if (serviceSectors.has(sector) && !hasCorporation) return { allowed: false, reason: 'Specialized service businesses require corporation membership' };
  return { allowed: true };
}
