import 'dart:convert';

class UserProfile {
  final String name;
  final String email;
  final String? avatarUrl;
  final String authProvider; // 'google' or 'email' or 'guest'

  UserProfile({
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.authProvider,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'authProvider': authProvider,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      name: map['name'] as String? ?? 'User',
      email: map['email'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
      authProvider: map['authProvider'] as String? ?? 'email',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory UserProfile.fromJson(String source) =>
      UserProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

