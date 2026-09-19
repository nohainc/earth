class EarthBuildingMeta {
  /// Stable V5 family visuals. These keys intentionally do not include a
  /// tier suffix: every tier in a family keeps the same visual identity.
  static const Map<String, String> _v5FamilyAssets = {
    'SOLAR_MICROGRID': 'solar-array-c91e277d',
    'VERTICAL_FARM': 'aeroponic-farm-90983d18',
    'MATERIALS_RECOVERY': 'polymer-foundry-6823337d',
    'PRECISION_FABRICATION': 'cnc-fabrication-plant-9f7c537b',
    'COMPUTE_CLUSTER': 'neural-data-center-0bb6ca25',
    'DATA_SERVICES_STUDIO': 'transit-hub-1b3dd2e6',
    'COMMUNITY_CLINIC': 'bionic-medical-center-9924775e',
    'EXTRACTION_REFINING_COMPLEX': 'geothermal-core-fbbdab4d',
    'CIVIC_DATA_NETWORK': 'hyperloop-terminal-8b848c58',
    'PUBLIC_MEDICAL_CENTER': 'urban-district-module-8ec2f7a6',
    'RESEARCH_EDUCATION_CAMPUS': 'orbital-spaceport-7b583845',
  };

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
    final cleanType =
        buildingType.toLowerCase().replaceAll(RegExp(r'-t\d+$'), '');
    final filename =
        _buildingAssets[cleanType] ?? 'urban-district-module-8ec2f7a6';
    return 'assets/buildings/$filename.png';
  }

  /// Returns the stable visual for a V5 family. Unknown families use the
  /// intentional generic district visual rather than borrowing a tier image.
  static String getFamilyAssetPath(String? familyCode) {
    final key = familyCode?.trim().toUpperCase();
    final filename = (key == null || key.isEmpty)
        ? 'urban-district-module-8ec2f7a6'
        : _v5FamilyAssets[key] ?? 'urban-district-module-8ec2f7a6';
    return 'assets/buildings/$filename.png';
  }

  static Set<String> get v5FamilyVisualKeys => _v5FamilyAssets.keys.toSet();

  /// List of all unique building asset image paths for precaching.
  static List<String> getAllAssetPaths() {
    final uniqueFiles = {..._buildingAssets.values, ..._v5FamilyAssets.values};
    return uniqueFiles.map((file) => 'assets/buildings/$file.png').toList();
  }
}
