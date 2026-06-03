import 'package:flutter_test/flutter_test.dart';
import 'package:vox_atc_demo/services/command_parser.dart';

// Placeholder — logic to be implemented in Phase 3.
void main() {
  group(
    'CommandParser.parse',
    () {
      test('parses taxi instruction', () {
        const input = 'SVA123 taxi via alpha hold short runway 34 left';

        final result = CommandParser.parse(input);

        expect(result, isNotNull);
        expect(result!.callsign, 'SVA123');
        expect(result.action, 'taxi');
      });

      test('parses hold position instruction', () {
        const input = 'Gulf Air 387 hold position';

        final result = CommandParser.parse(input);

        expect(result, isNotNull);
        expect(result!.callsign, 'GFA387');
        expect(result.action, 'hold_position');
      });

      test('parses pushback instruction', () {
        const input = 'Emirates 671 pushback approved facing south';

        final result = CommandParser.parse(input);

        expect(result, isNotNull);
        expect(result!.callsign, 'UAE671');
        expect(result.action, 'pushback');
      });
    },
    skip: 'Phase 3 — Command Parser not implemented yet',
  );
}
