class AppUser {
  const AppUser({
    required this.id,
    required this.nickname,
    required this.isAnonymous,
    this.avatarUrl,
  });

  final String id;
  final String nickname;
  final bool isAnonymous;
  final String? avatarUrl;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    nickname: json['nickname'] as String,
    isAnonymous: json['is_anonymous'] as bool? ?? true,
    avatarUrl: json['avatar_url'] as String?,
  );
}
