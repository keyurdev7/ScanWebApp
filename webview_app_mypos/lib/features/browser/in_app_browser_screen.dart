import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../services/report_service.dart';
import '../../services/report_api_service.dart';
import '../../l10n/app_localizations.dart';

class InAppBrowserScreen extends ConsumerStatefulWidget {
  final String url;
  final String? injectValue;

  const InAppBrowserScreen({super.key, required this.url, this.injectValue});

  @override
  ConsumerState<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends ConsumerState<InAppBrowserScreen> {
  InAppWebViewController? webViewController;
  double progress = 0;
  bool isLoading = true;
  String currentUrl = '';
  bool _hasFatalError = false;

  bool _isWhitelistedUrl(String? url, String whitelistedBaseUrl) {
    if (url == null || url.isEmpty) return false;
    if (kDebugMode) return true;

    final lowerUrl = url.toLowerCase();
    final baseWithoutScheme = whitelistedBaseUrl
        .toLowerCase()
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '');

    final urlWithoutScheme = lowerUrl.replaceFirst(RegExp(r'^https?://'), '');

    if (urlWithoutScheme.startsWith(baseWithoutScheme)) return true;

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
    final whitelistedBaseUrl = ref.watch(whitelistedBaseUrlProvider);

    return Scaffold(
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
              supportMultipleWindows: false,
              cacheEnabled: true,
              clearCache: false,
              safeBrowsingEnabled: false,
              useOnDownloadStart: true,
              useOnLoadResource: false,
              // Stability settings for specialized hardware
              useHybridComposition: false, 
              hardwareAcceleration: false,
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
                          constraints.video = { facingMode: 'environment' };
                        } else if (typeof constraints.video === 'object') {
                          constraints.video.facingMode = 'environment';
                          delete constraints.video.deviceId;
                        }
                        console.log('Antigravity: Patched constraints', constraints);
                      }
                    }

                    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                      const originalGetUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
                      navigator.mediaDevices.getUserMedia = function(constraints) {
                        patchConstraints(constraints);
                        return originalGetUserMedia(constraints);
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
                    ReportApiService().submitReport(
                      scanType: 'ticket',
                      scanResult: status,
                    );
                  } else {
                    bool success = args[1] as bool;
                    ReportService().incrementBurgenlandScan(success: success);
                    ReportApiService().submitReport(
                      scanType: 'burgenland',
                      scanResult: success ? 'success' : 'fail',
                    );
                  }
                },
              );
            },
            onPermissionRequest: (controller, permissionRequest) async {
              try {
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
              } catch (e) {
                return PermissionResponse(
                  resources: [],
                  action: PermissionResponseAction.DENY,
                );
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              if (!_isWhitelistedUrl(url, whitelistedBaseUrl)) {
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
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              final urlString = url.toString();
              if (!_isWhitelistedUrl(urlString, whitelistedBaseUrl)) {
                controller.stopLoading();
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

              if (widget.injectValue != null &&
                  urlString.contains('burgenlandtrails.at') &&
                  urlString.contains('mqz1ppt')) {
                try {
                  await controller.evaluateJavascript(
                    source: """
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

              if (urlString.contains('feratel.com')) {
                try {
                  await controller.evaluateJavascript(
                    source: """
                    (function() {
                      if (window._autoLoginStarted) return;
                      var userField = document.getElementById('username');
                      if (!userField) return;
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
                          }
                        }
                        attempts++;
                        if (attempts >= maxAttempts) clearInterval(loginInterval);
                      }, 500);
                    })();
                  """,
                  );
                } catch (e) {
                  debugPrint("Error auto-logging in: $e");
                }
              }

              try {
                final evaluatorScript = """
                if (!window.reportScanTaskStarted) {
                  window.reportScanTaskStarted = true;
                  const isTicketMode = window.location.href.includes('burgenlandtrails');
                  if (isTicketMode) {
                      window._lastTicketSuccess = false;
                      window._lastTicketInvalid = false;
                      window._lastTicketFail = false;
                      setInterval(() => {
                         const resultDiv = document.getElementById('bt-ticket-result');
                         if (resultDiv) {
                            const text = resultDiv.innerText || resultDiv.textContent || '';
                            if (text.includes('✅ Gültiges Ticket')) {
                               if (!window._lastTicketSuccess) {
                                  window._lastTicketSuccess = true;
                                  window.flutter_inappwebview.callHandler('ScanResult', 'ticket', 'success');
                               }
                            } else if (text.includes('⚠️ Ticket ist ungültig')) {
                               if (!window._lastTicketInvalid) {
                                  window._lastTicketInvalid = true;
                                  window.flutter_inappwebview.callHandler('ScanResult', 'ticket', 'invalid');
                               }
                            } else if (text.includes('Ticket existiert nicht')) {
                               if (!window._lastTicketFail) {
                                  window._lastTicketFail = true;
                                  window.flutter_inappwebview.callHandler('ScanResult', 'ticket', 'fail');
                               }
                            }
                         }
                      }, 500);
                  } else {
                      const checkInterval = setInterval(() => {
                         const statusDiv = document.querySelector('.text-center.status');
                         if (statusDiv) {
                            const text = statusDiv.innerText || statusDiv.textContent || '';
                            if (text.includes('OK')) {
                               clearInterval(checkInterval);
                               window.flutter_inappwebview.callHandler('ScanResult', 'burgenland', true);
                            } else if (text.includes('NO')) {
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
            },
            onRenderProcessGone: (controller, detail) {
              setState(() {
                _hasFatalError = true;
              });
            },
          ),
          if (isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                      ),
                      onPressed: () => webViewController?.reload(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isLoading && progress < 1.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
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
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('webview_crash_error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: Text(context.tr('close')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
