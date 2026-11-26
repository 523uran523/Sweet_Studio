import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'money_format.dart';

// Тексты напоминаний об оплате (§Э2.1).
//
// Смысл этапа в том, чтобы мастер отправлял должнику вменяемое сообщение за
// один тап, не связываясь с API мессенджеров: приложение только готовит
// текст и отдаёт его системному share (или кладёт в буфер обмена).
//
// Генерация вынесена из виджетов сюда, чтобы формулировку можно было
// зафиксировать тестом без поднятия UI.

/// Куда текст ушёл из интерфейса.
enum ReminderShareResult { shared, copied, failed }

/// Сообщение о доплате по заказу.
///
/// [paymentMethod] — ключ из `kPaymentMethods`; без него фраза про перевод
/// не добавляется: выдумывать реквизиты хуже, чем промолчать.
String paymentReminderText({
  required String clientName,
  required String jobTitle,
  required int remainingCents,
  required DateTime dueAt,
  String? paymentMethod,
  Map<String, String>? paymentMethodLabels,
}) {
  final name = clientName.trim().isEmpty ? 'друг' : clientName.trim();
  final methodLabel = paymentMethod == null || paymentMethod.trim().isEmpty
      ? null
      : (paymentMethodLabels?[paymentMethod] ?? paymentMethod).trim();

  final buffer = StringBuffer()
    ..writeln('$name, добрый день!')
    ..writeln(
      'По вашему заказу «${jobTitle.trim()}» осталась доплата '
      '${money(remainingCents)} до '
      '${DateFormat('d MMMM yyyy', 'ru').format(dueAt)}.',
    );
  if (methodLabel != null && methodLabel.isNotEmpty) {
    buffer.writeln('Если удобно, можете перевести на $methodLabel.');
  }
  buffer.write('Спасибо!');
  return buffer.toString();
}

/// Сообщение о просроченном шаге по заявке (§Э3, та же механика).
String leadFollowUpText({
  required String clientName,
  required String leadTitle,
  required DateTime nextStepAt,
}) {
  final name = clientName.trim().isEmpty ? 'друг' : clientName.trim();
  return '$name, добрый день! Возвращаюсь к вам по «${leadTitle.trim()}» — '
      'договаривались вернуться ${DateFormat('d MMMM yyyy', 'ru').format(nextStepAt)}. '
      'Подскажите, актуально ли ещё?';
}

/// Отдаёт текст системному share; при недоступности — в буфер обмена.
///
/// На web и эмуляторе `Share.share` бросает исключение, поэтому запасной
/// путь с буфером — не косметика, а основной сценарий для этих платформ.
/// Вызывающая сторона по результату показывает подсказку пользователю.
Future<ReminderShareResult> shareReminderText(String text) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text));
    return ReminderShareResult.shared;
  } catch (_) {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ReminderShareResult.copied;
    } catch (_) {
      return ReminderShareResult.failed;
    }
  }
}
