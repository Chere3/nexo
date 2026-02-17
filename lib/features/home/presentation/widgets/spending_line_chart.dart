import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../transactions/domain/transaction.dart';

class SpendingLineChart extends StatelessWidget {
  const SpendingLineChart({super.key, required this.entries});

  final List<FinanceEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last7 = List.generate(7, (i) => DateTime(now.year, now.month, now.day - (6 - i)));

    final spots = <FlSpot>[];
    for (var i = 0; i < last7.length; i++) {
      final day = last7[i];
      final total = entries
          .where((e) => e.type == EntryType.expense)
          .where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day)
          .fold<double>(0, (sum, e) => sum + e.amount);
      spots.add(FlSpot(i.toDouble(), total));
    }

    return Card(
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 6,
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
                      final i = value.toInt();
                      return Text(i >= 0 && i < labels.length ? labels[i] : '');
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
