import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';
import '../../models/course.dart';
import '../../models/course_material.dart';
import '../pdf_viewer_screen.dart';
import 'video_player_screen.dart';

class CourseExploreScreen extends StatefulWidget {
  const CourseExploreScreen({Key? key}) : super(key: key);

  @override
  State<CourseExploreScreen> createState() => _CourseExploreScreenState();
}

class _CourseExploreScreenState extends State<CourseExploreScreen> {
  bool _isLoading = true;
  bool _isEnrolled = false;
  String? _error;
  Course? _course;
  List<CourseMaterial> _materials = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCourseDetails();
    });
  }

  Future<void> _loadCourseDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      final courseId = args['courseId'] as String;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final courseProvider = Provider.of<CourseProvider>(context, listen: false);

      // First check if we're enrolled using the efficient method
      final isEnrolled = courseProvider.isEnrolledInCourse(courseId);
    
      final course = await courseProvider.fetchCourseDetails(authProvider.token, courseId);
      if (course == null) {
        setState(() {
          _error = courseProvider.error ?? 'Failed to load course details';
          _isLoading = false;
        });
        return;
      }

      final materials = await courseProvider.fetchCourseMaterials(authProvider.token, courseId);

      setState(() {
        _course = course;
        _isEnrolled = isEnrolled;
        _materials = materials;
        _isLoading = false;
      });
    
      // Log enrollment status for debugging
      print('Course ${course.title} (ID: ${course.id}) - Enrollment status: $_isEnrolled');
    } catch (e) {
      setState(() {
        _error = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // Update the _viewPdf method to use the in-app PDF viewer
  Future<void> _viewPdf(String url) async {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(
            pdfUrl: url,
            title: 'PDF Viewer',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening PDF: ${e.toString()}')),
      );
    }
  }

  void _showPaymentPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Premium Content', style: GoogleFonts.poppins()),
        content: Text(
          'You need to enroll in this course to access the materials. Would you like to proceed to payment?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8852E5),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamed(
                '/courses/payment',
                arguments: {'course': _course},
              );
            },
            child: Text('Proceed to Payment', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _viewCourseVideo() {
    if (_course?.videoUrl != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: _course!.videoUrl!,
            title: _course!.title,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video available for this course')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Course Details', style: GoogleFonts.poppins()),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Course Details', style: GoogleFonts.poppins()),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text('Error', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 16)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8852E5)),
                  child: Text('Go Back', style: GoogleFonts.poppins()),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_course == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Course Details', style: GoogleFonts.poppins()),
        ),
        body: Center(child: Text('Course not found', style: GoogleFonts.poppins())),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_course!.title, style: GoogleFonts.poppins()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 200,
              width: double.infinity,
              color: Colors.indigo.shade100,
              child: Center(
                child: Icon(Icons.book, size: 80, color: theme.primaryColor),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _course!.title,
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Grade ${_course!.grade}',
                    style: GoogleFonts.poppins(color: theme.primaryColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('by ${_course!.teacherName ?? 'Unknown Teacher'}',
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('\$${_course!.price.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                if (_isEnrolled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Text('Enrolled',
                        style: GoogleFonts.poppins(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            if (_course?.videoUrl != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _viewCourseVideo,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Watch Course Video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Course Materials',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                if (!_isEnrolled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, size: 16, color: Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text('Premium Content',
                            style: GoogleFonts.poppins(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_materials.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text('No materials available for this course',
                      style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey)),
                ),
              )
            else
              Column(
                children: List.generate(_materials.length, (index) {
                  final material = _materials[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Stack(
                      children: [
                        ListTile(
                          leading: Icon(
                            material.type == 'pdf' ? Icons.picture_as_pdf : Icons.note,
                            color: material.type == 'pdf' ? Colors.red : Colors.blue,
                          ),
                          title: Text(material.title, style: GoogleFonts.poppins()),
                          subtitle: Text(material.description, style: GoogleFonts.poppins(fontSize: 13)),
                          trailing: _isEnrolled
                              ? IconButton(
                                  icon: Icon(
                                    material.type == 'pdf' ? Icons.open_in_new : Icons.visibility,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  onPressed: () {
                                    if (material.fileUrl != null) {
                                      _viewPdf(material.fileUrl!);
                                    } else if (material.content != null) {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(material.title, style: GoogleFonts.poppins()),
                                          content: SingleChildScrollView(
                                            child: Text(material.content!, style: GoogleFonts.poppins()),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(),
                                              child: Text('Close', style: GoogleFonts.poppins()),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(Icons.lock, color: Colors.grey),
                                  onPressed: _showPaymentPrompt,
                                ),
                        ),
                        if (!_isEnrolled)
                          Positioned.fill(
                            child: Material(
                              color: Colors.white.withOpacity(0.5),
                              child: InkWell(
                                onTap: _showPaymentPrompt,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock, color: Colors.grey.shade700, size: 24),
                                      const SizedBox(height: 4),
                                      Text('Enroll to Access',
                                          style: GoogleFonts.poppins(
                                              color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}
