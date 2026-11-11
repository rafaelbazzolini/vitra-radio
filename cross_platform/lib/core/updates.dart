import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService extends ChangeNotifier {
  static const repository = 'rafaelbazzolini/vitra-radio';
  static final releases = Uri.https('github.com', '/$repository/releases/latest');
  final notifications = FlutterLocalNotificationsPlugin();
  String? availableVersion;
  String currentVersion = '';
  bool checking = false;
  bool notificationReady = false;
  String? error;
  static bool isNewer(String next, String current) {
    List<int> parts(String s) => s.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final a = parts(next), b = parts(current);
    for (var i = 0; i < 3; i++) { final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0; if (x != y) return x > y; }
    return false;
  }
  Future<void> initializeNotifications() async {
    try {
      await notifications.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        macOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        linux: LinuxInitializationSettings(defaultActionName: 'Ver atualização'),
        windows: WindowsInitializationSettings(appName: 'Vitra Radio', appUserModelId: 'Vitra.Radio', guid: '2e79a73c-1727-48df-a4fe-5fcf7672fe6b'),
      ), onDidReceiveNotificationResponse: (_) { openRelease(); });
      notificationReady = true;
    } catch (_) { notificationReady = false; }
  }
  Future<void> requestNotificationPermission() async {
    if (!notificationReady) await initializeNotifications();
    if (Platform.isAndroid) { await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission(); }
    if (Platform.isIOS) { await notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: false, sound: false); }
    if (Platform.isMacOS) { await notifications.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: false, sound: false); }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('updateNotifications', true);
  }
  Future<void> check() async {
    if (checking) return;
    checking = true; error = null; notifyListeners();
    try {
      final package = await PackageInfo.fromPlatform(); currentVersion = package.version;
      final response = await http.get(Uri.https('api.github.com', '/repos/$repository/releases/latest'), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'VitraRadio/$currentVersion'}).timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) return;
      if (response.statusCode != 200) throw const FormatException('Não foi possível consultar as versões.');
      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final next = release['tag_name'] as String;
      if (release['draft'] == true || release['prerelease'] == true || !isNewer(next, currentVersion)) return;
      availableVersion = next;
      final prefs = await SharedPreferences.getInstance();
      if (notificationReady && prefs.getBool('updateNotifications') == true && prefs.getString('lastUpdateNotice') != next) {
        await notifications.show(id: 9001, title: 'Vitra Radio $next disponível', body: 'Uma nova versão está pronta. Toque para ver a atualização.', notificationDetails: const NotificationDetails(android: AndroidNotificationDetails('updates', 'Atualizações', channelDescription: 'Novas versões do Vitra Radio'), iOS: DarwinNotificationDetails(), macOS: DarwinNotificationDetails(), linux: LinuxNotificationDetails(), windows: WindowsNotificationDetails()));
        await prefs.setString('lastUpdateNotice', next);
      }
    } catch (_) { error = 'Sem conexão com as versões. Tente novamente mais tarde.'; }
    finally { checking = false; notifyListeners(); }
  }
  Future<void> openRelease() => launchUrl(releases, mode: LaunchMode.externalApplication).then((_) {});
}
