import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

Future<void> showFormationComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    {required bool city, String? communityId, String? cityId}) async {
  final name = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: Text(city ? 'Form a City' : 'Form a Corporation'),
            content: TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText: city ? 'City name' : 'Corporation name')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (name.text.trim().length < 3) return;
                    final selectedName = name.text.trim();
                    await action(() => city
                        ? const EarthApi()
                            .createCity(selectedName, communityId!)
                        : const EarthApi()
                            .createCorporation(selectedName, cityId!));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit')),
            ],
          ));
  name.dispose();
}
