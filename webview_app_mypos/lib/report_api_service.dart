import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Service responsible for submitting scan reports to the remote API
/// after every scan event (Burgenland or Ticket).
///
/// Uses Dio with retry logic and timeout handling.
/// Follows the Repository pattern – no direct API calls from UI.
class ReportApiService {
  static final ReportApiService _instance = ReportApiService._internal();
  factory ReportApiService() => _instance;
  ReportApiService._internal();

  static const String _tag = '[REPORT_API]';
  static const String _baseUrl = 'http://168.119.21.197:8080';
  static const String _submitReportPath = '/api/submit_report';
  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 10);

  /// Auto-incrementing call counter for unique log identification
  static int _callCount = 0;

  late final Dio _dio = _createDio();

  // Cached device info to avoid repeated async lookups
  String? _cachedDeviceId;
  String? _cachedDeviceName;
  String? _cachedAppVersion;

  Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add logging interceptor in debug mode
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (obj) => debugPrint('$_tag [DIO] $obj'),
        ),
      );
    }

    return dio;
  }

  /// Initialize device info cache at app start for faster submissions.
  Future<void> init() async {
    debugPrint('$_tag 🚀 Initializing ReportApiService...');
    await _loadDeviceInfo();
    debugPrint('$_tag ✅ Initialized | device_id=$_cachedDeviceId | device_name=$_cachedDeviceName | app_version=$_cachedAppVersion');
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _cachedDeviceId = androidInfo.id;
        _cachedDeviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedDeviceId = iosInfo.identifierForVendor ?? iosInfo.name;
        _cachedDeviceName = iosInfo.name;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      _cachedAppVersion = packageInfo.version;
    } catch (e) {
      debugPrint('$_tag ❌ Error loading device info: $e');
    }
  }

  /// Submits a single scan result to the remote API.
  ///
  /// Called after every scan event. Sends only the result of the
  /// individual scan that just occurred (not cumulative data).
  ///
  /// [scanType] – 'ticket' or 'burgenland'
  /// [scanResult] – 'success', 'fail', or 'invalid' (invalid only for ticket)
  ///
  /// Uses retry logic with exponential backoff.
  Future<bool> submitReport({
    required String scanType,
    required String scanResult,
  }) async {
    _callCount++;
    final callId = _callCount;
    final timestamp = DateTime.now().toIso8601String();

    debugPrint('');
    debugPrint('══════════════════════════════════════════════');
    debugPrint('$_tag #$callId 📤 API CALL STARTED');
    debugPrint('$_tag #$callId ⏰ Timestamp: $timestamp');
    debugPrint('$_tag #$callId 🔍 Scan Type: $scanType | Result: $scanResult');
    debugPrint('══════════════════════════════════════════════');

    try {
      // Ensure device info is loaded
      if (_cachedDeviceId == null) {
        debugPrint('$_tag #$callId ⚠️ Device info not cached, loading now...');
        await _loadDeviceInfo();
      }

      // Build payload with only the current scan result (1 for match, 0 for rest)
      final payload = {
        'device_id': _cachedDeviceId ?? 'unknown_device',
        'device_name': _cachedDeviceName ?? 'Unknown Device',
        'app_version': _cachedAppVersion ?? '1.0.0',
        'burgenland_success':
            (scanType == 'burgenland' && scanResult == 'success') ? 1 : 0,
        'burgenland_fail':
            (scanType == 'burgenland' && scanResult == 'fail') ? 1 : 0,
        'ticket_success':
            (scanType == 'ticket' && scanResult == 'success') ? 1 : 0,
        'ticket_invalid':
            (scanType == 'ticket' && scanResult == 'invalid') ? 1 : 0,
        'ticket_fail':
            (scanType == 'ticket' && scanResult == 'fail') ? 1 : 0,
      };

      debugPrint('$_tag #$callId 📦 Payload: $payload');
      debugPrint('$_tag #$callId 🌐 POST $_baseUrl$_submitReportPath');

      // Retry with exponential backoff
      for (int attempt = 1; attempt <= _maxRetries; attempt++) {
        try {
          debugPrint('$_tag #$callId 🔄 Attempt $attempt/$_maxRetries...');

          final response = await _dio.post(
            _submitReportPath,
            data: payload,
          );

          debugPrint('$_tag #$callId 📥 Response status: ${response.statusCode}');
          debugPrint('$_tag #$callId 📥 Response body: ${response.data}');

          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('$_tag #$callId ✅ SUCCESS - Report submitted (attempt $attempt)');
            debugPrint('══════════════════════════════════════════════');
            debugPrint('');
            return true;
          } else {
            debugPrint(
              '$_tag #$callId ⚠️ Unexpected status code: ${response.statusCode} (attempt $attempt)',
            );
          }
        } on DioException catch (e) {
          debugPrint(
            '$_tag #$callId ❌ FAILED (attempt $attempt/$_maxRetries): ${e.type} - ${e.message}',
          );
          if (e.response != null) {
            debugPrint('$_tag #$callId 📥 Error response: ${e.response?.data}');
          }

          if (attempt < _maxRetries) {
            // Exponential backoff: 1s, 2s, 4s
            final delay = Duration(seconds: 1 << (attempt - 1));
            debugPrint('$_tag #$callId ⏳ Retrying in ${delay.inSeconds}s...');
            await Future.delayed(delay);
          } else {
            debugPrint('$_tag #$callId 💀 ALL RETRIES EXHAUSTED - Logging to Sentry');
            // Final attempt failed – log to Sentry
            try {
              Sentry.captureException(
                e,
                stackTrace: e.stackTrace,
                withScope: (scope) {
                  scope.setTag('api_endpoint', _submitReportPath);
                  scope.setTag('call_id', callId.toString());
                  scope.setContexts('request_payload', payload);
                },
              );
            } catch (_) {}
          }
        }
      }

      debugPrint('$_tag #$callId ❌ FINAL RESULT: FAILED');
      debugPrint('══════════════════════════════════════════════');
      debugPrint('');
      return false;
    } catch (e, stackTrace) {
      debugPrint('$_tag #$callId ❌ UNEXPECTED ERROR: $e');
      debugPrint('══════════════════════════════════════════════');
      debugPrint('');
      try {
        Sentry.captureException(e, stackTrace: stackTrace);
      } catch (_) {}
      return false;
    }
  }
}
