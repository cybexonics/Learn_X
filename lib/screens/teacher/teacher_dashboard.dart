import 'package:flutter/material.dart';
import '../../screens/teacher/course_materials_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/teacher/teacher_upcoming_sessions.dart';
import '../../widgets/teacher/teacher_courses.dart';
import '../../widgets/notification_badge.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({Key? key}) : super(key: key);

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
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
      
      // Fetch data
      await Future.wait([
        courseProvider.fetchAvailableCourses(authProvider.token, null),
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
    final courseProvider = Provider.of<CourseProvider>(context);
    
    // Filter courses by teacher
    final teacherId = user?.id;
    final teacherCourses = courseProvider.availableCourses
        .where((course) => course.teacherId == teacherId)
        .toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'create_session',
            onPressed: () {
              Navigator.of(context).pushNamed('/sessions/create');
            },
            child: const Icon(Icons.video_call),
            tooltip: 'Create Session',
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'create_course',
            onPressed: () {
              Navigator.of(context).pushNamed('/courses/create');
            },
            child: const Icon(Icons.add),
            tooltip: 'Create Course',
          ),
        ],
      ),
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
                      'Welcome, ${user?.name ?? 'Teacher'}!',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your courses and sessions',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    
                    // Stats cards
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.book),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${teacherCourses.length}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('Active Courses'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.people),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${teacherCourses.fold(0, (sum, course) => sum + (course.students?.length ?? 0))}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('Total Students'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Upcoming sessions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Upcoming Live Sessions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/sessions/create');
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('New Session'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const TeacherUpcomingSessions(),
                    const SizedBox(height: 24),
                    
                    // My courses
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'My Courses',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            if (teacherCourses.isNotEmpty) {
                              // Use direct navigation with MaterialPageRoute to ensure proper arguments passing
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CourseMaterialsScreen(courseId: teacherCourses[0].id),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Create a course first to manage materials')),
                              );
                            }
                          },
                          icon: const Icon(Icons.book),
                          label: const Text('Manage Materials'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const TeacherCourses(),
                  ],
                ),
              ),
            ),
    );
  }
}
