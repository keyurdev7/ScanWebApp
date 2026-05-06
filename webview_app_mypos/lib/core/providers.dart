import 'package:flutter_riverpod/flutter_riverpod.dart';

// Providers for global state
final whitelistedBaseUrlProvider = StateProvider<String>((ref) => 'https://taxizuschuss.app.graz.at/');
final isTicketScanModeProvider = StateProvider<bool>((ref) => false);

// Constant for ticket checker URL
const String ticketCheckerUrl = 'https://burgenlandtrails.at/mqz1ppt9p6arx45lclxzxxvx5vsfb9hatudjv320hfkizeeu9va6yngjbqierlmt/';
