import 'package:flutter/material.dart';
import 'package:planner/models/user_profile.dart';
import 'package:planner/screens/home_screen.dart';
import 'package:planner/services/local_session.dart';
import 'package:planner/services/profile_service.dart';

class AuthGate extends StatefulWidget {
  final Function(ThemeMode) toggleTheme;

  const AuthGate({super.key, required this.toggleTheme});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final ProfileService _profileService = ProfileService();
  UserProfile? _profile;
  Object? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!_isLoading || _loadError != null) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      var profile = await _profileService.getProfile();
      final profileName = profile?.fullName?.trim();
      final savedName = LocalSession.instance.name?.trim();

      if ((profileName == null || profileName.isEmpty) &&
          savedName != null &&
          savedName.isNotEmpty) {
        await _profileService.saveProfile(
          savedName,
          avatarUrl: profile?.avatarUrl,
        );
        profile = await _profileService.getProfile();
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Не удалось загрузить локальный профиль: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  void _onNameSaved(String name) {
    setState(() {
      _profile = UserProfile(
        id: LocalSession.instance.userId,
        fullName: name,
        avatarUrl: _profile?.avatarUrl,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Не удалось загрузить профиль',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Проверьте хранилище приложения и попробуйте ещё раз.\n$_loadError',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadProfile,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final name = _profile?.fullName?.trim();
    if (name == null || name.isEmpty) {
      return _NameSetupScreen(
        avatarUrl: _profile?.avatarUrl,
        onSaved: _onNameSaved,
      );
    }

    return HomeScreen(toggleTheme: widget.toggleTheme);
  }
}

class _NameSetupScreen extends StatefulWidget {
  final String? avatarUrl;
  final ValueChanged<String> onSaved;

  const _NameSetupScreen({required this.avatarUrl, required this.onSaved});

  @override
  State<_NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<_NameSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final ProfileService _profileService = ProfileService();
  bool _isSaving = false;
  String? _saveError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      await _profileService.saveProfile(name, avatarUrl: widget.avatarUrl);
      if (!mounted) return;
      widget.onSaved(name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Не удалось сохранить имя: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/splash/logo.png',
                      width: 144,
                      height: 144,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Добро пожаловать в Dayo',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Как к вам обращаться? Это имя появится в приветствии.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      maxLength: 40,
                      onFieldSubmitted: (_) => _saveName(),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите имя';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Ваше имя',
                        hintText: 'Например, Алекс',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _saveError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveName,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text(_isSaving ? 'Сохраняем…' : 'Продолжить'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
