import 'package:masters/data/models/attribute_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttributeType.parse', () {
    test('text accepts any string', () {
      final type = AttributeType(
        key: 'color',
        valueType: 'text',
        entityType: 'item',
        label: 'Цвет',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('красный');
      expect(result, isNotNull);
      expect(result!.text, 'красный');
      expect(result.num, isNull);
    });

    test('text accepts empty → empty AttributeValue', () {
      final type = AttributeType(
        key: 'color',
        valueType: 'text',
        entityType: 'item',
        label: 'Цвет',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('');
      expect(result, isNotNull);
      expect(result!.isEmpty, true);
    });

    test('number parses integer', () {
      final type = AttributeType(
        key: 'weight',
        valueType: 'number',
        entityType: 'item',
        label: 'Вес, кг',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('5');
      expect(result, isNotNull);
      expect(result!.num, 5.0);
      expect(result.text, isNull);
    });

    test('number parses float with dot', () {
      final type = AttributeType(
        key: 'weight',
        valueType: 'number',
        entityType: 'item',
        label: 'Вес, кг',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('1.5');
      expect(result, isNotNull);
      expect(result!.num, 1.5);
    });

    test('number parses comma as decimal separator', () {
      final type = AttributeType(
        key: 'weight',
        valueType: 'number',
        entityType: 'item',
        label: 'Вес, кг',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('1,5');
      expect(result, isNotNull);
      expect(result!.num, 1.5);
      expect(result.display, '1,5');
    });

    test('number rejects non-numeric string', () {
      final type = AttributeType(
        key: 'weight',
        valueType: 'number',
        entityType: 'item',
        label: 'Вес, кг',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('полтора кг');
      expect(result, isNull);
    });

    test('number rejects text in numeric field', () {
      final type = AttributeType(
        key: 'quantity',
        valueType: 'number',
        entityType: 'item',
        label: 'Количество',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('abc');
      expect(result, isNull);
    });

    test('date accepts valid дд.мм.гггг', () {
      final type = AttributeType(
        key: 'due_date',
        valueType: 'date',
        entityType: 'job',
        label: 'Срок',
        createdAt: DateTime(2026, 1, 1),
      );
      final result = type.parse('07.11.2026');
      expect(result, isNotNull);
      expect(result!.text, '07.11.2026');
    });

    test('date rejects invalid дд.мм.гггг', () {
      final type = AttributeType(
        key: 'due_date',
        valueType: 'date',
        entityType: 'job',
        label: 'Срок',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(type.parse('07/11/2026'), isNull);
      expect(type.parse('7.11.2026'), isNull);
      expect(type.parse('32.11.2026'), isNull);
      expect(type.parse('07.13.2026'), isNull);
      expect(type.parse('текст'), isNull);
    });

    test('number rejects text → simulates setAttributeValue validation', () {
      final type = AttributeType(
        key: 'weight',
        valueType: 'number',
        entityType: 'item',
        label: 'Вес, кг',
        createdAt: DateTime(2026, 1, 1),
      );
      final parsed = type.parse('не число');
      expect(parsed, isNull);
    });
  });
}
