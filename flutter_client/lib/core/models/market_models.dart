class MarketInstrumentSummary {
  final String id;
  final String symbol;
  final String instrumentType;
  final String? baseAssetCode;
  final String? quoteAssetCode;
  final String lotSize;
  final String priceTick;
  final String status;
  final String rulesVersion;
  final String? genesisReferencePrice;

  const MarketInstrumentSummary({
    required this.id,
    required this.symbol,
    required this.instrumentType,
    required this.baseAssetCode,
    required this.quoteAssetCode,
    required this.lotSize,
    required this.priceTick,
    required this.status,
    required this.rulesVersion,
    required this.genesisReferencePrice,
  });

  factory MarketInstrumentSummary.fromJson(Map<String, dynamic> json) {
    final base = json['baseAsset'] is Map
        ? Map<String, dynamic>.from(json['baseAsset'] as Map)
        : const <String, dynamic>{};
    final quote = json['quoteAsset'] is Map
        ? Map<String, dynamic>.from(json['quoteAsset'] as Map)
        : const <String, dynamic>{};
    return MarketInstrumentSummary(
      id: json['id']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      instrumentType: json['instrumentType']?.toString() ?? 'SPOT',
      baseAssetCode: base['code']?.toString(),
      quoteAssetCode: quote['code']?.toString(),
      lotSize: json['lotSize']?.toString() ?? '1',
      priceTick: json['priceTick']?.toString() ?? '0.01',
      status: json['status']?.toString() ?? 'UNKNOWN',
      rulesVersion: json['rulesVersion']?.toString() ?? '',
      genesisReferencePrice: json['genesisReferencePrice']?.toString(),
    );
  }
}

class MarketOrder {
  final String id;
  final String? instrumentId;
  final MarketInstrumentSummary? instrument;
  final String? product;
  final String side;
  final String status;
  final String quantity;
  final String filledQuantity;
  final String remainingQuantity;
  final String limitPrice;
  final String? rulesVersion;
  final String sourceType;
  final String? policyId;
  final int? goodTilGameDay;
  final String? createdAt;
  final int fillCount;
  final String grossValueUnits;
  final String grossValue;
  final String? averageFillPrice;
  final String? weightedAverageFillPrice;
  final String reservationStatus;
  final String initialEscrowUnits;
  final String initialEscrow;
  final String remainingReservationUnits;
  final String remainingReservation;
  final String cancellationRefundUnits;
  final String cancellationRefund;
  final String filledGrossValueUnits;
  final String filledGrossValue;
  final String totalFeePaidUnits;
  final String totalFeePaid;
  final String reservedEscrowUnits;
  final String reservedEscrow;
  final String feesPaidUnits;
  final String feesPaid;
  final String releasedEscrowUnits;
  final String releasedEscrow;

  const MarketOrder({
    required this.id,
    required this.instrumentId,
    required this.instrument,
    required this.product,
    required this.side,
    required this.status,
    required this.quantity,
    required this.filledQuantity,
    required this.remainingQuantity,
    required this.limitPrice,
    required this.rulesVersion,
    required this.sourceType,
    required this.policyId,
    required this.goodTilGameDay,
    required this.createdAt,
    required this.fillCount,
    required this.grossValueUnits,
    required this.grossValue,
    required this.averageFillPrice,
    required this.weightedAverageFillPrice,
    required this.reservationStatus,
    required this.initialEscrowUnits,
    required this.initialEscrow,
    required this.remainingReservationUnits,
    required this.remainingReservation,
    required this.cancellationRefundUnits,
    required this.cancellationRefund,
    required this.filledGrossValueUnits,
    required this.filledGrossValue,
    required this.totalFeePaidUnits,
    required this.totalFeePaid,
    required this.reservedEscrowUnits,
    required this.reservedEscrow,
    required this.feesPaidUnits,
    required this.feesPaid,
    required this.releasedEscrowUnits,
    required this.releasedEscrow,
  });

  factory MarketOrder.fromJson(Map<String, dynamic> json) => MarketOrder(
        id: json['id']?.toString() ?? '',
        instrumentId: json['instrumentId']?.toString(),
        instrument: json['instrument'] is Map
            ? MarketInstrumentSummary.fromJson(
                Map<String, dynamic>.from(json['instrument'] as Map))
            : null,
        product: json['product']?.toString(),
        side: json['side']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        quantity: json['quantity']?.toString() ?? '0',
        filledQuantity: json['filledQuantity']?.toString() ?? '0',
        remainingQuantity: json['remainingQuantity']?.toString() ?? '0',
        limitPrice: json['limitPrice']?.toString() ?? '0.00',
        rulesVersion: json['rulesVersion']?.toString(),
        sourceType: json['sourceType']?.toString() ?? 'MANUAL',
        policyId: json['policyId']?.toString(),
        goodTilGameDay: int.tryParse(json['goodTilGameDay']?.toString() ?? ''),
        createdAt: json['createdAt']?.toString(),
        fillCount: int.tryParse(json['fillCount']?.toString() ?? '') ?? 0,
        grossValueUnits: json['grossValueUnits']?.toString() ?? '0',
        grossValue: json['grossValue']?.toString() ?? '0.00',
        averageFillPrice: json['averageFillPrice']?.toString(),
        weightedAverageFillPrice:
            json['weightedAverageFillPrice']?.toString() ??
            json['averageFillPrice']?.toString(),
        reservationStatus: json['reservationStatus']?.toString() ?? 'NONE',
        initialEscrowUnits: json['initialEscrowUnits']?.toString() ?? '0',
        initialEscrow: json['initialEscrow']?.toString() ?? '0',
        remainingReservationUnits:
            json['remainingReservationUnits']?.toString() ??
            json['reservedEscrowUnits']?.toString() ??
            '0',
        remainingReservation: json['remainingReservation']?.toString() ??
            json['reservedEscrow']?.toString() ??
            '0',
        cancellationRefundUnits:
            json['cancellationRefundUnits']?.toString() ?? '0',
        cancellationRefund: json['cancellationRefund']?.toString() ?? '0',
        filledGrossValueUnits:
            json['filledGrossValueUnits']?.toString() ??
            json['grossValueUnits']?.toString() ??
            '0',
        filledGrossValue: json['filledGrossValue']?.toString() ??
            json['grossValue']?.toString() ??
            '0',
        totalFeePaidUnits: json['totalFeePaidUnits']?.toString() ??
            json['feesPaidUnits']?.toString() ??
            '0',
        totalFeePaid: json['totalFeePaid']?.toString() ??
            json['feesPaid']?.toString() ??
            '0',
        reservedEscrowUnits: json['reservedEscrowUnits']?.toString() ?? '0',
        reservedEscrow: json['reservedEscrow']?.toString() ?? '0',
        feesPaidUnits: json['feesPaidUnits']?.toString() ?? '0',
        feesPaid: json['feesPaid']?.toString() ?? '0.00',
        releasedEscrowUnits: json['releasedEscrowUnits']?.toString() ?? '0',
        releasedEscrow: json['releasedEscrow']?.toString() ?? '0',
      );
}

class MarketOrderPage {
  final List<MarketOrder> orders;
  final String? nextCursor;

  const MarketOrderPage({required this.orders, required this.nextCursor});
}

class MarketQuote {
  final bool ok;
  final MarketInstrumentSummary? instrument;
  final String side;
  final String quantity;
  final String limitPrice;
  final String baseValueUnits;
  final String feeUnits;
  final String totalEscrowUnits;
  final String feeBps;
  final String? availableQuantity;
  final String? reservedQuantity;
  final String? currentQuantity;
  final String? error;

  const MarketQuote({
    required this.ok,
    required this.instrument,
    required this.side,
    required this.quantity,
    required this.limitPrice,
    required this.baseValueUnits,
    required this.feeUnits,
    required this.totalEscrowUnits,
    required this.feeBps,
    required this.availableQuantity,
    required this.reservedQuantity,
    required this.currentQuantity,
    required this.error,
  });

  factory MarketQuote.fromJson(Map<String, dynamic> json) => MarketQuote(
        ok: json['ok'] == true,
        instrument: json['instrument'] is Map
            ? MarketInstrumentSummary.fromJson(
                Map<String, dynamic>.from(json['instrument'] as Map))
            : null,
        side: json['side']?.toString() ?? '',
        quantity: json['quantity']?.toString() ?? '0',
        limitPrice: json['limitPrice']?.toString() ?? '0.00',
        baseValueUnits: json['baseValueUnits']?.toString() ?? '0',
        feeUnits: json['feeUnits']?.toString() ?? '0',
        totalEscrowUnits: json['totalEscrowUnits']?.toString() ?? '0',
        feeBps: json['feeBps']?.toString() ?? '0',
        availableQuantity: json['availableQuantity']?.toString(),
        reservedQuantity: json['reservedQuantity']?.toString(),
        currentQuantity: json['currentQuantity']?.toString(),
        error: json['error']?.toString(),
      );

  factory MarketQuote.failure(String message) => MarketQuote(
        ok: false,
        instrument: null,
        side: '',
        quantity: '0',
        limitPrice: '0.00',
        baseValueUnits: '0',
        feeUnits: '0',
        totalEscrowUnits: '0',
        feeBps: '0',
        availableQuantity: null,
        reservedQuantity: null,
        currentQuantity: null,
        error: message,
      );
}

enum MarketCandleInterval {
  hourly,
  daily;

  String get wireName => name;
}

class MarketCandle {
  final String periodId;
  final String open;
  final String high;
  final String low;
  final String close;
  final String volume;
  final int fillCount;

  const MarketCandle({
    required this.periodId,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.fillCount,
  });

  factory MarketCandle.fromJson(Map<String, dynamic> json) => MarketCandle(
        periodId: json['periodId']?.toString() ?? '',
        open: json['open']?.toString() ?? '0.00',
        high: json['high']?.toString() ?? '0.00',
        low: json['low']?.toString() ?? '0.00',
        close: json['close']?.toString() ?? '0.00',
        volume: json['volume']?.toString() ?? '0',
        fillCount: int.tryParse(json['fillCount']?.toString() ?? '') ?? 0,
      );
}

class MarketBook {
  final MarketInstrumentSummary? instrument;
  final List<MarketOrder> bids;
  final List<MarketOrder> asks;

  const MarketBook({required this.instrument, required this.bids, required this.asks});

  factory MarketBook.fromJson(Map<String, dynamic> json) => MarketBook(
        instrument: json['instrument'] is Map
            ? MarketInstrumentSummary.fromJson(
                Map<String, dynamic>.from(json['instrument'] as Map))
            : null,
        bids: _orders(json['bids']),
        asks: _orders(json['asks']),
      );

  static List<MarketOrder> _orders(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((row) => MarketOrder.fromJson(Map<String, dynamic>.from(row))).toList()
      : const [];
}

class HouseCommodityPosition {
  final String product;
  final String currentQuantity;
  final String reservedQuantity;
  final String availableQuantity;

  const HouseCommodityPosition({
    required this.product,
    required this.currentQuantity,
    required this.reservedQuantity,
    required this.availableQuantity,
  });

  factory HouseCommodityPosition.fromJson(Map<String, dynamic> json) =>
      HouseCommodityPosition(
        product: json['product']?.toString() ?? '',
        currentQuantity: json['currentQuantity']?.toString() ?? '0',
        reservedQuantity: json['reservedQuantity']?.toString() ?? '0',
        availableQuantity: json['availableQuantity']?.toString() ?? '0',
      );
}
