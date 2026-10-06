// test/test_helpers/test_app_wrapper.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class TestAppWrapper extends StatefulWidget {
  final Widget child;
  const TestAppWrapper({required this.child, super.key});

  @override
  State<TestAppWrapper> createState() => _TestAppWrapperState();
}

class _TestAppWrapperState extends State<TestAppWrapper> {
  int _testCounter = 0;

  void _increment() => setState(() => _testCounter++);

  @override
  Widget build(BuildContext context) {
    // En release devolvemos solo el child
    if (kReleaseMode) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '$_testCounter',
                  key: const Key('counter'),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'test_counter_fab',
                onPressed: _increment,
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
