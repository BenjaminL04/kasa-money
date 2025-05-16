import 'package:flutter/material.dart';
import 'qr.dart'; // Import the new QR page

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SendAny Page',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SendAnyPage(),
    );
  }
}

class SendAnyPage extends StatefulWidget {
  @override
  _SendAnyPageState createState() => _SendAnyPageState();
}

class _SendAnyPageState extends State<SendAnyPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFF9B29), // Set the background color here
      body: QrPage(), // Use the new QR page here
    );
  }
}
