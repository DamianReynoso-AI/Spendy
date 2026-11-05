import 'package:flutter/material.dart';

/// Punto de entrada provisional. Las pantallas (M-01) se agregan después.
void main() => runApp(const SpendyApp());

class SpendyApp extends StatelessWidget {
  const SpendyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'SPENDY',
      home: Scaffold(body: Center(child: Text('SPENDY'))),
    );
  }
}
