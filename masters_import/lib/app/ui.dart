import 'package:flutter/cupertino.dart';

import 'theme/app_theme.dart';

/// A soft, rounded surface used instead of Material cards.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final surface = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? colors.card,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return surface;

    // CupertinoButton would repaint every descendant with the theme accent,
    // which turned card titles blue. A press effect of our own keeps the
    // typography intact.
    return _PressableSurface(onTap: onTap!, radius: radius, child: surface);
  }
}

class _PressableSurface extends StatefulWidget {
  const _PressableSurface({
    required this.onTap,
    required this.radius,
    required this.child,
  });

  final VoidCallback onTap;
  final double radius;
  final Widget child;

  @override
  State<_PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<_PressableSurface> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 110),
        opacity: _pressed ? 0.62 : 1,
        child: widget.child,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.75,
          color: context.colors.secondaryLabel,
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = enabled && onPressed != null;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.82,
      onPressed: active ? onPressed : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
        decoration: BoxDecoration(
          color: active ? colors.accent : colors.cardElevated,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 19,
                color: active ? const Color(0xFFFFFFFF) : colors.tertiaryLabel,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: active
                      ? const Color(0xFFFFFFFF)
                      : colors.tertiaryLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.dense = false,
    this.alignment = MainAxisAlignment.center,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;

  /// Уменьшенная версия: ниже по высоте и мельче шрифт. Используется там,
  /// где действия стоят рядом и не должны занимать полстроки.
  final bool dense;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconSize = dense ? 15.0 : 18.0;
    final fontSize = dense ? 14.0 : 16.0;
    final tone = destructive ? colors.red : colors.accent;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.7,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: dense ? 9 : 13,
          horizontal: dense ? 10 : 18,
        ),
        decoration: BoxDecoration(
          color: destructive
              ? colors.tint(colors.red, 0.10)
              : colors.cardElevated,
          borderRadius: BorderRadius.circular(dense ? 11 : 13),
        ),
        child: Row(
          mainAxisAlignment: alignment,
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: tone),
              SizedBox(width: dense ? 5 : 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка «подпись — значение» с гарантированным выравниванием: подпись
/// занимает свободное место и обрезается, значение всегда прижато вправо.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.emphasis = false,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasis;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2.5 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: dense ? 13 : 14.5,
                color: colors.secondaryLabel,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: dense ? 13.5 : 15,
                fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ?? colors.label,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

/// Компактная строка списка внутри карточки: иконка, заголовок, подпись и
/// шеврон. Заменяет простыню полноширинных кнопок.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.titleColor,
    this.subtitleColor,
    this.showChevron = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final Color? titleColor;
  final Color? subtitleColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 12,
        vertical: dense ? 7 : 10,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          if (leading == null && icon != null) ...[
            Icon(
              icon,
              size: dense ? 16 : 18,
              color: iconColor ?? colors.accent,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 14.5 : 16,
                    fontWeight: FontWeight.w500,
                    color: titleColor ?? colors.label,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 11.5 : 12.5,
                      color: subtitleColor ?? colors.secondaryLabel,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (showChevron)
            Icon(
              CupertinoIcons.chevron_right,
              size: 15,
              color: colors.tertiaryLabel,
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

/// Одна компактная кнопка-действие в ряду: иконка над подписью.
class MiniAction extends StatelessWidget {
  const MiniAction({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color ?? colors.accent;
    final enabled = onPressed != null;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.6,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: colors.cardElevated,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: enabled ? tint : colors.tertiaryLabel),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: enabled ? tint : colors.tertiaryLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Компактная кнопка-«пилюля»: иконка и подпись в одну строку. Используется
/// в рядах быстрых действий, где полноширинные кнопки выглядят тяжело.
class ChipButton extends StatelessWidget {
  const ChipButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color ?? colors.accent;
    final enabled = onPressed != null;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.6,
      minimumSize: const Size(0, 32),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: colors.tint(tint, enabled ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: enabled ? tint : colors.tertiaryLabel,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: enabled ? tint : colors.tertiaryLabel,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка «ещё»: открывает меню действий. Держит редкие действия вне
/// основного экрана, чтобы не растягивать его простынёй кнопок.
class OverflowMenuButton extends StatelessWidget {
  const OverflowMenuButton({
    super.key,
    required this.actions,
    this.title,
    this.icon = CupertinoIcons.ellipsis_circle,
    this.size = 22,
  });

  final List<CupertinoActionSheetAction> actions;
  final String? title;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size(size + 12, size + 12),
      onPressed: actions.isEmpty
          ? null
          : () => showCupertinoModalPopup<void>(
              context: context,
              builder: (sheetContext) => CupertinoActionSheet(
                title: title == null ? null : Text(title!),
                actions: actions,
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Отмена'),
                ),
              ),
            ),
      child: Icon(icon, size: size, color: context.colors.accent),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.height = 5,
    this.color,
    this.trackColor,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clamped = value.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: trackColor ?? colors.cardElevated,
            borderRadius: BorderRadius.circular(height),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: constraints.maxWidth * clamped,
              height: height,
              decoration: BoxDecoration(
                color: color ?? colors.accent,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        );
      },
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color ?? colors.secondaryLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: colors.tint(tint, 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tint,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0, this.color});

  final double indent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(height: 0.5, color: color ?? context.colors.separator),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.tint,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = tint ?? colors.accent;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: accent),
            const SizedBox(height: 10),
          ],
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: colors.label,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit != null) ...[
            const SizedBox(height: 1),
            Text(
              unit!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: colors.secondaryLabel),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.tertiaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 29,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(icon, size: size * 0.58, color: const Color(0xFFFFFFFF)),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 5,
      decoration: BoxDecoration(
        color: context.colors.tertiaryLabel.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.art,
    this.actions = const [],
  });

  final String title;
  final String message;
  final Widget? art;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (art != null) ...[art!, const SizedBox(height: 28)],
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: colors.label,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: colors.secondaryLabel,
            ),
          ),
          if (actions.isNotEmpty) ...[const SizedBox(height: 24), ...actions],
        ],
      ),
    );
  }
}

Future<void> showAppAlert(
  BuildContext context, {
  required String title,
  String? message,
}) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Хорошо'),
        ),
      ],
    ),
  );
}

Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Продолжить',
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// Способы оплаты для выбора в интерфейсе (§1.4).
const Map<String, String> kPaymentMethods = {
  'cash': 'Наличные',
  'kaspi': 'Kaspi',
  'card': 'Карта',
  'transfer': 'Перевод',
};

/// Показывает модалку выбора способа оплаты.
/// Возвращает выбранный ключ или `null` (пропуск).
Future<String?> showPaymentMethodPicker(BuildContext context) {
  final colors = context.colors;
  return showCupertinoModalPopup<String?>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (builderContext, setModalState) {
        return Container(
          height: 200,
          color: builderContext.colors.card,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Отмена'),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                  Text(
                    'Способ оплаты',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: builderContext.colors.label,
                    ),
                  ),
                  CupertinoButton(
                    child: const Text('Пропустить'),
                    onPressed: () => Navigator.of(sheetContext).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in kPaymentMethods.entries)
                        ChipButton(
                          label: entry.value,
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(entry.key),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
