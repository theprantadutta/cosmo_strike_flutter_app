enum Direction {
  up,
  down,
  left,
  right;

  Direction get opposite {
    switch (this) {
      case Direction.up:
        return Direction.down;
      case Direction.down:
        return Direction.up;
      case Direction.left:
        return Direction.right;
      case Direction.right:
        return Direction.left;
    }
  }

  bool get isHorizontal => this == Direction.left || this == Direction.right;
  bool get isVertical => this == Direction.up || this == Direction.down;
}
