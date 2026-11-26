import 'package:flutter/cupertino.dart';

import 'theme/app_theme.dart';
import 'ui.dart';
import '../core/money_format.dart';

/// Компактный индикатор расхода годового лимита НПД (2.4М ₽ по умолчанию).
class TaxRadarBar extends StatelessWidget {
  const TaxRadarBar({
    super.key,
    required this.incomeCents,
    required this.limitCents,
    this.compact = false,
    this.showWarning = true,
  });

  final int incomeCents;
  final int limitCents;
  final bool compact;
  final bool showWarning;

  double get _raw =>
      limitCents <= 0 ? 0.0 : incomeCents / limitCents.toDouble();

  Color _color(AppColors colors) {
    final p = _raw;
    if (p >= 0.95) return colors.red;
    if (p >= 0.80) return CupertinoColors.systemYellow;
    return colors.green;
  }

  String _money(int cents) => money(cents);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = _raw.clamp(0.0, 1.0);
    final pct = (_raw * 100).clamp(0.0, 999.0);
    final left = limitCents - incomeCents;
    final leftClamped = left < 0 ? 0 : left;
    final barColor = _color(colors);

    final warningText = pct >= 95
        ? 'Лимит НПД почти исчерпан. Измените налоговую схему.'
        : (pct >= 80 ? 'Приближение к лимиту НПД (2.4М ${moneySymbol}/год).' : null);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Налоговый радар (НПД)',
                  style: TextStyle(
                    color: colors.secondaryLabel,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: barColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ProgressBar(value: progress, color: barColor, height: 6),
          const SizedBox(height: 4),
          Text(
            '${_money(incomeCents)} из ${_money(limitCents)} · до лимита ${_money(leftClamped)}',
            style: TextStyle(color: colors.secondaryLabel, fontSize: 11),
          ),
          if (showWarning && warningText != null) ...[
            const SizedBox(height: 2),
            Text(
              warningText,
              style: TextStyle(
                color: barColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Налоговый радар (НПД)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${pct.toStringAsFixed(0)}% из лимита',
              style: TextStyle(color: barColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(value: progress, color: barColor, height: 8),
        const SizedBox(height: 6),
        Text(
          '${_money(incomeCents)} из ${_money(limitCents)}',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
        ),
        Text(
          'До лимита: ${_money(leftClamped)}',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
        ),
        if (showWarning && warningText != null) ...[
          const SizedBox(height: 4),
          Text(
            warningText,
            style: TextStyle(
              color: barColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
