import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'cron_task_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class ReportService {
  static const String _burgenlandPrefix = 'burgenland_count_';
  static const String _burgenlandFailPrefix = 'burgenland_fail_count_';
  static const String _ticketPrefix = 'ticket_count_';
  static const String _ticketInvalidPrefix = 'ticket_invalid_count_';
  static const String _ticketFailPrefix = 'ticket_fail_count_';

  // Make it a singleton
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  Future<void> init() async {
    // 1. Request necessary permissions for background reliability
    if (Platform.isAndroid) {
      await Permission.notification.request();

      // We still do initial requests here, but the UI will handle thorough checks
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }

      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    }

    // 2. Initialize Alarm Manager for EXACT timing even if killed
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();

      // Schedule the primary daily trigger at 23:55 (11:55 PM)
      // Use index 0 for this specific task
      await AndroidAlarmManager.periodic(
        const Duration(days: 1),
        0,
        alarmCallback,
        exact: true,
        wakeup: true,
        startAt: _getNextOccurrence(23, 55),
        rescheduleOnReboot: true,
      );

      // Hourly check to ensure the service remains active (Safety net)
      // Use index 1 for this specific task
      await AndroidAlarmManager.periodic(
        const Duration(minutes: 15),
        1,
        hourlyServiceCheckCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    }

    // 3. (REMOVED) We no longer auto-send missed emails on app start. User wants this manual.
    // We only check for missing dates on-demand in the Info overlay.
    // await _checkAndSendEmail();
    // 4. Initialize Foreground Service for status and persistence
    await initializeService();
  }

  // Calculate next occurrence of a specific time (HH:mm)
  DateTime _getNextOccurrence(int hour, int minute) {
    final now = DateTime.now();
    DateTime scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'scan_app_foreground',
      'Scan App Background Service',
      description: 'Ensures daily reports are sent exactly at scheduled time.',
      importance: Importance.high,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'scan_app_foreground',
        initialNotificationTitle: 'Scan APP Background Service',
        initialNotificationContent: 'Running schedule...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  void dispose() {
    // No longer using internal timer as service handles it
  }

  String _getDateString(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> incrementBurgenlandScan({bool success = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = _getDateString(DateTime.now());
      final key = success
          ? "$_burgenlandPrefix$date"
          : "$_burgenlandFailPrefix$date";
      int current = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, current + 1);
      debugPrint(
        "Burgenland scan incremented (success: $success): ${current + 1} for $date",
      );
    } catch (e) {
      debugPrint("Error incrementing burgenland scan: $e");
    }
  }

  Future<void> incrementTicketScan({String status = 'success'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = _getDateString(DateTime.now());
      String key;
      if (status == 'success') {
        key = "$_ticketPrefix$date";
      } else if (status == 'invalid') {
        key = "$_ticketInvalidPrefix$date";
      } else {
        key = "$_ticketFailPrefix$date";
      }

      int current = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, current + 1);
      debugPrint(
        "Ticket scan incremented (status: $status): ${current + 1} for $date",
      );
    } catch (e) {
      debugPrint("Error incrementing ticket scan: $e");
    }
  }

  Future<void> _checkAndSendEmail() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    if (kDebugMode) {
      // Uncomment to force send for debugging
      await sendMail(now);
      return;
    }

    // 1. Check if we missed sending for YESTERDAY completely
    // E.g., device was off at 23:55 or app killed and service failed
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = _getDateString(yesterday);
    final sentYesterdayStrKey = "sent_$yesterdayStr";

    if (prefs.getBool(sentYesterdayStrKey) != true) {
      // We haven't sent yesterday's report yet. Send it immediately!
      bool success = await sendMail(yesterday);
      if (success) {
        await prefs.setBool(sentYesterdayStrKey, true);
      }
    }

    // 2. Check if we reached the scheduled time TODAY
    // Execute schedule specifically at 23:55 PM every day
    final todayStr = _getDateString(now);
    final sentTodayStrKey = "sent_$todayStr";
    final sendHour = 23;
    final sendMinute = 55;

    if (now.hour == sendHour && now.minute >= sendMinute) {
      // It's time to send today's report
      if (prefs.getBool(sentTodayStrKey) != true) {
        bool success = await sendMail(now);
        if (success) {
          await prefs.setBool(sentTodayStrKey, true);
        }
      }
    }
  }

  Future<Map<String, int>> getReportData(DateTime reportDate) async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = _getDateString(reportDate);

    return {
      'burgenlandCount': prefs.getInt("$_burgenlandPrefix$dateStr") ?? 0,
      'burgenlandFailCount':
          prefs.getInt("$_burgenlandFailPrefix$dateStr") ?? 0,
      'ticketCount': prefs.getInt("$_ticketPrefix$dateStr") ?? 0,
      'ticketInvalidCount': prefs.getInt("$_ticketInvalidPrefix$dateStr") ?? 0,
      'ticketFailCount': prefs.getInt("$_ticketFailPrefix$dateStr") ?? 0,
    };
  }

  Future<bool> sendMail(DateTime reportDate, {String? subject}) async {
    try {
      final dateStr = _getDateString(reportDate);
      final data = await getReportData(reportDate);

      int burgenlandCount = data['burgenlandCount']!;
      int burgenlandFailCount = data['burgenlandFailCount']!;
      int ticketCount = data['ticketCount']!;
      int ticketInvalidCount = data['ticketInvalidCount']!;
      int ticketFailCount = data['ticketFailCount']!;

      debugPrint("===  DEBUG LOG ===");
      debugPrint("Date: $dateStr");
      debugPrint(
        "Burgenland Scans -> Local DB: Success = $burgenlandCount, Failed = $burgenlandFailCount",
      );
      debugPrint(
        "Ticket Scans     -> Local DB: Success = $ticketCount, Invalid = $ticketInvalidCount, Failed = $ticketFailCount",
      );
      debugPrint("===================================");

      if (kDebugMode) {
        // In debug mode we still return true but don't actually send via SMTP if desired,
        // but here the user might want to see it.
        // Actually, the original code had: if (kDebugMode) return true;
        // return true;
      }

      String deviceName = "Unknown Device";
      try {
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
      } catch (e) {
        debugPrint("Error getting device info: $e");
      }

      String appVersion = "Unknown";
      try {
        final PackageInfo packageInfo = await PackageInfo.fromPlatform();
        appVersion = "${packageInfo.version} (${packageInfo.buildNumber})";
      } catch (e) {
        debugPrint("Error getting app version: $e");
      }

      final smtpServer = SmtpServer(
        'smtp.node4web.at',
        port: 465,
        ssl: true,
        username: 'logoreport@aecora.at',
        password: 'jxVnnuFs_9XCQ',
      );

      final message = Message()
        ..from = const Address('logoreport@aecora.at', 'Scan APP')
        ..recipients.add('Office@logo1.at')
        ..ccRecipients.add('markus.matousek@aecora.at')
        ..bccRecipients.add('keyurdev.7@gmail.com')
        ..subject = subject ?? 'Daily Scan Report - $dateStr'
        ..html =
            """
          <h2>Daily Scan Report</h2>
          <p>Date: $dateStr</p>
          <p>Device: $deviceName</p>
          <hr/>
          <table border="1" cellpadding="5" cellspacing="0" style="text-align: center;">
            <tr style="background-color: #f2f2f2;">
              <th>Scan Type</th>
              <th style="color: green;">Successful</th>
              <th style="color: orange;">Invalid</th>
              <th style="color: red;">Wrong QR Code</th>
              <th>Total</th>
            </tr>
            <tr>
              <td style="text-align: left;">Burgenland Card</td>
              <td>$burgenlandCount</td>
              <td>-</td>
              <td>$burgenlandFailCount</td>
              <td>${burgenlandCount + burgenlandFailCount}</td>
            </tr>
            <tr>
              <td style="text-align: left;">Ticket Scan</td>
              <td>$ticketCount</td>
              <td>$ticketInvalidCount</td>
              <td>$ticketFailCount</td>
              <td>${ticketCount + ticketInvalidCount + ticketFailCount}</td>
            </tr>
            <tr style="font-weight: bold; background-color: #e6e6e6;">
              <th style="text-align: left;">Grand Total</th>
              <th style="color: green;">${burgenlandCount + ticketCount}</th>
              <th style="color: orange;">$ticketInvalidCount</th>
              <th style="color: red;">${burgenlandFailCount + ticketFailCount}</th>
              <th>${burgenlandCount + ticketCount + ticketInvalidCount + burgenlandFailCount + ticketFailCount}</th>
            </tr>
          </table>
          <br/>
          <p><em>Auto-generated by Scan App on device.</em></p>
          <p>Version: $appVersion</p>
        """;

      debugPrint(
        "Sending email report for $dateStr to markus.matousek@aecora.at ...",
      );
      if (!kDebugMode) {
        final sendReportResult = await send(message, smtpServer);
        debugPrint(
          '✅ Message successfully sent: ${sendReportResult.toString()}',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'last_mail_sent_time',
          DateTime.now().toIso8601String(),
        );
        // Log Success to Sentry (Only if initialized)
        try {
          Sentry.captureMessage(
            "✅ Mail Report Sent Successfully",
            level: SentryLevel.info,
            withScope: (scope) {
              scope.setTag("date", dateStr);
              scope.setTag("device", deviceName);
              scope.setContexts("report_data", data);
            },
          );
        } catch (e) {
          debugPrint("Sentry not initialized in this isolate: $e");
        }
      } else {
        // Also record it in debug mode to test UI if needed
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'last_mail_sent_time',
          DateTime.now().toIso8601String(),
        );

        // Log Debug Trigger to Sentry
        try {
          Sentry.addBreadcrumb(
            Breadcrumb(
              category: 'mail_report',
              message: 'Debug Mail Triggered (No SMTP)',
              data: {'date': dateStr, 'device': deviceName, 'data': data},
              level: SentryLevel.debug,
            ),
          );
        } catch (e) {
          debugPrint("Sentry not initialized in this isolate: $e");
        }
      }

      return true;
    } on MailerException catch (e, stackTrace) {
      debugPrint('❌ MailerException occurred while sending email:');
      for (var problem in e.problems) {
        debugPrint('Problem: ${problem.code}: ${problem.msg}');
      }
      // Capture Exception in Sentry
      try {
        Sentry.captureException(e, stackTrace: stackTrace);
      } catch (_) {}
      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ General error sending report email: $e');
      // Capture Exception in Sentry
      try {
        Sentry.captureException(e, stackTrace: stackTrace);
      } catch (_) {}
      return false;
    }
  }

  Future<List<DateTime>> getMissedReportDates() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    List<DateTime> missed = [];

    // Check yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = _getDateString(yesterday);
    if (prefs.getBool("sent_$yesterdayStr") != true) {
      missed.add(yesterday);
    }

    // Check today (past 23:55)
    final todayStr = _getDateString(now);
    if (now.hour == 23 && now.minute >= 55) {
      if (prefs.getBool("sent_$todayStr") != true) {
        missed.add(now);
      }
    }
    return missed;
  }

  Future<bool> sendManualReport(DateTime reportDate) async {
    bool success = await sendMail(reportDate);
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("sent_${_getDateString(reportDate)}", true);
    }
    return success;
  }

  // Exposed for workmanager/alarm use
  static Future<void> checkAndSendEmailBackground() async {
    final instance = ReportService._internal();
    await instance._checkAndSendEmail();
  }

  // Permission helpers
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true;
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  static Future<bool> isExactAlarmPermissionGranted() async {
    if (!Platform.isAndroid) return true;
    return await Permission.scheduleExactAlarm.isGranted;
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  static Future<void> requestExactAlarmPermission() async {
    if (Platform.isAndroid) {
      await Permission.scheduleExactAlarm.request();
    }
  }
}

@pragma('vm:entry-point')
void alarmCallback() async {
  debugPrint("⏰ [ALARM] Triggered daily mail schedule");
  await ReportService.checkAndSendEmailBackground();
}

@pragma('vm:entry-point')
void hourlyServiceCheckCallback() async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint("⏰ [ALARM] Hourly service status check triggered");
  final service = FlutterBackgroundService();
  bool isRunning = await service.isRunning();
  if (!isRunning) {
    debugPrint("⚠️ Background service not running, attempting to start...");
    // Just start it. DO NOT call initializeService() here as it calls .configure()
    // which is only allowed in the main isolate.
    await service.startService();
  } else {
    debugPrint("✅ Background service is already active. Skipping.");
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize CronTaskService for background report flow
  // CronTaskService().init();

  if (service is AndroidServiceInstance) {
    // Explicitly set as foreground immediately to prevent OS from killing it
    service.setAsForegroundService();

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Background status update loop (also serves as a secondary timer)
  Timer.periodic(const Duration(minutes: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "Scan APP Service",
          content:
              "Active & Monitoring schedule (Last check ${DateTime.now().hour}:${DateTime.now().minute})",
        );
      }
    }
    // Still run the check as a fallback every 10 mins if alive
    await ReportService.checkAndSendEmailBackground();
  });
}
