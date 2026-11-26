import 'dart:math';

import 'package:intl/intl.dart';

String newId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  // 48 bits of timestamp keep the id sortable across devices.
  final timestamp = now & ((1 << 48) - 1);
  final random = Random.secure();
  String hex(int value, int width) =>
      value.toRadixString(16).padLeft(width, '0').substring(0, width);

  final part1 = (timestamp >> 16) & 0xFFFFFFFF;
  final part2 = timestamp & 0xFFFF;
  final randomA = random.nextInt(0x1000) & 0xFFF;
  final randomB = random.nextInt(0x8000) & 0x7FFF;
  final tail = List.generate(
    14,
    (_) => random.nextInt(16),
  ).map((v) => v.toRadixString(16)).join();
  return '${hex(part1, 8)}-${hex(part2, 4)}-7${hex(randomA, 3)}-'
      '${hex((randomB & 0x3FFF) | 0x8000, 4)}-$tail';
}

String formatMinutes(int minutes) {
  if (minutes <= 0) return '0 мин';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest мин';
  if (rest == 0) return '$hours ч';
  return '$hours ч $rest мин';
}

String pluralRu(int value, List<String> forms) {
  final abs = value.abs() % 100;
  if (abs >= 11 && abs <= 14) return forms[2];

  switch (abs % 10) {
    case 1:
      return forms[0];
    case 2:
    case 3:
    case 4:
      return forms[1];
    default:
      return forms[2];
  }
}

String booksWord(int value) => pluralRu(value, ['книга', 'книги', 'книг']);
String pagesWord(int value) =>
    pluralRu(value, ['страница', 'страницы', 'страниц']);
String sessionsWord(int value) =>
    pluralRu(value, ['сессия', 'сессии', 'сессий']);
String daysWord(int value) => pluralRu(value, ['день', 'дня', 'дней']);

String cardsWord(int value) =>
    pluralRu(value, ['карточка', 'карточки', 'карточек']);
String visitsWord(int value) => pluralRu(value, ['визит', 'визита', 'визитов']);
String ordersWord(int value) => pluralRu(value, ['заказ', 'заказа', 'заказов']);
String itemsWord(int value) =>
    pluralRu(value, ['позиция', 'позиции', 'позиций']);
String peopleWord(int value) =>
    pluralRu(value, ['человек', 'человека', 'человек']);
String eventsWord(int value) =>
    pluralRu(value, ['событие', 'события', 'событий']);
String objectsWord(int value) =>
    pluralRu(value, ['объект', 'объекта', 'объектов']);
String recordsWord(int value) =>
    pluralRu(value, ['запись', 'записи', 'записей']);
String operationsWord(int value) =>
    pluralRu(value, ['операция', 'операции', 'операций']);
String accountsWord(int value) => pluralRu(value, ['счёт', 'счёта', 'счетов']);
String suppliersWord(int value) =>
    pluralRu(value, ['поставщик', 'поставщика', 'поставщиков']);
String clientsWord(int value) =>
    pluralRu(value, ['клиент', 'клиента', 'клиентов']);
String employeesWord(int value) =>
    pluralRu(value, ['сотрудник', 'сотрудника', 'сотрудников']);
String minutesWord(int value) => pluralRu(value, ['минута', 'минуты', 'минут']);

/// «2 карточки», «5 заказов» — число вместе с правильной формой слова.
String countLabel(int value, List<String> forms) =>
    '${formatNumber(value)} ${pluralRu(value, forms)}';

DateTime? parseDateOrNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().replaceAll('/', '-');
  return DateTime.tryParse(normalized);
}

String formatDay(DateTime date) => DateFormat('d MMM', 'ru').format(date);

String formatFullDate(DateTime date) =>
    DateFormat('d MMMM y', 'ru').format(date);

String formatMonthShort(int month) =>
    DateFormat('LLL', 'ru').format(DateTime(2020, month)).replaceAll('.', '');

String formatNumber(num value) =>
    NumberFormat.decimalPattern('ru').format(value);

String formatIsoDay(DateTime? date) =>
    date == null ? '' : DateFormat('yyyy-MM-dd').format(date);

String dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

String pluralShelfCount(int count) =>
    '${formatNumber(count)} ${booksWord(count)}';

double clamp01(double value) => value.clamp(0.0, 1.0);

int clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

String timerLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
