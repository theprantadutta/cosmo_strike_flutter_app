import 'package:shared_preferences/shared_preferences.dart';

/// Centralized privacy-policy version + acceptance tracking.
///
/// The accepted *version string* is what we persist — not a plain boolean — so
/// that whenever the policy materially changes we bump
/// [currentPrivacyPolicyVersion] and every user (new and existing) is asked to
/// review and accept the updated policy again. Acceptance counts as current
/// only when the stored version exactly matches [currentPrivacyPolicyVersion].
///
/// Keep this in lockstep with the `**Policy Version:**` / `**Document Version:**`
/// fields in `PRIVACY.md` — bump both together when the policy changes.
class PrivacyPolicy {
  PrivacyPolicy._();

  /// Current policy version. Bump on every material change to PRIVACY.md.
  static const String currentPrivacyPolicyVersion = '2.0';

  /// New key: stores the policy version the user last accepted.
  static const String _versionKey = 'privacy_policy_accepted_version';

  /// Legacy key (pre-versioning): a plain bool. Kept only so we can recognize
  /// the prior install state — we deliberately do NOT grandfather legacy
  /// acceptances into the new version, because the 2.0 change (ads) is
  /// material and those users should re-accept.
  static const String _legacyKey = 'privacy_policy_accepted';

  /// True only when the user has accepted the *current* policy version.
  static Future<bool> isCurrentVersionAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_versionKey) == currentPrivacyPolicyVersion;
    } catch (_) {
      // If prefs can't be read, fail safe by treating it as not accepted so
      // the user is shown the policy.
      return false;
    }
  }

  /// Record acceptance of the current policy version.
  static Future<void> recordAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_versionKey, currentPrivacyPolicyVersion);
      // Keep the legacy flag set too, for any older code path still reading it.
      await prefs.setBool(_legacyKey, true);
    } catch (_) {
      // Non-critical — acceptance will simply be re-requested next launch.
    }
  }
}
