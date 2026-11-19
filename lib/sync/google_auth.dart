// Google hesabı girişi.
// Android: google_sign_in (Android OAuth istemcisi, paket adı + SHA-1 ile eşleşir).
// Windows: googleapis_auth loopback akışı (Masaüstü OAuth istemcisi). İstemci kimliği derlemede verilir:
//   flutter build windows --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...

import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const driveScopes = [drive.DriveApi.driveAppdataScope];

abstract class GoogleAuth {
  String? get email;
  Future<http.Client?> signInSilently();
  Future<http.Client?> signIn();
  Future<void> signOut();

  static GoogleAuth create() => Platform.isAndroid || Platform.isIOS ? MobileGoogleAuth() : DesktopGoogleAuth();
}

class MobileGoogleAuth implements GoogleAuth {
  final _gs = GoogleSignIn(scopes: [...driveScopes, 'email']);
  @override
  String? email;

  Future<http.Client?> _client(GoogleSignInAccount? acc) async {
    if (acc == null) return null;
    email = acc.email;
    return _gs.authenticatedClient();
  }

  @override
  Future<http.Client?> signInSilently() async => _client(await _gs.signInSilently());

  @override
  Future<http.Client?> signIn() async => _client(await _gs.signIn());

  @override
  Future<void> signOut() async {
    await _gs.signOut();
    email = null;
  }
}

class DesktopGoogleAuth implements GoogleAuth {
  static const _clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
  static const _prefsKey = 'google_credentials';

  @override
  String? email;
  gauth.AutoRefreshingAuthClient? _client;

  gauth.ClientId get _id => gauth.ClientId(_clientId, _clientSecret.isEmpty ? null : _clientSecret);

  Future<void> _persist(gauth.AccessCredentials c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(c.toJson()));
  }

  Future<void> _fetchEmail(http.Client c) async {
    try {
      final about = await drive.DriveApi(c).about.get($fields: 'user(emailAddress)');
      email = about.user?.emailAddress;
    } catch (_) {}
  }

  @override
  Future<http.Client?> signInSilently() async {
    if (_client != null) return _client;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || _clientId.isEmpty) return null;
    try {
      final creds = gauth.AccessCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (creds.refreshToken == null) return null;
      final c = gauth.autoRefreshingClient(_id, creds, http.Client());
      c.credentialUpdates.listen(_persist);
      _client = c;
      await _fetchEmail(c);
      return c;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<http.Client?> signIn() async {
    if (_clientId.isEmpty) {
      throw StateError('Windows için GOOGLE_DESKTOP_CLIENT_ID derleme sırasında verilmedi (README: Google Cloud kurulumu).');
    }
    final c = await gauth.clientViaUserConsent(_id, driveScopes, (url) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    });
    await _persist(c.credentials);
    c.credentialUpdates.listen(_persist);
    _client = c;
    await _fetchEmail(c);
    return c;
  }

  @override
  Future<void> signOut() async {
    _client?.close();
    _client = null;
    email = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
