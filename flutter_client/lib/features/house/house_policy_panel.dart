import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
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
  final _spendCap = TextEditingController(text: '0');
  final _foodReserve = TextEditingController(text: '0');
  final _energyReserve = TextEditingController(text: '0');
  final _materialReserve = TextEditingController(text: '0');
  final _componentsReserve = TextEditingController(text: '0');
  final _computeReserve = TextEditingController(text: '0');
  final _foodPrice = TextEditingController(text: '0');
  final _energyPrice = TextEditingController(text: '0');
  final _materialPrice = TextEditingController(text: '0');
  final _componentsPrice = TextEditingController(text: '0');
  final _computePrice = TextEditingController(text: '0');
  final _foodSalePrice = TextEditingController(text: '0');
  final _energySalePrice = TextEditingController(text: '0');
  final _materialSalePrice = TextEditingController(text: '0');
  final _componentsSalePrice = TextEditingController(text: '0');
  final _computeSalePrice = TextEditingController(text: '0');
  final _foodQuantity = TextEditingController(text: '0');
  final _energyQuantity = TextEditingController(text: '0');
  final _materialQuantity = TextEditingController(text: '0');
  final _componentsQuantity = TextEditingController(text: '0');
  final _computeQuantity = TextEditingController(text: '0');
  String _operatingMode = 'BALANCED';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _policies = [];

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
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await const EarthApi().listHousePolicies();
      final raw = response['policies'];
      if (!mounted) return;
      setState(() {
        _policies = raw is List
            ? raw.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
            : [];
        _loading = false;
        _error = response['ok'] == false ? response['error']?.toString() : null;
      });
      _applyActivePolicies();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _applyActivePolicies() {
    Map<String, dynamic>? active(String type) {
      for (final policy in _policies) {
        if (policy['policy_type'] == type && policy['status'] == 'ACTIVE') return policy;
      }
      return null;
    }

    final operating = active('OPERATING');
    final reserve = active('INVENTORY_RESERVE');
    final standing = active('MARKET_STANDING');
    if (operating != null) _operatingMode = operating['operating_mode']?.toString() ?? 'BALANCED';
    final reserveMap = _map(reserve?['reserve_floor_units']);
    final inputPriceMap = _map(standing?['max_input_price_units']);
    final salePriceMap = _map(standing?['min_sale_price_units']);
    final quantityMap = _map(operating?['procurement_quantity_units']);
    _set(_foodReserve, reserveMap['FOOD']);
    _set(_energyReserve, reserveMap['ENERGY']);
    _set(_materialReserve, reserveMap['MATERIAL']);
    _set(_componentsReserve, reserveMap['COMPONENTS']);
    _set(_computeReserve, reserveMap['COMPUTE']);
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
    _set(_spendCap, standing?['daily_spend_cap_units']);
    if (mounted) setState(() {});
  }

  Map<String, String> _map(dynamic value) {
    if (value is! Map) return {};
    return value.map((key, value) => MapEntry(key.toString().toUpperCase(), value.toString()));
  }

  void _set(TextEditingController controller, dynamic value) {
    if (value != null) controller.text = value.toString();
  }

  String _value(TextEditingController controller) => controller.text.trim().isEmpty ? '0' : controller.text.trim();

  Map<String, String> _values(List<(String, String, TextEditingController)> fields) {
    final result = <String, String>{};
    for (final field in fields) {
      if (_value(field.$3) != '0') result[field.$1] = _value(field.$3);
    }
    return result;
  }

  Future<void> _save() async {
    final day = asInt(widget.state.clock['day']) ?? 0;
    if (day < 1) {
      setState(() => _error = 'The current game day is unavailable. Try again after the world state refreshes.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final reserve = _values([
        ('FOOD', 'Food', _foodReserve), ('ENERGY', 'Energy', _energyReserve),
        ('MATERIAL', 'Material', _materialReserve), ('COMPONENTS', 'Components', _componentsReserve),
        ('COMPUTE', 'Compute', _computeReserve),
      ]);
      final prices = _values([
        ('FOOD', 'Food', _foodPrice), ('ENERGY', 'Energy', _energyPrice),
        ('MATERIAL', 'Material', _materialPrice), ('COMPONENTS', 'Components', _componentsPrice),
        ('COMPUTE', 'Compute', _computePrice),
      ]);
      final salePrices = _values([
        ('FOOD', 'Food', _foodSalePrice), ('ENERGY', 'Energy', _energySalePrice),
        ('MATERIAL', 'Material', _materialSalePrice), ('COMPONENTS', 'Components', _componentsSalePrice),
        ('COMPUTE', 'Compute', _computeSalePrice),
      ]);
      final quantities = _values([
        ('FOOD', 'Food', _foodQuantity), ('ENERGY', 'Energy', _energyQuantity),
        ('MATERIAL', 'Material', _materialQuantity), ('COMPONENTS', 'Components', _componentsQuantity),
        ('COMPUTE', 'Compute', _computeQuantity),
      ]);
      for (final entry in [
        {'type': 'OPERATING', 'mode': _operatingMode, 'quantity': quantities},
        {'type': 'INVENTORY_RESERVE', 'reserve': reserve},
        {'type': 'MARKET_STANDING', 'prices': prices, 'salePrices': salePrices},
      ]) {
        final response = await const EarthApi().saveHousePolicy(
          policyType: entry['type'] as String,
          effectiveFromGameDay: day + 1,
          operatingMode: entry['mode'] as String? ?? 'BALANCED',
          dailySpendCapUnits: _value(_spendCap),
          reserveFloorUnits: entry['reserve'] is Map ? Map<String, String>.from(entry['reserve'] as Map) : reserve,
          maxInputPriceUnits: entry['prices'] is Map ? Map<String, String>.from(entry['prices'] as Map) : prices,
          minSalePriceUnits: entry['salePrices'] is Map ? Map<String, String>.from(entry['salePrices'] as Map) : salePrices,
          procurementQuantityUnits: entry['quantity'] is Map ? Map<String, String>.from(entry['quantity'] as Map) : quantities,
        );
        if (response['ok'] != true) throw StateError(response['error']?.toString() ?? 'Policy save failed');
      }
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('House policies saved for the next game day.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _policies.where((p) => p['status'] == 'ACTIVE').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPageCockpit(
          tag: 'HOUSE CONTROL',
          status: _loading ? 'LOADING' : '$activeCount ACTIVE POLICIES',
          statusColor: context.primaryColor,
          infoTitle: 'HOUSE POLICY & AUTOMATION',
          infoDescription: 'Policies are evaluated by the server during daily settlement. They protect reserves and place normal market actions automatically; exceptions remain visible for human decisions.',
          title: 'HOUSE POLICIES',
          subtitle: 'Set the operating rules that carry your House through the next game day',
        ),
        const SizedBox(height: 24),
        if (_error != null) _message(context, _error!, true),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          _section(context, 'OPERATING MODE', Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              value: _operatingMode,
              decoration: const InputDecoration(labelText: 'House operating mode'),
              items: const ['CONSERVATIVE', 'BALANCED', 'GROWTH', 'CUSTOM']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => _operatingMode = v ?? 'BALANCED'),
            )),
            const SizedBox(width: 16),
            Expanded(child: _field(_spendCap, 'Daily CREDIT spend cap')),
          ])),
          _section(context, 'INVENTORY RESERVES', Column(children: _resources.map((r) {
            final controller = _reserveController(r.$1);
            return _resourceRow(r.$2, controller, null);
          }).toList())),
          _section(context, 'STANDING PROCUREMENT', Column(children: _resources.map((r) {
            final controller = _priceController(r.$1);
            return _resourceRow('Maximum ${r.$2} input price', controller, '0 = no automatic buy');
          }).toList())),
          _section(context, 'PROCUREMENT QUANTITY', Column(children: _resources.map((r) {
            final controller = _quantityController(r.$1);
            return _resourceRow('${r.$2} units to buy', controller, '0 = no automatic buy');
          }).toList())),
          _section(context, 'STANDING SALES', Column(children: _resources.map((r) {
            final controller = _salePriceController(r.$1);
            return _resourceRow('Minimum ${r.$2} sale price', controller, '0 = no automatic sale');
          }).toList())),
          Align(alignment: Alignment.centerRight, child: EarthButton(
            label: _saving ? 'SAVING…' : 'SAVE POLICIES', icon: Icons.save_outlined,
            variant: EarthButtonVariant.primary, onPressed: _saving || widget.busy ? null : _save,
          )),
          const SizedBox(height: 10),
          Text('Changes become effective on game day ${asInt(widget.state.clock['day']) == null ? '—' : (asInt(widget.state.clock['day'])! + 1)}.', style: context.widgetFooterStyle),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: EarthSection(title: title, showSurface: true, child: child),
      );

  Widget _field(TextEditingController controller, String label) => TextField(
        controller: controller, keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );

  Widget _resourceRow(String label, TextEditingController controller, String? hint) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [Expanded(child: Text(label)), SizedBox(width: 180, child: _field(controller, hint ?? 'Minimum units'))]),
      );

  Widget _message(BuildContext context, String text, bool error) => Container(
        margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: (error ? context.errorColor : context.successColor).withValues(alpha: .1), border: Border.all(color: (error ? context.errorColor : context.successColor).withValues(alpha: .4)), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: context.widgetFooterStyle),
      );

  TextEditingController _reserveController(String key) => switch (key) {
        'FOOD' => _foodReserve, 'ENERGY' => _energyReserve, 'MATERIAL' => _materialReserve,
        'COMPONENTS' => _componentsReserve, _ => _computeReserve,
      };

  TextEditingController _priceController(String key) => switch (key) {
        'FOOD' => _foodPrice, 'ENERGY' => _energyPrice, 'MATERIAL' => _materialPrice,
        'COMPONENTS' => _componentsPrice, _ => _computePrice,
      };

  TextEditingController _salePriceController(String key) => switch (key) {
        'FOOD' => _foodSalePrice, 'ENERGY' => _energySalePrice, 'MATERIAL' => _materialSalePrice,
        'COMPONENTS' => _componentsSalePrice, _ => _computeSalePrice,
      };

  TextEditingController _quantityController(String key) => switch (key) {
        'FOOD' => _foodQuantity, 'ENERGY' => _energyQuantity, 'MATERIAL' => _materialQuantity,
        'COMPONENTS' => _componentsQuantity, _ => _computeQuantity,
      };
}
