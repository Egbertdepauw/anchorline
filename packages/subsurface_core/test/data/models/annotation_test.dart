import 'package:subsurface_core/data/models/annotation.dart';
import 'package:test/test.dart';

void main() {
  final t = DateTime.utc(2026, 11, 2);
  final a = DiveAnnotation(
    diveId: 'd',
    notes: 'hello',
    rating: 3,
    siteName: 'Om Sid',
    createdAt: t,
    updatedAt: t,
  );

  test('copyWith() keeps every field', () {
    final b = a.copyWith();
    expect(b.notes, 'hello');
    expect(b.rating, 3);
    expect(b.siteName, 'Om Sid');
  });

  test('Patch(null) clears a field', () {
    expect(a.copyWith(notes: const Patch(null)).notes, isNull);
    expect(a.copyWith(siteName: const Patch(null)).siteName, isNull);
  });

  test('Patch(value) sets a field and leaves the others alone', () {
    final b = a.copyWith(rating: const Patch(5));
    expect(b.rating, 5);
    expect(b.notes, 'hello');
  });
}
