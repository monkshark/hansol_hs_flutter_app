import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hansol_high_school/data/auth_service.dart';
import 'package:hansol_high_school/l10n/app_localizations.dart';
import 'package:hansol_high_school/styles/app_colors.dart';
import 'package:hansol_high_school/styles/responsive.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  bool _busy = false;
  UserProfile? _profile;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.getUserProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loaded = true;
    });
  }

  bool _hasProvider(String providerId) {
    return AuthService.currentUser?.providerData
            .any((p) => p.providerId == providerId) ??
        false;
  }

  Future<void> _runLink(Future<LinkResult> Function() linkFn) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await linkFn();
    AuthService.clearProfileCache();
    await _loadProfile();
    if (!mounted) return;
    setState(() => _busy = false);

    final l = AppLocalizations.of(context)!;
    String? message;
    switch (result) {
      case LinkResult.success:
        message = l.account_connectSuccess;
        break;
      case LinkResult.alreadyInUse:
        message = l.account_connectAlreadyLinked;
        break;
      case LinkResult.failed:
        message = l.account_connectFailed;
        break;
      case LinkResult.cancelled:
        message = null;
        break;
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<LinkResult> _linkKakao() async {
    try {
      kakao.OAuthToken token;
      if (await kakao.isKakaoTalkInstalled()) {
        token = await kakao.UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
      }
      final ok = await AuthService.linkKakaoAccount(token.accessToken);
      return ok ? LinkResult.success : LinkResult.failed;
    } catch (e) {
      return LinkResult.failed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
        title: Text(l.account_connectedTitle),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(l.account_connectedDesc,
                    style: TextStyle(
                        fontSize: Responsive.sp(context, 13),
                        color: AppColors.theme.mealTypeTextColor,
                        height: 1.5)),
                const SizedBox(height: 20),
                _providerRow(
                  isDark: isDark,
                  label: 'Google',
                  svgAsset: 'assets/icons/google.svg',
                  connected: _hasProvider('google.com'),
                  onConnect: () => _runLink(AuthService.linkGoogle),
                ),
                if (Platform.isIOS)
                  _providerRow(
                    isDark: isDark,
                    label: 'Apple',
                    svgAsset: 'assets/icons/apple.svg',
                    svgColor: isDark ? Colors.white : Colors.black,
                    connected: _hasProvider('apple.com'),
                    onConnect: () => _runLink(AuthService.linkApple),
                  ),
                _providerRow(
                  isDark: isDark,
                  label: '카카오',
                  svgAsset: 'assets/icons/kakao.svg',
                  svgColor: const Color(0xFFFEE500),
                  connected: _profile?.linkedKakaoId != null,
                  onConnect: () => _runLink(_linkKakao),
                ),
                _providerRow(
                  isDark: isDark,
                  label: 'GitHub',
                  svgAsset: 'assets/icons/github.svg',
                  svgColor: isDark ? Colors.white : const Color(0xFF24292F),
                  connected: _hasProvider('github.com'),
                  onConnect: () => _runLink(AuthService.linkGitHub),
                ),
              ],
            ),
    );
  }

  Widget _providerRow({
    required bool isDark,
    required String label,
    required String svgAsset,
    Color? svgColor,
    required bool connected,
    required VoidCallback onConnect,
  }) {
    final l = AppLocalizations.of(context)!;
    final borderColor = isDark ? const Color(0xFF3A3D45) : const Color(0xFFE5E7EB);
    final bgColor = isDark ? const Color(0xFF2A2D35) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          SvgPicture.asset(svgAsset,
              width: 26,
              height: 26,
              colorFilter: svgColor != null
                  ? ColorFilter.mode(svgColor, BlendMode.srcIn)
                  : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: Responsive.sp(context, 15),
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color)),
                const SizedBox(height: 2),
                Text(connected ? l.account_connected : l.account_notConnected,
                    style: TextStyle(
                        fontSize: Responsive.sp(context, 12),
                        color: connected
                            ? const Color(0xFF4CAF50)
                            : AppColors.theme.mealTypeTextColor)),
              ],
            ),
          ),
          if (!connected)
            TextButton(
              onPressed: _busy ? null : onConnect,
              child: Text(l.account_connectButton,
                  style: TextStyle(color: AppColors.theme.primaryColor)),
            )
          else
            Icon(Icons.check_circle, color: const Color(0xFF4CAF50), size: Responsive.r(context, 20)),
        ],
      ),
    );
  }
}
