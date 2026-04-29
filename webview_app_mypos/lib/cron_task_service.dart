// import 'package:cron/cron.dart';
// import 'package:flutter/foundation.dart';
// import 'report_service.dart';

// class CronTaskService {
//   static final CronTaskService _instance = CronTaskService._internal();
//   factory CronTaskService() => _instance;
//   CronTaskService._internal();

//   final _cron = Cron();

//   void init() {
//     if (kDebugMode) {
//       debugPrint("Initializing CronTaskService with cron package...");
//     }

//     // Schedule the task to run every day at 23:55
//     // Format: 'minutes hours day month weekday'
//     _cron.schedule(Schedule.parse('55 23 * * *'), () async {
//       debugPrint("🕒 [CRON Package] Triggering scheduled job...");
//       await SendMail();
//     });

//     // Optional: For testing in debug mode, you could trigger it every minute
//     /*
//     if (kDebugMode) {
//       _cron.schedule(Schedule.parse('* * * * *'), () async {
//          debugPrint("🕒 [CRON Package Test] Minutely trigger...");
//          // await SendMail(); 
//       });
//     }
//     */
//   }

//   Future<void> SendMail() async {
//     try {
//       final now = DateTime.now();
//       final reportService = ReportService();
      
//       // Format the date string as YYYY-MM-DD for the subject
//       final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
//       debugPrint("📤 [CRON Flow] Executing SendMail()...");
      
//       // Send the mail using the CRON flow's specific title
//       await reportService.sendMail(
//         now, 
//         subject: 'Daily Scan Status Report - $dateStr'
//       );
//     } catch (e) {
//       debugPrint("Error in CronTaskService.SendMail: $e");
//     }
//   }

//   void dispose() {
//     _cron.close();
//   }
// }
