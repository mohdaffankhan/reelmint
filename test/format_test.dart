import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('minutes and seconds', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(const Duration(seconds: 7)), '00:07');
      expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12:05');
    });
    test('hours', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
    test('centiseconds', () {
      expect(
        formatDuration(
          const Duration(seconds: 3, milliseconds: 456),
          showMs: true,
        ),
        '00:03.45',
      );
    });
  });

  group('formatBytes', () {
    test('scales units', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('formatRelativeDate', () {
    test('today / yesterday / weekday / older', () {
      final now = DateTime.now();
      expect(
        formatRelativeDate(DateTime(now.year, now.month, now.day, 9, 5)),
        'Today, 9:05 AM',
      );
      final y = now.subtract(const Duration(days: 1));
      expect(
        formatRelativeDate(DateTime(y.year, y.month, y.day, 13, 0)),
        'Yesterday, 1:00 PM',
      );
      final w = now.subtract(const Duration(days: 3));
      expect(
        formatRelativeDate(DateTime(w.year, w.month, w.day, 0, 30)),
        matches(RegExp(r'^\w{3}, 12:30 AM$')),
      );
      expect(formatRelativeDate(DateTime(2001, 3, 4)), 'Mar 4 2001');
    });
  });

  group('resolutionLabel', () {
    test('uses the short edge', () {
      expect(resolutionLabel(0, 0), '—');
      expect(resolutionLabel(720, 1600), '720p');
      expect(resolutionLabel(2400, 1080), '1080p');
      expect(resolutionLabel(1440, 3200), '1440p');
      expect(resolutionLabel(2160, 3840), '4K');
      expect(resolutionLabel(480, 854), '480p');
      expect(resolutionLabel(360, 640), '360p');
    });
  });
}
