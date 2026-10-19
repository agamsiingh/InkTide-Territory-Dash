import 'dart:typed_data';

/// Grid of cells. Each cell has an owner (0 = unclaimed, otherwise a player
/// id 1..[maxPlayers]) and a trail mark (0 = none, otherwise the id of the
/// player whose trail crosses it).
class Arena {
  Arena(this.width, this.height)
      : owner = Uint8List(width * height),
        trail = Uint8List(width * height),
        _stamp = Uint32List(width * height),
        _queue = Int32List(width * height) {
    counts[0] = width * height;
  }

  static const int maxPlayers = 16;

  final int width;
  final int height;
  final Uint8List owner;
  final Uint8List trail;

  /// Cells owned per player id (index 0 = unclaimed cells).
  final Int32List counts = Int32List(maxPlayers + 1);

  /// Bumped whenever ownership changes, so renderers can cache.
  int version = 0;

  /// When non-null, every changed cell index is appended here (the server
  /// drains it to send small updates instead of the whole grid).
  List<int>? changeLog;

  final Uint32List _stamp;
  final Int32List _queue;
  int _stampValue = 0;

  int get cellCount => width * height;

  void reset() {
    // Network clients get told which cells emptied.
    final log = changeLog;
    if (log != null) {
      for (var i = 0; i < owner.length; i++) {
        if (owner[i] != 0) log.add(i);
      }
    }
    owner.fillRange(0, owner.length, 0);
    trail.fillRange(0, trail.length, 0);
    counts.fillRange(0, counts.length, 0);
    counts[0] = cellCount;
    version++;
  }

  /// Replaces the whole ownership grid (a client receiving the full arena).
  /// Cells with an owner above [maxPlayers] are treated as unclaimed.
  void loadOwners(List<int> data) {
    counts.fillRange(0, counts.length, 0);
    for (var i = 0; i < owner.length; i++) {
      final o = i < data.length && data[i] <= maxPlayers ? data[i] : 0;
      owner[i] = o;
      counts[o]++;
    }
    trail.fillRange(0, trail.length, 0);
    version++;
  }

  int index(int x, int y) => y * width + x;
  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  void setOwner(int idx, int id) {
    final prev = owner[idx];
    if (prev == id) return;
    counts[prev]--;
    counts[id]++;
    owner[idx] = id;
    changeLog?.add(idx);
    version++;
  }

  double percentOf(int id) => counts[id] * 100.0 / cellCount;

  /// Claims a filled disc for [id] (used for spawn territory).
  void claimDisc(double cx, double cy, double r, int id) {
    final x0 = (cx - r).floor(), x1 = (cx + r).ceil();
    final y0 = (cy - r).floor(), y1 = (cy + r).ceil();
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (!inBounds(x, y)) continue;
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        if (dx * dx + dy * dy <= r * r) setOwner(index(x, y), id);
      }
    }
  }

  /// Removes all territory belonging to [id]. Returns cells released.
  int releaseAll(int id) {
    if (counts[id] == 0) return 0;
    var n = 0;
    for (var i = 0; i < owner.length; i++) {
      if (owner[i] == id) {
        setOwner(i, 0);
        n++;
      }
    }
    return n;
  }

  /// Hands every cell of [from] over to [to]. Returns the cells moved.
  int transferAll(int from, int to) {
    if (from == to || counts[from] == 0) return 0;
    var n = 0;
    for (var i = 0; i < owner.length; i++) {
      if (owner[i] == from) {
        setOwner(i, to);
        n++;
      }
    }
    return n;
  }

  /// Converts [trailCells] of player [id] to territory and fills every region
  /// fully enclosed by [id]'s territory. Returns the number of newly owned
  /// cells (trail cells included).
  int capture(int id, List<int> trailCells) {
    var gained = 0;
    for (final idx in trailCells) {
      if (trail[idx] == id) trail[idx] = 0;
      if (owner[idx] != id) {
        setOwner(idx, id);
        gained++;
      }
    }
    // Flood fill from the border through cells not owned by [id]. Anything
    // not reached is enclosed by [id]'s territory.
    _stampValue++;
    if (_stampValue == 0xFFFFFFFF) {
      _stamp.fillRange(0, _stamp.length, 0);
      _stampValue = 1;
    }
    final s = _stampValue;
    var head = 0, tail = 0;
    void seed(int idx) {
      if (owner[idx] != id && _stamp[idx] != s) {
        _stamp[idx] = s;
        _queue[tail++] = idx;
      }
    }

    for (var x = 0; x < width; x++) {
      seed(index(x, 0));
      seed(index(x, height - 1));
    }
    for (var y = 0; y < height; y++) {
      seed(index(0, y));
      seed(index(width - 1, y));
    }
    while (head < tail) {
      final idx = _queue[head++];
      final x = idx % width, y = idx ~/ width;
      if (x > 0) seed(idx - 1);
      if (x < width - 1) seed(idx + 1);
      if (y > 0) seed(idx - width);
      if (y < height - 1) seed(idx + width);
    }
    for (var i = 0; i < owner.length; i++) {
      if (owner[i] != id && _stamp[i] != s) {
        setOwner(i, id);
        gained++;
      }
    }
    return gained;
  }

  /// Removes the trail marks of [id] listed in [trailCells].
  void clearTrail(int id, List<int> trailCells) {
    for (final idx in trailCells) {
      if (trail[idx] == id) trail[idx] = 0;
    }
  }
}
