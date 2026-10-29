import 'package:flutter/material.dart';

/// Temporary outlet for MH12 until the shared COD shell is integrated.
class CodRoutePage extends StatelessWidget {
  const CodRoutePage({this.orderId, super.key});

  final String? orderId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh12-outlet'),
      label: 'Đối soát tiền thu hộ',
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Giao diện đối soát tiền thu hộ chưa được tích hợp.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
