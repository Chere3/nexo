import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../transactions/domain/transaction.dart';

class ExpensePieChart extends StatelessWidget {
  const ExpensePieChart({super.key, required this.entries});

  final List<FinanceEntry> entries;

  @override
  Widget build(BuildContext context) {
    final expenseEntries = entries.where((e) => e.type == EntryType.expense).toList();
    final grouped = <String, double>{};
    for (final e in expenseEntries) {
      grouped[e.category] = (grouped[e.category] ?? 0) + e.amount;
    }

    if (grouped.isEmpty) {
      return const Card(child: SizedBox(height: 180, child: Center(child: Text('Sin gastos aún'))));
    }

    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Colors.orange,
      Colors.teal,
    ];

    final sections = grouped.entries.toList().asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      return PieChartSectionData(
        value: item.value,
        color: colors[idx % colors.length],
        title: item.key,
        radius: 58,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      );
    }).toList();

    return Card(
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 24,
              sections: sections,
            ),
          ),
        ),
      ),
    );
  }
}
