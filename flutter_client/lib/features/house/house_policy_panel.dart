import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class HousePolicyPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const HousePolicyPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<HousePolicyPanel> createState() => _HousePolicyPanelState();
}

class _HousePolicyPanelState extends State<HousePolicyPanel> {
  final _spendCap = TextEditingController();
  final _foodReserve = TextEditingController();
  final _energyReserve = TextEditingController();
  final _materialReserve = TextEditingController();
  final _componentsReserve = TextEditingController();
  final _computeReserve = TextEditingController();
  final _foodSellAbove = TextEditingController();
  final _energySellAbove = TextEditingController();
  final _materialSellAbove = TextEditingController();
  final _componentsSellAbove = TextEditingController();
  final _computeSellAbove = TextEditingController();
  final _foodPrice = TextEditingController();
  final _energyPrice = TextEditingController();
  final _materialPrice = TextEditingController();
  final _componentsPrice = TextEditingController();
  final _computePrice = TextEditingController();
  final _foodSalePrice = TextEditingController();
  final _energySalePrice = TextEditingController();
  final _materialSalePrice = TextEditingController();
  final _componentsSalePrice = TextEditingController();
  final _computeSalePrice = TextEditingController();
  final _foodQuantity = TextEditingController();
  final _energyQuantity = TextEditingController();
  final _materialQuantity = TextEditingController();
  final _componentsQuantity = TextEditingController();
  final _computeQuantity = TextEditingController();
  final _foodMaxSell = TextEditingController();
  final _energyMaxSell = TextEditingController();
  final _materialMaxSell = TextEditingController();
  final _componentsMaxSell = TextEditingController();
  final _computeMaxSell = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _automationEnabled = true;
  String? _error;
  List<Map<String, dynamic>> _policies = [];
  List<Map<String, dynamic>> _scheduledPolicies = [];
  List<Map<String, dynamic>> _executionSummaries = [];
  Map<String, String> _currentInventory = {};
  Map<String, String> _referencePrices = {};

  final _resources = const [
    ('FOOD', 'Food'),
    ('ENERGY', 'Energy'),
    ('MATERIAL', 'Material'),
    ('COMPONENTS', 'Components'),
    ('COMPUTE', 'Compute'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _spendCap,
      _foodReserve,
      _energyReserve,
      _materialReserve,
      _componentsReserve,
      _computeReserve,
      _foodSellAbove, _energySellAbove, _materialSellAbove, _componentsSellAbove, _computeSellAbove,
      _foodPrice,
      _energyPrice,
      _materialPrice,
      _componentsPrice,
      _computePrice,
      _foodSalePrice,
      _energySalePrice,
      _materialSalePrice,
      _componentsSalePrice,
      _computeSalePrice,
      _foodQuantity,
      _energyQuantity,
      _materialQuantity,
      _componentsQuantity,
      _computeQuantity,
      _foodMaxSell, _energyMaxSell, _materialMaxSell, _componentsMaxSell, _computeMaxSell,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await const EarthApi().getHouseAutomation();
      final raw = response['current'];
      final scheduledRaw = response['scheduled'];
      if (!mounted) return;
      setState(() {
        _policies = raw is Map
            ? [Map<String, dynamic>.from(raw)]
            : [];
        _scheduledPolicies = scheduledRaw is Map
            ? [Map<String, dynamic>.from(scheduledRaw)]
            : [];
        final summaries = response['recentExecutionSummaries'];
        _executionSummaries = summaries is List
            ? summaries.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
            : [];
        final inventory = response['currentInventory'];
        _currentInventory = _map(inventory);
        final prices = response['referenceMarketPrices'];
        _referencePrices = prices is List
            ? {
                for (final item in prices.whereType<Map>())
                  item['product']?.toString().toUpperCase() ?? '':
                      item['referencePrice']?.toString() ?? 'UNAVAILABLE',
              }
            : {};
        _loading = false;
        _error = response['ok'] == false ? response['error']?.toString() : null;
      });
      _applyActivePolicies();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _applyActivePolicies() {
    final config = _policies.isEmpty ? null : _policies.first;
    if (config != null) {
      _automationEnabled = config['enabled'] == true;
    }
    final reserveMap = _map(config?['minimumReserve']);
    final sellAboveMap = _map(config?['sellAbove']);
    final inputPriceMap = _map(config?['maxInputPrice']);
    final salePriceMap = _map(config?['minSalePrice']);
    final quantityMap = _map(config?['maxBuyQuantity']);
    final maxSellMap = _map(config?['maxSellQuantity']);
    _set(_foodReserve, reserveMap['FOOD']);
    _set(_energyReserve, reserveMap['ENERGY']);
    _set(_materialReserve, reserveMap['MATERIAL']);
    _set(_componentsReserve, reserveMap['COMPONENTS']);
    _set(_computeReserve, reserveMap['COMPUTE']);
    _set(_foodSellAbove, sellAboveMap['FOOD']);
    _set(_energySellAbove, sellAboveMap['ENERGY']);
    _set(_materialSellAbove, sellAboveMap['MATERIAL']);
    _set(_componentsSellAbove, sellAboveMap['COMPONENTS']);
    _set(_computeSellAbove, sellAboveMap['COMPUTE']);
    _set(_foodPrice, inputPriceMap['FOOD']);
    _set(_energyPrice, inputPriceMap['ENERGY']);
    _set(_materialPrice, inputPriceMap['MATERIAL']);
    _set(_componentsPrice, inputPriceMap['COMPONENTS']);
    _set(_computePrice, inputPriceMap['COMPUTE']);
    _set(_foodSalePrice, salePriceMap['FOOD']);
    _set(_energySalePrice, salePriceMap['ENERGY']);
    _set(_materialSalePrice, salePriceMap['MATERIAL']);
    _set(_componentsSalePrice, salePriceMap['COMPONENTS']);
    _set(_computeSalePrice, salePriceMap['COMPUTE']);
    _set(_foodQuantity, quantityMap['FOOD']);
    _set(_energyQuantity, quantityMap['ENERGY']);
    _set(_materialQuantity, quantityMap['MATERIAL']);
    _set(_componentsQuantity, quantityMap['COMPONENTS']);
    _set(_computeQuantity, quantityMap['COMPUTE']);
    _set(_foodMaxSell, maxSellMap['FOOD']);
    _set(_energyMaxSell, maxSellMap['ENERGY']);
    _set(_materialMaxSell, maxSellMap['MATERIAL']);
    _set(_componentsMaxSell, maxSellMap['COMPONENTS']);
    _set(_computeMaxSell, maxSellMap['COMPUTE']);
    _set(_spendCap, config?['dailySpendCap']);
    if (mounted) setState(() {});
  }

  Map<String, String> _map(dynamic value) {
    if (value is! Map) return {};
    return value.map((key, value) =>
        MapEntry(key.toString().toUpperCase(), value.toString()));
  }

  void _set(TextEditingController controller, dynamic value) {
    if (value != null) controller.text = value.toString();
  }

  String? _value(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Map<String, String> _values(
      List<(String, String, TextEditingController)> fields) {
    final result = <String, String>{};
    for (final field in fields) {
      final value = _value(field.$3);
      if (value != null) result[field.$1] = value;
    }
    return result;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final reserve = _values([
        ('FOOD', 'Food', _foodReserve),
        ('ENERGY', 'Energy', _energyReserve),
        ('MATERIAL', 'Material', _materialReserve),
        ('COMPONENTS', 'Components', _componentsReserve),
        ('COMPUTE', 'Compute', _computeReserve),
      ]);
      final prices = _values([
        ('FOOD', 'Food', _foodPrice),
        ('ENERGY', 'Energy', _energyPrice),
        ('MATERIAL', 'Material', _materialPrice),
        ('COMPONENTS', 'Components', _componentsPrice),
        ('COMPUTE', 'Compute', _computePrice),
      ]);
      final salePrices = _values([
        ('FOOD', 'Food', _foodSalePrice),
        ('ENERGY', 'Energy', _energySalePrice),
        ('MATERIAL', 'Material', _materialSalePrice),
        ('COMPONENTS', 'Components', _componentsSalePrice),
        ('COMPUTE', 'Compute', _computeSalePrice),
      ]);
      final quantities = _values([
        ('FOOD', 'Food', _foodQuantity),
        ('ENERGY', 'Energy', _energyQuantity),
        ('MATERIAL', 'Material', _materialQuantity),
        ('COMPONENTS', 'Components', _componentsQuantity),
        ('COMPUTE', 'Compute', _computeQuantity),
      ]);
      final sellAbove = _values([
        ('FOOD', 'Food', _foodSellAbove), ('ENERGY', 'Energy', _energySellAbove),
        ('MATERIAL', 'Material', _materialSellAbove), ('COMPONENTS', 'Components', _componentsSellAbove), ('COMPUTE', 'Compute', _computeSellAbove),
      ]);
      final maxSell = _values([
        ('FOOD', 'Food', _foodMaxSell), ('ENERGY', 'Energy', _energyMaxSell),
        ('MATERIAL', 'Material', _materialMaxSell), ('COMPONENTS', 'Components', _componentsMaxSell), ('COMPUTE', 'Compute', _computeMaxSell),
      ]);
      final preview = await const EarthApi().previewHouseAutomation(
        enabled: _automationEnabled,
        dailySpendCap: _value(_spendCap) ?? '0',
        minimumReserve: reserve,
        sellAbove: sellAbove,
        maxInputPrice: prices,
        minSalePrice: salePrices,
        maxBuyQuantity: quantities,
        maxSellQuantity: maxSell,
      );
      if (preview['ok'] != true) {
        throw StateError(preview['error']?.toString() ?? 'Automation preview failed');
      }
      final blockers = preview['blockers'] is List ? preview['blockers'] as List : const [];
      if (blockers.isNotEmpty) {
        throw StateError(blockers.map((item) => item is Map ? item['reason'] : item).join('; '));
      }
      if (!mounted || !await _confirmPreview(preview)) return;
      final response = await const EarthApi().saveHouseAutomation(
        enabled: _automationEnabled,
        dailySpendCap: _value(_spendCap) ?? '0',
        minimumReserve: reserve,
        sellAbove: sellAbove,
        maxInputPrice: prices,
        minSalePrice: salePrices,
        maxBuyQuantity: quantities,
        maxSellQuantity: maxSell,
      );
      if (response['ok'] != true) {
        throw StateError(
            response['error']?.toString() ?? 'Automation save failed');
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('House policies saved for the next game day.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmPreview(Map<String, dynamic> preview) async {
    final actions = preview['actions'] is List ? preview['actions'] as List : const [];
    final reservation = preview['maximumCreditReservation']?.toString() ?? '0.00';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('CONFIRM AUTOMATION'),
            content: SizedBox(
              width: 440,
              child: actions.isEmpty
                  ? const Text('No automated market action is currently required.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preview reservation: $reservation C'),
                        const SizedBox(height: 12),
                        ...actions.map((action) => Text(
                              '${action['actionType']} ${action['quantity']} ${action['product']} @ ${action['limitPrice']} C',
                            )),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SAVE CONFIGURATION')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final currentPolicies = _policies.where((p) => p['status'] == 'ACTIVE');
    final scheduled = _scheduledPolicies.where((p) => p['status'] == 'ACTIVE');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPageCockpit(
          tag: 'HOUSE CONTROL',
          status: _loading
              ? 'LOADING'
              : currentPolicies.isEmpty || !_automationEnabled
                  ? 'AUTOMATION OFF'
                  : 'AUTOMATION ON',
          statusColor: context.primaryColor,
          infoTitle: 'HOUSE POLICY & AUTOMATION',
          infoDescription:
              'The server evaluates the active configuration once after each closed game day has been finalized. It may submit market orders for the next market cycle; exceptions remain visible for human decisions.',
          title: 'HOUSE AUTOMATION',
          subtitle:
              'Server-evaluated resource controls after daily settlement finalization',
        ),
        const SizedBox(height: 24),
        if (_error != null) _message(context, _error!, true),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          _section(context, 'AUTOMATION STATE', SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automation enabled'),
              subtitle: const Text('Disabling takes effect on the server-resolved scheduled day.'),
              value: _automationEnabled,
              onChanged: _saving ? null : (value) => setState(() => _automationEnabled = value))),
          if (_executionSummaries.isNotEmpty)
            _section(context, 'RECENT EXECUTION', Column(
              children: _executionSummaries.map(_executionSummary).toList(),
            )),
          _section(context, 'SPENDING CONTROL',
              _field(_spendCap, 'Daily CREDIT spend cap')),
          _section(context, 'RESOURCE CONTROLS', Column(
            children: _resources.map((resource) => _resourceCard(resource.$1, resource.$2)).toList(),
          )),
          Align(
              alignment: Alignment.centerRight,
              child: EarthButton(
                label: _saving ? 'SAVING…' : 'SAVE POLICIES',
                icon: Icons.save_outlined,
                variant: EarthButtonVariant.primary,
                onPressed: _saving || widget.busy ? null : _save,
              )),
          const SizedBox(height: 10),
          Text(
              'The saved configuration becomes effective on the next valid game day after settlement finalization. ${scheduled.isNotEmpty ? 'A scheduled configuration is set for game day ${scheduled.first['effectiveFromGameDay']}.' : 'No scheduled replacement is currently queued.'}',
              style: context.widgetFooterStyle),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: EarthSection(title: title, showSurface: true, child: child),
      );

  Widget _resourceCard(String code, String label) {
    final current = _policies.isEmpty ? null : _policies.first;
    final scheduled = _scheduledPolicies.isEmpty ? null : _scheduledPolicies.first;
    final scheduledDay = scheduled?['effectiveFromGameDay']?.toString();
    final differences = _resourceDifferences(code, current, scheduled);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .55),
        border: Border.all(color: context.mutedColor.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label.toUpperCase(), style: context.widgetTitleStyle)),
              Text('INVENTORY ${_currentInventory[code] ?? 'UNAVAILABLE'}', style: context.widgetFooterStyle),
            ],
          ),
          const SizedBox(height: 4),
          Text('Reference / last clearing price: ${_referencePrices[code] ?? 'UNAVAILABLE'} C per unit', style: context.widgetFooterStyle),
          if (scheduled != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                differences.isEmpty
                    ? 'No ${label.toLowerCase()} changes scheduled.'
                    : 'SCHEDULED DIFFERENCE · effective game day $scheduledDay',
                style: context.widgetFooterStyle.copyWith(color: differences.isEmpty ? context.mutedColor : context.primaryColor),
              ),
            ),
          if (differences.isNotEmpty)
            ...differences.map((difference) => Text(difference, style: context.widgetFooterStyle)),
          const Divider(height: 20),
          Text('BUY BAND', style: context.widgetFooterStyle.copyWith(color: context.primaryColor)),
          _resourceRow('Minimum reserve', _reserveController(code), 'Blank = no automatic buy target'),
          _resourceRow('Maximum input price', _priceController(code), 'Blank = buying disabled'),
          _resourceRow('Maximum buy quantity', _quantityController(code), 'Blank = full reserve shortfall'),
          const SizedBox(height: 4),
          Text('SELL BAND', style: context.widgetFooterStyle.copyWith(color: context.primaryColor)),
          _resourceRow('Sell above', _sellAboveController(code), 'Blank = no automatic selling'),
          _resourceRow('Minimum sale price', _salePriceController(code), 'Blank = selling disabled'),
          _resourceRow('Maximum sell quantity', _maxSellController(code), 'Blank = all available excess'),
        ],
      ),
    );
  }

  List<String> _resourceDifferences(String code, Map<String, dynamic>? current, Map<String, dynamic>? scheduled) {
    if (scheduled == null) return [];
    const fields = <(String, String)>[
      ('minimumReserve', 'Minimum reserve'),
      ('maxInputPrice', 'Maximum input price'),
      ('maxBuyQuantity', 'Maximum buy quantity'),
      ('sellAbove', 'Sell above'),
      ('minSalePrice', 'Minimum sale price'),
      ('maxSellQuantity', 'Maximum sell quantity'),
    ];
    final differences = <String>[];
    for (final field in fields) {
      final activeValue = _policyMapValue(current, field.$1, code);
      final scheduledValue = _policyMapValue(scheduled, field.$1, code);
      if (activeValue != scheduledValue) {
        differences.add('${field.$2}: ${activeValue ?? '—'} → ${scheduledValue ?? '—'}');
      }
    }
    return differences;
  }

  String? _policyMapValue(Map<String, dynamic>? policy, String field, String code) {
    final value = policy?[field];
    if (value is! Map) return null;
    final result = value[code] ?? value[code.toUpperCase()] ?? value[code.toLowerCase()];
    return result?.toString();
  }

  Widget _executionSummary(Map<String, dynamic> summary) {
    final day = summary['gameDay']?.toString() ?? '?';
    final counts = <String, dynamic>{
      'NO ACTION': summary['noActionCount'],
      'ORDER PLACED': summary['orderPlacedCount'],
      'PARTIALLY FILLED': summary['partiallyFilledCount'],
      'FILLED': summary['filledCount'],
      'EXPIRED': summary['expiredCount'],
      'SKIPPED': summary['skippedCount'],
      'FAILED': summary['failedCount'],
    };
    final visible = counts.entries.where((entry) => (entry.value is num ? entry.value : int.tryParse('${entry.value}') ?? 0) > 0);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Text('DAY $day', style: context.widgetTitleStyle),
            ...visible.map((entry) => Chip(
              label: Text('${entry.key} ${entry.value}'),
              visualDensity: VisualDensity.compact,
            )),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );

  Widget _resourceRow(
          String label, TextEditingController controller, String? hint) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(label)),
          SizedBox(
              width: 180, child: _field(controller, hint ?? 'Minimum units'))
        ]),
      );

  Widget _message(BuildContext context, String text, bool error) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: (error ? context.errorColor : context.successColor)
                .withValues(alpha: .1),
            border: Border.all(
                color: (error ? context.errorColor : context.successColor)
                    .withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: context.widgetFooterStyle),
      );

  TextEditingController _reserveController(String key) => switch (key) {
        'FOOD' => _foodReserve,
        'ENERGY' => _energyReserve,
        'MATERIAL' => _materialReserve,
        'COMPONENTS' => _componentsReserve,
        _ => _computeReserve,
      };

  TextEditingController _priceController(String key) => switch (key) {
        'FOOD' => _foodPrice,
        'ENERGY' => _energyPrice,
        'MATERIAL' => _materialPrice,
        'COMPONENTS' => _componentsPrice,
        _ => _computePrice,
      };

  TextEditingController _salePriceController(String key) => switch (key) {
        'FOOD' => _foodSalePrice,
        'ENERGY' => _energySalePrice,
        'MATERIAL' => _materialSalePrice,
        'COMPONENTS' => _componentsSalePrice,
        _ => _computeSalePrice,
      };

  TextEditingController _quantityController(String key) => switch (key) {
        'FOOD' => _foodQuantity,
        'ENERGY' => _energyQuantity,
        'MATERIAL' => _materialQuantity,
        'COMPONENTS' => _componentsQuantity,
        _ => _computeQuantity,
      };

  TextEditingController _sellAboveController(String key) => switch (key) {
        'FOOD' => _foodSellAbove,
        'ENERGY' => _energySellAbove,
        'MATERIAL' => _materialSellAbove,
        'COMPONENTS' => _componentsSellAbove,
        _ => _computeSellAbove,
      };

  TextEditingController _maxSellController(String key) => switch (key) {
        'FOOD' => _foodMaxSell,
        'ENERGY' => _energyMaxSell,
        'MATERIAL' => _materialMaxSell,
        'COMPONENTS' => _componentsMaxSell,
        _ => _computeMaxSell,
      };
}
