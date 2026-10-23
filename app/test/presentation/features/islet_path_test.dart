import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/presentation/features/island/islet_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const states = [
    NodeState.done,
    NodeState.done,
    NodeState.current,
    NodeState.open,
    NodeState.locked,
  ];
  // Cut after the current lesson, as the screen does round its card.
  const above = IsletRun(states, first: 0, end: 3, top: 76, bottom: 16);
  const below = IsletRun(states, first: 3, end: 5, top: 70, bottom: 52);

  test('one constant step, the columns taking turns', () {
    expect(above.centre(0, 390), const Offset(91, 76));
    expect(above.centre(1, 390) - above.centre(0, 390), const Offset(208, 104));
    expect(
      above.centre(2, 390) - above.centre(1, 390),
      const Offset(-208, 104),
    );
    expect(
      below.centre(4, 390) - below.centre(3, 390),
      const Offset(-208, 104),
    );
  });

  test('the zig-zag carries on below the card', () {
    expect(below.centre(3, 390), const Offset(299, 70));
    expect(below.centre(3, 360).dx - above.centre(2, 360).dx, 208);
  });

  test('a run holds its islets, their bases and the room below', () {
    expect(above.height, 76 + 2 * 104 + 50 + 16);
    expect(below.height, 70 + 104 + 50 + 52);
    const one = IsletRun(
      [NodeState.current],
      first: 0,
      end: 1,
      top: 76,
      bottom: 16,
    );
    expect(one.height, 76 + 50 + 16);
  });
}
