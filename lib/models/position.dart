import 'package:cosmo_strike_flutter_app/utils/direction.dart';

class Position {
  final int x;
  final int y;

  const Position(this.x, this.y);

  Position operator +(Position other) => Position(x + other.x, y + other.y);
  Position operator -(Position other) => Position(x - other.x, y - other.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  Position move(Direction direction) {
    switch (direction) {
      case Direction.up:
        return Position(x, y - 1);
      case Direction.down:
        return Position(x, y + 1);
      case Direction.left:
        return Position(x - 1, y);
      case Direction.right:
        return Position(x + 1, y);
    }
  }

  bool isWithinBounds(int width, int height) {
    return x >= 0 && x < width && y >= 0 && y < height;
  }

  @override
  String toString() => 'Position($x, $y)';

  // JSON serialization
  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y};
  }

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(json['x'] ?? 0, json['y'] ?? 0);
  }
}
