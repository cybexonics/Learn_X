import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This is a singleton class to manage push notifications
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;
  String? _token;
  late BuildContext _context;
  
  // Initialize the notification service
  Future<void> initialize(BuildContext context) async {
    if (_initialized) return;
    
    _context = context;
    
    // Initialize Firebase if not already initialized
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
    }
    
    // Request permission for iOS
    if (Platform.isIOS) {
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    
    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final DarwinInitializationSettings initializationSettingsIOS = 
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
        );
    
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );
    
    // Create notification channel for Android
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      );
      
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    
    // Get FCM token
    _token = await _fcm.getToken();
    debugPrint('FCM Token: $_token');
    
    // Save token to shared preferences
    if (_token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', _token!);
      
      // Register token with backend
      await _registerTokenWithBackend(_token!);
    }
    
    // Configure FCM message handling
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Check for initial message (app opened from terminated state)
    final RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
    
    _initialized = true;
  }
  
  // Register FCM token with backend
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token');
      
      if (authToken == null) {
        debugPrint('Auth token not found, skipping FCM token registration');
        return;
      }
      
      final url = Uri.parse('$apiUrl/users/me/device-token');
      
      await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'device_token': token,
          'device_type': Platform.isAndroid ? 'android' : 'ios',
        }),
      );
      
      debugPrint('FCM token registered with backend');
    } catch (e) {
      debugPrint('Error registering FCM token with backend: $e');
    }
  }
  
  // Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground message received: ${message.notification?.title}');
    
    // Show local notification
    if (message.notification != null) {
      await _showLocalNotification(
        message.notification!.title ?? 'New Notification',
        message.notification!.body ?? '',
        message.data,
      );
    }
  }
  
  // Handle when app is opened from a notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('App opened from notification: ${message.notification?.title}');
    
    // Navigate based on notification data
    if (message.data.containsKey('action_type') && message.data.containsKey('action_id')) {
      _navigateBasedOnAction(message.data['action_type'], message.data['action_id']);
    } else {
      // Default navigation to notifications screen
      Navigator.of(_context).pushNamed('/notifications');
    }
  }
  
  // Show local notification
  Future<void> _showLocalNotification(String title, String body, Map<String, dynamic> payload) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );
    
    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: json.encode(payload),
    );
  }
  
  // Handle iOS local notification
  void _onDidReceiveLocalNotification(int id, String? title, String? body, String? payload) {
    debugPrint('iOS local notification: $title');
  }
  
  // Handle notification tap
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    
    if (response.payload != null) {
      try {
        final data = json.decode(response.payload!);
        if (data.containsKey('action_type') && data.containsKey('action_id')) {
          _navigateBasedOnAction(data['action_type'], data['action_id']);
        } else {
          // Default navigation to notifications screen
          Navigator.of(_context).pushNamed('/notifications');
        }
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
        Navigator.of(_context).pushNamed('/notifications');
      }
    } else {
      Navigator.of(_context).pushNamed('/notifications');
    }
  }
  
  // Navigate based on notification action
  void _navigateBasedOnAction(String actionType, String actionId) {
    switch (actionType) {
      case 'course':
        Navigator.of(_context).pushNamed(
          '/courses/explore',
          arguments: {'courseId': actionId},
        );
        break;
      case 'session':
        Navigator.of(_context).pushNamed(
          '/live-session',
          arguments: {'sessionId': actionId},
        );
        break;
      case 'material':
        // Navigate to course material
        break;
      case 'payment':
        // Navigate to payment history
        break;
      default:
        Navigator.of(_context).pushNamed('/notifications');
    }
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for background handlers
  await Firebase.initializeApp();
  
  debugPrint('Background message received: ${message.notification?.title}');
  
  // No need to show a notification as FCM will automatically display it
}
