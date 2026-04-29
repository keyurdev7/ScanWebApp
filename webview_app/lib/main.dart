import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

   String whitelistedBaseUrl = 'https://taxizuschuss.app.graz.at/';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web APP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const QRScannerScreen(),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController(
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

  @override
  void initState() {
    super.initState();
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
          await _cameraController.start();
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
        await _cameraController.start();
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

  Future<void> _pauseScanner() async {
    if (!_isUploadMode && _cameraAvailable && _hasCameraPermission) {
      await _cameraController.stop();
    }
  }

  Future<void> _reinitializeCamera() async {
    if (!_isUploadMode && _cameraAvailable && _hasCameraPermission) {
      setState(() {
        _isInitializingCamera = true;
      });
      
      try {
        // Stop the current controller
        await _cameraController.stop();
        // Wait a bit to ensure camera is fully released
        await Future.delayed(const Duration(milliseconds: 300));
        // Start the camera again
        await _cameraController.start();
        setState(() {
          _isInitializingCamera = false;
        });
      } catch (e) {
        setState(() {
          _isInitializingCamera = false;
          _cameraAvailable = false;
          _isUploadMode = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to reinitialize camera. Please restart the app.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
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

    // Normalize URL
    String normalizedUrl = url.trim();

    // Handle www. prefix
    if (normalizedUrl.toLowerCase().startsWith('www.')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    // Parse to ensure it's a valid URL
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) return false;

    // Check if URL starts with whitelisted base URL
    final urlString = uri.toString().toLowerCase();
    final baseUrl = whitelistedBaseUrl.toLowerCase();

    return urlString.startsWith(baseUrl);
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

    // First check if it's a valid URL
    if (!_isValidUrl(code)) {
      setState(() {
        _isProcessingQR = false;
      });
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid URL format. Please scan a valid URL.'),
            duration: Duration(seconds: 3),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              // 'URL not allowed. Only ${whitelistedBaseUrl} is permitted.',
              'Invalid QR Code',
            ),
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
      // Navigate to webview
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => InAppBrowserScreen(url: normalizedUrl),
        ),
      ).then((v)async{
        // Reset navigation flag and reinitialize camera when returning
      setState(() {
        _isNavigating = false;
        _lastScannedUrl = null;
        _lastScanTime = null;
      });
      
      // Properly reinitialize camera when returning to this screen
      await _reinitializeCamera();
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
        title: const Text('QR Code Scanned'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL detected:'),
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
            child: const Text('Cancel'),
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
                // Pause scanner before navigating
                await _pauseScanner();
                
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        InAppBrowserScreen(url: normalizedUrl),
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
            },
            child: const Text('Open'),
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
        final BarcodeCapture? result = await _cameraController.analyzeImage(
          image.path,
        );

        if (result != null && result.barcodes.isNotEmpty) {
          final code = result.barcodes.first.rawValue;
          if (code != null && code.isNotEmpty) {
            // First check if it's a valid URL
            if (!_isValidUrl(code)) {
              setState(() {
                _isProcessingQR = false;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invalid URL format. Please scan a valid URL.',
                    ),
                    duration: Duration(seconds: 3),
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
                    content: Text(
                      // 'URL not allowed. Only ${whitelistedBaseUrl} is permitted.',
                      'Invalid QR Code',
                    ),
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
                const SnackBar(
                  content: Text('No QR code found in the image.'),
                  duration: Duration(seconds: 2),
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
              const SnackBar(
                content: Text('No QR code found in the image.'),
                duration: Duration(seconds: 2),
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
              content: Text('Error decoding QR code: $e'),
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
            content: Text('Error picking image: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isUploadMode = !_isUploadMode;
      if (!_isUploadMode && _cameraAvailable && _hasCameraPermission) {
        _cameraController.start();
      } else {
        _cameraController.stop();
      }
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Are you sure you want to exit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          // Exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(
        children: [
          // Camera preview or upload placeholder
          if (!_isUploadMode && _cameraAvailable && _hasCameraPermission)
            MobileScanner(
              controller: _cameraController,
              onDetect: _handleQRCode,
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
                          ? 'Upload QR Image'
                          : _hasCameraPermission
                          ? 'Camera not available'
                          : 'Camera permission denied',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),

          // Overlay buttons
          SafeArea(
            child: Column(
              children: [
                // Top bar with toggle button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_cameraAvailable && _hasCameraPermission)
                        FloatingActionButton(
                          onPressed: _toggleMode,
                          backgroundColor: Colors.white.withOpacity(0.9),
                          child: Icon(
                            _isUploadMode ? Icons.camera_alt : Icons.upload,
                            color: Colors.black87,
                          ),
                        ),
                    ],
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
                          onPressed: _pickImage,
                          backgroundColor: Colors.white.withOpacity(0.9),
                          icon: const Icon(Icons.image, color: Colors.black87),
                          label: const Text(
                            'Upload QR Image',
                            style: TextStyle(color: Colors.black87),
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

                  child: const Center(child: SizedBox(width: 300, height: 300)),
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
                    const Text(
                      'Initializing Camera...',
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

  const InAppBrowserScreen({super.key, required this.url});

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  InAppWebViewController? webViewController;
  double progress = 0;
  bool isLoading = true;
  String currentUrl = '';

  // Whitelisted base URL (same as in QRScannerScreen)
  

  bool _isWhitelistedUrl(String? url) {
    if (url == null || url.isEmpty) return false;

    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    final urlString = uri.toString().toLowerCase();
    final baseUrl = whitelistedBaseUrl.toLowerCase();

    return urlString.startsWith(baseUrl);
  }

  @override
  void initState() {
    super.initState();
    currentUrl = widget.url;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // title: const Text('Payment'),
        actions: [
          if (webViewController != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                webViewController?.reload();
              },
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useHybridComposition: true,
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url.toString();

                // Check if the URL is whitelisted
                if (!_isWhitelistedUrl(url)) {
                  // Block navigation and show alert
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Navigation blocked. Only ${whitelistedBaseUrl} is allowed.',
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
                          'Navigation blocked. Only ${whitelistedBaseUrl} is allowed.',
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
                
                // Pop back to QR scanner only if URL contains "success"
                if (mounted && urlString.toLowerCase().contains('success')) {
                  Navigator.of(context).pop();
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
                    content: Text('Error loading page: ${error.description}'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            ),
          ),
          if (isLoading && progress < 1.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
