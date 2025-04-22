import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/student/class_selector.dart';
import '../../widgets/student/upcoming_sessions.dart';
import '../../widgets/student/available_courses.dart';
import '../../widgets/student/enrolled_courses.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_badge.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({Key? key}) : super(key: key);

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  bool _isInit = true;
  bool _isLoading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _fetchData();
      _isInit = false;
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final courseProvider = Provider.of<CourseProvider>(context, listen: false);
      final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
      
      // Initialize the course provider
      await courseProvider.initialize(authProvider.token);
      
      // Fetch data
      await Future.wait([
        courseProvider.fetchAvailableCourses(
          authProvider.token,
          authProvider.user?.classLevel,
        ),
        courseProvider.fetchEnrolledCourses(authProvider.token),
        courseProvider.fetchUpcomingSessions(authProvider.token),
        notificationProvider.fetchNotifications(authProvider.token, authProvider.user?.id ?? ''),
      ]);
      
      // Check for errors
      if (courseProvider.error != null) {
        setState(() {
          _error = courseProvider.error;
        });
        courseProvider.clearError();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load data: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          NotificationBadge(
            child: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.of(context).pushNamed('/notifications');
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error message if any
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    
                    // Welcome message
                    Text(
                      'Welcome, ${user?.name ?? 'Student'}!',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Let\'s continue your learning journey',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    
                    // Class selector
                    // const ClassSelector(),
                    // const SizedBox(height: 24),
                    
                    // Upcoming sessions
                    const Text(
                      'Upcoming Live Sessions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const UpcomingSessions(),
                    const SizedBox(height: 18),

                    // Available courses
                    const Text(
                      'Available Courses',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const AvailableCourses(),
                    const SizedBox(height: 18),
                    
                    // Enrolled courses
                    const Text(
                      'My Courses',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const EnrolledCourse(),
                    const SizedBox(height: 18),
                    
                  ],
                ),
              ),
            ),
    );
  }
}
