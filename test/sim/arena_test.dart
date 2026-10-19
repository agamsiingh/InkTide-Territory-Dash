import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/arena.dart';

/// Fresh arena with consistent counters (counts[0] == cellCount).
Arena newArena(int w, int h) => Arena(w, h)..reset();

/// Marks [cells] (x, y pairs) as trail of [id] and returns their indices.
List<int> layTrail(Arena a, int id, List<(int, int)> cells) {
  final out = <int>[];
  for (final (x, y) in cells) {
    final i = a.index(x, y);
    a.trail[i] = id;
    out.add(i);
  }
  return out;
}

void own(Arena a, int id, List<(int, int)> cells) {
  for (final (x, y) in cells) {
    a.setOwner(a.index(x, y), id);
  }
}

int sumCounts(Arena a) => a.counts.fold(0, (s, c) => s + c);

int countOwned(Arena a, int id) => a.owner.where((o) => o == id).length;

void expectConsistent(Arena a) {
  expect(sumCounts(a), a.cellCount, reason: 'sum of counts must equal cellCount');
  for (var id = 0; id <= Arena.maxPlayers; id++) {
    expect(a.counts[id], countOwned(a, id), reason: 'counts[$id] out of sync with owner grid');
  }
}

void main() {
  group('Arena basics', () {
    test('reset makes every cell unclaimed and counts consistent', () {
      final a = newArena(12, 8);
      expect(a.cellCount, 96);
      expect(a.counts[0], 96);
      expect(a.owner.every((o) => o == 0), isTrue);
      expect(a.trail.every((t) => t == 0), isTrue);
      expectConsistent(a);
    });

    test('index / inBounds', () {
      final a = newArena(10, 5);
      expect(a.index(0, 0), 0);
      expect(a.index(3, 2), 23);
      expect(a.inBounds(9, 4), isTrue);
      expect(a.inBounds(10, 4), isFalse);
      expect(a.inBounds(-1, 0), isFalse);
      expect(a.inBounds(0, 5), isFalse);
    });

    test('setOwner updates counts, percent and version', () {
      final a = newArena(10, 10);
      final v0 = a.version;
      a.setOwner(a.index(1, 1), 3);
      a.setOwner(a.index(2, 1), 3);
      expect(a.counts[3], 2);
      expect(a.percentOf(3), closeTo(2.0, 1e-9));
      expect(a.version, greaterThan(v0));
      final v1 = a.version;
      a.setOwner(a.index(1, 1), 3); // no-op
      expect(a.version, v1);
      expectConsistent(a);
    });
  });

  group('claimDisc', () {
    test('r=2.6 disc at a cell centre claims 21 cells', () {
      final a = newArena(20, 20);
      a.claimDisc(10.5, 10.5, 2.6, 1);
      expect(a.counts[1], 21);
      expect(a.owner[a.index(10, 10)], 1);
      expect(a.owner[a.index(12, 11)], 1);
      expect(a.owner[a.index(12, 12)], 0); // corner outside radius
      expectConsistent(a);
    });

    test('disc is clipped at the arena edge', () {
      final a = newArena(20, 20);
      a.claimDisc(0.5, 0.5, 2.6, 2);
      expect(a.counts[2], 8);
      expectConsistent(a);
    });

    test('disc overwrites other owners and keeps counts consistent', () {
      final a = newArena(20, 20);
      a.claimDisc(10.5, 10.5, 2.6, 1);
      a.claimDisc(12.5, 10.5, 2.6, 2);
      expect(a.counts[1] + a.counts[2], lessThan(42));
      expect(a.owner[a.index(12, 10)], 2);
      expectConsistent(a);
    });
  });

  group('capture', () {
    test('U-shaped trail from own territory fills the enclosed pocket', () {
      final a = newArena(10, 10);
      own(a, 1, [for (var x = 2; x <= 6; x++) (x, 2)]);
      final trail = layTrail(a, 1, [
        (2, 3), (2, 4), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (6, 4), (6, 3),
      ]);
      final gained = a.capture(1, trail);
      expect(gained, 9 + 6, reason: '9 trail cells + 3x2 interior');
      expect(a.counts[1], 5 + 15);
      for (var y = 3; y <= 4; y++) {
        for (var x = 3; x <= 5; x++) {
          expect(a.owner[a.index(x, y)], 1, reason: 'interior ($x,$y)');
        }
      }
      expect(a.owner[a.index(7, 4)], 0);
      expect(a.owner[a.index(4, 6)], 0);
      expect(a.trail.every((t) => t == 0), isTrue);
      expectConsistent(a);
    });

    test('loop that runs along the arena border encloses the inside', () {
      final a = newArena(10, 10);
      own(a, 1, [for (var y = 0; y < 10; y++) (0, y)]);
      own(a, 1, [for (var y = 0; y < 10; y++) (4, y)]);
      // Trail along the top and bottom rows (border cells) between the walls.
      final trail = layTrail(a, 1, [
        for (var x = 1; x <= 3; x++) (x, 0),
        for (var x = 1; x <= 3; x++) (x, 9),
      ]);
      final gained = a.capture(1, trail);
      expect(gained, 6 + 3 * 8);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x <= 4; x++) {
          expect(a.owner[a.index(x, y)], 1);
        }
        for (var x = 5; x < 10; x++) {
          expect(a.owner[a.index(x, y)], 0, reason: 'outside ($x,$y) must stay free');
        }
      }
      expectConsistent(a);
    });

    test('arena border is not a wall: open side is not captured', () {
      final a = newArena(10, 10);
      own(a, 1, [for (var x = 0; x < 10; x++) (x, 0)]);
      // Straight trail from the owned top row down to the bottom border.
      final trail = layTrail(a, 1, [for (var y = 1; y < 10; y++) (5, y)]);
      final gained = a.capture(1, trail);
      expect(gained, 9, reason: 'only trail cells; both halves touch the border');
      expect(a.owner[a.index(2, 5)], 0);
      expect(a.owner[a.index(8, 5)], 0);
      expectConsistent(a);
    });

    test('U against the border plus own territory corner closes a loop', () {
      final a = newArena(10, 10);
      own(a, 1, [for (var x = 0; x <= 4; x++) (x, 0)]);
      final trail = layTrail(a, 1, [
        (0, 1), (0, 2), (0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (4, 2), (4, 1),
      ]);
      final gained = a.capture(1, trail);
      expect(gained, 9 + 6);
      expect(a.owner[a.index(2, 2)], 1);
      expect(a.owner[a.index(5, 1)], 0);
      expectConsistent(a);
    });

    test('capture takes cells from another owner (trail and enclosed)', () {
      final a = newArena(10, 10);
      own(a, 1, [for (var x = 2; x <= 6; x++) (x, 2)]);
      own(a, 2, [(4, 4), (3, 3), (4, 5), (8, 8)]); // (4,5) lies on the trail path
      final before2 = a.counts[2];
      final trail = layTrail(a, 1, [
        (2, 3), (2, 4), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (6, 4), (6, 3),
      ]);
      final gained = a.capture(1, trail);
      expect(gained, 15);
      expect(a.owner[a.index(4, 4)], 1);
      expect(a.owner[a.index(3, 3)], 1);
      expect(a.owner[a.index(4, 5)], 1);
      expect(a.owner[a.index(8, 8)], 2, reason: 'cells outside the loop stay');
      expect(a.counts[2], before2 - 3);
      expectConsistent(a);
    });

    test('repeated captures only count newly owned cells', () {
      final a = newArena(12, 12);
      own(a, 1, [for (var x = 2; x <= 6; x++) (x, 2)]);
      final t1 = layTrail(a, 1, [
        (2, 3), (2, 4), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (6, 4), (6, 3),
      ]);
      expect(a.capture(1, t1), 15);
      final afterFirst = a.counts[1];
      // Capturing again with an empty trail gains nothing.
      expect(a.capture(1, const []), 0);
      expect(a.counts[1], afterFirst);
      // A second loop extending the block to the right.
      final t2 = layTrail(a, 1, [
        (7, 2), (8, 2), (9, 2), (9, 3), (9, 4), (9, 5), (8, 5), (7, 5),
      ]);
      final gained2 = a.capture(1, t2);
      expect(gained2, 8 + 4, reason: '8 trail + (7..8, 3..4) interior');
      expect(a.counts[1], afterFirst + gained2);
      // Re-capturing already owned cells gains nothing.
      expect(a.capture(1, [a.index(3, 3), a.index(8, 4)]), 0);
      expectConsistent(a);
    });

    test('capture leaves other players trail marks intact', () {
      final a = newArena(10, 10);
      own(a, 1, [for (var x = 2; x <= 6; x++) (x, 2)]);
      a.trail[a.index(4, 4)] = 2;
      final trail = layTrail(a, 1, [
        (2, 3), (2, 4), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (6, 4), (6, 3),
      ]);
      a.capture(1, trail);
      expect(a.trail[a.index(4, 4)], 2);
      expect(a.owner[a.index(4, 4)], 1);
    });

    test('percent matches counts after a capture', () {
      final a = newArena(20, 20);
      a.claimDisc(10.5, 10.5, 2.6, 1);
      final trail = layTrail(a, 1, [
        for (var x = 13; x <= 15; x++) (x, 10),
        (15, 11), (15, 12), (15, 13),
        for (var x = 14; x >= 10; x--) (x, 13),
      ]);
      a.capture(1, trail);
      expect(a.percentOf(1), closeTo(a.counts[1] * 100 / 400, 1e-9));
      expectConsistent(a);
    });
  });

  group('releaseAll / clearTrail', () {
    test('releaseAll frees every cell of a player', () {
      final a = newArena(20, 20);
      a.claimDisc(5.5, 5.5, 2.6, 1);
      a.claimDisc(14.5, 14.5, 2.6, 2);
      final released = a.releaseAll(1);
      expect(released, 21);
      expect(a.counts[1], 0);
      expect(a.counts[2], 21);
      expect(a.counts[0], 400 - 21);
      expect(a.owner.contains(1), isFalse);
      expectConsistent(a);
    });

    test('releaseAll on a player without cells is a no-op', () {
      final a = newArena(10, 10);
      final v = a.version;
      expect(a.releaseAll(5), 0);
      expect(a.version, v);
    });

    test('clearTrail only removes marks of the given id', () {
      final a = newArena(10, 10);
      final mine = layTrail(a, 1, [(1, 1), (2, 1), (3, 1)]);
      layTrail(a, 2, [(5, 5)]);
      // A cell listed for player 1 that is now marked by player 2.
      a.trail[a.index(3, 1)] = 2;
      a.clearTrail(1, mine);
      expect(a.trail[a.index(1, 1)], 0);
      expect(a.trail[a.index(2, 1)], 0);
      expect(a.trail[a.index(3, 1)], 2);
      expect(a.trail[a.index(5, 5)], 2);
    });
  });
}
