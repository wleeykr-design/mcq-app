import 'package:flutter/material.dart';
import 'screens/home_shell.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Batch27App());
}

class Batch27App extends StatefulWidget {
  const Batch27App({super.key});

  @override
  State<Batch27App> createState() => _Batch27AppState();
}

class _Batch27AppState extends State<Batch27App> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Batch 27 — منصة أسئلة MCQ',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _controller.data.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: HomeShell(controller: _controller),
        );
      },
    );
  }
}
