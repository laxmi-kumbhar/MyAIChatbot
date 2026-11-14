import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class AuthService {
  static const String _userKey = 'current_user_profile';
  static const String _accountsDbKey = 'registered_accounts_db_v3';

  // Pre-registered accounts including owner Laxmi Kumbhar
  static final List<_RegisteredAccount> _seedAccounts = [
    _RegisteredAccount(
      name: 'Laxmi Kumbhar',
      email: 'laxmikumbhar589@gmail.com',
      password: 'password123',
      provider: 'email',
    ),
    _RegisteredAccount(
      name: 'Demo User',
      email: 'demo@gmail.com',
      password: 'password123',
      provider: 'email',
    ),
    _RegisteredAccount(
      name: 'Admin',
      email: 'admin@gmail.com',
      password: 'password123',
      provider: 'email',
    ),
  ];

  // Strict email regex matching valid standard email addresses
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  // Strict Gmail regex
  static final RegExp _gmailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@gmail\.com$',
    caseSensitive: false,
  );

  /// Validates standard email syntax
  static bool isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || trimmed.length > 254) return false;
    if (!trimmed.contains('.') || trimmed.contains('..') || trimmed.contains(' ')) {
      return false;
    }
    return _emailRegex.hasMatch(trimmed);
  }

  /// Validates specifically Gmail addresses
  static bool isValidGmail(String email) {
    final trimmed = email.trim();
    if (!isValidEmail(trimmed)) return false;
    return _gmailRegex.hasMatch(trimmed);
  }

  /// Get currently signed-in user from persistent storage
  Future<UserProfile?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_userKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        return UserProfile.fromJson(jsonStr);
      }
    } catch (_) {}
    return null;
  }

  /// Sign in with Google: requires a valid @gmail.com address
  Future<UserProfile> signInWithGoogle({String? email, String? name}) async {
    final cleanEmail = email?.trim() ?? '';

    if (cleanEmail.isEmpty) {
      throw Exception('Please enter your Gmail address.');
    }

    if (!isValidGmail(cleanEmail)) {
      throw Exception('Invalid Gmail address. Must end with @gmail.com (e.g. yourname@gmail.com).');
    }

    final accounts = await _loadRegisteredAccounts();
    final normalized = cleanEmail.toLowerCase();

    // Check if already registered
    _RegisteredAccount? existing;
    for (final acc in accounts) {
      if (acc.email.toLowerCase() == normalized) {
        existing = acc;
        break;
      }
    }

    String chosenName = name?.trim() ?? '';
    if (chosenName.isEmpty) {
      chosenName = existing != null
          ? existing.name
          : cleanEmail.split('@').first.replaceAll('.', ' ').capitalize();
    }

    if (existing == null) {
      // Register this Google account into the accounts database
      accounts.add(_RegisteredAccount(
        name: chosenName,
        email: cleanEmail,
        password: '', // Google accounts don't store local password
        provider: 'google',
      ));
      await _saveRegisteredAccounts(accounts);
    }

    final user = UserProfile(
      name: chosenName,
      email: cleanEmail,
      avatarUrl: 'https://lh3.googleusercontent.com/a/default-user',
      authProvider: 'google',
    );

    await _saveUserSession(user);
    return user;
  }

  /// Sign in with Email and Password
  /// REJECTS any email that does not already exist in the registered accounts!
  Future<UserProfile> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty) {
      throw Exception('Please enter your email address.');
    }

    if (!isValidEmail(cleanEmail)) {
      throw Exception('Invalid email format. Please enter a valid email address (e.g. name@gmail.com).');
    }

    if (cleanPassword.isEmpty) {
      throw Exception('Please enter your password.');
    }

    final accounts = await _loadRegisteredAccounts();
    final normalized = cleanEmail.toLowerCase();

    // 1. Check if email exists in database
    _RegisteredAccount? account;
    for (final acc in accounts) {
      if (acc.email.toLowerCase() == normalized) {
        account = acc;
        break;
      }
    }

    if (account == null) {
      throw Exception('No account found with this email ($cleanEmail). Please click "Sign Up" below to create an account.');
    }

    // 2. Check if password matches
    if (account.password.isNotEmpty && account.password != cleanPassword) {
      throw Exception('Your password is wrong. Please check your password and try again.');
    }

    final user = UserProfile(
      name: account.name,
      email: account.email,
      authProvider: account.provider,
    );

    await _saveUserSession(user);
    return user;
  }

  /// Sign up with Name, Email, and Password
  /// Validates email format and ensures email is not already taken
  Future<UserProfile> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanName.isEmpty) {
      throw Exception('Please enter your full name.');
    }

    if (cleanEmail.isEmpty) {
      throw Exception('Please enter your email address.');
    }

    if (!isValidEmail(cleanEmail)) {
      throw Exception('Invalid email address. Please enter a valid email (e.g. yourname@gmail.com).');
    }

    if (cleanPassword.length < 6) {
      throw Exception('Password must be at least 6 characters long.');
    }

    final accounts = await _loadRegisteredAccounts();
    final normalized = cleanEmail.toLowerCase();

    // Check if account already exists - if so, update its password & sign in
    final existingIndex = accounts.indexWhere((acc) => acc.email.toLowerCase() == normalized);
    if (existingIndex != -1) {
      final updated = _RegisteredAccount(
        name: cleanName.isNotEmpty ? cleanName : accounts[existingIndex].name,
        email: cleanEmail,
        password: cleanPassword,
        provider: 'email',
      );
      accounts[existingIndex] = updated;
      await _saveRegisteredAccounts(accounts);

      final user = UserProfile(
        name: updated.name,
        email: updated.email,
        authProvider: 'email',
      );
      await _saveUserSession(user);
      return user;
    }

    // Add to registered database
    final newAccount = _RegisteredAccount(
      name: cleanName,
      email: cleanEmail,
      password: cleanPassword,
      provider: 'email',
    );
    accounts.add(newAccount);
    await _saveRegisteredAccounts(accounts);

    final user = UserProfile(
      name: cleanName,
      email: cleanEmail,
      authProvider: 'email',
    );

    await _saveUserSession(user);
    return user;
  }

  /// Quick guest access option
  Future<UserProfile> continueAsGuest() async {
    final user = UserProfile(
      name: 'Guest Explorer',
      email: 'guest@myaichatbot.local',
      authProvider: 'guest',
    );

    await _saveUserSession(user);
    return user;
  }

  /// Sign out and clear active session
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }

  Future<void> _saveUserSession(UserProfile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, user.toJson());
  }

  /// Load registered accounts from persistent storage and ensure seed accounts exist
  Future<List<_RegisteredAccount>> _loadRegisteredAccounts() async {
    List<_RegisteredAccount> accounts = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = prefs.getStringList(_accountsDbKey);
      list ??= prefs.getStringList('registered_accounts_db_v2');
      if (list != null && list.isNotEmpty) {
        accounts = list.map((item) => _RegisteredAccount.fromMap(jsonDecode(item))).toList();
      }
    } catch (_) {}

    // Ensure all seed accounts exist in the accounts database
    bool changed = false;
    for (final seed in _seedAccounts) {
      final exists = accounts.any((a) => a.email.toLowerCase() == seed.email.toLowerCase());
      if (!exists) {
        accounts.add(seed);
        changed = true;
      }
    }

    if (changed || accounts.isEmpty) {
      await _saveRegisteredAccounts(accounts);
    }
    return accounts;
  }

  Future<void> _saveRegisteredAccounts(List<_RegisteredAccount> accounts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = accounts.map((acc) => jsonEncode(acc.toMap())).toList();
      await prefs.setStringList(_accountsDbKey, list);
    } catch (_) {}
  }
}

class _RegisteredAccount {
  final String name;
  final String email;
  final String password;
  final String provider;

  _RegisteredAccount({
    required this.name,
    required this.email,
    required this.password,
    required this.provider,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'password': password,
    'provider': provider,
  };

  factory _RegisteredAccount.fromMap(Map<String, dynamic> map) => _RegisteredAccount(
    name: map['name'] as String? ?? 'User',
    email: map['email'] as String? ?? '',
    password: map['password'] as String? ?? '',
    provider: map['provider'] as String? ?? 'email',
  );
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
