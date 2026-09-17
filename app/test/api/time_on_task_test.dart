import 'package:akimath_app/api/time_on_task.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bound itself, at its edges.
///
/// `contract_parity_test.dart` is what holds [maxReportableTimeOnTask] to the
/// number in `contract/openapi.json`; this file is about the behaviour either
/// side of it, which the document cannot say.
void main() {
  group('a measurement inside the bound is the value that travels', () {
    test('an ordinary item, untouched', () {
      expect(
        reportableTimeOnTask(const Duration(seconds: 7, milliseconds: 400)),
        const Duration(seconds: 7, milliseconds: 400),
      );
    });

    test('zero, which is a real reading and not a missing one', () {
      expect(reportableTimeOnTask(Duration.zero), Duration.zero);
    });

    test('the last millisecond under the ceiling', () {
      final Duration justUnder =
          maxReportableTimeOnTask - const Duration(milliseconds: 1);

      expect(reportableTimeOnTask(justUnder), justUnder);
    });

    test('and the ceiling itself, which is admitted rather than clipped', () {
      expect(reportableTimeOnTask(maxReportableTimeOnTask), maxReportableTimeOnTask);
    });
  });

  group('a measurement outside it is brought in', () {
    test('one millisecond past the ceiling saturates', () {
      expect(
        reportableTimeOnTask(maxReportableTimeOnTask + const Duration(milliseconds: 1)),
        maxReportableTimeOnTask,
      );
    });

    test('an item left open for an afternoon saturates at the same value, '
        'neither scaled nor wrapped', () {
      expect(
        reportableTimeOnTask(const Duration(hours: 3, minutes: 20)),
        maxReportableTimeOnTask,
      );
    });

    test('a negative one floors at zero', () {
      expect(reportableTimeOnTask(const Duration(milliseconds: -1)), Duration.zero);
      expect(reportableTimeOnTask(const Duration(hours: -2)), Duration.zero);
    });
  });

  test('whatever a clock hands in, what comes out is inside the range the wire '
      'admits', () {
    const List<Duration> measured = <Duration>[
      Duration(hours: -9),
      Duration(milliseconds: -1),
      Duration.zero,
      Duration(seconds: 3),
      Duration(minutes: 59, seconds: 59, milliseconds: 999),
      Duration(hours: 1),
      Duration(hours: 1, milliseconds: 1),
      Duration(days: 4),
    ];

    for (final Duration one in measured) {
      final Duration sent = reportableTimeOnTask(one);

      expect(sent.isNegative, isFalse, reason: '$one');
      expect(sent, lessThanOrEqualTo(maxReportableTimeOnTask), reason: '$one');
    }
  });
}
