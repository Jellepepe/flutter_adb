import 'package:flutter/material.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrPairingPanel extends StatelessWidget {
  const QrPairingPanel({
    super.key,
    required this.onStart,
    this.onCancel,
    this.pairingData,
    this.isPairing = false,
    this.statusText,
  });

  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final AdbQrPairingData? pairingData;
  final bool isPairing;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('QR Pairing', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                    'Generate a QR code here, then scan it from Wireless debugging on the Android device.'),
                const SizedBox(height: 24),
                if (pairingData != null) ...[
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(25),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        data: pairingData!.qrPayload,
                        size: 250,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square, color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SelectableText('Service: ${pairingData!.serviceName}',
                      style: theme.textTheme.bodyLarge),
                  SelectableText('Password: ${pairingData!.password}',
                      style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 16),
                ],
                if (statusText != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(127),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusText!, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(height: 24),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isPairing ? null : onStart,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isPairing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(pairingData == null
                                ? 'Generate QR & Pair'
                                : 'Generate New QR'),
                      ),
                    ),
                    if (onCancel != null) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: isPairing ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
