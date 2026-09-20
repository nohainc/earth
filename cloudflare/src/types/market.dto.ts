/** Canonical Market wire contracts. Monetary and quantity values are strings. */
export type MarketAssetSummary = {
  id: string;
  code: string | null;
  decimals: number | null;
};

export type MarketInstrumentSummary = {
  id: string;
  symbol: string;
  instrumentType: 'SPOT';
  baseAsset: MarketAssetSummary;
  quoteAsset: MarketAssetSummary;
  lotSize: string;
  priceTick: string;
  status: string;
  rulesVersion: string;
  genesisReferencePrice: string | null;
};

export type MarketOrder = {
  id: string;
  instrumentId: string | null;
  instrument: MarketInstrumentSummary | null;
  product: string | null;
  side: 'buy' | 'sell';
  status: string;
  quantity: string;
  filledQuantity: string;
  remainingQuantity: string;
  limitPrice: string;
  rulesVersion: string | null;
  sourceType: string;
  policyId: string | null;
  goodTilGameDay: number | null;
  createdAt: string | null;
  fillCount: number;
  grossValueUnits: string;
  grossValue: string;
  averageFillPrice: string | null;
  weightedAverageFillPrice: string | null;
  reservationStatus: string;
  initialEscrowUnits: string;
  initialEscrow: string;
  remainingReservationUnits: string;
  remainingReservation: string;
  cancellationRefundUnits: string;
  cancellationRefund: string;
  filledGrossValueUnits: string;
  filledGrossValue: string;
  totalFeePaidUnits: string;
  totalFeePaid: string;
  reservedEscrowUnits: string;
  reservedEscrow: string;
  feesPaidUnits: string;
  feesPaid: string;
  releasedEscrowUnits: string;
  releasedEscrow: string;
};

export type MarketQuote = {
  ok: boolean;
  instrument: MarketInstrumentSummary;
  side: 'buy' | 'sell';
  quantity: string;
  limitPrice: string;
  baseValueUnits: string;
  feeUnits: string;
  totalEscrowUnits: string;
  feeBps: string;
  availableQuantity: string | null;
  reservedQuantity: string | null;
  currentQuantity: string | null;
  nextClearing: { gameDay: number; gameMinute: number; intervalMinutes: number; schedule: string };
  generatedFrom: string;
};

export type MarketCandle = {
  periodId: string;
  open: string;
  high: string;
  low: string;
  close: string;
  volume: string;
  fillCount: number;
};

export type MarketBook = {
  instrument: MarketInstrumentSummary;
  bids: MarketOrder[];
  asks: MarketOrder[];
  state: Record<string, string | null>;
};

export type HouseCommodityPosition = {
  product: string;
  currentQuantity: string;
  reservedQuantity: string;
  availableQuantity: string;
};

export interface MarketTradeDTO { id: string; order_id?: string; commodity?: string; quantity?: string; price?: string; game_day?: number; }
