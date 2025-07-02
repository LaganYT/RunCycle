import 'dart:io';
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
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
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
    PermissionStatus status = await Permission.notification.status;

    if (status.isGranted) {
      // Permission is already granted
    } else if (status.isDenied) {
      // Permission is denied, but we can request it
      status = await Permission.notification.request();
      if (!status.isGranted) {
        // Show dialog if permission is still not granted
        _showPermissionDialog();
        return;
      }
    } else {
      // Handle other cases like permanently denied
      _showPermissionDialog();
      return;
    }

    if (Platform.isAndroid) {
      final alarmStatus = await Permission.scheduleExactAlarm.status;
      if (alarmStatus.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    }
  }

  void _showPermissionDialog() {
    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
                'Notifications are required to send daily reminders. Please enable notifications in your device settings.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
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
          iOS: DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
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

class DayStats {
  final int steps;
  final double distance;
  final double calories;
  final List<HealthDataPoint> workouts;
  final bool isLoading;

  DayStats({
    this.steps = 0,
    this.distance = 0.0,
    this.calories = 0.0,
    this.workouts = const [],
    this.isLoading = true,
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
      navigatorKey: navigatorKey,
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
  Map<DateTime, DayStats> _dayStatsCache = {};
  bool _isLoading = true; // For initial loading only
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
    _authorizeAndFetchData();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useImperial = prefs.getBool('useImperial') ?? false;
    });
  }

  Future<void> _updateStreak(bool hasWorkoutToday) async {
    final prefs = await SharedPreferences.getInstance();
    int currentStreak = prefs.getInt('streak') ?? 0;
    final lastWorkoutString = prefs.getString('lastWorkoutDate');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lastWorkoutString != null) {
      final lastWorkoutDate = DateTime.parse(lastWorkoutString);
      final difference = today.difference(lastWorkoutDate).inDays;

      if (hasWorkoutToday) {
        if (difference == 1) {
          // Workout yesterday, and today. Streak continues.
          currentStreak++;
        } else if (difference > 1) {
          // Gap in workouts. Check for streak ending yesterday.
          if (await _hasWorkoutOnDate(today.subtract(const Duration(days: 1)))) {
            currentStreak = 1; // Start of a new streak today.
            for (int i = 1; i < 100; i++) { // Check up to 100 days back
              if (await _hasWorkoutOnDate(today.subtract(Duration(days: i)))) {
                currentStreak++;
              } else {
                break;
              }
            }
          } else {
             currentStreak = 1; // New streak starts today
          }
        }
        // if difference is 0, streak was already updated. Do nothing.
        await prefs.setString('lastWorkoutDate', today.toIso8601String());
      } else { // No workout today
        if (difference == 1) {
          // Last workout was yesterday. Streak is safe for now.
        } else if (difference > 1) {
          // Last workout was before yesterday. Streak is broken.
          currentStreak = 0;
        }
      }
    } else if (hasWorkoutToday) {
      currentStreak = 1;
      await prefs.setString('lastWorkoutDate', today.toIso8601String());
    }

    await prefs.setInt('streak', currentStreak);
    if (mounted) {
      setState(() {
        _streak = currentStreak;
      });
    }
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

  Future<void> fetchData([DateTime? date]) async {
    final dateToFetch = date ?? _selectedDate;
    final midnight = DateTime(dateToFetch.year, dateToFetch.month, dateToFetch.day);

    // Show loading state for the specific day
    setState(() {
      _dayStatsCache[midnight] = DayStats(isLoading: true);
      if (date == null) _isLoading = true;
    });

    final nextMidnight = midnight.add(const Duration(days: 1));

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

      int steps = 0;
      double distance = 0.0;
      double calories = 0.0;
      List<HealthDataPoint> workouts = [];

      // Process the data
      for (HealthDataPoint point in healthData) {
        if (point.type == HealthDataType.STEPS) {
          steps += (point.value as NumericHealthValue).numericValue.toInt();
        } else if (point.type == HealthDataType.DISTANCE_WALKING_RUNNING) {
          distance +=
              (point.value as NumericHealthValue).numericValue.toDouble();
        } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          calories +=
              (point.value as NumericHealthValue).numericValue.toDouble();
        } else if (point.type == HealthDataType.WORKOUT) {
          workouts.add(point);
        }
      }

      // Update the cache and UI
      setState(() {
        _dayStatsCache[midnight] = DayStats(
          steps: steps,
          distance: distance,
          calories: calories,
          workouts: workouts,
          isLoading: false,
        );
        if (date == null) _isLoading = false;
      });

      final today = DateTime.now();
      if (dateToFetch.year == today.year &&
          dateToFetch.month == today.month &&
          dateToFetch.day == today.day) {
        _updateStreak(workouts.isNotEmpty);
      }
    } catch (e) {
      debugPrint("Error fetching health data for $midnight: $e");
      setState(() {
        _dayStatsCache[midnight] = DayStats(isLoading: false); // Stop loading on error
        if (date == null) _isLoading = false;
      });
    }
  }

  void _onPageChanged(int page) {
    if (page == _currentPage) return;

    final daysOffset = page - _initialPage;
    final newDate = _baseDate.add(Duration(days: daysOffset));
    final dayOnly = DateTime(newDate.year, newDate.month, newDate.day);
    
    setState(() {
      _selectedDate = newDate;
      _currentPage = page;
    });

    if (!_dayStatsCache.containsKey(dayOnly)) {
      fetchData(newDate);
    }
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
    // Data for today will be fetched by onPageChanged or initial load.
    // If it's already today, we can force a refresh.
    if (_isToday()) {
      fetchData();
    }
  }

  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<bool> _hasWorkoutOnDate(DateTime date) async {
    final midnight = DateTime(date.year, date.month, date.day);
    final nextMidnight = midnight.add(const Duration(days: 1));
    final workouts = await health.getHealthDataFromTypes(
      startTime: midnight,
      endTime: nextMidnight,
      types: [HealthDataType.WORKOUT],
    );
    return workouts.any((p) => p.type == HealthDataType.WORKOUT);
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
               controller: _pageController,
               onPageChanged: _onPageChanged,
               itemBuilder: (context, page) {
                 final daysOffset = page - _initialPage;
                 final date = _baseDate.add(Duration(days: daysOffset));
                 final dayOnly = DateTime(date.year, date.month, date.day);

                 final dayStats = _dayStatsCache[dayOnly] ?? DayStats(isLoading: true);
                 if (dayStats.isLoading && _dayStatsCache[dayOnly] == null) {
                   // This check prevents re-fetching if already loading
                   // It might be called when page is scrolling into view
                   Future.microtask(() => fetchData(date));
                 }

                 return RefreshIndicator(
                     onRefresh: () => fetchData(date),
                     child: _buildDayView(date, dayStats));
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

  Widget _buildDayView(DateTime date, DayStats stats) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bool isTodayPage =
        date.year == today.year && date.month == today.month && date.day == today.day;

    if (stats.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
                    key: ValueKey<String>('stats_${date.toIso8601String()}'),
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
                            trailing: Text('${stats.steps}'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.map),
                            title: const Text('Distance'),
                            trailing: Text(_useImperial
                                ? '${(stats.distance * 0.000621371).toStringAsFixed(2)} mi'
                                : '${(stats.distance / 1000).toStringAsFixed(2)} km'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.local_fire_department),
                            title: const Text('Calories'),
                            trailing:
                              Text('${stats.calories.toStringAsFixed(0)} cal'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (stats.workouts.isNotEmpty)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Card(
                      key: ValueKey<int>(stats.workouts.hashCode),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text('Workouts',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 10),
                            ...stats.workouts.map((workout) {
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
