import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/consequence_preview_card.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showDecommissionDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.errorColor.withValues(alpha: 0.5)),
            ),
            title: Text('Recycle machine?', style: dialogContext.pageTitleStyle.copyWith(color: dialogContext.errorColor)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'This permanently decommissions the machine and salvages 25 Material and 5 Components.',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Recycle',
                variant: EarthButtonVariant.danger,
                onPressed: () async {
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .decommissionMachine(machineId, otp: otpCode));
                },
              ),
            ],
          ));
}

Future<void> showMachineUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Upgrade machine', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'Upgrade cost: 600 Credits and 20 Components. Capacity increases by +0.2 and installation reduces condition by 5%.',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Upgrade',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .upgradeMachine(machineId, otp: otpCode));
                },
              ),
            ],
          ));
}

Future<void> showMachineSaleDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final buyer = TextEditingController();
  final price = TextEditingController(text: '1200');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Sell machine', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: buyer,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Buyer Human ID'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price in Credits (CR)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Sell',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final targetBuyer = buyer.text.trim();
                  final parsedPrice = double.tryParse(price.text.trim());
                  if (targetBuyer.isEmpty || parsedPrice == null || parsedPrice <= 0) return;
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi().sellMachine(
                      machineId, targetBuyer, parsedPrice,
                      otp: otpCode));
                },
              ),
            ],
          ));
}

class CatalogMachineModel {
  final String type;
  final String name;
  final String category;
  final int tier;
  final String output;
  final String inputResource;
  final double inputPerOutput;
  final int credit;
  final int material;
  final double capacity;
  final String description;
  final String? requiredTech;

  const CatalogMachineModel({
    required this.type,
    required this.name,
    required this.category,
    required this.tier,
    required this.output,
    required this.inputResource,
    required this.inputPerOutput,
    required this.credit,
    required this.material,
    required this.capacity,
    required this.description,
    this.requiredTech,
  });

  static const List<CatalogMachineModel> defaultCatalog = [
    // --- ENERGY ---
    CatalogMachineModel(
      type: 'solar-photovoltaic-array',
      name: 'Solar Photovoltaic Array',
      category: 'energy',
      tier: 1,
      output: 'energy',
      inputResource: 'material',
      inputPerOutput: 0.05,
      credit: 3200,
      material: 50,
      capacity: 1.5,
      description: 'Terrestrial photovoltaic solar panel field converting planetary solar flux into clean electrical power.',
    ),
    CatalogMachineModel(
      type: 'geothermal-tap',
      name: 'Geothermal Deep Tap',
      category: 'energy',
      tier: 2,
      output: 'energy',
      inputResource: 'material',
      inputPerOutput: 0.10,
      credit: 6800,
      material: 110,
      capacity: 2.2,
      description: 'Pressurized deep-bore thermal exchange well tapping mantle heat for continuous high-stability base-load power.',
    ),
    CatalogMachineModel(
      type: 'fusion-tokamak-rig',
      name: 'Magnetic Fusion Dynamo',
      category: 'energy',
      tier: 3,
      output: 'energy',
      inputResource: 'components',
      inputPerOutput: 0.15,
      credit: 14500,
      material: 220,
      capacity: 3.5,
      description: 'Deuterium-tritium magnetic confinement tokamak generating massive high-density megawatt output.',
    ),
    CatalogMachineModel(
      type: 'orbital-solar-collector',
      name: 'Orbital Microwave Beam Array',
      category: 'energy',
      tier: 4,
      output: 'energy',
      inputResource: 'components',
      inputPerOutput: 0.20,
      credit: 32000,
      material: 450,
      capacity: 5.0,
      description: 'Geosynchronous orbital satellite swarm beaming constant unfiltered solar power via phased microwave rectennas.',
      requiredTech: 'Orbital Logistics',
    ),

    // --- FOOD ---
    CatalogMachineModel(
      type: 'hydroponic-tower',
      name: 'Vertical Hydroponic Tower',
      category: 'food',
      tier: 1,
      output: 'food',
      inputResource: 'energy',
      inputPerOutput: 0.30,
      credit: 3400,
      material: 55,
      capacity: 1.4,
      description: 'Automated vertical aeroponic cultivation tower growing nutrient-dense crops under optimized LED spectrums.',
    ),
    CatalogMachineModel(
      type: 'algae-photobioreactor',
      name: 'Micro-Algae Bio-Vat',
      category: 'food',
      tier: 2,
      output: 'food',
      inputResource: 'energy',
      inputPerOutput: 0.40,
      credit: 7200,
      material: 120,
      capacity: 2.3,
      description: 'High-density helical tube bio-reactor cultivating spirulina and lipid-rich biomass cultures with rapid doubling times.',
    ),
    CatalogMachineModel(
      type: 'cellular-meat-bioreactor',
      name: 'Cultured Protein Synthesizer',
      category: 'food',
      tier: 3,
      output: 'food',
      inputResource: 'energy',
      inputPerOutput: 0.50,
      credit: 15000,
      material: 240,
      capacity: 3.6,
      description: 'Sterile perfusion bioreactor cultivating pure cellular muscle and connective protein tissues without livestock overhead.',
    ),
    CatalogMachineModel(
      type: 'biosphere-dome',
      name: 'Automated Climate Biome',
      category: 'food',
      tier: 4,
      output: 'food',
      inputResource: 'energy',
      inputPerOutput: 0.60,
      credit: 34000,
      material: 480,
      capacity: 5.0,
      description: 'Pressurized geodesic planetary enclosure supporting polyculture self-regulating agricultural ecosystems.',
      requiredTech: 'Food Synthesis',
    ),

    // --- MINING / EXTRACTION ---
    CatalogMachineModel(
      type: 'sub-crustal-bore-drill',
      name: 'Deep Rotary Bore Drill',
      category: 'extraction',
      tier: 1,
      output: 'material',
      inputResource: 'energy',
      inputPerOutput: 0.40,
      credit: 3600,
      material: 60,
      capacity: 1.5,
      description: 'Diamond-tipped rotary drill shaft penetrating upper crustal strata for basic mineral ore extraction.',
    ),
    CatalogMachineModel(
      type: 'automated-strip-excavator',
      name: 'Continuous Bucket-Wheel Excavator',
      category: 'extraction',
      tier: 2,
      output: 'material',
      inputResource: 'energy',
      inputPerOutput: 0.50,
      credit: 7800,
      material: 135,
      capacity: 2.4,
      description: 'Giant multi-bucket continuous surface mining crawler excavating heavy tonnage of silicate and metallic ores.',
    ),
    CatalogMachineModel(
      type: 'plasma-quarry-harvester',
      name: 'Plasma Arc Mineral Slicer',
      category: 'extraction',
      tier: 3,
      output: 'material',
      inputResource: 'energy',
      inputPerOutput: 0.70,
      credit: 16500,
      material: 260,
      capacity: 3.8,
      description: 'High-temperature ionized plasma torch grid extracting hyper-concentrated rare-earth minerals.',
    ),
    CatalogMachineModel(
      type: 'asteroid-impact-smelter',
      name: 'Orbital Asteroid Snare & Smelter',
      category: 'extraction',
      tier: 4,
      output: 'material',
      inputResource: 'energy',
      inputPerOutput: 0.80,
      credit: 36000,
      material: 520,
      capacity: 5.2,
      description: 'Near-space tug and mass-driver platform capturing mineral-rich platinum-group metallic planetesimals.',
      requiredTech: 'Deep Crust Bore Extraction',
    ),

    // --- MANUFACTURING / COMPONENTS ---
    CatalogMachineModel(
      type: 'cnc-machining-cell',
      name: '5-Axis Precision CNC Mill',
      category: 'components',
      tier: 1,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 1.20,
      credit: 4000,
      material: 70,
      capacity: 1.4,
      description: 'High-speed automated milling and lathe center producing standardized mechanical linkages and gears.',
    ),
    CatalogMachineModel(
      type: 'robotic-assembly-line',
      name: 'Multi-Arm Autonomous Assembly Line',
      category: 'components',
      tier: 2,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 1.10,
      credit: 8400,
      material: 145,
      capacity: 2.2,
      description: 'Coordinated 6-DOF robotic manipulator conveyor building complex mechanical, electrical, and pneumatic subassemblies.',
    ),
    CatalogMachineModel(
      type: 'nano-alloy-foundry',
      name: 'Molecular Sintering & Alloy Forge',
      category: 'components',
      tier: 3,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 1.00,
      credit: 17500,
      material: 280,
      capacity: 3.6,
      description: 'Laser powder-bed fusion and atomic lattice foundry forging ultra-durable carbon-titanium composite components.',
    ),
    CatalogMachineModel(
      type: 'quantum-fabrication-rig',
      name: 'Sub-Atomic Lattice Fabricator',
      category: 'components',
      tier: 4,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 0.90,
      credit: 38000,
      material: 540,
      capacity: 5.0,
      description: 'Topologically protected quantum nanotech assembler synthesizing defect-free high-spec machinery components.',
      requiredTech: 'Automated Assembly',
    ),

    // --- COMPUTE & DATA ---
    CatalogMachineModel(
      type: 'server-cluster-rack',
      name: 'Edge Data Server Cluster',
      category: 'compute',
      tier: 1,
      output: 'compute',
      inputResource: 'energy',
      inputPerOutput: 0.50,
      credit: 4200,
      material: 75,
      capacity: 1.3,
      description: 'Liquid-cooled high-density blade servers providing distributed computational cycles for telemetry and research.',
    ),
    CatalogMachineModel(
      type: 'quantum-annealing-rig',
      name: 'Cryogenic Quantum Core',
      category: 'compute',
      tier: 2,
      output: 'compute',
      inputResource: 'energy',
      inputPerOutput: 0.70,
      credit: 9200,
      material: 160,
      capacity: 2.1,
      description: 'Superconducting qubit processor operating at milli-Kelvin temperatures to solve complex algorithmic optimizations.',
    ),
    CatalogMachineModel(
      type: 'neural-synapse-mainframe',
      name: 'Neuromorphic AI Matrix',
      category: 'compute',
      tier: 3,
      output: 'compute',
      inputResource: 'energy',
      inputPerOutput: 0.80,
      credit: 19000,
      material: 310,
      capacity: 3.5,
      description: 'Massive memristor-based bio-mimetic neural network processing vast real-time simulations and strategic analytics.',
    ),
    CatalogMachineModel(
      type: 'orbital-satellite-relay',
      name: 'Orbital Sensor Constellation',
      category: 'compute',
      tier: 4,
      output: 'compute',
      inputResource: 'energy',
      inputPerOutput: 1.00,
      credit: 40000,
      material: 580,
      capacity: 4.8,
      description: 'Planetary mesh satellite constellation providing uninterrupted deep telemetry, planetary imaging, and quantum communications.',
      requiredTech: 'Cryogenic Supercomputing',
    ),

    // --- SPECIALIZED ROBOTICS & HABITATS ---
    CatalogMachineModel(
      type: 'service-robot-hub',
      name: 'Autonomous Service Drone Hub',
      category: 'specialized',
      tier: 2,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 0.90,
      credit: 7500,
      material: 125,
      capacity: 1.8,
      description: 'Rapid-dispatch robotic service bay specializing in machine conditioning, preventative maintenance, and repair parts.',
    ),
    CatalogMachineModel(
      type: 'modular-housing-printer',
      name: '3D Habitat Constructor',
      category: 'specialized',
      tier: 2,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 1.40,
      credit: 8800,
      material: 150,
      capacity: 2.0,
      description: 'Large-scale gantry 3D printer extruding geopolymer structures, residential modules, and urban habitat infrastructure.',
    ),
    CatalogMachineModel(
      type: 'bio-synthetic-refinery',
      name: 'Enzymatic Biochemical Refinery',
      category: 'specialized',
      tier: 3,
      output: 'components',
      inputResource: 'food',
      inputPerOutput: 1.00,
      credit: 16000,
      material: 250,
      capacity: 3.2,
      description: 'Continuous catalytic bio-reactor converting raw organic carbohydrates into bio-plastics, lubricants, and polymers.',
    ),
    CatalogMachineModel(
      type: 'orbital-shipyard-cradle',
      name: 'Microgravity Heavy Drydock',
      category: 'specialized',
      tier: 4,
      output: 'components',
      inputResource: 'material',
      inputPerOutput: 1.20,
      credit: 45000,
      material: 650,
      capacity: 5.5,
      description: 'Zero-gravity orbital construction scaffolding capable of assembling super-heavy industrial machinery and space transports.',
      requiredTech: 'Orbital Logistics',
    ),
  ];
}

Future<void> showMachineAcquisitionDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  List<dynamic> productionCatalog,
) async {
  final seenTypes = <String>{};
  final catalogOptions = <Map<String, dynamic>>[];
  for (final sector in productionCatalog.whereType<Map>()) {
    final machineTypes = sector['machineTypes'] is List ? sector['machineTypes'] as List : const [];
    final catalogList = sector['catalog'] is List ? sector['catalog'] as List : const [];
    for (int i = 0; i < catalogList.length; i++) {
      final item = catalogList[i];
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final inferredType = (map['type'] ?? map['id'] ?? (i < machineTypes.length ? machineTypes[i] : null))?.toString().trim();
        if (inferredType != null && inferredType.isNotEmpty && !seenTypes.contains(inferredType)) {
          seenTypes.add(inferredType);
          map['type'] = inferredType;
          catalogOptions.add(map);
        }
      }
    }
    if (catalogList.isEmpty) {
      for (final type in machineTypes) {
        final machineType = type.toString().trim();
        final acquisition = sector['acquisition'] is Map ? Map<String, dynamic>.from(sector['acquisition'] as Map) : const <String, dynamic>{};
        if (acquisition.isNotEmpty && machineType.isNotEmpty && !seenTypes.contains(machineType)) {
          seenTypes.add(machineType);
          catalogOptions.add({'type': machineType, 'output': sector['output']?.toString() ?? 'resource', ...acquisition});
        }
      }
    }
  }

  final options = catalogOptions.isNotEmpty
      ? catalogOptions
      : CatalogMachineModel.defaultCatalog.map((m) => {
            'type': m.type,
            'name': m.name,
            'category': m.category,
            'tier': m.tier,
            'output': m.output,
            'inputResource': m.inputResource,
            'inputPerOutput': m.inputPerOutput,
            'credit': m.credit,
            'material': m.material,
            'capacity': m.capacity,
            'description': m.description,
            if (m.requiredTech != null) 'requiredTech': m.requiredTech,
          }).toList();

  String selectedCategory = 'all';
  String selectedType = options.first['type'].toString();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final rawFiltered = selectedCategory == 'all'
            ? options
            : options.where((opt) => (opt['category']?.toString() ?? 'energy') == selectedCategory).toList();

        // Guaranteed unique types in filteredOptions
        final filteredSeen = <String>{};
        final filteredOptions = <Map<String, dynamic>>[];
        for (final opt in rawFiltered) {
          final t = opt['type']?.toString().trim() ?? '';
          if (t.isNotEmpty && !filteredSeen.contains(t)) {
            filteredSeen.add(t);
            filteredOptions.add(opt);
          }
        }

        if (filteredOptions.isNotEmpty && !filteredOptions.any((opt) => opt['type'].toString() == selectedType)) {
          selectedType = filteredOptions.first['type'].toString();
        }

        final selectedOption = filteredOptions.isNotEmpty
            ? filteredOptions.firstWhere(
                (option) => option['type'].toString() == selectedType,
                orElse: () => filteredOptions.first,
              )
            : options.first;

        final machineName = (selectedOption['name'] ?? selectedOption['type'])?.toString() ?? selectedType;
        final outputResource = (selectedOption['output'] ?? 'resource').toString().toUpperCase();
        final inputResource = (selectedOption['inputResource'] ?? 'energy').toString().toUpperCase();
        final capacity = (selectedOption['capacity'] ?? 1.5).toString();
        final creditCost = asDoubleOr(selectedOption['credit'], 3600.0);
        final materialCost = asIntOr(selectedOption['material'], 60);
        final tier = asIntOr(selectedOption['tier'], 1);
        final description = selectedOption['description']?.toString() ?? '';
        final requiredTech = selectedOption['requiredTech']?.toString();

        return AlertDialog(
          backgroundColor: dialogContext.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
            side: BorderSide(color: dialogContext.subtleBorderColor),
          ),
          title: Row(
            children: [
              const Icon(Icons.precision_manufacturing_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Acquire Machine', style: dialogContext.pageTitleStyle),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a production or extraction asset from the catalog to expand planetary yield.',
                    style: dialogContext.widgetFooterStyle,
                  ),
                  const SizedBox(height: 12),
                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final cat in [
                          {'id': 'all', 'label': 'ALL (24)'},
                          {'id': 'energy', 'label': '⚡ ENERGY'},
                          {'id': 'food', 'label': '🌾 FOOD'},
                          {'id': 'extraction', 'label': '⛏️ MINING'},
                          {'id': 'components', 'label': '⚙️ FABRICATION'},
                          {'id': 'compute', 'label': '📡 COMPUTE'},
                          {'id': 'specialized', 'label': '🤖 SPECIALIZED'},
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(cat['label']!),
                              selected: selectedCategory == cat['id'],
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    selectedCategory = cat['id']!;
                                  });
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: filteredOptions.any((opt) => opt['type'].toString() == selectedType)
                        ? selectedType
                        : (filteredOptions.isNotEmpty ? filteredOptions.first['type'].toString() : null),
                    items: filteredOptions.map((option) {
                      final optType = option['type'].toString();
                      final optName = (option['name'] ?? optType.replaceAll('-', ' ')).toString().toUpperCase();
                      final optCredit = option['credit'] ?? 0;
                      final optMat = option['material'] ?? 0;
                      return DropdownMenuItem<String>(
                        value: optType,
                        child: Text(
                          '$optName · $optCredit CR + $optMat Mat',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dialogContext.surfaceColor.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: dialogContext.subtleBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            EarthBadge(
                              label: 'TIER $tier ASSET',
                              variant: tier >= 4
                                  ? EarthBadgeVariant.danger
                                  : tier >= 3
                                      ? EarthBadgeVariant.primary
                                      : EarthBadgeVariant.neutral,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Flow: $inputResource → $outputResource · ${capacity}x Base Capacity',
                                style: dialogContext.widgetFooterStyle.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(description, style: dialogContext.captionStyle),
                        ],
                        if (requiredTech != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.science_outlined, size: 14, color: Colors.cyanAccent),
                              const SizedBox(width: 4),
                              Text(
                                'Recommended Research: $requiredTech',
                                style: dialogContext.captionStyle.copyWith(color: Colors.cyanAccent),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConsequencePreviewCard(
                    consequence: DecisionConsequence.machineAcquisition(
                      machineName: machineName.toUpperCase(),
                      costCredits: creditCost,
                      outputYield: '$outputResource yield ($capacity x scaling)',
                      businessName: 'Personal Inventory & Enterprises',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            EarthButton(
              label: 'Cancel',
              variant: EarthButtonVariant.neutral,
              onPressed: () => Navigator.pop(dialogContext),
            ),
            EarthButton(
              label: 'Acquire',
              variant: EarthButtonVariant.primary,
              onPressed: () async {
                Navigator.pop(dialogContext);
                await action(() => const EarthApi().acquireMachine(selectedType));
              },
            ),
          ],
        );
      },
    ),
  );
}
