import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../utils/formatters.dart';
import '../../../models/models.dart';

/// Donut chart (tap-aware) with center total and legend below.
class SpendingDonut extends StatefulWidget {
  final List<SpendingCategory> categories;
  final double total;

  const SpendingDonut({super.key, required this.categories, required this.total});

  @override
  State<SpendingDonut> createState() => _SpendingDonutState();
}

/// Returns the touched section index clamped to `[0, length)` as a nullable
/// index, or `null` when the touch did not land on a section.
///
/// fl_chart reports `-1` for touches that miss every section (for example
/// inside the donut hole, where `centerSpaceRadius` carves out a gap). That
/// value must never be used as a list index or it throws a `RangeError`.
int? safeSectionIndex(int? index, int length) {
  if (index == null || index < 0 || index >= length) return null;
  return index;
}

class _SpendingDonutState extends State<SpendingDonut> {
  int? _selected;

  /// Only return an index that is actually valid for the current categories.
  /// [PieTouchData] reports `-1` when the touch lands outside every section
  /// (e.g. inside the donut hole), which would otherwise crash the build.
  int? get _activeIndex => safeSectionIndex(_selected, widget.categories.length);

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 58,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent || event is FlTapDownEvent) {
                        final index = response?.touchedSection?.touchedSectionIndex;
                        setState(() {
                          // -1 means the touch missed every section (donut hole).
                          _selected = safeSectionIndex(index, widget.categories.length);
                        });
                      }
                    },
                  ),
                  sections: List.generate(widget.categories.length, (i) {
                    final c = widget.categories[i];
                    final active = _selected == i;
                    return PieChartSectionData(
                      value: c.amount,
                      color: c.category.color,
                      radius: active ? 34 : 30,
                      showTitle: false,
                    );
                  }),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    active == null
                        ? Formatters.inr(widget.total)
                        : Formatters.inr(widget.categories[active].amount),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active == null ? 'Total Expenses' : widget.categories[active].category.label,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < widget.categories.length; i++)
          _LegendRow(
            category: widget.categories[i],
            selected: _selected == i,
            onTap: () => setState(() {
              _selected = _selected == i ? null : i;
            }),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final SpendingCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _LegendRow({required this.category, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: category.category.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.category.label,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
            Text(Formatters.inr(category.amount),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              child: Text('${category.pct}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Area chart: historical expenses (blue) + predicted month (purple, dashed).
///
/// [predicted] is optional so the chart can be drawn history-only when there is
/// no forecast to plot in the same currency as [historic].
class ExpensePredictionChart extends StatelessWidget {
  final List<double> historic;
  final double? predicted;
  final List<String> labels;

  const ExpensePredictionChart({
    super.key,
    required this.historic,
    required this.predicted,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    const histColor = AppColors.savings;
    const predColor = AppColors.ai;
    final pred = predicted;

    final histSpots = List.generate(
        historic.length, (i) => FlSpot(i.toDouble(), historic[i]));
    final predSpots = pred == null
        ? <FlSpot>[]
        : [
            FlSpot(
              historic.length - 1.toDouble(),
              historic.last,
            ),
            FlSpot(historic.length.toDouble(), pred),
          ];

    // With no forecast there is no point at x == historic.length, so don't
    // render the "predicted" month on the axis either.
    final axisLabels =
        pred == null ? labels.take(historic.length).toList(growable: false) : labels;
    final predictedX = pred == null ? -1 : historic.length;

    final bars = <LineChartBarData>[
      LineChartBarData(
        spots: histSpots,
        isCurved: true,
        curveSmoothness: 0.3,
        barWidth: 3,
        color: histColor,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              histColor.withValues(alpha: .3),
              histColor.withValues(alpha: .02),
            ],
          ),
        ),
      ),
    ];
    if (pred != null) {
      bars.add(
        LineChartBarData(
          spots: predSpots,
          isCurved: true,
          barWidth: 3,
          color: predColor,
          dashArray: [6, 4],
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
              radius: 4,
              color: predColor,
              strokeWidth: 2,
              strokeColor: AppColors.bg,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                predColor.withValues(alpha: .28),
                predColor.withValues(alpha: .02),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 20000,
          maxY: 50000,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10000,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.line.withValues(alpha: .7),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '₹${(v / 1000).round()}k',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= axisLabels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      axisLabels[i],
                      style: TextStyle(
                        color: i == predictedX
                            ? AppColors.ai
                            : AppColors.textMuted,
                        fontSize: 10.5,
                        fontWeight: i == predictedX
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceAlt,
              getTooltipItems: (spots) => spots.map((s) {
                return LineTooltipItem(
                  Formatters.inr(s.y),
                  const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                );
              }).toList(),
            ),
          ),
          lineBarsData: bars,
          extraLinesData: pred == null
              ? null
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: pred,
                      color: predColor.withValues(alpha: .35),
                      strokeWidth: 1,
                      dashArray: [4, 5],
                    ),
                  ],
                ),
        ),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      ),
    );
  }
}

/// Simple animated progress bar used for budgets, goals and SHAP bars.
class ProgressBar extends StatelessWidget {
  final double value; // 0..1 (may exceed for over-budget)
  final Color color;
  final double height;

  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: AppColors.surfaceAlt,
        color: color,
      ),
    );
  }
}

/// Rotate a percentage into a pie arc length helper.
double pctToRad(double pct) => 2 * math.pi * (pct / 100);