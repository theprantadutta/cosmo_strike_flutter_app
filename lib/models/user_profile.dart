import 'dart:convert';

enum UserStatus {
  online,
  offline,
  playing;

  String get displayName {
    switch (this) {
      case UserStatus.online:
        return 'Online';
      case UserStatus.offline:
        return 'Offline';
      case UserStatus.playing:
        return 'Playing';
    }
  }

  String get emoji {
    switch (this) {
      case UserStatus.online:
        return '🟢';
      case UserStatus.offline:
        return '⚫';
      case UserStatus.playing:
        return '🎮';
    }
  }
}

class UserProfile {
  final String uid;
  final String displayName;
  final String username; // Unique username for user identification
  final String email;
  final String? photoUrl;
  final int highScore;
  final int totalGamesPlayed;
  final int level;
  final DateTime joinedDate;
  final DateTime lastSeen;
  final UserStatus status;
  final List<String> friends;
  final List<String> friendRequests; // Received friend requests
  final List<String> sentRequests; // Sent friend requests
  final Map<String, dynamic> gameStats;
  final bool isPublic; // Whether profile is visible to others
  final String? statusMessage; // Custom status message

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.email,
    this.photoUrl,
    this.highScore = 0,
    this.totalGamesPlayed = 0,
    this.level = 1,
    required this.joinedDate,
    required this.lastSeen,
    this.status = UserStatus.offline,
    this.friends = const [],
    this.friendRequests = const [],
    this.sentRequests = const [],
    this.gameStats = const {},
    this.isPublic = true,
    this.statusMessage,
  });

  /// The label to surface in lists, leaderboards, and friend rows.
  /// Prefers the (now backend-backfilled) username; falls back to the
  /// display name; finally 'Anonymous' if both are empty.
  String get publicLabel {
    if (username.isNotEmpty && username != 'Anonymous') return username;
    if (displayName.isNotEmpty && displayName != 'Anonymous') return displayName;
    return 'Anonymous';
  }

  UserProfile copyWith({
    String? uid,
    String? displayName,
    String? username,
    String? email,
    String? photoUrl,
    int? highScore,
    int? totalGamesPlayed,
    int? level,
    DateTime? joinedDate,
    DateTime? lastSeen,
    UserStatus? status,
    List<String>? friends,
    List<String>? friendRequests,
    List<String>? sentRequests,
    Map<String, dynamic>? gameStats,
    bool? isPublic,
    String? statusMessage,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      highScore: highScore ?? this.highScore,
      totalGamesPlayed: totalGamesPlayed ?? this.totalGamesPlayed,
      level: level ?? this.level,
      joinedDate: joinedDate ?? this.joinedDate,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      friends: friends ?? this.friends,
      friendRequests: friendRequests ?? this.friendRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      gameStats: gameStats ?? this.gameStats,
      isPublic: isPublic ?? this.isPublic,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'displayName': displayName,
      'username': username,
      'email': email,
      'photoUrl': photoUrl,
      'highScore': highScore,
      'totalGamesPlayed': totalGamesPlayed,
      'level': level,
      'joinedDate': joinedDate.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'status': status.name,
      'friends': friends,
      'friendRequests': friendRequests,
      'sentRequests': sentRequests,
      'gameStats': gameStats,
      'isPublic': isPublic,
      'statusMessage': statusMessage,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'] ?? '',
      displayName: json['displayName'] ?? '',
      username:
          json['username'] ??
          json['displayName'] ??
          'Player', // Fallback to displayName for existing users
      email: json['email'] ?? '',
      photoUrl: json['photoUrl'],
      highScore: json['highScore'] ?? 0,
      totalGamesPlayed: json['totalGamesPlayed'] ?? 0,
      level: json['level'] ?? 1,
      joinedDate: DateTime.parse(
        json['joinedDate'] ?? DateTime.now().toIso8601String(),
      ),
      lastSeen: DateTime.parse(
        json['lastSeen'] ?? DateTime.now().toIso8601String(),
      ),
      status: UserStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => UserStatus.offline,
      ),
      friends: List<String>.from(json['friends'] ?? []),
      friendRequests: List<String>.from(json['friendRequests'] ?? []),
      sentRequests: List<String>.from(json['sentRequests'] ?? []),
      gameStats: Map<String, dynamic>.from(json['gameStats'] ?? {}),
      isPublic: json['isPublic'] ?? true,
      statusMessage: json['statusMessage'],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory UserProfile.fromJsonString(String jsonString) {
    return UserProfile.fromJson(jsonDecode(jsonString));
  }

  // Helper methods
  bool isFriend(String userId) => friends.contains(userId);
  bool hasSentRequestTo(String userId) => sentRequests.contains(userId);
  bool hasRequestFrom(String userId) => friendRequests.contains(userId);

  String get formattedJoinDate {
    final now = DateTime.now();
    final difference = now.difference(joinedDate);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '${years}y ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return 'Just now';
    }
  }

  String get formattedLastSeen {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (status == UserStatus.online) return 'Online now';
    if (status == UserStatus.playing) return 'Playing now';

    if (difference.inDays > 0) {
      return 'Last seen ${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return 'Last seen ${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return 'Last seen ${difference.inMinutes}m ago';
    } else {
      return 'Last seen just now';
    }
  }

  int get friendsCount => friends.length;
  int get pendingRequestsCount => friendRequests.length;
}

enum FriendRequestType { sent, received }

class FriendRequest {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String fromUserName;
  final String toUserName;
  final String? fromUserPhotoUrl;
  final DateTime createdAt;
  final FriendRequestType type;

  const FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUserName,
    required this.toUserName,
    this.fromUserPhotoUrl,
    required this.createdAt,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'fromUserName': fromUserName,
      'toUserName': toUserName,
      'fromUserPhotoUrl': fromUserPhotoUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FriendRequest.fromJson(
    Map<String, dynamic> json,
    FriendRequestType type,
  ) {
    return FriendRequest(
      id: json['id'] ?? '',
      fromUserId: json['fromUserId'] ?? '',
      toUserId: json['toUserId'] ?? '',
      fromUserName: json['fromUserName'] ?? '',
      toUserName: json['toUserName'] ?? '',
      fromUserPhotoUrl: json['fromUserPhotoUrl'],
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      type: type,
    );
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
