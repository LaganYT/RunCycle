import 'package:flutter/material.dart';
import 'package:health/health.dart';

final ValueNotifier<ThemeMode> themeNotifier =
    ValueNotifier(ThemeMode.system);

void main() {
  runApp(
    ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MyApp(themeMode: currentMode);
      },
    ),
  );
}

class MyApp extends StatelessWidget {
  final ThemeMode themeMode;
  const MyApp({super.key, required this.themeMode});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RunCycle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _streak = 0;
  int _steps = 0;
  double _distance = 0.0;
  Health health = Health();

  @override
  void initState() {
    super.initState();
    _authorizeAndFetchData();
  }

  Future<void> _authorizeAndFetchData() async {
    // Define the health data types we want to read.
    final types = [
      HealthDataType.STEPS,
      HealthDataType.DISTANCE_WALKING_RUNNING,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    ];

    // Request authorization to read the data.
    bool requested = await health.requestAuthorization(types);

    if (requested) {
      fetchData();
    } else {
      // Handle case where user denies permission.
      debugPrint("Authorization not granted");
    }
  }

  Future<void> fetchData() async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // Clear previous data
    setState(() {
      _steps = 0;
      _distance = 0.0;
    });

    try {
      // Fetch new data
      List<HealthDataPoint> healthData =
          await health.getHealthDataFromTypes(
            startTime: yesterday,
            endTime: now,
            types: [
              HealthDataType.STEPS,
              HealthDataType.DISTANCE_WALKING_RUNNING,
            ],
          );

      // Process the data
      for (HealthDataPoint point in healthData) {
        if (point.type == HealthDataType.STEPS) {
          _steps += (point.value as NumericHealthValue).numericValue.toInt();
        } else if (point.type == HealthDataType.DISTANCE_WALKING_RUNNING) {
          _distance += (point.value as NumericHealthValue).numericValue.toDouble();
        }
      }

      // Update the UI
      setState(() {});
    } catch (e) {
      debugPrint("Error fetching health data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('RunCycle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: fetchData,
            tooltip: 'Sync',
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Your current run streak:',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '$_streak days',
              style: Theme.of(context)
                  .textTheme
                  .displayMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            const Text('Today\'s stats:'),
            Text('Steps: $_steps'),
            Text('Distance: ${(_distance / 1000).toStringAsFixed(2)} km'),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, ThemeMode currentMode, __) {
                final isDarkMode = currentMode == ThemeMode.dark ||
                    (currentMode == ThemeMode.system &&
                        MediaQuery.of(context).platformBrightness ==
                            Brightness.dark);
                return SwitchListTile(
                  title: const Text('Dark Mode'),
                  value: isDarkMode,
                  onChanged: (bool value) {
                    themeNotifier.value =
                        value ? ThemeMode.dark : ThemeMode.light;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
