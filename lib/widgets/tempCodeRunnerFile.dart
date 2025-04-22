import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final isStudent = authProvider.isStudent;
    
    return Drawer(
      child: Column(
        children: [
          // User info header
          UserAccountsDrawerHeader(
            accountName: Text(user?.name ?? 'User'),
            accountEmail: Text(user?.email ?? 'user@example.com'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                user?.name?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
          ),
          
          // Menu items
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.of(context).pop();
              if (isStudent) {
                Navigator.of(context).pushReplacementNamed('/student-dashboard');
              } else {
                Navigator.of(context).pushReplacementNamed('/teacher-dashboard');
              }
            },
          ),
          
          if (isStudent)
            ListTile(
              leading: const Icon(Icons.book),
              title: const Text('My Courses'),
              onTap: () {
                Navigator.of(context).pop();
                // Navigate to enrolled courses
              },
            ),
          
          if (!isStudent)
            ListTile(
              leading: const Icon(Icons.add_box),
              title: const Text('Create Course'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/courses/create');
              },
            ),
          
          ListTile(
            leading: const Icon(Icons.video_call),
            title: const Text('Live Sessions'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/live_session_screen');
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.of(context).pop();
              // Navigate to profile
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              // Navigate to settings
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('Help & Support'),
            onTap: () {
              Navigator.of(context).pop();
              // Navigate to help
            },
          ),
          
          const Spacer(),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Logout'),
            onTap: () async {
              await authProvider.logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
    );
  }
}

