import 'package:flutter/material.dart';

class ReceivePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Choose which currency to receive",
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/receive_zarp');
            },
            child: Container(
              color: Colors.grey[900],
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Image.asset(
                    'assets/zarp.png',
                    width: 24,
                    height: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    "ZARP",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
          Divider(color: Colors.white),
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/receive_btc_page');
            },
            child: Container(
              color: Colors.grey[900],
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Image.asset(
                    'assets/btc.png',
                    width: 24,
                    height: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    "BTC",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}