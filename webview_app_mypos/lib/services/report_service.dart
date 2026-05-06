import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simplified ReportService that only handles local scan counters.
/// Removed background tasks, mailing, and alarm scheduling as requested.
class ReportService {
  static const String _burgenlandPrefix = 'burgenland_count_';
  static const String _burgenlandFailPrefix = 'burgenland_fail_count_';
  static const String _ticketPrefix = 'ticket_count_';
  static const String _ticketInvalidPrefix = 'ticket_invalid_count_';
  static const String _ticketFailPrefix = 'ticket_fail_count_';

  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  Future<void> initialize() async {
    // Basic initialization if needed in the future
    debugPrint("ReportService initialized (Local Counters Only)");
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
}
