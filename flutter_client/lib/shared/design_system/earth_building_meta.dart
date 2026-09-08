class EarthBuildingMeta {
  static const Map<String, String> _economicPurposes = {
    'restaurant': 'Liquid Credit Profit & Resident Consumption',
    'retail-store': 'Retail Sales & Domestic Equipment Turnover',
    'commercial-mall': 'Multi-Tenant Commercial Hub & Shareholder Dividends',
    'corporate-plaza': 'Multi-Tenant Commercial Hub & Shareholder Dividends',
    'residential-habitation-block':
        'High-Density Resident Habitation & Citizen Domicile',
    'private-estate-plot':
        'Residential Domicile, Life Sustenance & 3D Vertical Estate Capacity',
    'logistics-warehouse': 'Supply Chain Routing & Distribution Cost Reduction',
    'fabrication-plant':
        'Precision Component Fabrication & Machine Spare Parts',
    'robotics-facility':
        'Precision Component Fabrication & Machine Spare Parts',
    'fabrication-laboratory':
        'Advanced Machine Component & High-Tech Assembly',
    'chemical-foundry':
        'Structural Material Synthesis & Construction Feedstock',
    'materials-refinery':
        'Structural Material Synthesis & Construction Feedstock',
    'recycling-cooperative':
        'Material Reclamation & Component Recovery from Waste',
    'solar-array-complex': 'Clean Photovoltaic Energy & Grid Baseline',
    'solar-array': 'Clean Photovoltaic Energy & Grid Baseline',
    'battery-storage-array': 'Surplus Energy Reserve & Grid Stability Buffer',
    'geothermal-grid': 'Municipal Baseload Energy & Citizen UBI Funding',
    'urban-climate-grid': 'District Thermal Regulation & Climate Mitigation',
    'municipal-power-exchange':
        'Regional Power Distribution & Public Grid Revenue',
    'vertical-farm': 'Fresh Protein, Organic Nutrition & Urban Food Reserves',
    'biotech-greenhouse':
        'High-Yield Organic Biomass & Pharmaceutical Feedstock',
    'public-food-reserve':
        'Strategic Municipal Food Security & Emergency Nutrition',
    'server-farm': 'High-Throughput Quantum & Neural Compute Generation',
    'quantum-datacenter':
        'High-Throughput Quantum & Neural Compute Generation',
    'data-services-studio':
        'Commercial Data Telemetry & Analytics Compute Services',
    'civic-data-network':
        'Municipal High-Speed Data & Administration Efficiency',
    'medical-clinic': 'Urban Healthcare, Longevity & Disease Protection',
    'medical-center': 'Urban Healthcare, Longevity & Disease Protection',
    'municipal-medical-center':
        'Comprehensive Regional Healthcare & Health Resilience',
    'water-reclamation-plant':
        'Municipal Water Recycling & Resource Loss Mitigation',
    'water-sanitation-authority':
        'Municipal Water Purity & Sanitation Infrastructure',
    'regional-waterworks-consortium':
        'Large-Scale Water Infrastructure & Utility Dividends',
    'transit-terminus': 'Municipal Transit and District Connectivity',
    'metro-station': 'Municipal Transit and District Connectivity',
    'urban-district-module': 'Municipal Land & Citizen Capacity Expansion',
    'district-expansion': 'Municipal Land & Citizen Capacity Expansion',
    'transit-hyperloop':
        'High-Speed Logistics & Public Passenger Dividends',
    'hyperloop-terminal':
        'High-Speed Logistics & Public Passenger Dividends',
    'orbital-spaceport':
        'Orbital Shuttles, Off-World Mining Logistics & High Prestige',
    'spaceport':
        'Orbital Shuttles, Off-World Mining Logistics & High Prestige',
    'planetary-freight-terminal':
        'Heavy Inter-City Freight Logistics & Commercial Dividends',
    'orbital-communications-array':
        'Orbital Satellite Relay & Telecommunication Dividends',
    'civic-housing-authority':
        'Public Affordable Housing & Citizen Population Influx',
    'public-education-campus':
        'Workforce Skill Development & Research Capability',
    'emergency-response-command':
        'City Emergency Command & Disaster Resilience',
    'municipal-resource-exchange':
        'District Resource Clearing & Commodity Balancing',
    'atmospheric-processing-station':
        'Urban Air Purification & Environmental Health',
    'advanced-research-hub':
        'Planetary R&D Acceleration & Breakthrough Tech Licensing',
  };

  /// Resolves the canonical economic purpose for any building entry or blueprint.
  static String getEconomicPurpose(
    dynamic itemOrType, {
    String? ownership,
    String? category,
  }) {
    if (itemOrType is Map) {
      final explicitPurpose = itemOrType['primaryEconomicPurpose']?.toString() ??
          itemOrType['primary_economic_purpose']?.toString() ??
          itemOrType['economic_purpose']?.toString() ??
          itemOrType['economicPurpose']?.toString();
      if (explicitPurpose != null &&
          explicitPurpose.trim().isNotEmpty &&
          explicitPurpose != 'Economic Production' &&
          explicitPurpose != 'Municipal Public Utility') {
        return explicitPurpose.trim();
      }

      final type = (itemOrType['building_type'] ??
              itemOrType['type'] ??
              itemOrType['id'] ??
              '')
          .toString()
          .toLowerCase()
          .replaceAll(RegExp(r'-t\d+$'), '');

      if (_economicPurposes.containsKey(type)) {
        return _economicPurposes[type]!;
      }

      final cat = (category ?? itemOrType['category'] ?? '').toString().toLowerCase();
      final own = (ownership ??
              itemOrType['ownership_class'] ??
              itemOrType['defaultOwnershipClass'] ??
              itemOrType['ownershipClass'] ??
              '')
          .toString()
          .toLowerCase();

      return _fallbackForCategory(cat, own);
    }

    final key = itemOrType
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'-t\d+$'), '');
    if (_economicPurposes.containsKey(key)) {
      return _economicPurposes[key]!;
    }

    return _fallbackForCategory(
        category?.toLowerCase() ?? '', ownership?.toLowerCase() ?? '');
  }

  static const Map<String, String> _buildingAssets = {
    'restaurant': 'molecular-bistro-6b24dd20',
    'retail-store': 'retail-tools-boutique-1f89749b',
    'commercial-mall': 'commercial-galleria-5a2e708d',
    'fabrication-plant': 'cnc-fabrication-plant-9f7c537b',
    'chemical-foundry': 'polymer-foundry-6823337d',
    'solar-array-complex': 'solar-array-c91e277d',
    'geothermal-grid': 'geothermal-core-fbbdab4d',
    'vertical-farm': 'aeroponic-farm-90983d18',
    'server-farm': 'neural-data-center-0bb6ca25',
    'medical-clinic': 'bionic-medical-center-9924775e',
    'transit-hyperloop': 'hyperloop-terminal-8b848c58',
    'orbital-spaceport': 'orbital-spaceport-7b583845',
    'transit-terminus': 'transit-hub-1b3dd2e6',
    'urban-district-module': 'urban-district-module-8ec2f7a6',
    'private-estate-plot': 'private-estate-plot-d75224d6',
  };

  /// Returns the asset path for the specified building type.
  static String getAssetPath(String buildingType) {
    final cleanType = buildingType.toLowerCase().replaceAll(RegExp(r'-t\d+$'), '');
    final filename = _buildingAssets[cleanType] ?? 'urban-district-module-8ec2f7a6';
    return 'assets/buildings/$filename.png';
  }

  /// List of all unique building asset image paths for precaching.
  static List<String> getAllAssetPaths() {
    final uniqueFiles = _buildingAssets.values.toSet();
    return uniqueFiles.map((file) => 'assets/buildings/$file.png').toList();
  }

  static String _fallbackForCategory(String category, String ownership) {
    switch (category) {
      case 'commercial':
        return 'Commercial Enterprise & Credit Revenue Generation';
      case 'energy':
        return 'Clean Energy Production & Grid Baseload Capacity';
      case 'food':
        return 'Urban Food Production & Biomass Reserves';
      case 'manufacturing':
        return 'Industrial Material & Component Fabrication';
      case 'compute':
        return 'High-Throughput Compute & Neural Processing';
      case 'medical':
        return 'Urban Healthcare, Longevity & Disease Protection';
      case 'civic':
        return 'Municipal Infrastructure & Citizen Dividends';
      case 'orbital':
        return 'Orbital Logistics & Planetary Space Operations';
      default:
        return ownership == 'civic' || ownership == 'public_investment'
            ? 'Municipal Public Utility & Citizen Dividends'
            : 'Liquid Credit Profit & Resident Consumption';
    }
  }
}

