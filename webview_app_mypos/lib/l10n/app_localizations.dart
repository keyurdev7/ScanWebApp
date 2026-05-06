import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'Scan APP',
      'exit_app_title': 'Exit App',
      'exit_app_content': 'Are you sure you want to exit?',
      'cancel': 'Cancel',
      'exit': 'Exit',
      'camera_permission_required': 'Camera Permission Required',
      'camera_permission_content': 'Please grant camera permission to use the scanner. You can enable it in your device settings.',
      'location_permission_required': 'Location Permission Required',
      'location_permission_content': 'Please grant location permission to improve scan accuracy and reporting. You can enable it in your device settings.',
      'gallery_permission_required': 'Gallery Permission Required',
      'gallery_permission_content': 'Please grant gallery permission to upload QR codes from your photos. You can enable it in your device settings.',
      'settings': 'Settings',
      'choose_scan_type': 'Choose Scan Type',
      'scan_type_description': 'Select the appropriate option below to configure the scanner for your needs.',
      'burgenland_card': 'BURGENLAND CARD',
      'burgenland_card_desc': 'Scan and verify Burgenland tourist cards seamlessly.',
      'ticket_scan': 'TICKET SCAN',
      'ticket_scan_desc': 'Scan trail tickets and access passes quickly.',
      'trigger_test_report': 'Triggering test report...',
      'debug_send_report_now': 'DEBUG: Send Report Now',
      'background_reliability': 'Background Reliability',
      'background_desc': 'The OS may stop background tasks to save battery when the phone is locked. To ensure daily reports are sent reliably, please disable battery optimization for this app.',
      'disable_optimization': 'DISABLE OPTIMIZATION',
      'retry_camera': 'Retry Camera',
      'pause_scanner': 'Pause Scanner',
      'resume_scanner': 'Resume Scanner',
      'select_image': 'Select Image',
      'close': 'Close',
      'language': 'Language',
      'upload_qr_image': 'Upload QR Image',
      'camera_not_avail': 'Camera not available',
      'camera_denied': 'Camera permission denied',
      'scanning_trail_tickets': 'SCANNING TRAIL TICKETS...',
      'scanning_burgenland_cards': 'SCANNING BURGENLAND CARDS...',
      'ticket_mode': 'TICKET MODE',
      'card_mode': 'CARD MODE',
      'init_camera': 'Initializing Camera...',
      'init_camera_failed': 'Failed to reinitialize camera. Please restart the app.',
      'app_info_tooltip': 'Application Info',
      'information_title': 'Information',
      'last_mail_sent': 'Last Mail Sent: ',
      'application_version': 'Application Version: ',
      'device': 'Device: ',
      'missed_reports': 'Missed Reports:',
      'send_report': 'Send',
      'no_history': 'No history available',
      'sending_report_for': 'Sending report for',
      'report_sent_for': 'Report sent for',
      'invalid_url_format': 'Invalid URL format. Please scan a valid URL.',
      'url_not_allowed': 'URL not allowed. Only',
      'is_permitted': 'is permitted.',
      'invalid_qr_code': 'Invalid QR Code',
      'no_qr_found': 'No QR code found in the image.',
      'error_decoding_qr': 'Error decoding QR code:',
      'error_picking_image': 'Error picking image:',
      'nav_blocked_1': 'Navigation blocked. Only',
      'nav_blocked_2': 'is allowed.',
      'error_loading_page': 'Error loading page:',
      'camera_init_error': 'The camera could not be initialized. Please ensure it is not being used by another app.',
      'qr_code_scanned': 'QR Code Scanned',
      'url_detected': 'URL detected:',
      'open': 'Open',
      'webview_crash_error': 'Web view process crashed unexpectedly.',
      'restart_app_required': 'Please restart the application.',
      'today_status': 'Today\'s Scan Status',
      'successful': 'Successful',
      'invalid': 'Invalid',
      'wrong_qr': 'Wrong QR Code',
      'total': 'Total',
    },
    'de': {
      'app_title': 'Scan APP',
      'exit_app_title': 'App beenden',
      'exit_app_content': 'Bist du sicher, dass du die App beenden möchtest?',
      'cancel': 'Abbrechen',
      'exit': 'Beenden',
      'camera_permission_required': 'Kamera-Berechtigung erforderlich',
      'camera_permission_content': 'Bitte erlaube den Zugriff auf die Kamera, um den Scanner zu nutzen. Dies kann in den Geräteeinstellungen aktiviert werden.',
      'location_permission_required': 'Standort-Berechtigung erforderlich',
      'location_permission_content': 'Bitte erlaube den Zugriff auf den Standort, um die Scangenauigkeit und Berichterstattung zu verbessern. Dies kann in den Geräteeinstellungen aktiviert werden.',
      'gallery_permission_required': 'Galerie-Berechtigung erforderlich',
      'gallery_permission_content': 'Bitte erlaube den Zugriff auf die Galerie, um QR-Codes aus deinen Fotos hochzuladen. Dies kann in den Geräteeinstellungen aktiviert werden.',
      'settings': 'Einstellungen',
      'choose_scan_type': 'Scan-Typ wählen',
      'scan_type_description': 'Wähle unten die passende Option, um den Scanner für deine Bedürfnisse zu konfigurieren.',
      'burgenland_card': 'BURGENLAND KARTE',
      'burgenland_card_desc': 'Burgenland-Touristenkarten nahtlos scannen und verifizieren.',
      'ticket_scan': 'TICKET-SCAN',
      'ticket_scan_desc': 'Trail-Tickets und Zugangspässe schnell scannen.',
      'trigger_test_report': 'Testbericht wird ausgelöst...',
      'debug_send_report_now': 'DEBUG: Jetzt Bericht senden',
      'background_reliability': 'Hintergrund-Zuverlässigkeit',
      'background_desc': 'Das Betriebssystem stoppt möglicherweise Hintergrundaufgaben, um Batterie zu sparen, wenn das Telefon gesperrt ist. Um sicherzustellen, dass tägliche Berichte zuverlässig gesendet werden, deaktiviere bitte die Batterieoptimierung für diese App.',
      'disable_optimization': 'OPTIMIERUNG DEAKTIVIEREN',
      'retry_camera': 'Kamera erneut versuchen',
      'pause_scanner': 'Scanner pausieren',
      'resume_scanner': 'Scanner fortsetzen',
      'select_image': 'Bild auswählen',
      'close': 'Schließen',
      'language': 'Sprache',
      'upload_qr_image': 'QR-Bild hochladen',
      'camera_not_avail': 'Kamera nicht verfügbar',
      'camera_denied': 'Kamerazugriff verweigert',
      'scanning_trail_tickets': 'TRAIL-TICKETS SCANNEN...',
      'scanning_burgenland_cards': 'BURGENLAND CARDS SCANNEN...',
      'ticket_mode': 'TICKET-MODUS',
      'card_mode': 'CARD-MODUS',
      'init_camera': 'Kamera initialisieren...',
      'init_camera_failed': 'Kamera konnte nicht neu initialisiert werden. Bitte App neu starten.',
      'app_info_tooltip': 'App-Informationen',
      'information_title': 'Informationen',
      'last_mail_sent': 'Zuletzt gesendete E-Mail: ',
      'application_version': 'App-Version: ',
      'device': 'Gerät: ',
      'missed_reports': 'Verpasste Berichte:',
      'send_report': 'Senden',
      'no_history': 'Keine Historie verfügbar',
      'sending_report_for': 'Bericht wird gesendet für',
      'report_sent_for': 'Bericht gesendet für',
      'invalid_url_format': 'Ungültiges URL-Format. Bitte scannen Sie eine gültige URL.',
      'url_not_allowed': 'URL nicht erlaubt. Nur',
      'is_permitted': 'ist zulässig.',
      'invalid_qr_code': 'Ungültiger QR-Code',
      'no_qr_found': 'Kein QR-Code im Bild gefunden.',
      'error_decoding_qr': 'Fehler beim Decodieren des QR-Codes:',
      'error_picking_image': 'Fehler bei der Bildauswahl:',
      'nav_blocked_1': 'Navigation blockiert. Nur',
      'nav_blocked_2': 'ist zulässig.',
      'error_loading_page': 'Fehler beim Laden der Seite:',
      'camera_init_error': 'Die Kamera konnte nicht initialisiert werden. Bitte stellen Sie sicher, dass sie nicht von einer anderen App verwendet wird.',
      'qr_code_scanned': 'QR-Code gescannt',
      'url_detected': 'URL erkannt:',
      'open': 'Öffnen',
      'webview_crash_error': 'Der Webansicht-Prozess ist unerwartet abgestürzt.',
      'restart_app_required': 'Bitte starten Sie die Anwendung neu.',
      'today_status': 'Heutiger Scan-Status',
      'successful': 'Erfolgreich',
      'invalid': 'Ungültig',
      'wrong_qr': 'Falscher QR-Code',
      'total': 'Gesamt',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? _localizedValues['de']?[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'de'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

class LanguageSettings {
  static const String _languageKey = 'language_code';

  static Future<Locale> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_languageKey);
    // Default is German ('de')
    return Locale(languageCode ?? 'de');
  }

  static Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }
}

extension LocalizationHelper on BuildContext {
  String tr(String key) {
    return AppLocalizations.of(this)?.translate(key) ?? key;
  }
}
