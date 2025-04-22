import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification.dart';

class NotificationProvider with ChangeNotifier {
  List<AppNotification> _notifications = [];
  bool _isLoading = false;
  String? _error;
  late SharedPreferences _prefs;
  bool _isInitialized = false;
  int _unreadCount = 0;

  List<AppNotification> get notifications => [..._notifications];
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get unreadCount => _unreadCount;

  NotificationProvider() {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadNotificationsFromPrefs();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> fetchNotifications(String? token, String userId) async {
    if (token == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }

      final url = Uri.parse('$apiUrl/notifications');
      print('Fetching notifications from: $url');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('Fetch notifications response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> notificationsData = json.decode(response.body);
        _notifications = notificationsData
            .map((data) => AppNotification.fromJson(data))
            .toList();
        
        // Sort notifications by date (newest first)
        _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // Count unread notifications
        _updateUnreadCount();
        
        // Save to shared preferences
        _saveNotificationsToPrefs();
        
        _error = null;
        _isLoading = false;
        notifyListeners();
      } else {
        // For demo purposes, generate mock notifications if API fails
        _generateMockNotifications(userId);
        _error = null;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      print('Fetch notifications error: $e');
      
      // For demo purposes, generate mock notifications if API fails
      _generateMockNotifications(userId);
      _error = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  void _generateMockNotifications(String userId) {
    // Only generate mock data if we don't already have notifications
    if (_notifications.isNotEmpty) return;
    
    final now = DateTime.now();
    
    // Generate different notifications based on user role
    // We'll determine role based on the presence of notifications in shared preferences
    final isTeacher = _prefs.getBool('is_teacher') ?? false;
    
    if (isTeacher) {
      _notifications = [
        AppNotification(
          id: '1',
          userId: userId,
          title: 'Welcome to LearnLive!',
          message: 'Thank you for joining as a teacher. Start creating courses now!',
          actionType: 'welcome',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
        AppNotification(
          id: '2',
          userId: userId,
          title: 'Course Created Successfully',
          message: 'Your course "Mathematics for 6th Grade" has been created.',
          actionType: 'course',
          actionId: '123',
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
        AppNotification(
          id: '3',
          userId: userId,
          title: 'New Student Enrolled',
          message: 'Alex Smith has enrolled in your "Mathematics for 6th Grade" course.',
          actionType: 'course',
          actionId: '123',
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
        AppNotification(
          id: '4',
          userId: userId,
          title: 'Session Starting Soon',
          message: 'Your "Introduction to Fractions" session starts in 30 minutes.',
          actionType: 'session',
          actionId: '456',
          createdAt: now.subtract(const Duration(minutes: 30)),
        ),
        AppNotification(
          id: '5',
          userId: userId,
          title: 'Payment Received',
          message: 'You received a payment of ₹1000 from Emma Thompson.',
          actionType: 'payment',
          createdAt: now.subtract(const Duration(minutes: 15)),
        ),
      ];
    } else {
      _notifications = [
        AppNotification(
          id: '1',
          userId: userId,
          title: 'Welcome to LearnLive!',
          message: 'Thank you for joining our platform. Start exploring courses now!',
          actionType: 'welcome',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
        AppNotification(
          id: '2',
          userId: userId,
          title: 'New Course Available',
          message: 'Check out our new "Advanced Mathematics" course for Grade 7.',
          actionType: 'course',
          actionId: '123',
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
        AppNotification(
          id: '3',
          userId: userId,
          title: 'Upcoming Live Session',
          message: 'Your "Introduction to Fractions" session starts in 2 hours.',
          actionType: 'session',
          actionId: '456',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        AppNotification(
          id: '4',
          userId: userId,
          title: 'New Course Material',
          message: 'New study materials have been added to "Science Exploration".',
          actionType: 'material',
          actionId: '789',
          createdAt: now.subtract(const Duration(minutes: 45)),
        ),
        AppNotification(
          id: '5',
          userId: userId,
          title: 'Payment Successful',
          message: 'Your payment of ₹1000 has been processed successfully.',
          actionType: 'payment',
          createdAt: now.subtract(const Duration(minutes: 15)),
        ),
      ];
    }
    
    // Sort notifications by date (newest first)
    _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Update unread count
    _updateUnreadCount();
    
    // Save to shared preferences
    _saveNotificationsToPrefs();
  }

  Future<void> markAsRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    _notifications[index] = _notifications[index].copyWith(isRead: true);
    _updateUnreadCount();
    _saveNotificationsToPrefs();
    notifyListeners();

    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/notifications/$notificationId/read');
      final token = _prefs.getString('token');
      
      if (token != null) {
        await http.put(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      print('Mark notification as read error: $e');
    }
  }

  Future<void> markAllAsRead(String? token) async {
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    _updateUnreadCount();
    _saveNotificationsToPrefs();
    notifyListeners();

    try {
      if (token == null) return;
      
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/notifications/read-all');
      
      await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      print('Mark all notifications as read error: $e');
    }
  }

  Future<void> deleteNotification(String notificationId, String? token) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    _notifications.removeAt(index);
    _updateUnreadCount();
    _saveNotificationsToPrefs();
    notifyListeners();

    try {
      if (token == null) return;
      
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/notifications/$notificationId');
      
      await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      print('Delete notification error: $e');
    }
  }

  void addNotification(AppNotification notification) {
    _notifications.insert(0, notification); // Add to the beginning of the list
    _updateUnreadCount();
    _saveNotificationsToPrefs();
    notifyListeners();
  }

  void _updateUnreadCount() {
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

  Future<void> _saveNotificationsToPrefs() async {
    try {
      final notificationsJson = _notifications.map((n) => json.encode(n.toJson())).toList();
      await _prefs.setStringList('notifications', notificationsJson);
    } catch (e) {
      print('Error saving notifications to prefs: $e');
    }
  }

  Future<void> _loadNotificationsFromPrefs() async {
    try {
      final notificationsJson = _prefs.getStringList('notifications');
      
      if (notificationsJson != null && notificationsJson.isNotEmpty) {
        _notifications = notificationsJson
            .map((json) => AppNotification.fromJson(jsonDecode(json)))
            .toList();
        
        // Sort notifications by date (newest first)
        _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // Update unread count
        _updateUnreadCount();
        
        notifyListeners();
      }
    } catch (e) {
      print('Error loading notifications from prefs: $e');
    }
  }

  void setUserRole(bool isTeacher) {
    _prefs.setBool('is_teacher', isTeacher);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
