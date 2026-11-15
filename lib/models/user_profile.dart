class UserProfile {
  final String id;
  final String? fullName;
  final String? avatarUrl; // ← новое поле

  UserProfile({required this.id, this.fullName, this.avatarUrl});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'], // ← загрузка из БД
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'avatar_url': avatarUrl, // ← сохранение в БД
      };
}