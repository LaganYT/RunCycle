import 'dart:convert';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:http/http.dart' as http;

class StravaService {
  static const _clientId = '166809';
  static const _clientSecret = '89cbe50555191a02162d3a4a78ccf251e57f376e';
  static const _redirectUri = 'runcycle';
  static const _authorizeUrl = 'https://www.strava.com/oauth/authorize';
  static const _tokenUrl = 'https://www.strava.com/oauth/token';

  String? _accessToken;

  Future<void> authenticate() async {
    final authUrl = '$_authorizeUrl'
        '?client_id=$_clientId'
        '&redirect_uri=$_redirectUri'
        '&response_type=code'
        '&scope=activity:read';
    final result = await FlutterWebAuth.authenticate(
      url: authUrl,
      callbackUrlScheme: 'runcycle',
    );
    final code = Uri.parse(result).queryParameters['code'];
    final resp = await http.post(Uri.parse(_tokenUrl), body: {
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'code': code,
      'grant_type': 'authorization_code',
    });
    final json = jsonDecode(resp.body);
    _accessToken = json['access_token'];
  }

  Future<List<Map<String, dynamic>>> fetchActivities({
    DateTime? before,
    DateTime? after,
  }) async {
    if (_accessToken == null) await authenticate();
    final params = <String, String>{};
    if (before != null) params['before'] = (before.millisecondsSinceEpoch ~/ 1000).toString();
    if (after  != null) params['after']  = (after.millisecondsSinceEpoch  ~/ 1000).toString();
    final uri = Uri.https('www.strava.com', '/api/v3/athlete/activities', params);
    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $_accessToken',
    });
    return List<Map<String, dynamic>>.from(jsonDecode(resp.body));
  }
}
