export interface BusinessDTO { id: string; owner_id?: string; name?: string; sector?: string; status?: string; }
export interface BusinessProfileDTO extends BusinessDTO { valuation?: number; treasury?: number; revenue?: number; profit?: number; }
