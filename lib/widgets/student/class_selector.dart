import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';

class ClassSelector extends StatefulWidget {
  const ClassSelector({Key? key}) : super(key: key);

  @override
  State<ClassSelector> createState() => _ClassSelectorState();
}

class _ClassSelectorState extends State<ClassSelector> {
  String? _selectedClass;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize with user's class level
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    _selectedClass = user?.classLevel;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final courseProvider = Provider.of<CourseProvider>(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Your Class',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedClass,
              decoration: const InputDecoration(
                hintText: 'Select your class',
                prefixIcon: Icon(Icons.school),
              ),
              items: const [
                DropdownMenuItem(
                  value: '5',
                  child: Text('Grade 5'),
                ),
                DropdownMenuItem(
                  value: '6',
                  child: Text('Grade 6'),
                ),
                DropdownMenuItem(
                  value: '7',
                  child: Text('Grade 7'),
                ),
                DropdownMenuItem(
                  value: '8',
                  child: Text('Grade 8'),
                ),
              ],
              onChanged: _isLoading
                  ? null
                  : (value) async {
                      if (value != _selectedClass) {
                        setState(() {
                          _selectedClass = value;
                          _isLoading = true;
                        });
                        
                        // Update user's class level
                        await authProvider.updateClassLevel(value!);
                        
                        // Fetch courses for the selected class
                        await courseProvider.fetchAvailableCourses(
                          authProvider.token,
                          value,
                        );
                        
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    },
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

