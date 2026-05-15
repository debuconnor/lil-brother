import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/tv_discovery_provider.dart';
import 'providers/tv_provider.dart';
import 'screens/home_screen.dart';

void main() {
    runApp(
        MultiProvider(
            providers: [
                ChangeNotifierProvider(create: (_) => TvProvider()..init()),
                ChangeNotifierProvider(create: (_) => TvDiscoveryProvider()),
            ],
            child: const LilBrotherApp(),
        ),
    );
}

class LilBrotherApp extends StatelessWidget {
    const LilBrotherApp({super.key});

    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            title: 'lil-brother',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                    primary: Colors.greenAccent,
                    surface: Color(0xFF1A1A2E),
                ),
                scaffoldBackgroundColor: const Color(0xFF1A1A2E),
            ),
            home: const HomeScreen(),
        );
    }
}
