import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Business Name'),
        centerTitle: true,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Business Logo
          Container(
            padding: EdgeInsets.all(20.0),
            child: Image.asset(
              'assets/logo.png', // Replace with your actual image path
              height: 100.0, // Adjust the height as needed
            ),
          ),
          
          // Login Button
          ElevatedButton(
            onPressed: () {
              // Add your login button functionality here
              print('Login button pressed');
            },
            child: Text('Login'),
          ),
          
          // Register Button
          ElevatedButton(
            onPressed: () {
              // Add your register button functionality here
              print('Register button pressed');
            },
            child: Text('Register'),
          ),
        ],
      ),
    );
  }
}
