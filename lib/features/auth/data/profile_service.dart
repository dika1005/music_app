import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User profile data
class UserProfile extends Equatable {
  final String name;
  final String avatarInitial;
  final DateTime? lastLogin;

  const UserProfile({
    this.name = '',
    this.avatarInitial = '',
    this.lastLogin,
  });

  bool get hasProfile => name.isNotEmpty;

  String get displayName => name.isNotEmpty ? name : 'Pengguna';

  String get initial {
    if (avatarInitial.isNotEmpty) return avatarInitial;
    if (name.isEmpty) return 'P';
    return name[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatarInitial': avatarInitial,
    'lastLogin': lastLogin?.millisecondsSinceEpoch,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String? ?? '',
    avatarInitial: json['avatarInitial'] as String? ?? '',
    lastLogin: json['lastLogin'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['lastLogin'] as int)
        : null,
  );

  UserProfile copyWith({String? name, String? avatarInitial, DateTime? lastLogin}) =>
      UserProfile(
        name: name ?? this.name,
        avatarInitial: avatarInitial ?? this.avatarInitial,
        lastLogin: lastLogin ?? this.lastLogin,
      );

  @override
  List<Object?> get props => [name, avatarInitial, lastLogin];
}

/// Profile state
class ProfileState extends Equatable {
  final UserProfile profile;
  const ProfileState({this.profile = const UserProfile()});

  ProfileState copyWith({UserProfile? profile}) =>
      ProfileState(profile: profile ?? this.profile);

  @override
  List<Object?> get props => [profile];
}

/// Profile cubit for managing user profile
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit() : super(const ProfileState());

  static const _kProfile = 'app.profile';
  static const _kPassword = 'app.password';
  SharedPreferences? _prefs;

  Future<void> restore() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      final raw = p.getString(_kProfile);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        emit(state.copyWith(
          profile: UserProfile.fromJson(json).copyWith(
            lastLogin: DateTime.now(),
          ),
        ));
        _persist();
      }
    } catch (_) {}
  }

  /// Create or update profile
  Future<bool> saveProfile(String name, String password) async {
    if (name.trim().isEmpty) return false;
    final profile = UserProfile(
      name: name.trim(),
      avatarInitial: name.trim()[0].toUpperCase(),
      lastLogin: DateTime.now(),
    );
    emit(state.copyWith(profile: profile));

    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      await p.setString(_kProfile, jsonEncode(profile.toJson()));
      if (password.isNotEmpty) {
        await p.setString(_kPassword, password);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verify password for login
  Future<bool> verifyPassword(String password) async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      final stored = p.getString(_kPassword) ?? '';
      return stored == password;
    } catch (_) {
      return false;
    }
  }

  /// Logout / clear profile
  Future<void> logout() async {
    emit(const ProfileState());
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      await p.remove(_kProfile);
      await p.remove(_kPassword);
    } catch (_) {}
  }

  void _persist() {
    final p = _prefs;
    if (p == null) return;
    try {
      p.setString(_kProfile, jsonEncode(state.profile.toJson()));
    } catch (_) {}
  }
}
