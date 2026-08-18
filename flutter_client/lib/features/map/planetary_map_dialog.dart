import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

void showPlanetaryMapDialog(
  BuildContext context, {
  required EarthApi api,
  EarthState? state,
  String? initialRegionId,
  String? initialPlotId,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => PlanetaryMapDialog(
      api: api,
      state: state,
      initialRegionId: initialRegionId,
      initialPlotId: initialPlotId,
    ),
  );
}

class PlanetaryMapDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String? initialRegionId;
  final String? initialPlotId;

  const PlanetaryMapDialog({
    super.key,
    required this.api,
    this.state,
    this.initialRegionId,
    this.initialPlotId,
  });

  @override
  State<PlanetaryMapDialog> createState() => _PlanetaryMapDialogState();
}

class _PlanetaryMapDialogState extends State<PlanetaryMapDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _loading = true;
  String? _error;
  String? _successMessage;

  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _plots = [];
  String _selectedRegionId = 'REG-PACIFIC-RIM';
  Map<String, dynamic>? _selectedPlot;

  int _leaseDurationDays = 30;
  bool _isClaiming = false;
  bool _isUpgrading = false;
  bool _isHarvesting = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _loadMapData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadMapData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.planetaryRegions();
      final regionsList = ((res['regions'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final plotsList = ((res['plots'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      String targetRegion = widget.initialRegionId ??
          (regionsList.isNotEmpty ? regionsList.first['id'].toString() : 'REG-PACIFIC-RIM');
      Map<String, dynamic>? targetPlot;

      if (widget.initialPlotId != null) {
        targetPlot = plotsList.firstWhere(
          (p) => p['id'] == widget.initialPlotId,
          orElse: () => plotsList.isNotEmpty ? plotsList.first : {},
        );
        if (targetPlot.isNotEmpty && targetPlot['region_id'] != null) {
          targetRegion = targetPlot['region_id'].toString();
        }
      } else {
        final regionPlots = plotsList.where((p) => p['region_id'] == targetRegion).toList();
        targetPlot = regionPlots.isNotEmpty ? regionPlots.first : null;
      }

      if (mounted) {
        setState(() {
          _regions = regionsList;
          _plots = plotsList;
          _selectedRegionId = targetRegion;
          _selectedPlot = targetPlot != null && targetPlot.isNotEmpty ? targetPlot : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _claimLease(String plotId) async {
    setState(() {
      _isClaiming = true;
      _error = null;
    });
    try {
      final res = await widget.api.claimPlotLease(
        plotId: plotId,
        durationDays: _leaseDurationDays,
      );
      if (mounted) {
        final totalPaid = res['totalPaid'] ?? '';
        final expires = res['expiresGameDay'] ?? '';
        setState(() {
          _isClaiming = false;
          _successMessage = 'Concession lease secured! ' + totalPaid.toString() + ' CR paid (Expires Day ' + expires.toString() + ').';
        });
        await _loadMapData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isClaiming = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _upgradePlot(String plotId) async {
    setState(() {
      _isUpgrading = true;
      _error = null;
    });
    try {
      final res = await widget.api.upgradePlotInfrastructure(plotId: plotId);
      if (mounted) {
        final newLevel = res['newLevel'] ?? '';
        setState(() {
          _isUpgrading = false;
          _successMessage = 'Infrastructure upgraded to Mark ' + newLevel.toString() + '! Production yields boosted by 35%.';
        });
        await _loadMapData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpgrading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _harvestYield(String plotId) async {
    setState(() {
      _isHarvesting = true;
      _error = null;
    });
    try {
      final res = await widget.api.harvestPlotYield(plotId: plotId);
      if (mounted) {
        final amt = res['harvestedAmount'] ?? 0;
        final resType = res['resourceType'] ?? 'resource';
        setState(() {
          _isHarvesting = false;
          _successMessage = 'Harvested ' + amt.toString() + ' units of ' + resType.toString().toUpperCase() + ' to your reserves.';
        });
        await _loadMapData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isHarvesting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(1100.0, screenSize.width - 24);
    final dialogHeight = math.min(740.0, screenSize.height - 24);

    final selectedRegion = _regions.firstWhere(
      (r) => r['id'] == _selectedRegionId,
      orElse: () => {
        'id': _selectedRegionId,
        'name': 'Pacific Rim Sprawl',
        'biome_type': 'coastal',
        'climate_status': 'optimal',
        'base_solar_index': 1.15,
        'base_geothermal_index': 1.30,
      },
    );

    final currentRegionPlots = _plots.where((p) => p['region_id'] == _selectedRegionId).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: canvasColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthColors.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(220),
              blurRadius: 36,
              spreadRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              _buildTopHeader(),
              if (_error != null) _buildAlertBanner(_error!, isError: true),
              if (_successMessage != null) _buildAlertBanner(_successMessage!, isError: false),
              Expanded(
                child: _loading && _regions.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: EarthColors.cyanAccent))
                    : Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildTacticalMapCanvas(selectedRegion, currentRegionPlots),
                          ),
                          Container(
                            width: math.min(360.0, dialogWidth * 0.42),
                            decoration: const BoxDecoration(
                              color: EarthColors.cardSurface,
                              border: Border(left: BorderSide(color: EarthColors.borderSubtle)),
                            ),
                            child: _selectedPlot != null
                                ? _buildPlotInspector(_selectedPlot!, selectedRegion)
                                : const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'Select a territory node on the tactical map to inspect concession rights.',
                                        style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.public, color: EarthColors.cyanAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'PLANETARY TACTICAL GRID & CONCESSION LEASES',
                    style: TextStyle(
                      color: EarthColors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.9,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _regions.map((region) {
                final isSelected = region['id'] == _selectedRegionId;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedRegionId = region['id'].toString();
                        final rPlots = _plots.where((p) => p['region_id'] == _selectedRegionId).toList();
                        _selectedPlot = rPlots.isNotEmpty ? rPlots.first : null;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? EarthColors.cyanAccent : EarthColors.panelSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? EarthColors.cyanAccent : EarthColors.borderSubtle,
                        ),
                      ),
                      child: Text(
                        (region['name'] ?? region['id']).toString().toUpperCase(),
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(String message, {required bool isError}) {
    final color = isError ? Colors.redAccent : EarthColors.cyanAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: color.withAlpha(25),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: EarthColors.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() {
              _error = null;
              _successMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTacticalMapCanvas(
    Map<String, dynamic> region,
    List<Map<String, dynamic>> plots,
  ) {
    return Container(
      color: const Color(0xFF090B14),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: _TacticalMapPainter(
                  animValue: _animController.value,
                  regionId: _selectedRegionId,
                  plots: plots,
                  selectedPlotId: _selectedPlot?['id']?.toString(),
                ),
              );
            },
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              return Stack(
                children: plots.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final plot = entry.value;
                  final isSelected = _selectedPlot?['id'] == plot['id'];
                  final resource = (plot['primary_resource'] ?? 'energy').toString();
                  final isLeased = plot['lease_holder_id'] != null &&
                      plot['lease_holder_id'] != 'null' &&
                      plot['lease_holder_id'].toString().trim().isNotEmpty;

                  final posX = _getNodeCoordinateX(idx, plots.length, w);
                  final posY = _getNodeCoordinateY(idx, plots.length, h);

                  return Positioned(
                    left: posX - 26,
                    top: posY - 26,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPlot = plot),
                      child: Tooltip(
                        message: plot['plot_name'].toString() + ' (' + resource.toUpperCase() + ')',
                        child: _buildNodeWidget(plot, isSelected, isLeased, resource),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: EarthColors.borderSubtle),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _telemetryPill('BIOME', (region['biome_type'] ?? 'regional').toString().toUpperCase(), Icons.terrain),
                    const SizedBox(width: 8),
                    _telemetryPill('SOLAR', region['base_solar_index'].toString() + 'x', Icons.wb_sunny_outlined),
                    const SizedBox(width: 8),
                    _telemetryPill('GEOTHERMAL', region['base_geothermal_index'].toString() + 'x', Icons.local_fire_department_outlined),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeWidget(
    Map<String, dynamic> plot,
    bool isSelected,
    bool isLeased,
    String resource,
  ) {
    Color accentColor = EarthColors.cyanAccent;
    IconData icon = Icons.bolt;
    if (resource == 'food') {
      accentColor = Colors.greenAccent;
      icon = Icons.eco;
    } else if (resource == 'material') {
      accentColor = Colors.orangeAccent;
      icon = Icons.layers;
    } else if (resource == 'compute') {
      accentColor = Colors.cyanAccent;
      icon = Icons.memory;
    }

    final level = plot['development_level'] ?? 1;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? accentColor.withAlpha(50)
            : (isLeased ? Colors.black.withAlpha(200) : Colors.black.withAlpha(140)),
        border: Border.all(
          color: isSelected ? accentColor : (isLeased ? Colors.amberAccent : EarthColors.borderSubtle),
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: accentColor.withAlpha(150), blurRadius: 14, spreadRadius: 2)]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isSelected ? accentColor : Colors.white, size: 15),
          const SizedBox(height: 1),
          Text(
            'L' + level.toString(),
            style: TextStyle(
              color: isSelected ? accentColor : (isLeased ? Colors.amberAccent : EarthColors.textMuted),
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryPill(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: EarthColors.cyanAccent),
        const SizedBox(width: 3),
        Text(label + ': ', style: const TextStyle(color: EarthColors.textMuted, fontSize: 9)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9)),
      ],
    );
  }

  Widget _buildPlotInspector(
    Map<String, dynamic> plot,
    Map<String, dynamic> region,
  ) {
    final plotId = plot['id'] ?? '';
    final plotName = plot['plot_name'] ?? 'Territory Plot';
    final resource = (plot['primary_resource'] ?? 'energy').toString();
    final baseYield = _parseNum(plot['base_yield_rate']);
    final devLevel = _parseInt(plot['development_level'], fallback: 1);
    final maxLevel = _parseInt(plot['max_level'], fallback: 5);
    final infraName = plot['infrastructure_name'] ?? 'Standard Resource Rig';
    final rawLeaseHolder = plot['lease_holder_id'];
    final isLeased = rawLeaseHolder != null &&
        rawLeaseHolder != 'null' &&
        rawLeaseHolder.toString().trim().isNotEmpty;
    final leaseHolder = isLeased ? (plot['lease_holder_name'] ?? rawLeaseHolder) : null;
    final rawExpires = plot['lease_expires_game_day'];
    final expires = (rawExpires != null && rawExpires != 'null') ? rawExpires : null;
    final dailyFee = _parseNum(plot['daily_lease_fee']);
    final unharvested = _parseNum(plot['accumulated_yield']);

    final isMyLease = isLeased && plot['lease_holder_id'] == 'H-0044';

    final nextUpgradeLvl = devLevel + 1;
    final upgradeCreditCost = nextUpgradeLvl * 500.0;
    final upgradeMatCost = nextUpgradeLvl * 25;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCommodityBadge(resource),
              Text(
                plotId,
                style: const TextStyle(color: EarthColors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plotName,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            region['name'].toString() + ' · ' + (plot['terrain_type'] ?? 'terrain').toString().toUpperCase(),
            style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('Installed Facility:', style: TextStyle(color: EarthColors.textMuted, fontSize: 10.5), overflow: TextOverflow.ellipsis),
                    ),
                    Text('Level ' + devLevel.toString() + ' / ' + maxLevel.toString(), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 10.5)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  infraName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStat('Daily Yield', baseYield.toStringAsFixed(1) + ' ' + resource + '/day'),
                    _buildStat('Lease Fee', dailyFee.toStringAsFixed(0) + ' CR/day'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isLeased ? Colors.amberAccent.withAlpha(15) : EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isLeased ? Colors.amberAccent.withAlpha(80) : EarthColors.borderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isLeased ? Icons.verified_user : Icons.lock_open_outlined,
                      size: 13,
                      color: isLeased ? Colors.amberAccent : EarthColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        isLeased ? 'ACTIVE CONCESSION LEASE' : 'CONCESSION AVAILABLE FOR LEASE',
                        style: TextStyle(
                          color: isLeased ? Colors.amberAccent : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (isLeased) ...[
                  Text('Leaseholder: ' + leaseHolder.toString(), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                  Text('Expires on Game Day: ' + expires.toString(), style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5)),
                ] else ...[
                  const Text(
                    'Exclusive territorial rights grant full yield harvesting and facility upgrade control.',
                    style: TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (isLeased) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EarthColors.panelSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EarthColors.cyanAccent.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Accumulated Yield:', style: TextStyle(color: EarthColors.textMuted, fontSize: 10)),
                        Text(
                          unharvested.toStringAsFixed(1) + ' ' + resource.toUpperCase(),
                          style: const TextStyle(color: EarthColors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    key: const Key('btn-harvest-yield'),
                    onPressed: (_isHarvesting || unharvested <= 0) ? null : () => _harvestYield(plotId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EarthColors.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                    ),
                    child: Text(_isHarvesting ? 'HARVESTING...': 'HARVEST YIELD'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (!isLeased || isMyLease) ...[
            if (!isLeased) ...[
              const Text('SECURE CONCESSION LEASE', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _leaseDurationDays.toDouble(),
                      min: 7,
                      max: 90,
                      divisions: 83,
                      activeColor: EarthColors.cyanAccent,
                      onChanged: (v) => setState(() => _leaseDurationDays = v.toInt()),
                    ),
                  ),
                  Text(_leaseDurationDays.toString() + ' Days', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total: ' + (dailyFee * _leaseDurationDays).toStringAsFixed(0) + ' CR', style: const TextStyle(color: EarthColors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ElevatedButton(
                    key: const Key('btn-claim-lease'),
                    onPressed: _isClaiming ? null : () => _claimLease(plotId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EarthColors.goldMetallic,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                    ),
                    child: Text(_isClaiming ? 'SECURING...': 'CLAIM LEASE'),
                  ),
                ],
              ),
            ] else if (devLevel < maxLevel) ...[
              const Text('UPGRADE INFRASTRUCTURE', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Cost: ' + upgradeCreditCost.toStringAsFixed(0) + ' CR + ' + upgradeMatCost.toString() + ' Material',
                style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('btn-upgrade-plot'),
                  onPressed: _isUpgrading ? null : () => _upgradePlot(plotId),
                  icon: const Icon(Icons.arrow_upward, size: 13),
                  label: Text(_isUpgrading ? 'UPGRADING...': 'UPGRADE TO MARK ' + nextUpgradeLvl.toString() + ' (+35% Yield)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EarthColors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStat(String label, String val) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildCommodityBadge(String resource) {
    Color color = Colors.amberAccent;
    IconData icon = Icons.bolt;
    if (resource == 'food') {
      color = Colors.greenAccent;
      icon = Icons.eco;
    } else if (resource == 'material') {
      color = Colors.orangeAccent;
      icon = Icons.layers;
    } else if (resource == 'compute') {
      color = Colors.cyanAccent;
      icon = Icons.memory;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(resource.toUpperCase(), style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static double _getNodeCoordinateX(int index, int total, double width) {
    final cols = math.max(2, math.sqrt(total).ceil());
    final col = index % cols;
    final step = (width - 100) / (cols > 1 ? (cols - 1) : 1);
    return 50 + col * step;
  }

  static double _getNodeCoordinateY(int index, int total, double height) {
    final cols = math.max(2, math.sqrt(total).ceil());
    final row = index ~/ cols;
    final totalRows = (total / cols).ceil();
    final step = (height - 120) / (totalRows > 1 ? (totalRows - 1) : 1);
    return 50 + row * step;
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  static int _parseInt(dynamic val, {int fallback = 0}) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? fallback;
    return fallback;
  }
}

class _TacticalMapPainter extends CustomPainter {
  final double animValue;
  final String regionId;
  final List<Map<String, dynamic>> plots;
  final String? selectedPlotId;

  _TacticalMapPainter({
    required this.animValue,
    required this.regionId,
    required this.plots,
    this.selectedPlotId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = const Color(0xFF1B2438).withAlpha(80)
      ..strokeWidth = 1.0;

    const spacing = 40.0;
    for (double x = 0; x < w; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final center = Offset(w / 2, h / 2);
    final sweepRadius = math.min(w, h) * 0.45;

    final ringPaint = Paint()
      ..color = EarthColors.cyanAccent.withAlpha(25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, sweepRadius * 0.33, ringPaint);
    canvas.drawCircle(center, sweepRadius * 0.66, ringPaint);
    canvas.drawCircle(center, sweepRadius, ringPaint);

    final sweepAngle = animValue * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          EarthColors.cyanAccent.withAlpha(35),
        ],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: sweepRadius));

    canvas.drawCircle(center, sweepRadius, sweepPaint);

    final conduitPaint = Paint()
      ..color = EarthColors.cyanAccent.withAlpha(40)
      ..strokeWidth = 1.5;

    for (int i = 0; i < plots.length - 1; i++) {
      final p1 = Offset(
        _PlanetaryMapDialogState._getNodeCoordinateX(i, plots.length, w),
        _PlanetaryMapDialogState._getNodeCoordinateY(i, plots.length, h),
      );
      final p2 = Offset(
        _PlanetaryMapDialogState._getNodeCoordinateX(i + 1, plots.length, w),
        _PlanetaryMapDialogState._getNodeCoordinateY(i + 1, plots.length, h),
      );
      canvas.drawLine(p1, p2, conduitPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TacticalMapPainter oldDelegate) {
    return oldDelegate.animValue != animValue ||
        oldDelegate.regionId != regionId ||
        oldDelegate.selectedPlotId != selectedPlotId;
  }
}
