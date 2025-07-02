import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  static final NotificationService _notificationService =
      NotificationService._internal();

  factory NotificationService() {
    return _notificationService;
  }

  NotificationService._internal();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Configure the time zone
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    await requestPermissions();
    await flutterLocalNotificationsPlugin.zonedSchedule(
        0,
        'RunCycle Daily Reminder',
        'Don\'t forget to check your activity today!',
        _nextInstanceOfTime(time),
        const NotificationDetails(
          android: AndroidNotificationDetails(
              'daily_reminder_channel_id', 'Daily Reminders',
              channelDescription: 'Channel for daily activity reminders'),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time);
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> cancelNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone database
  tz.initializeTimeZones();

  // Initialize notifications
  await NotificationService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      themeMode: ThemeMode.system,
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
  double _calories = 0.0;
  List<HealthDataPoint> _workouts = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  DateTime _baseDate = DateTime.now(); // Add base date for PageView calculations
  Health health = Health();
  late PageController _pageController;
  static const int _initialPage = 10000;
  int _currentPage = _initialPage;
  bool _useImperial = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
    // Initialize base date to today
    final now = DateTime.now();
    _baseDate = DateTime(now.year, now.month, now.day);
    _selectedDate = _baseDate;
    _loadSettings();
    _updateStreak();
    _authorizeAndFetchData();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useImperial = prefs.getBool('useImperial') ?? false;
    });
  }

  Future<void> _updateStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final lastOpenString = prefs.getString('lastOpenDate');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int currentStreak = prefs.getInt('streak') ?? 0;

    if (lastOpenString != null) {
      final lastOpenDate = DateTime.parse(lastOpenString);
      final difference = today.difference(lastOpenDate).inDays;

      if (difference == 1) {
        currentStreak++;
      } else if (difference > 1) {
        currentStreak = 1; // Reset streak
      }
      // if difference is 0, do nothing to streak.
    } else {
      currentStreak = 1; // First open
    }

    await prefs.setString('lastOpenDate', today.toIso8601String());
    await prefs.setInt('streak', currentStreak);

    setState(() {
      _streak = currentStreak;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _authorizeAndFetchData() async {
    // Define the health data types we want to read.
    final types = [
      HealthDataType.STEPS,
      HealthDataType.DISTANCE_WALKING_RUNNING,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.WORKOUT,
    ];

    // Request authorization to read the data.
    bool requested = await health.requestAuthorization(types);

    if (requested) {
      fetchData();
    } else {
      // Handle case where user denies permission.
      debugPrint("Authorization not granted");
      setState(() => _isLoading = false);
    }
  }

  Future<void> fetchData() async {
    setState(() => _isLoading = true);
    final midnight =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final nextMidnight = midnight.add(const Duration(days: 1));

    // Clear previous data
    setState(() {
      _steps = 0;
      _distance = 0.0;
      _calories = 0.0;
      _workouts = [];
    });

    try {
      // Fetch new data
      List<HealthDataPoint> healthData =
          await health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: nextMidnight,
        types: [
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_WALKING_RUNNING,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.WORKOUT,
        ],
      );

      // Process the data
      for (HealthDataPoint point in healthData) {
        if (point.type == HealthDataType.STEPS) {
          _steps += (point.value as NumericHealthValue).numericValue.toInt();
        } else if (point.type == HealthDataType.DISTANCE_WALKING_RUNNING) {
          _distance +=
              (point.value as NumericHealthValue).numericValue.toDouble();
        } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          _calories +=
              (point.value as NumericHealthValue).numericValue.toDouble();
        } else if (point.type == HealthDataType.WORKOUT) {
          _workouts.add(point);
        }
      }

      // Update the UI
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching health data: $e");
      setState(() => _isLoading = false);
    }
  }

  void _onPageChanged(int page) {
    if (page == _currentPage) return;

    final daysOffset = page - _initialPage;
    final newDate = _baseDate.add(Duration(days: daysOffset));
    
    setState(() {
      _selectedDate = newDate;
      _currentPage = page;
    });
    fetchData();
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    setState(() {
      _selectedDate = today;
      _baseDate = today;
      _currentPage = _initialPage;
    });

    _pageController.animateToPage(
      _initialPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    fetchData();
  }

  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('RunCycle - Streak: $_streak 🔥'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
              if (result == true) {
                _loadSettings();
              }
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
               physics: _isToday()
                   ? const ClampingScrollPhysics()
                   : const AlwaysScrollableScrollPhysics(),
               controller: _pageController,
               onPageChanged: _onPageChanged,
               itemBuilder: (context, page) {
                 final daysOffset = page - _initialPage;
                 final date = _baseDate.add(Duration(days: daysOffset));
                 return RefreshIndicator(
                     onRefresh: fetchData, child: _buildDayView(date));
               },
             ),
      floatingActionButton:
          !_isToday() ? FloatingActionButton(
              onPressed: _goToToday,
              child: const Icon(Icons.calendar_today),
              tooltip: 'Go to Today',
            )
          : null,
    );
  }

  Widget _buildDayView(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bool isTodayPage =
        date.year == today.year && date.month == today.month && date.day == today.day;

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                    // use the local `date`, not `_selectedDate`
                    Text(
                      DateFormat.yMMMEd().format(date),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      // disable when this page *is* today
                      onPressed: isTodayPage
                          ? null
                          : () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Card(
                    // include the `date` in the key so stats always remap to the right page
                    key: ValueKey<String>(
                        'stats_${date.toIso8601String()}_$_steps$_distance$_calories'),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text('Daily Stats',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          ListTile(
                            leading: const Icon(Icons.directions_walk),
                            title: const Text('Steps'),
                            trailing: Text('$_steps'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.map),
                            title: const Text('Distance'),
                            trailing: Text(_useImperial
                                ? '${(_distance * 0.000621371).toStringAsFixed(2)} mi'
                                : '${(_distance / 1000).toStringAsFixed(2)} km'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.local_fire_department),
                            title: const Text('Calories'),
                            trailing:
                              Text('${_calories.toStringAsFixed(0)} cal'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_workouts.isNotEmpty)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Card(
                      key: ValueKey<int>(_workouts.hashCode),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text('Workouts',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 10),
                            ..._workouts.map((workout) {
                              final workoutData =
                                  workout.value as WorkoutHealthValue;
                              final activityType =
                                  workoutData.workoutActivityType;
                              return ListTile(
                                leading: Icon(_getWorkoutIcon(activityType)),
                                title: Text(activityType.name
                                    .replaceAll('_', ' ')
                                    .split(' ')
                                    .map((l) =>
                                        l[0].toUpperCase() + l.substring(1))
                                    .join(' ')),
                                subtitle: Text(
                                    '${workout.dateFrom.toLocal().hour}:${workout.dateFrom.toLocal().minute.toString().padLeft(2, '0')} - ${workout.dateTo.toLocal().hour}:${workout.dateTo.toLocal().minute.toString().padLeft(2, '0')}'),
                                trailing: Text(
                                    '${workoutData.totalEnergyBurned?.round() ?? 0} cal'),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  IconData _getWorkoutIcon(HealthWorkoutActivityType type) {
    switch (type) {
      case HealthWorkoutActivityType.RUNNING:
        return Icons.directions_run;
      case HealthWorkoutActivityType.WALKING:
        return Icons.directions_walk;
      case HealthWorkoutActivityType.SWIMMING:
        return Icons.pool;
      default:
        return Icons.fitness_center;
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TimeOfDay? _notificationTime;
  bool _useImperial = false;
  bool _settingsChanged = false;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString('notificationTime');
    if (timeString != null) {
      final parts = timeString.split(':');
      setState(() {
        _notificationTime =
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      });
    }
    setState(() {
      _useImperial = prefs.getBool('useImperial') ?? false;
    });
  }

  Future<void> _selectNotificationTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _notificationTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _notificationTime) {
      setState(() {
        _notificationTime = picked;
        _settingsChanged = true;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'notificationTime', '${picked.hour}:${picked.minute}');
      await _notificationService.scheduleDailyReminder(picked);
    }
  }

  Future<void> _clearNotificationTime() async {
    setState(() {
      _notificationTime = null;
      _settingsChanged = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notificationTime');
    await _notificationService.cancelNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _settingsChanged);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
        ),
        body: ListView(
          children: [
            ListTile(
              title: const Text('Daily Reminder'),
              subtitle: Text(_notificationTime == null
                  ? 'Not set'
                  : _notificationTime!.format(context)),
              trailing: _notificationTime != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearNotificationTime,
                      tooltip: 'Clear reminder',
                    )
                  : null,
              onTap: () => _selectNotificationTime(context),
            ),
            SwitchListTile(
              title: const Text('Use Imperial Units'),
              subtitle: const Text('Miles instead of kilometers'),
              value: _useImperial,
              onChanged: (bool value) async {
                setState(() {
                  _useImperial = value;
                  _settingsChanged = true;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('useImperial', value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
