// send_page_ext.dart

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class SendPageExt extends StatefulWidget {
  final Function(String) onCodeScanned;

  SendPageExt({required this.onCodeScanned});

  @override
  _SendPageExtState createState() => _SendPageExtState();
}

class _SendPageExtState extends State<SendPageExt> {
  late QRViewController _qrViewController;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 400,
          height: 400,
          child: QRView(
            key: _qrKey,
            onQRViewCreated: _onQRViewCreated,
          ),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onCodeScanned('Manual Input'); // Replace with actual manual input
          },
          child: Text('Input Manually'),
        ),
      ],
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;

    controller.scannedDataStream.listen((scanData) {
      widget.onCodeScanned(scanData.code ?? 'No data');
    });
  }

  @override
  void dispose() {
    _qrViewController.dispose();
    super.dispose();
  }
}
