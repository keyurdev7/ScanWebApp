import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/zxing.dart' as zx;
import 'package:zxing_lib/qrcode.dart' as qr;
import 'package:zxing_lib/common.dart' as common;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../browser/in_app_browser_screen.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController cameraController = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
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
      setState(() {
        _hasCameraPermission = true;
      });
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
      await cameraController.stop();
      cameraController.dispose();

      cameraController = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        formats: [BarcodeFormat.qrCode],
      );

      await cameraController.start();
      if (mounted) {
        setState(() {
          _scannerKey = UniqueKey();
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

  bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  bool _isWhitelistedUrl(String? url, String whitelistedBaseUrl) {
    if (url == null || url.isEmpty) return false;

    String normalizedUrl = url.trim().toLowerCase();
    if (url.toLowerCase().startsWith('www.')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) return false;

    final urlWithoutScheme = uri.toString().replaceFirst(
      RegExp(r'^https?://'),
      '',
    );
    final baseWithoutScheme = whitelistedBaseUrl
        .toLowerCase()
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '');

    if (urlWithoutScheme.startsWith(baseWithoutScheme)) return true;

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
    if (_isScanning || _isProcessingQR || _isNavigating) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    _isNavigating = true;
    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    String normalizedUrl = code.trim();
    if (code.toLowerCase().startsWith('www.')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    final now = DateTime.now();
    if (_lastScannedUrl == normalizedUrl &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      _isNavigating = false;
      return;
    }

    await _pauseScanner();

    setState(() {
      _isProcessingQR = true;
      _lastScannedUrl = normalizedUrl;
      _lastScanTime = now;
    });

    final isTicketScanMode = ref.read(isTicketScanModeProvider);
    final whitelistedBaseUrl = ref.read(whitelistedBaseUrlProvider);

    if (isTicketScanMode) {
      setState(() {
        _isScanning = true;
      });

      HapticFeedback.mediumImpact();

      setState(() {
        _isScanning = false;
        _isProcessingQR = false;
      });

      if (mounted) {
        await cameraController.stop();
        await cameraController.dispose();
        await Future.delayed(const Duration(milliseconds: 400));

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
                  _scannerKey = UniqueKey();

                  cameraController = MobileScannerController(
                    autoStart: false,
                    detectionSpeed: DetectionSpeed.noDuplicates,
                    facing: CameraFacing.back,
                    formats: [BarcodeFormat.qrCode],
                  );
                });
                await _reinitializeCamera();
              }
            });
      }
      return;
    }

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

      await _reinitializeCamera();
      return;
    }

    if (!_isWhitelistedUrl(code, whitelistedBaseUrl)) {
      setState(() {
        _isProcessingQR = false;
      });
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('invalid_qr_code')),
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

      await _reinitializeCamera();
      return;
    }

    setState(() {
      _isScanning = true;
    });

    HapticFeedback.mediumImpact();

    setState(() {
      _isScanning = false;
      _isProcessingQR = false;
    });

    if (mounted) {
      await cameraController.stop();
      await cameraController.dispose();
      await Future.delayed(const Duration(milliseconds: 400));

      await Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => InAppBrowserScreen(url: normalizedUrl),
            ),
          )
          .then((v) async {
            if (mounted) {
              setState(() {
                _isNavigating = false;
                _lastScannedUrl = null;
                _lastScanTime = null;
                _scannerKey = UniqueKey();

                cameraController = MobileScannerController(
                  autoStart: false,
                  detectionSpeed: DetectionSpeed.noDuplicates,
                  facing: CameraFacing.back,
                  formats: [BarcodeFormat.qrCode],
                );
              });
              await _reinitializeCamera();
            }
          });
    } else {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image == null) return;

      setState(() {
        _isProcessingQR = true;
      });

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
              // ignore
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
          final whitelistedBaseUrl = ref.read(whitelistedBaseUrlProvider);

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

          if (!_isWhitelistedUrl(code, whitelistedBaseUrl)) {
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
            await _pauseScanner();

            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => InAppBrowserScreen(url: normalizedUrl),
              ),
            );

            setState(() {
              _isNavigating = false;
              _lastScannedUrl = null;
              _lastScanTime = null;
            });

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
    final isTicketScanMode = ref.watch(isTicketScanModeProvider);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: Stack(
          children: [
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
                            padding: const EdgeInsets.only(left: 25, right: 25),
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

            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
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
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),

                        Container(
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
                  ),
                ),
              ),

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
