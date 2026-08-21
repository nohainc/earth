import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';

void showReincarnationDialog(
  BuildContext context, {
  required Map<String, dynamic> deceasedHuman,
  required EarthApi api,
  required ValueChanged<Map<String, dynamic>> onReborn,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ReincarnationDialog(
      deceasedHuman: deceasedHuman,
      api: api,
      onReborn: onReborn,
    ),
  );
}

class ReincarnationDialog extends StatefulWidget {
  final Map<String, dynamic> deceasedHuman;
  final EarthApi api;
  final ValueChanged<Map<String, dynamic>> onReborn;

  const ReincarnationDialog({
    super.key,
    required this.deceasedHuman,
    required this.api,
    required this.onReborn,
  });

  @override
  State<ReincarnationDialog> createState() => _ReincarnationDialogState();
}

class _ReincarnationDialogState extends State<ReincarnationDialog> {
  final _nameController = TextEditingController();
  late final TextEditingController _dynastyController;
  String _selectedCity = 'CITY-0084';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _dynastyController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final existingDynasty = widget.deceasedHuman['dynasty_name']?.toString().trim();
    _dynastyController = TextEditingController(
      text: existingDynasty == null || existingDynasty.isEmpty
          ? 'Founding Dynasty'
          : existingDynasty,
    );
  }

  Future<void> _submitRebirth() async {
    final name = _nameController.text.trim();
    if (name.length < 2 || name.length > 80) {
      setState(() => _error = 'Display name must be 2–80 characters');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.rebirth(
        name,
        dynastyName: _dynastyController.text.trim(),
        startingCityId: _selectedCity,
      );
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        widget.onReborn(res);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _submitting = false;
        });
      }
    }
  }

  Future<void> _submitClaimHeir() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.claimHeir();
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        widget.onReborn(res);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.deceasedHuman['display_name']?.toString() ??
        widget.deceasedHuman['name']?.toString() ??
        'Former Citizen';
    final legacy = widget.deceasedHuman['legacy']?.toString() ?? '0';
    final standing = widget.deceasedHuman['standing']?.toString() ?? '0';

    return Dialog(
      backgroundColor: EarthColors.panelSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: EarthColors.goldMetallic, width: 1.5),
      ),
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Memorial Header
              Row(
                children: [
                  const Icon(Icons.nightlight_round,
                      color: EarthColors.goldMetallic, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MORTALITY & DYNASTIC SUCCESSION',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: EarthColors.goldMetallic,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'The life journey of $name has entered the Planetary Pantheon.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: EarthColors.textMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Eulogy Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EarthColors.cardSurface,
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: EarthColors.goldMetallic.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEMORIAL INSCRIPTION',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: EarthColors.goldMetallic,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '“$name contributed to the planetary economy and civic governance. Inscribed forever into the civilization records of Earth.”',
                      style: const TextStyle(
                        color: Colors.white,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _statBadge(Icons.star, 'Lifetime Legacy: $legacy'),
                        _statBadge(Icons.shield, 'Final Standing: $standing'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Next Steps Header
              Text(
                'CHOOSE YOUR CONTINUATION PATH',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: EarthColors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
              ),
              const SizedBox(height: 12),

              // Option 1: Claim Designated Heir
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: EarthColors.cardSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: EarthColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin,
                        color: EarthColors.cyanAccent, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Step Into Designated Successor',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Continue as the designated heir. The estate, productive assets, resources, and registered responsibilities transfer according to the will.',
                            style: TextStyle(
                                color: EarthColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submitClaimHeir,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EarthColors.cyanAccent.withAlpha(40),
                        foregroundColor: EarthColors.cyanAccent,
                        side: const BorderSide(color: EarthColors.cyanAccent),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('CLAIM HEIR'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Option 2: Forge New Identity (Rebirth)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EarthColors.cardSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: EarthColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.auto_awesome,
                            color: EarthColors.goldMetallic, size: 22),
                        SizedBox(width: 10),
                          Text(
                          'Create New Adult (Civic Rebirth)',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Begin a new generation at legal adulthood (Age 20) with an indexed starter package. The new character carries dynasty legacy forward but does not directly claim the predecessor’s estate. Your selected city determines initial civic affiliation: if it belongs to a corporation, the new character joins that corporation. A 500 Credit naturalization fee is allocated between the central and city treasuries.',
                      style:
                          TextStyle(color: EarthColors.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'New Character Display Name',
                        hintText: 'e.g. Marcus Vance II',
                        isDense: true,
                        filled: true,
                        fillColor: EarthColors.panelSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dynastyController,
                      decoration: const InputDecoration(
                        labelText: 'Dynastic Family House',
                        hintText: 'e.g. Vance Dynasty',
                        isDense: true,
                        filled: true,
                        fillColor: EarthColors.panelSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCity,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Arrival Jurisdiction & City',
                        isDense: true,
                        filled: true,
                        fillColor: EarthColors.panelSurface,
                      ),
                      dropdownColor: EarthColors.cardSurface,
                      items: const [
                        DropdownMenuItem(
                            value: 'CITY-0084',
                            child:
                                Text('New Carthage (Founding City)')),
                        DropdownMenuItem(
                            value: 'city-singapore',
                            child: Text('Singapore (Maritime & Logistics)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCity = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submitRebirth,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: EarthColors.goldMetallic,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Text(
                                'PAY 500 C NATURALIZATION FEE & REBIRTH',
                                style: TextStyle(fontWeight: FontWeight.bold),
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

  Widget _statBadge(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: EarthColors.goldMetallic),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
              color: EarthColors.goldMetallic,
              fontSize: 12,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
