export interface MarketOrderDTO { id: string; commodity?: string; side?: 'buy' | 'sell'; quantity?: number; price?: number; status?: string; }
export interface MarketTradeDTO { id: string; order_id?: string; commodity?: string; quantity?: number; price?: number; game_day?: number; }
