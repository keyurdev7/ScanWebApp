import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/report_service.dart';
import '../../services/report_api_service.dart';
import '../../l10n/app_localizations.dart';
import '../scanner/qr_scanner_screen.dart';
import '../browser/in_app_browser_screen.dart';
import '../../core/providers.dart';
import '../../main.dart' show myAppKey;

class SelectionScreen extends ConsumerStatefulWidget {
  const SelectionScreen({super.key});

  @override
  ConsumerState<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends ConsumerState<SelectionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Delay initialization of background checks and logging to avoid race conditions
    // during early startup on specialized devices (e.g., qcom F20)
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        ReportApiService().logAppStart();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _showAppInfoDialog() async {
    String appVersion = "Unknown";
    String deviceName = "Unknown";
    String lastMailSentStr = context.tr('no_history');
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
    return await _requestAndHandlePermission(
      Permission.camera,
      'camera_permission_required',
      'camera_permission_content',
    );
  }

  Future<bool> _requestAndHandlePermission(
    Permission permission,
    String titleKey,
    String contentKey,
  ) async {
    if (kIsWeb) return true;
    var status = await permission.request();
    if (status.isGranted || status.isLimited) return true;
    if (mounted) {
      await _showPermissionSettingsDialog(titleKey, contentKey);
    }
    return false;
  }

  Future<void> _showPermissionSettingsDialog(
    String titleKey,
    String contentKey,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.tr(titleKey)),
        content: Text(context.tr(contentKey)),
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

  Future<bool> _checkAndRequestLocationPermission() async {
    if (kIsWeb) return true;
    await Permission.accessMediaLocation.request();
    return await _requestAndHandlePermission(
      Permission.locationWhenInUse,
      'location_permission_required',
      'location_permission_content',
    );
  }

  Future<bool> _checkAndRequestGalleryPermission() async {
    return true;
    // if (kIsWeb) return true;
    // if (Platform.isAndroid) {
    //   final status = await Permission.photos.status;
    //   if (status.isGranted || status.isLimited) return true;
    //   bool granted = await _requestAndHandlePermission(
    //     Permission.photos,
    //     'gallery_permission_required',
    //     'gallery_permission_content',
    //   );
    //   if (!granted) {
    //     granted = await _requestAndHandlePermission(
    //       Permission.storage,
    //       'gallery_permission_required',
    //       'gallery_permission_content',
    //     );
    //   }
    //   return granted;
    // }
    // return await _requestAndHandlePermission(
    //   Permission.photos,
    //   'gallery_permission_required',
    //   'gallery_permission_content',
    // );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) SystemNavigator.pop();
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildCircleButton(
                              Icons.info_outline_rounded,
                              _showAppInfoDialog,
                              context.tr('app_info_tooltip'),
                            ),
                            _buildLanguageDropdown(),
                          ],
                        ),
                        // const SizedBox(height: 20),
                        _buildHeaderIcon(),
                        const SizedBox(height: 8),
                        _buildHeaderText(),
                        const SizedBox(height: 20),
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
                            ref
                                    .read(whitelistedBaseUrlProvider.notifier)
                                    .state =
                                'https://card-mobile-check.feratel.com/';
                            ref.read(isTicketScanModeProvider.notifier).state =
                                false;
                            if (await _checkAndRequestPermissions()) {
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
                            ref
                                    .read(whitelistedBaseUrlProvider.notifier)
                                    .state =
                                'https://burgenlandtrails.at/';
                            ref.read(isTicketScanModeProvider.notifier).state =
                                true;
                            if (await _checkAndRequestPermissions()) {
                              if (context.mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const QRScannerScreen(),
                                  ),
                                );
                              }
                            }
                          },
                        ),
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

  Future<bool> _checkAndRequestPermissions() async {
    return (await _checkAndRequestCameraPermission()) &&
        (await _checkAndRequestLocationPermission()) &&
        (await _checkAndRequestGalleryPermission());
  }

  Widget _buildCircleButton(
    IconData icon,
    VoidCallback onPressed,
    String tooltip,
  ) {
    return Container(
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
        icon: Icon(icon, color: const Color(0xFF6C757D), size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _buildLanguageDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
          value: Localizations.localeOf(context).languageCode,
          icon: const Icon(
            Icons.language_rounded,
            size: 18,
            color: Color(0xFF6C757D),
          ),
          isDense: true,
          items: const [
            DropdownMenuItem(
              value: 'de',
              child: Text('DE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            DropdownMenuItem(
              value: 'en',
              child: Text('EN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
          onChanged: (String? newValue) {
            if (newValue != null) {
              LanguageSettings.setLanguage(newValue);
              myAppKey.currentState?.setLocale(Locale(newValue));
            }
          },
        ),
      ),
    );
  }

  Widget _buildHeaderIcon() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.qr_code_scanner_rounded,
          size: 45,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildHeaderText() {
    return Column(
      children: [
        Text(
          context.tr('choose_scan_type'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E1E1E),
          ),
        ),
        // const SizedBox(height: 8),
        Text(
          context.tr('scan_type_description'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF6C757D),
            height: 1.5,
          ),
        ),
      ],
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
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
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
