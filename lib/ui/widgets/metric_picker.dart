import 'package:flutter/material.dart';

/// A full-width searchable list, independent of the width of its trigger.
Future<String?> pickMetric(
  BuildContext context,
  Map<String, List<String>> groups,
  String selected, {
  bool allowNone = false,
}) {
  var query = '';
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        return AlertDialog(
          title: const Text('Choose a metric'),
          content: SizedBox(
            width: 480,
            height: MediaQuery.sizeOf(context).height * .6,
            child: Column(
              children: [
                TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search all metrics',
                  ),
                  onChanged: (value) =>
                      update(() => query = value.toLowerCase()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      if (allowNone && ('none single metric').contains(query))
                        ListTile(
                          title: const Text('None (single metric)'),
                          selected: selected == 'none',
                          onTap: () => Navigator.pop(context, 'none'),
                        ),
                      for (final group in groups.entries)
                        if (group.value.any(
                          (m) => m.toLowerCase().contains(query),
                        )) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(
                              group.key,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          for (final metric in group.value)
                            if (metric.toLowerCase().contains(query))
                              ListTile(
                                title: Text(metric.replaceAll('_', ' ')),
                                selected: selected == metric,
                                trailing: selected == metric
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () => Navigator.pop(context, metric),
                              ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );
}
