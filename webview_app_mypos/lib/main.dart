import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:typed_data';
import 'dart:collection';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/zxing.dart' as zx;
import 'package:zxing_lib/qrcode.dart' as qr;
import 'package:zxing_lib/common.dart' as common;
import 'report_service.dart';
import 'report_api_service.dart';
import 'cron_task_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

String whitelistedBaseUrl = 'https://taxizuschuss.app.graz.at/';
bool isTicketScanMode = false;
const String ticketCheckerUrl =
    'https://burgenlandtrails.at/mqz1ppt9p6arx45lclxzxxvx5vsfb9hatudjv320hfkizeeu9va6yngjbqierlmt/';

// Global key to access the state of MyApp to change language
final GlobalKey<_MyAppState> myAppKey = GlobalKey<_MyAppState>();

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://5c3727305dcb9c2581801ef9190c2621@o4511219225853952.ingest.us.sentry.io/4511219227623424';
      options.tracesSampleRate = 1.0;
      options.attachScreenshot = true;
      options.enableLogs = true;
      options.enableTombstone = true;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      // await ReportService().init();
      await ReportApiService().init();
      // CronTaskService().init();
      runApp(MyApp(key: myAppKey));
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final savedLocale = await LanguageSettings.getLanguage();
    setState(() {
      _locale = savedLocale;
    });
  }

  void setLocale(Locale value) {
    setState(() {
      _locale = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_locale == null) {
      return const SizedBox(); // Show nothing while loading language
    }

    return MaterialApp(
      title: 'Scan APP',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SelectionScreen(),
    );
  }
}

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen>
    with WidgetsBindingObserver {
  bool _isBatteryOptimized = false;
  bool _isExactAlarmDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBackgroundPermissions();
    _logDeviceActivity();
  }

  Future<void> _logDeviceActivity() async {
    try {
      String deviceName = "Unknown";
      String appVersion = "Unknown";

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      appVersion = "${packageInfo.version} (${packageInfo.buildNumber})";

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceName = "${androidInfo.brand} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
      }

      await Sentry.captureMessage(
        "📱 App Started on Device: $deviceName",
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag("device_name", deviceName);
          scope.setTag("app_version", appVersion);
        },
      );
    } catch (e) {
      debugPrint("Error logging device activity: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBackgroundPermissions();
    }
  }

  Future<void> _showAppInfoDialog() async {
    String appVersion = "Unknown";
    String deviceName = "Unknown";
    String lastMailSentStr = context.tr('no_history');
    List<DateTime> missedDates = [];
    Map<String, int> todayData = {};

    try {
      todayData = await ReportService().getReportData(DateTime.now());
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      appVersion = "${packageInfo.version} (${packageInfo.buildNumber})";

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceName = "${androidInfo.brand} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
      } else if (kIsWeb) {
        WebBrowserInfo webBrowserInfo = await deviceInfo.webBrowserInfo;
        deviceName = webBrowserInfo.userAgent ?? "Web Browser";
      }

      final prefs = await SharedPreferences.getInstance();
      String? sentTime = prefs.getString('last_mail_sent_time');
      if (sentTime != null) {
        DateTime dt = DateTime.parse(sentTime).toLocal();
        lastMailSentStr =
            "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      }

      List<DateTime> allMissedDates = await ReportService()
          .getMissedReportDates();
      // Filter out dates that have 0 total scans
      missedDates = [];
      for (var d in allMissedDates) {
        final dData = await ReportService().getReportData(d);
        final totalScans =
            (dData['burgenlandCount'] ?? 0) +
            (dData['burgenlandFailCount'] ?? 0) +
            (dData['ticketCount'] ?? 0) +
            (dData['ticketInvalidCount'] ?? 0) +
            (dData['ticketFailCount'] ?? 0);
        if (totalScans > 0) {
          missedDates.add(d);
        }
      }
    } catch (e) {
      debugPrint("Error fetching info: $e");
    }

    if (!mounted) return;

    showDialog(
      context: context,
      fullscreenDialog: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              context.tr('information_title'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('last_mail_sent'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  Text(lastMailSentStr),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('application_version'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  Text(appVersion),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('device'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  Text(deviceName),

                  const SizedBox(height: 20),
                  const Divider(),
                  Text(
                    context.tr('today_status'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildTodayReportTable(context, todayData),

                  if (missedDates.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    Text(
                      context.tr('missed_reports'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    ...missedDates.map((date) {
                      String dateStr =
                          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(dateStr),
                            ElevatedButton(
                              onPressed: () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${context.tr('sending_report_for')} $dateStr...',
                                    ),
                                  ),
                                );
                                bool success = await ReportService()
                                    .sendManualReport(date);
                                if (success && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${context.tr('report_sent_for')} $dateStr',
                                      ),
                                    ),
                                  );
                                  setDialogState(() {
                                    missedDates.remove(date);
                                  });
                                }
                              },
                              child: Text(context.tr('send_report')),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('close')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkBackgroundPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      final isBatteryIgnored =
          await ReportService.isBatteryOptimizationIgnored();
      final isAlarmGranted =
          await ReportService.isExactAlarmPermissionGranted();

      if (mounted) {
        setState(() {
          _isBatteryOptimized = !isBatteryIgnored;
          _isExactAlarmDenied = !isAlarmGranted;
        });
      }
    }
  }

  Future<void> _requestBackgroundPermissions() async {
    if (_isBatteryOptimized) {
      await ReportService.requestIgnoreBatteryOptimizations();
    }
    if (_isExactAlarmDenied) {
      await ReportService.requestExactAlarmPermission();
    }
    // Re-check after a short delay or when user returns
    await _checkBackgroundPermissions();
  }

  Future<bool> _onWillPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('exit_app_title')),
        content: Text(context.tr('exit_app_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('exit')),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  Future<bool> _checkAndRequestCameraPermission() async {
    bool hasPermission = true;
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      hasPermission = status.isGranted;
    }

    if (!hasPermission) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('camera_permission_required')),
            content: Text(context.tr('camera_permission_content')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('cancel')),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: Text(context.tr('settings')),
              ),
            ],
          ),
        );
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          // Exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),

        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              double maxWidth = constraints.maxWidth > 600
                  ? 500
                  : constraints.maxWidth;
              return SizedBox(
                width: maxWidth,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    // padding: const EdgeInsets.symmetric(
                    //   horizontal: 24.0,
                    //   vertical: 32.0,
                    // ),
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 24,
                      top: 12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF6C757D),
                                  size: 20,
                                ),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                onPressed: _showAppInfoDialog,
                                tooltip: context.tr('app_info_tooltip'),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: Localizations.localeOf(
                                    context,
                                  ).languageCode,
                                  icon: const Padding(
                                    padding: EdgeInsets.only(left: 4.0),
                                    child: Icon(
                                      Icons.language_rounded,
                                      size: 18,
                                      color: Color(0xFF6C757D),
                                    ),
                                  ),
                                  isDense: true,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'de',
                                      child: Text(
                                        'DE',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF495057),
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'en',
                                      child: Text(
                                        'EN',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF495057),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      LanguageSettings.setLanguage(newValue);
                                      myAppKey.currentState?.setLocale(
                                        Locale(newValue),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),

                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 45,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        // const SizedBox(height: 32),
                        Text(
                          context.tr('choose_scan_type'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E1E1E),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('scan_type_description'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF6C757D),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // _buildScanOptionCard(
                        //   context: context,
                        //   title: 'BURGENLAND CARD',
                        //   description:
                        //       'Scan and verify Burgenland tourist cards seamlessly.',
                        //   icon: Icons.badge_rounded,
                        //   gradientColors: [
                        //     const Color(0xFF4776E6),
                        //     const Color(0xFF8E54E9),
                        //   ],
                        //   shadowColor: const Color(0xFF4776E6),
                        //   onTap: () async {
                        //     whitelistedBaseUrl =
                        //         'https://www.neusiedlersee.com/';
                        //     isTicketScanMode = false;

                        //     //   whitelistedBaseUrl =
                        //     // 'https://card-mobile-check.feratel.com/';

                        //     // whitelistedBaseUrl = 'https://card-mobile-check.feratel.com/tenants/nsc01/checkpoints';

                        //     if (!(await _checkAndRequestCameraPermission()))
                        //       return;

                        //     if (context.mounted) {
                        //       Navigator.of(context).push(
                        //         MaterialPageRoute(
                        //           builder: (context) => const QRScannerScreen(),
                        //         ),
                        //       );
                        //     }
                        //   },
                        // ),
                        // const SizedBox(height: 20),
                        _buildScanOptionCard(
                          context: context,
                          title: context.tr('burgenland_card'),
                          description: context.tr('burgenland_card_desc'),
                          icon: Icons.badge_rounded,
                          gradientColors: [
                            const Color(0xFF4776E6),
                            const Color(0xFF8E54E9),
                          ],
                          shadowColor: const Color(0xFF4776E6),
                          onTap: () async {
                            whitelistedBaseUrl =
                                'https://card-mobile-check.feratel.com/';
                            isTicketScanMode = false;

                            if (!(await _checkAndRequestCameraPermission())) {
                              return;
                            }

                            if (context.mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const InAppBrowserScreen(
                                    url:
                                        'https://card-mobile-check.feratel.com/tenants/nsc01/checkpoints',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildScanOptionCard(
                          context: context,
                          title: context.tr('ticket_scan'),
                          description: context.tr('ticket_scan_desc'),
                          icon: Icons.confirmation_number_rounded,
                          gradientColors: [
                            const Color(0xFFFF512F),
                            const Color(0xFFDD2476),
                          ],
                          shadowColor: const Color(0xFFFF512F),
                          onTap: () async {
                            whitelistedBaseUrl = 'https://burgenlandtrails.at/';
                            isTicketScanMode = true;
                            //   whitelistedBaseUrl ='https://burgenlandtrails.at/mqz1ppt9p6arx45lclxzxxvx5vsfb9hatudjv320hfkizeeu9va6yngjbqierlmt/';

                            if (!(await _checkAndRequestCameraPermission())) {
                              return;
                            }

                            if (context.mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const QRScannerScreen(),
                                ),
                              );
                            }
                          },
                        ),
                        // Hidden debug trigger
                        if (kDebugMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 40.0),
                            child: TextButton.icon(
                              onPressed: () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      context.tr('trigger_test_report'),
                                    ),
                                  ),
                                );
                                await ReportService.checkAndSendEmailBackground();
                              },
                              icon: const Icon(Icons.bug_report, size: 16),
                              label: Text(
                                context.tr('debug_send_report_now'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        (!kIsWeb &&
                                (_isBatteryOptimized || _isExactAlarmDenied))
                            ? Column(
                                mainAxisSize: MainAxisSize.min,

                                children: [
                                  const SizedBox(height: 24),
                                  _buildBackgroundWarningCard(),
                                ],
                              )
                            : SizedBox(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScanOptionCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradientColors,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          highlightColor: gradientColors[0].withOpacity(0.05),
          splashColor: gradientColors[0].withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 26, color: Colors.white),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C757D),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: shadowColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundWarningCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD591), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE7BA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.battery_alert_rounded,
                  color: Color(0xFFD48806),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('background_reliability'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2B2D42),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('background_desc'),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF595959),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _requestBackgroundPermissions,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD48806),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.settings_applications_rounded),
              label: Text(
                context.tr('disable_optimization'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayReportTable(BuildContext context, Map<String, int> data) {
    int bCount = data['burgenlandCount'] ?? 0;
    int bFail = data['burgenlandFailCount'] ?? 0;
    int tCount = data['ticketCount'] ?? 0;
    int tInvalid = data['ticketInvalidCount'] ?? 0;
    int tFail = data['ticketFailCount'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        border: TableBorder.symmetric(
          inside: BorderSide(color: Colors.grey.shade300),
        ),
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [
              _buildTableCell(
                Localizations.localeOf(context).languageCode == 'de'
                    ? 'Typ'
                    : 'Type',
                isHeader: true,
              ),
              _buildTableCell(
                context.tr('successful'),
                isHeader: true,
                color: Colors.green,
              ),
              _buildTableCell(
                context.tr('invalid'),
                isHeader: true,
                color: Colors.orange,
              ),
              _buildTableCell(
                context.tr('wrong_qr'),
                isHeader: true,
                color: Colors.red,
              ),
            ],
          ),
          TableRow(
            children: [
              _buildTableCell(context.tr('burgenland_card')),
              _buildTableCell(bCount.toString()),
              _buildTableCell('-'),
              _buildTableCell(bFail.toString()),
            ],
          ),
          TableRow(
            children: [
              _buildTableCell(context.tr('ticket_scan')),
              _buildTableCell(tCount.toString()),
              _buildTableCell(tInvalid.toString()),
              _buildTableCell(tFail.toString()),
            ],
          ),
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade50),
            children: [
              _buildTableCell(context.tr('total'), isHeader: true),
              _buildTableCell((bCount + tCount).toString(), isHeader: true),
              _buildTableCell(tInvalid.toString(), isHeader: true),
              _buildTableCell((bFail + tFail).toString(), isHeader: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 11 : 12,
          color: color,
        ),
      ),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController cameraController = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _isScanning = false;
  bool _isUploadMode = false;
  bool _hasCameraPermission = false;
  bool _cameraAvailable = true;
  bool _isInitializingCamera = false;
  bool _isProcessingQR = false;
  bool _isNavigating = false;
  String? _lastScannedUrl;
  DateTime? _lastScanTime;
  Key _scannerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializingCamera = true;
    });

    // Request camera permission for mobile
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      setState(() {
        _hasCameraPermission = status.isGranted;
        if (!_hasCameraPermission) {
          _isUploadMode = true;
          _cameraAvailable = false;
          _isInitializingCamera = false;
        }
      });

      if (_hasCameraPermission) {
        // Try to start camera
        try {
          await cameraController.start();
          setState(() {
            _isInitializingCamera = false;
          });
        } catch (e) {
          setState(() {
            _cameraAvailable = false;
            _isUploadMode = true;
            _isInitializingCamera = false;
          });
        }
      }
    } else {
      // On web, camera availability will be detected when trying to start
      setState(() {
        _hasCameraPermission = true;
      });
      // Try to start camera and catch if it fails
      try {
        await cameraController.start();
        setState(() {
          _isInitializingCamera = false;
        });
      } catch (e) {
        setState(() {
          _cameraAvailable = false;
          _isUploadMode = true;
          _isInitializingCamera = false;
        });
      }
    }
  }

  Future<void> _retryCamera() async {
    setState(() {
      _isInitializingCamera = true;
    });

    try {
      // Stop and dispose old controller
      await cameraController.stop();
      cameraController.dispose();

      // Create new controller
      cameraController = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );

      // Start again
      await cameraController.start();
      if (mounted) {
        setState(() {
          _scannerKey = UniqueKey(); // Force widget rebuild
          _cameraAvailable = true;
          _isInitializingCamera = false;
        });
      }
    } catch (e) {
      setState(() {
        _cameraAvailable = false;
        _isInitializingCamera = false;
      });
    }
  }

  Future<void> _pauseScanner() async {
    if (!_isUploadMode && _cameraAvailable && _hasCameraPermission) {
      await cameraController.stop();
    }
  }

  Future<void> _reinitializeCamera() async {
    if (!_isUploadMode && _hasCameraPermission) {
      if (!mounted) return;
      setState(() {
        _isInitializingCamera = true;
      });

      try {
        // Just start it. If it's already running, mobile_scanner handles it.
        // If we want a clean start, we already disposed it before coming here.
        await cameraController.start();
        if (mounted) {
          setState(() {
            _isInitializingCamera = false;
            _cameraAvailable = true;
          });
        }
      } catch (e) {
        debugPrint("Error re-initializing camera: $e");
        if (mounted) {
          setState(() {
            _isInitializingCamera = false;
            _cameraAvailable = false;
            _isUploadMode = true;
          });
        }
      }
    }
  }

  // Whitelisted base URL

  bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;

    // Try to parse as URI to validate URL format
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    // Check if it has a valid scheme
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  bool _isWhitelistedUrl(String? url) {
    if (url == null || url.isEmpty) return false;

    String normalizedUrl = url.trim().toLowerCase();
    if (normalizedUrl.startsWith('www.')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) return false;

    // Remove http:// or https:// from both the scanned URL and the whitelisted base URL
    final urlWithoutScheme = uri.toString().replaceFirst(
      RegExp(r'^https?://'),
      '',
    );
    final baseWithoutScheme = whitelistedBaseUrl
        .toLowerCase()
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '');

    if (urlWithoutScheme.startsWith(baseWithoutScheme)) return true;

    // Special allowance for Feratel login and OAuth redirects
    if (whitelistedBaseUrl.contains('feratel.com')) {
      final fullUrl = uri.toString();
      if (fullUrl.contains('idp.feratel.com') ||
          fullUrl.contains('oauth2/authorization') ||
          fullUrl.contains('login/oauth2/code') ||
          fullUrl.contains('auth/realms/')) {
        return true;
      }
    }

    return false;
  }

  Future<void> _handleQRCode(BarcodeCapture capture) async {
    // Prevent multiple simultaneous scans
    if (_isScanning || _isProcessingQR || _isNavigating) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    _isNavigating = true;
    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Normalize URL for comparison
    String normalizedUrl = code.trim();
    if (code.toLowerCase().startsWith('www.')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    // Debounce: prevent same URL from being processed multiple times within 2 seconds
    final now = DateTime.now();
    if (_lastScannedUrl == normalizedUrl &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      _isNavigating = false;
      return;
    }

    // Stop scanner immediately to prevent multiple detections
    await _pauseScanner();

    // Show processing indicator
    setState(() {
      _isProcessingQR = true;
      _lastScannedUrl = normalizedUrl;
      _lastScanTime = now;
    });

    // For Ticket Scan mode, we can be more flexible with the ID
    if (isTicketScanMode) {
      // If it's a ticket ID (even if not a URL), we proceed to the checker page
      setState(() {
        _isScanning = true;
      });

      HapticFeedback.mediumImpact();

      setState(() {
        _isScanning = false;
        _isProcessingQR = false;
      });

      if (mounted) {
        // Stop and dispose scanner before navigating to prevent camera conflicts with WebView
        await cameraController.stop();
        await cameraController.dispose();

        // Short delay to ensure native camera resources are released
        await Future.delayed(const Duration(milliseconds: 200));

        await Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) => InAppBrowserScreen(
                  url: ticketCheckerUrl,
                  injectValue: code,
                ),
              ),
            )
            .then((v) async {
              if (mounted) {
                setState(() {
                  _isNavigating = false;
                  _lastScannedUrl = null;
                  _lastScanTime = null;
                  _scannerKey = UniqueKey(); // Force MobileScanner rebuild

                  // Re-create the controller
                  cameraController = MobileScannerController(
                    autoStart: false,
                    detectionSpeed: DetectionSpeed.noDuplicates,
                    facing: CameraFacing.back,
                  );
                });
                await _reinitializeCamera();
              }
            });
      }
      return;
    }

    // First check if it's a valid URL
    if (!_isValidUrl(code)) {
      setState(() {
        _isProcessingQR = false;
      });
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('invalid_url_format')),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isNavigating = false;
        _lastScannedUrl = null;
        _lastScanTime = null;
      });

      // Properly reinitialize camera when returning to this screen
      await _reinitializeCamera();
      return;
    }

    // Then check if it's whitelisted
    if (!_isWhitelistedUrl(code)) {
      setState(() {
        _isProcessingQR = false;
      });
      HapticFeedback.lightImpact();
      if (mounted) {
        if (kDebugMode) {
          print(
            'URL not allowed. Only ${whitelistedBaseUrl} is permitted. Not ${code} normalizedUrl ${normalizedUrl}',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.tr('url_not_allowed')} $whitelistedBaseUrl ${context.tr('is_permitted')} Not $code',
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('invalid_qr_code')),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      setState(() {
        _isNavigating = false;
        _lastScannedUrl = null;
        _lastScanTime = null;
      });

      // Properly reinitialize camera when returning to this screen
      await _reinitializeCamera();
      return;
    }

    // URL is valid and whitelisted, proceed
    setState(() {
      _isScanning = true;
    });

    HapticFeedback.mediumImpact();

    setState(() {
      _isScanning = false;
      _isProcessingQR = false;
    });

    if (mounted) {
      // Stop and dispose scanner before navigating
      await cameraController.stop();
      await cameraController.dispose();

      // Short delay to ensure native camera resources are released
      await Future.delayed(const Duration(milliseconds: 200));

      // Navigate to webview
      await Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => InAppBrowserScreen(url: normalizedUrl),
            ),
          )
          .then((v) async {
            // Reset navigation flag and reinitialize camera when returning
            if (mounted) {
              setState(() {
                _isNavigating = false;
                _lastScannedUrl = null;
                _lastScanTime = null;
                _scannerKey = UniqueKey(); // Force MobileScanner rebuild

                // Re-create the controller
                cameraController = MobileScannerController(
                  autoStart: false,
                  detectionSpeed: DetectionSpeed.noDuplicates,
                  facing: CameraFacing.back,
                );
              });

              // Properly reinitialize camera when returning to this screen
              await _reinitializeCamera();
            }
          });
    } else {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  Future<void> showUrlDialog(String url) async {
    // Normalize URL (add https:// if it starts with www.)
    String normalizedUrl = url;
    if (url.toLowerCase().startsWith('www.')) {
      normalizedUrl = 'https://$url';
    }

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('qr_code_scanned')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('url_detected')),
            const SizedBox(height: 8),
            SelectableText(
              normalizedUrl,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              setState(() {
                _isScanning = false;
              });
            },
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              if (_isNavigating) return;

              Navigator.of(context).pop(true);
              setState(() {
                _isScanning = false;
                _isNavigating = true;
              });

              if (mounted) {
                // Stop and dispose scanner before navigating
                await cameraController.stop();
                await cameraController.dispose();

                // Short delay to ensure native camera resources are released
                await Future.delayed(const Duration(milliseconds: 200));

                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        InAppBrowserScreen(url: normalizedUrl),
                  ),
                );

                // Reset navigation flag and reinitialize camera when returning
                if (mounted) {
                  setState(() {
                    _isNavigating = false;
                    _lastScannedUrl = null;
                    _lastScanTime = null;
                    _scannerKey = UniqueKey(); // Force MobileScanner rebuild

                    // Re-create the controller
                    cameraController = MobileScannerController(
                      autoStart: false,
                      detectionSpeed: DetectionSpeed.noDuplicates,
                      facing: CameraFacing.back,
                    );
                  });

                  // Properly reinitialize camera when returning to this screen
                  await _reinitializeCamera();
                }
              } else {
                setState(() {
                  _isNavigating = false;
                });
              }
            },
            child: Text(context.tr('open')),
          ),
        ],
      ),
    );

    if (shouldOpen == null || !shouldOpen) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image == null) return;

      // Show processing indicator
      setState(() {
        _isProcessingQR = true;
      });

      // Analyze image using mobile_scanner
      // For mobile, use file path; for web, we'll need to handle differently
      try {
        String? scannedCode;
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          final decodedImage = img.decodeImage(bytes);
          if (decodedImage != null) {
            var pixelsInt32 = Int32List(
              decodedImage.width * decodedImage.height,
            );
            int i = 0;
            for (var p in decodedImage) {
              pixelsInt32[i++] =
                  (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
            }
            try {
              var source = zx.RGBLuminanceSource(
                decodedImage.width,
                decodedImage.height,
                pixelsInt32,
              );
              var binarizer = common.HybridBinarizer(source);
              var bitmap = zx.BinaryBitmap(binarizer);
              var reader = qr.QRCodeReader();
              var result = reader.decode(bitmap);
              scannedCode = result.text;
            } catch (e) {
              // zxing exceptions when barcode not found
            }
          }
        } else {
          final BarcodeCapture? result = await cameraController.analyzeImage(
            image.path,
          );
          if (result != null && result.barcodes.isNotEmpty) {
            scannedCode = result.barcodes.first.rawValue;
          }
        }

        if (scannedCode != null && scannedCode.isNotEmpty) {
          final code = scannedCode;
          if (code.isNotEmpty) {
            // First check if it's a valid URL
            if (!_isValidUrl(code)) {
              setState(() {
                _isProcessingQR = false;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('invalid_url_format')),
                    duration: const Duration(seconds: 3),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Then check if it's whitelisted
            if (!_isWhitelistedUrl(code)) {
              setState(() {
                _isProcessingQR = false;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('invalid_qr_code')),
                    duration: const Duration(seconds: 3),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // URL is valid and whitelisted, proceed
            String normalizedUrl = code.trim();
            if (code.toLowerCase().startsWith('www.')) {
              normalizedUrl = 'https://$normalizedUrl';
            }

            if (_isNavigating) {
              setState(() {
                _isProcessingQR = false;
              });
              return;
            }

            setState(() {
              _isScanning = false;
              _isProcessingQR = false;
              _isNavigating = true;
            });

            if (mounted) {
              // Pause scanner before navigating
              await _pauseScanner();

              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => InAppBrowserScreen(url: normalizedUrl),
                ),
              );

              // Reset navigation flag and reinitialize camera when returning
              setState(() {
                _isNavigating = false;
                _lastScannedUrl = null;
                _lastScanTime = null;
              });

              // Properly reinitialize camera when returning to this screen
              await _reinitializeCamera();
            } else {
              setState(() {
                _isNavigating = false;
              });
            }
          } else {
            setState(() {
              _isProcessingQR = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.tr('no_qr_found')),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else {
          setState(() {
            _isProcessingQR = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.tr('no_qr_found')),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        setState(() {
          _isProcessingQR = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${context.tr('error_decoding_qr')} $e'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isProcessingQR = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('error_picking_image')} $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _toggleMode() {
    if (_isNavigating || _isInitializingCamera) return;

    setState(() {
      _isUploadMode = !_isUploadMode;
      if (!_isUploadMode && _cameraAvailable && _hasCameraPermission) {
        try {
          cameraController.start();
        } catch (e) {
          debugPrint('Error starting camera in _toggleMode: $e');
        }
      } else {
        try {
          cameraController.stop();
        } catch (e) {
          debugPrint('Error stopping camera in _toggleMode: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Don't touch the controller if we are in upload mode, camera is not available,
    // or we are currently navigating/initializing (controller might be disposed)
    if (_isUploadMode ||
        !_cameraAvailable ||
        !_hasCameraPermission ||
        _isNavigating ||
        _isInitializingCamera) {
      return;
    }

    try {
      switch (state) {
        case AppLifecycleState.resumed:
          cameraController.start();
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          cameraController.stop();
          break;
      }
    } catch (e) {
      debugPrint('MobileScanner lifecycle error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        body: Stack(
          children: [
            // Camera preview or upload placeholder
            if (!_isUploadMode && _cameraAvailable && _hasCameraPermission)
              MobileScanner(
                key: _scannerKey,
                controller: cameraController,
                onDetect: _handleQRCode,
                errorBuilder: (context, error, child) {
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 42,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Camera Error: ${error.errorCode.name.toUpperCase()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: EdgeInsetsGeometry.only(
                              left: 25,
                              right: 25,
                            ),
                            child: Text(
                              context.tr('camera_init_error'),
                              textAlign: TextAlign.center,
                              maxLines: 5,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            onPressed: _retryCamera,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(context.tr('retry_camera')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isUploadMode ? Icons.image : Icons.camera_alt_outlined,
                        size: 80,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isUploadMode
                            ? context.tr('upload_qr_image')
                            : _hasCameraPermission
                            ? context.tr('camera_not_avail')
                            : context.tr('camera_denied'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Overlay buttons
            SafeArea(
              child: Column(
                children: [
                  // Professional Top bar with custom back and mode switch
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Glass back button
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),

                        // Premium Mode Switcher Pill
                        GestureDetector(
                          onTap: () {
                            // setState(() {
                            //   isTicketScanMode = !isTicketScanMode;
                            //   if (isTicketScanMode) {
                            //     whitelistedBaseUrl =
                            //         'https://burgenlandtrails.at/';
                            //   } else {
                            //     whitelistedBaseUrl =
                            //         'https://www.neusiedlersee.com/';
                            //   }
                            // });
                            // HapticFeedback.mediumImpact();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sync,
                                  size: 16,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  isTicketScanMode
                                      ? context.tr('ticket_mode')
                                      : context.tr('card_mode'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_cameraAvailable && _hasCameraPermission)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isUploadMode ? Icons.camera_alt : Icons.upload,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            onPressed: _toggleMode,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Soft Mode Status Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isTicketScanMode
                                  ? const Color(0xFFFF512F)
                                  : const Color(0xFF4776E6))
                              .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            (isTicketScanMode
                                    ? const Color(0xFFFF512F)
                                    : const Color(0xFF4776E6))
                                .withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      isTicketScanMode
                          ? context.tr('scanning_trail_tickets')
                          : context.tr('scanning_burgenland_cards'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Bottom buttons
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isUploadMode ||
                            !_cameraAvailable ||
                            !_hasCameraPermission)
                          FloatingActionButton.extended(
                            heroTag: 'upload_image',
                            onPressed: _pickImage,
                            backgroundColor: Colors.white.withOpacity(0.9),
                            icon: const Icon(
                              Icons.image,
                              color: Colors.black87,
                            ),
                            label: Text(
                              context.tr('upload_qr_image'),
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scanning overlay
            if (!_isUploadMode && _cameraAvailable && _hasCameraPermission)
              Center(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: const Center(
                      child: SizedBox(width: 300, height: 300),
                    ),
                  ),
                ),
              ),

            // Camera initialization progress overlay
            if (_isInitializingCamera)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('init_camera'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // QR code processing progress overlay
            if (_isProcessingQR)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Scanning QR Code...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InAppBrowserScreen extends StatefulWidget {
  final String url;
  final String? injectValue;

  const InAppBrowserScreen({super.key, required this.url, this.injectValue});

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  InAppWebViewController? webViewController;
  double progress = 0;
  bool isLoading = true;
  String currentUrl = '';
  bool _hasFatalError = false;

  // Whitelisted base URL (same as in QRScannerScreen)

  bool _isWhitelistedUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    if (kDebugMode) return true;

    final lowerUrl = url.toLowerCase();

    // Remove http:// or https:// from both the scanned URL and the whitelisted base URL
    final baseWithoutScheme = whitelistedBaseUrl
        .toLowerCase()
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '');

    final urlWithoutScheme = lowerUrl.replaceFirst(RegExp(r'^https?://'), '');

    if (urlWithoutScheme.startsWith(baseWithoutScheme)) return true;

    // Special allowance for Burgenland Card / Ticket modes
    if (lowerUrl.contains('feratel.com') ||
        lowerUrl.contains('burgenlandtrails.at')) {
      return true;
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // extendBodyBehindAppBar: true,
      // extendBody: true,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useShouldOverrideUrlLoading: true,
              supportMultipleWindows: true,
              cacheEnabled: true,
              clearCache: false,
              safeBrowsingEnabled: false,
              useOnDownloadStart: true,
              useOnLoadResource: true,
              // Unified settings for 6.x
              useHybridComposition: true,
              hardwareAcceleration: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              isFraudulentWebsiteWarningEnabled: false,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  (function() {
                    function patchConstraints(constraints) {
                      if (constraints && constraints.video) {
                        if (typeof constraints.video === 'boolean') {
                          constraints.video = { facingMode: { exact: 'environment' } };
                        } else if (typeof constraints.video === 'object') {
                          constraints.video.facingMode = { exact: 'environment' };
                          // Remove any conflicting deviceId
                          delete constraints.video.deviceId;
                        }
                        console.log('Antigravity: Patched constraints to force back camera', constraints);
                      }
                    }

                    // Patch navigator.mediaDevices.getUserMedia
                    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                      const originalGetUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
                      navigator.mediaDevices.getUserMedia = function(constraints) {
                        patchConstraints(constraints);
                        return originalGetUserMedia(constraints);
                      };
                    }
                    
                    // Patch older navigator.getUserMedia
                    const legacyGetUserMedia = navigator.getUserMedia || navigator.webkitGetUserMedia || navigator.mozGetUserMedia || navigator.msGetUserMedia;
                    if (legacyGetUserMedia) {
                      const originalLegacyGetUserMedia = legacyGetUserMedia.bind(navigator);
                      navigator.getUserMedia = function(constraints, success, error) {
                        patchConstraints(constraints);
                        return originalLegacyGetUserMedia(constraints, success, error);
                      };
                    }
                    
                    // Also patch mediaDevices.enumerateDevices to prioritize back camera if possible
                    if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
                      const originalEnumerateDevices = navigator.mediaDevices.enumerateDevices.bind(navigator.mediaDevices);
                      navigator.mediaDevices.enumerateDevices = async function() {
                        const devices = await originalEnumerateDevices();
                        console.log('Antigravity: Detected devices', devices);
                        return devices;
                      };
                    }
                  })();
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: false,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'ScanResult',
                callback: (args) {
                  if (!mounted) return;
                  String type = args[0];

                  if (type == 'ticket') {
                    String status = args[1].toString();
                    ReportService().incrementTicketScan(status: status);
                    // Submit this single scan result to remote API
                    ReportApiService().submitReport(
                      scanType: 'ticket',
                      scanResult: status,
                    );
                  } else {
                    bool success = args[1] as bool;
                    ReportService().incrementBurgenlandScan(success: success);
                    // Submit this single scan result to remote API
                    ReportApiService().submitReport(
                      scanType: 'burgenland',
                      scanResult: success ? 'success' : 'fail',
                    );
                  }

                  // ScaffoldMessenger.of(context).showSnackBar(
                  //   SnackBar(
                  //     content: Text(
                  //       success ? 'Scan Successful' : 'Scan Failed',
                  //     ),
                  //     backgroundColor: success ? Colors.green : Colors.red,
                  //     duration: const Duration(seconds: 2),
                  //   ),
                  // );
                  // Navigator.of(context).pop();
                },
              );
            },
            onPermissionRequest: (controller, permissionRequest) async {
              final grantedResources = <PermissionResourceType>[];
              for (final resource in permissionRequest.resources) {
                if (resource == PermissionResourceType.CAMERA) {
                  grantedResources.add(resource);
                }
              }
              return PermissionResponse(
                resources: grantedResources,
                action: grantedResources.isNotEmpty
                    ? PermissionResponseAction.GRANT
                    : PermissionResponseAction.DENY,
              );
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              // Check if the URL is whitelisted
              if (!_isWhitelistedUrl(url)) {
                print(
                  'Navigation blocked. Only ${whitelistedBaseUrl} is allowed. URL: ${url}',
                );
                // Block navigation and show alert
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${context.tr('nav_blocked_1')} $whitelistedBaseUrl ${context.tr('nav_blocked_2')}',
                      ),
                      duration: const Duration(seconds: 3),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return NavigationActionPolicy.CANCEL;
              }

              // Allow navigation to whitelisted URLs
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              // Double-check URL on load start
              final urlString = url.toString();
              if (!_isWhitelistedUrl(urlString)) {
                controller.stopLoading();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${context.tr('nav_blocked_1')} $whitelistedBaseUrl ${context.tr('nav_blocked_2')}',
                      ),
                      duration: const Duration(seconds: 3),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }

              setState(() {
                isLoading = true;
                currentUrl = urlString;
              });
            },
            onLoadStop: (controller, url) async {
              final urlString = url.toString();
              setState(() {
                isLoading = false;
                currentUrl = urlString;
              });

              // Auto-fill and submit for Burgenland Trails (with protection)
              if (widget.injectValue != null &&
                  urlString.contains('burgenlandtrails.at') &&
                  urlString.contains('mqz1ppt')) {
                try {
                  await controller.evaluateJavascript(
                    source:
                        """
                    (function() {
                      if (window._injectTicketStarted) return;
                      window._injectTicketStarted = true;
                      
                      var checkExist = setInterval(function() {
                        var input = document.getElementById('bt_ticket_id');
                        var button = document.getElementById('submit-ticket-id');
                        if (input) {
                          clearInterval(checkExist);
                          input.value = '${widget.injectValue}';
                          if (button) {
                            setTimeout(function() { button.click(); }, 300);
                          }
                        }
                      }, 500);
                      
                      setTimeout(function() { clearInterval(checkExist); }, 10000);
                    })();
                  """,
                  );
                } catch (e) {
                  debugPrint("Error injecting ticket ID: $e");
                }
              }

              // Auto-fill and login for Feratel Checkpoints (Resilient JS with protection)
              if (urlString.contains('feratel.com')) {
                try {
                  await controller.evaluateJavascript(
                    source: """
                    (function() {
                      if (window._autoLoginStarted) return;
                      var userField = document.getElementById('username');
                      if (!userField) return; // Only run on login page
                      
                      window._autoLoginStarted = true;
                      var attempts = 0;
                      var maxAttempts = 10;
                      var loginInterval = setInterval(function() {
                        var user = document.getElementById('username');
                        var pass = document.getElementById('password');
                        var loginBtn = document.querySelector('button[name="login"]');
                        
                        if (user && pass) {
                          clearInterval(loginInterval);
                          user.value = 'TaxLoi';
                          pass.value = 'TaxLoi1';
                          if (loginBtn) {
                            setTimeout(function() { loginBtn.click(); }, 300);
                          } else {
                            var form = document.querySelector('form');
                            if (form) form.submit();
                          }
                        }
                        
                        attempts++;
                        if (attempts >= maxAttempts) {
                          clearInterval(loginInterval);
                        }
                      }, 500);
                    })();
                  """,
                  );
                } catch (e) {
                  debugPrint("Error auto-logging in: $e");
                }
              }

              // Scan result evaluator
              try {
                final evaluatorScript = """
                if (!window.reportScanTaskStarted) {
                  window.reportScanTaskStarted = true;

                  const isTicketMode = window.location.href.includes('burgenlandtrails');
                  
                  if (isTicketMode) {
                      window._lastTicketSuccess = false;
                      window._lastTicketInvalid = false;
                      window._lastTicketFail = false;

                      // Check for result periodically
                      setInterval(() => {
                         const resultDiv = document.getElementById('bt-ticket-result');
                         if (resultDiv) {
                            const text = resultDiv.innerText || resultDiv.textContent || '';
                            if (text.includes('✅ Gültiges Ticket')) {
                               if (!window._lastTicketSuccess) {
                                  window._lastTicketSuccess = true;
                                  window._lastTicketInvalid = false;
                                  window._lastTicketFail = false; 
                                  window.flutter_inappwebview.callHandler('ScanResult', 'ticket', 'success');
                               }
                            } else if (text.includes('⚠️ Ticket ist ungültig')) {
                               if (!window._lastTicketInvalid) {
                                  window._lastTicketInvalid = true;
                                  window._lastTicketSuccess = false;
                                  window._lastTicketFail = false;
                                  window.flutter_inappwebview.callHandler('ScanResult', 'ticket', 'invalid');
                               }
                            } else if (text.includes('Ticket existiert nicht') || text.includes('Fehler bei der Anfrage')) {
                               if (!window._lastTicketFail) {
                                  window._lastTicketFail = true;
                                  window._lastTicketSuccess = false;
                                  window._lastTicketInvalid = false;
                                  window.flutter_inappwebview.callHandler('ScanResult', 'ticket', 'fail');
                               }
                            }
                         }
                      }, 500);

                      // Recognize new scans (resetting the tracking flags)
                      document.addEventListener('click', (e) => {
                          if (e.target && (e.target.id === 'submit-ticket-id' || e.target.closest('#submit-ticket-id'))) {
                              window._lastTicketSuccess = false;
                              window._lastTicketInvalid = false;
                              window._lastTicketFail = false;
                          }
                      });
                      document.addEventListener('submit', (e) => {
                          window._lastTicketSuccess = false;
                          window._lastTicketInvalid = false;
                          window._lastTicketFail = false;
                      });

                  } else {
                      // Burgenland Card logic (keeps the single-shot / single-page behavior)
                      const checkInterval = setInterval(() => {
                         const statusDiv = document.querySelector('.text-center.status');
                         if (statusDiv) {
                            const text = statusDiv.innerText || statusDiv.textContent || '';
                            if (text.includes('OK')) {
                               clearInterval(checkInterval);
                               window.flutter_inappwebview.callHandler('ScanResult', 'burgenland', true);
                            } else if (text.includes('NO') || text.includes('nicht gefunden')) {
                               clearInterval(checkInterval);
                               window.flutter_inappwebview.callHandler('ScanResult', 'burgenland', false);
                            }
                         }
                      }, 500);
                  }
                }
              """;
                await controller.evaluateJavascript(source: evaluatorScript);
              } catch (e) {
                debugPrint("Error evaluating result script: $e");
              }
            },
            onProgressChanged: (controller, progress) {
              setState(() {
                this.progress = progress / 100;
              });
            },
            onReceivedError: (controller, request, error) {
              setState(() {
                isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${context.tr('error_loading_page')} ${error.description}',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            onRenderProcessGone: (controller, detail) {
              setState(() {
                _hasFatalError = true;
              });
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Glass back button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),

                    // URL/Security Domain Pill (Subtle)
                    if (currentUrl.isNotEmpty)
                      Expanded(
                        child: Container(
                          // margin: const EdgeInsets.symmetric(horizontal: 16),
                          // padding: const EdgeInsets.symmetric(
                          //   horizontal: 12,
                          //   vertical: 8,
                          // ),
                          // decoration: BoxDecoration(
                          //   color: Colors.black.withOpacity(0.35),
                          //   borderRadius: BorderRadius.circular(20),
                          // ),
                          // child: Row(
                          //   mainAxisSize: MainAxisSize.min,
                          //   mainAxisAlignment: MainAxisAlignment.center,
                          //   children: [
                          //     Icon(
                          //       Icons.lock_rounded,
                          //       size: 12,
                          //       color: Colors.greenAccent.withOpacity(0.9),
                          //     ),
                          //     const SizedBox(width: 8),
                          //     Flexible(
                          //       child: Text(
                          //         WebUri(currentUrl).host,
                          //         maxLines: 1,
                          //         overflow: TextOverflow.ellipsis,
                          //         style: TextStyle(
                          //           color: Colors.white.withOpacity(0.9),
                          //           fontSize: 12,
                          //           fontWeight: FontWeight.w500,
                          //         ),
                          //       ),
                          //     ),
                          //   ],
                          // ),
                        ),
                      ),

                    // Glass reload button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      onPressed: () => webViewController?.reload(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Progress indicator at top (below safe area)
          if (isLoading && progress < 1.0)
            Positioned(
              // top: MediaQuery.of(context).padding.top + 56, // Push below header
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
          if (_hasFatalError)
            Container(
              color: Colors.black.withOpacity(0.9),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.redAccent,
                        size: 64,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('webview_crash_error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr('restart_app_required'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: Text(context.tr('close')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
