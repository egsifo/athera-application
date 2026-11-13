import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/real_data.dart';
import '../widgets/common.dart';

/// Real ISS radiation measurements (NASA RadLab). Everything shown is computed
/// from the bundled measurements; nothing is simulated on this screen.
class RadiationScreen extends StatefulWidget {
  const RadiationScreen({super.key, this.loader});
  final Future<IssRadiation> Function()? loader;

  @override
  State<RadiationScreen> createState() => _RadiationScreenState();
}

class _RadiationScreenState extends State<RadiationScreen> {
  late final Future<IssRadiation> _future = (widget.loader ?? IssRadiation.load)();
  String? _instrument;
  int _range = 1; // 0: 90 days, 1: 1 year, 2: all

  static const _ranges = ['90 days', '1 year', 'All'];

  String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radiation (real ISS data)')),
      body: FutureBuilder<IssRadiation>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingBox();
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: InfoBanner('The radiation data could not be loaded: ${snap.error}',
                  icon: Icons.error_outline_rounded, color: AC.red),
            );
          }
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(IssRadiation data) {
    final names = data.instruments.keys.toList();
    final name = _instrument ?? names.first;
    final all = data.instruments[name]!;
    final stats = RadStats(all);
    final last = all.last.date;
    final from = switch (_range) {
      0 => last.subtract(const Duration(days: 90)),
      1 => last.subtract(const Duration(days: 365)),
      _ => all.first.date,
    };
    final view = all.where((d) => !d.date.isBefore(from)).toList();
    final gaps = RadStats.gaps(all);

    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      InfoBanner(
        'MEASURED by NASA RadLab instruments on the ISS (${_ymd(all.first.date)} to ${_ymd(last)}). '
        'This is the dose rate inside the station module, not one astronaut\'s personal dose.',
        icon: Icons.satellite_alt_rounded,
        color: AC.cyan,
      ),
      const SizedBox(height: Sp.m),
      Wrap(spacing: Sp.s, children: [
        for (final n in names)
          ChoiceChip(label: Text(n), selected: n == name, onSelected: (_) => setState(() => _instrument = n)),
      ]),
      const SizedBox(height: Sp.m),
      Row(children: [
        _stat('Typical day (all-day mean)', stats.meanDailyDoseUGy == null ? 'n/a' : '${stats.meanDailyDoseUGy!.toStringAsFixed(0)} µGy/day',
            note: '${stats.completeDays} complete days'),
        const SizedBox(width: Sp.s),
        _stat('Quiet-time rate', stats.quietMedianRate == null ? 'n/a' : '${stats.quietMedianRate!.toStringAsFixed(1)} µGy/h',
            note: 'median of daily medians'),
      ]),
      const SizedBox(height: Sp.s),
      Row(children: [
        _stat('Highest day', stats.peakDay == null ? 'n/a' : '${stats.peakDay!.mean.toStringAsFixed(1)} µGy/h',
            note: stats.peakDay == null ? null : _ymd(stats.peakDay!.date)),
        const SizedBox(width: Sp.s),
        _stat('Highest instant', stats.peakInstant == null ? 'n/a' : '${stats.peakInstant!.max.toStringAsFixed(0)} µGy/h',
            note: stats.peakInstant == null ? null : _ymd(stats.peakInstant!.date)),
      ]),
      const SizedBox(height: Sp.l),
      Wrap(spacing: Sp.s, children: [
        for (var i = 0; i < _ranges.length; i++)
          ChoiceChip(label: Text(_ranges[i]), selected: i == _range, onSelected: (_) => setState(() => _range = i)),
      ]),
      const SectionHeader('Dose rate', subtitle: 'µGy per hour, daily mean (cyan) and daily median (blue)'),
      AtCard(child: SizedBox(height: 220, child: _rateChart(view))),
      const SizedBox(height: Sp.s),
      const Text(
        'The mean is pushed up by passes through the South Atlantic Anomaly; the median shows the quiet baseline. '
        'Breaks in the line are real gaps in the data.',
        style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
      ),
      const SectionHeader('Accumulated dose in this window', subtitle: 'Sum of measured complete days only'),
      AtCard(child: SizedBox(height: 180, child: _cumulativeChart(view))),
      const SizedBox(height: Sp.s),
      const Text(
        'Absorbed dose in µGy (1 mGy = 1000 µGy). It is not converted to mSv, because that needs a radiation-quality '
        'factor this data does not contain.',
        style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
      ),
      if (gaps.isNotEmpty) ...[
        const SectionHeader('Data gaps'),
        AtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final g in gaps.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${_ymd(g.$1)} to ${_ymd(g.$2)}  (${g.$2.difference(g.$1).inDays} days without data)',
                    style: const TextStyle(fontSize: 13)),
              ),
          ]),
        ),
      ],
      const SectionHeader('About this data'),
      AtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data.source, style: const TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: Sp.s),
          for (final n in data.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('• ', style: TextStyle(color: AC.textDim)),
                Expanded(child: Text(n, style: const TextStyle(fontSize: 13, height: 1.35))),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: Sp.xl),
    ]);
  }

  Widget _stat(String label, String value, {String? note}) => Expanded(
        child: AtCard(
          padding: const EdgeInsets.all(Sp.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AC.textDim, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            if (note != null) Text(note, style: const TextStyle(color: AC.textDim, fontSize: 11)),
          ]),
        ),
      );

  Widget _noData() => const Center(child: Text('No data in this window.', style: TextStyle(color: AC.textDim)));

  FlTitlesData _titles(List<RadDay> v, double x0, {required String Function(double) yLabel}) {
    final span = v.last.date.difference(v.first.date).inDays;
    final step = (span / 4).clamp(1, 1e9).toDouble();
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (y, meta) => Text(yLabel(y), style: const TextStyle(color: AC.textDim, fontSize: 10)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: step,
          reservedSize: 22,
          getTitlesWidget: (x, meta) {
            final d = v.first.date.add(Duration(days: (x - x0).round()));
            return Text(d.toIso8601String().substring(0, 7), style: const TextStyle(color: AC.textDim, fontSize: 10));
          },
        ),
      ),
    );
  }

  Widget _rateChart(List<RadDay> v) {
    if (v.isEmpty) return _noData();
    const x0 = 0.0;
    double x(RadDay d) => d.date.difference(v.first.date).inDays.toDouble();
    List<FlSpot> line(double Function(RadDay) f) {
      final s = <FlSpot>[];
      for (var i = 0; i < v.length; i++) {
        if (i > 0 && v[i].date.difference(v[i - 1].date).inDays > 3) s.add(FlSpot.nullSpot);
        if (v[i].complete) {
          s.add(FlSpot(x(v[i]), f(v[i])));
        } else if (s.isNotEmpty && s.last != FlSpot.nullSpot) {
          s.add(FlSpot.nullSpot);
        }
      }
      return s;
    }

    final top = v.where((d) => d.complete).fold<double>(10, (m, d) => d.mean > m ? d.mean : m);
    return LineChart(LineChartData(
      minX: 0,
      maxX: x(v.last) <= 0 ? 1 : x(v.last),
      minY: 0,
      maxY: (top * 1.1).ceilToDouble(),
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: _titles(v, x0, yLabel: (y) => y.toStringAsFixed(0)),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(spots: line((d) => d.mean), color: AC.cyan, barWidth: 1.6, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: line((d) => d.median), color: AC.blue, barWidth: 1.6, dotData: const FlDotData(show: false)),
      ],
    ));
  }

  Widget _cumulativeChart(List<RadDay> v) {
    if (v.isEmpty) return _noData();
    double sum = 0;
    final spots = <FlSpot>[];
    for (final d in v) {
      if (d.complete) sum += d.doseUGy;
      spots.add(FlSpot(d.date.difference(v.first.date).inDays.toDouble(), sum / 1000));
    }
    return LineChart(LineChartData(
      minX: 0,
      maxX: spots.last.x <= 0 ? 1 : spots.last.x,
      minY: 0,
      maxY: sum / 1000 <= 0 ? 1 : sum / 1000 * 1.05,
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: _titles(v, 0, yLabel: (y) => '${y.toStringAsFixed(y < 10 ? 1 : 0)} mGy'),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: AC.amber,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: AC.amber.withAlpha(30)),
        ),
      ],
    ));
  }
}
