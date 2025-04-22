import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user.dart';
import 'package:provider/provider.dart';
import 'notification_provider.dart';
import '../../services/push_notification_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;
  late SharedPreferences _prefs;
  bool _isInitialized = false;

  AuthProvider() {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadUserData();
    _isInitialized = true;
    notifyListeners();
  }
  
  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null;
  bool get isAuth => _token != null; // Added this getter as an alias for isAuthenticated
  bool get isStudent => _user?.role == 'student';
  bool get isTeacher => _user?.role == 'teacher';
  
  Future<bool> tryAutoLogin() async {
    // Wait for initialization if needed
    if (!_isInitialized) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        return !_isInitialized;
      });
    }
    
    // If already authenticated, return true
    if (isAuthenticated) {
      return true;
    }
    
    // Try to load from shared preferences
    _token = _prefs.getString('token');
    final userData = _prefs.getString('user');
    
    if (_token != null && userData != null) {
      _user = User.fromJson(json.decode(userData));
      notifyListeners();
    
    // Validate token by making a request to the server
    try {
      await _getUserData();
      print('Auto login successful for user: ${_user?.name}, role: ${_user?.role}');
      return true;
    } catch (e) {
      // If token is invalid, log out the user
      print('Auto login failed: $e');
      await logout();
      return false;
    }
  }
  
  return false;
}
  
  Future<void> _loadUserData() async {
    _token = _prefs.getString('token');
    final userData = _prefs.getString('user');
    
    if (_token != null && userData != null) {
      _user = User.fromJson(json.decode(userData));
      notifyListeners();
      
      // Validate token by making a request to the server
      try {
        await _getUserData();
      } catch (e) {
        // If token is invalid, log out the user
        await logout();
      }
    }
  }
  
  // Add this method to the AuthProvider class to update the notification provider when login/logout happens

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/token');
      print('Making login request to: $url');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': email,
          'password': password,
        },
      ).timeout(const Duration(seconds: 10));
      
      print('Login response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        _token = responseData['access_token'];
        
        // Get user data
        await _getUserData();
        
        // Save to shared preferences
        await _prefs.setString('token', _token!);
        await _prefs.setString('user', json.encode(_user!.toJson()));
        
        // Update notification provider with user role
        // Accessing context is not possible here, needs to be passed from UI
        // final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
        // notificationProvider.setUserRole(_user!.role == 'teacher');
        
        // Initialize push notifications
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   PushNotificationService().initialize(context);
        // });
        
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final responseData = json.decode(response.body);
        _error = responseData['detail'] ?? 'Authentication failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('Login error: $e');
      _error = 'Connection error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> signup(String name, String email, String password, String role) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/users');
      print('Making signup request to: $url');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('Signup response status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final responseData = json.decode(response.body);
        _error = responseData['detail'] ?? 'Registration failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('Signup error: $e');
      _error = 'Connection error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // Add debug logging to the _getUserData method to help diagnose role issues
  Future<void> _getUserData() async {
    if (_token == null) {
      throw Exception('No token available');
    }
    
    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/users/me');
      print('Getting user data from: $url');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      print('Get user data response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        _user = User.fromJson(userData);
        print('User role: ${_user!.role}, ID: ${_user!.id}');
      } else {
        throw Exception('Failed to load user data: ${response.statusCode}');
      }
    } catch (e) {
      print('Get user data error: $e');
      _error = e.toString();
      rethrow;
    }
  }
  
  Future<bool> updateClassLevel(String classLevel) async {
    if (_user?.role != 'student') {
      _error = 'Only students can update class level';
      notifyListeners();
      return false;
    }
    
    if (_token == null) {
      _error = 'Authentication required';
      notifyListeners();
      return false;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/users/me/class');
      print('Updating class level at: $url');
      
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'class_level': classLevel}),
      ).timeout(const Duration(seconds: 10));
      
      print('Update class level response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        _user = User.fromJson(userData);
        await _prefs.setString('user', json.encode(_user!.toJson()));
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final responseData = json.decode(response.body);
        _error = responseData['detail'] ?? 'Failed to update class level';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('Update class level error: $e');
      _error = 'Connection error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<void> logout() async {
    _token = null;
    _user = null;
    await _prefs.remove('token');
    await _prefs.remove('user');
    
    // Clear FCM token on logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fcm_token');
    
    notifyListeners();
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
