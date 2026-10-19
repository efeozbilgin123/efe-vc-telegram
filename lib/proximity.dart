import 'dart:math' as math;

class VoicePosition {
  const VoicePosition(this.x, this.y, this.z, this.dimension, this.receivedAt);

  final double x;
  final double y;
  final double z;
  final String dimension;
  final DateTime receivedAt;

  static VoicePosition? fromJson(Object? payload, {DateTime? now}) {
    if (payload is! Map) return null;
    double? number(Object? v) {
      if (v is! num) return null;
      final f = v.toDouble();
      return f.isFinite && f.abs() <= 30000000 ? f : null;
    }

    final x = number(payload['x']);
    final y = number(payload['y']);
    final z = number(payload['z']);
    final dimension = payload['dimension'];
    if (x == null || y == null || z == null ||
        dimension is! String || dimension.length > 96 || dimension.isEmpty) {
      return null;
    }
    return VoicePosition(x, y, z, dimension, now ?? DateTime.now());
  }

  Map<String, Object> toJson() => {
    'v': 1,
    'x': x,
    'y': y,
    'z': z,
    'dimension': dimension,
  };

  bool isFresh(DateTime now, {Duration ttl = const Duration(seconds: 5)}) =>
      now.difference(receivedAt).abs() <= ttl;

  double? distanceTo(VoicePosition other) {
    if (dimension != other.dimension) return null;
    final dx = x - other.x, dy = y - other.y, dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

bool shouldHear(VoicePosition? me, VoicePosition? other,
    {required double radius, DateTime? now}) {
  if (me == null || other == null || !radius.isFinite || radius <= 0) {
    return false;
  }
  final instant = now ?? DateTime.now();
  if (!me.isFresh(instant) || !other.isFresh(instant)) return false;
  final distance = me.distanceTo(other);
  return distance != null && distance <= radius;
}
