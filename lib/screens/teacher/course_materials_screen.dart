import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';
import '../../models/course.dart';
import '../../models/course_material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:http_parser/http_parser.dart'; // Add this import
import 'dart:convert'; // For json.decode

import '../pdf_viewer_screen.dart' show PdfViewerScreen;

class CourseMaterialsScreen extends StatefulWidget {
  final String? courseId;
  
  const CourseMaterialsScreen({Key? key, this.courseId}) : super(key: key);

  @override
  State<CourseMaterialsScreen> createState() => _CourseMaterialsScreenState();
}

class _CourseMaterialsScreenState extends State<CourseMaterialsScreen> {
  bool _isLoading = true;
  String? _error;
  Course? _course;
  List<CourseMaterial> _materials = [];

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedType = 'note';
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCourseDetails();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadCourseDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      String? courseId = widget.courseId;
      
      if (courseId == null) {
        setState(() {
          _error = 'Course ID not provided';
          _isLoading = false;
        });
        return;
      }
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final courseProvider = Provider.of<CourseProvider>(context, listen: false);
      
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
        _materials = materials;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _showAddMaterialDialog() {
    _titleController.clear();
    _descriptionController.clear();
    _contentController.clear();
    setState(() {
      _selectedType = 'note';
      _selectedFile = null;
    });
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Course Material'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Material Type'),
                Row(
                  children: [
                    Radio<String>(
                      value: 'note',
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedType = value!;
                        });
                      },
                    ),
                    const Text('Note'),
                    const SizedBox(width: 16),
                    Radio<String>(
                      value: 'pdf',
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedType = value!;
                        });
                      },
                    ),
                    const Text('PDF'),
                  ],
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                
                if (_selectedType == 'note')
                  TextField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      labelText: 'Note Content',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Upload PDF File'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _selectedFile != null 
                                  ? path.basename(_selectedFile!.path)
                                  : 'No file selected',
                                style: TextStyle(
                                  color: _selectedFile != null ? Colors.black : Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              FilePickerResult? result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf'],
                              );
                              
                              if (result != null) {
                                setDialogState(() {
                                  _selectedFile = File(result.files.single.path!);
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8852E5),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Browse'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_selectedFile != null)
                        Text(
                          'File size: ${(_selectedFile!.lengthSync() / 1024).toStringAsFixed(2)} KB',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color.fromARGB(255, 136, 82, 229),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _addMaterial();
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 136, 82, 229),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

Future<void> _addMaterial() async {
  if (_titleController.text.isEmpty || _descriptionController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please fill in all required fields')),
    );
    return;
  }
  
  if (_selectedType == 'note' && _contentController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please enter note content')),
    );
    return;
  }
  
  if (_selectedType == 'pdf' && _selectedFile == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a PDF file')),
    );
    return;
  }
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );
  
  try {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final courseProvider = Provider.of<CourseProvider>(context, listen: false);
    
    // Create multipart request
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.29.230:5000/courses/${_course!.id}/materials'),
    );
    
    // Add headers
    request.headers['Authorization'] = 'Bearer ${authProvider.token}';
    
    // Add form fields
    request.fields['title'] = _titleController.text;
    request.fields['description'] = _descriptionController.text;
    request.fields['type'] = _selectedType;
    
    if (_selectedType == 'note') {
      request.fields['content'] = _contentController.text;
    } else if (_selectedFile != null) {
      var fileStream = http.ByteStream(_selectedFile!.openRead());
      var length = await _selectedFile!.length();
      
      var multipartFile = http.MultipartFile(
        'file',
        fileStream,
        length,
        filename: path.basename(_selectedFile!.path),
        contentType: MediaType('application', 'pdf'),
      );
      
      request.files.add(multipartFile);
    }
    
    // Send request
    var response = await request.send();
    final responseBody = await response.stream.bytesToString();
    
    // Close loading dialog
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success - parse the response
      final jsonResponse = json.decode(responseBody);
      if (jsonResponse is Map<String, dynamic>) {
        // Refresh materials list
        await _loadCourseDetails();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Material added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Invalid response format');
      }
    } else {
      // Actual error case
      setState(() {
        _error = 'Failed to add material: ${response.statusCode} - $responseBody';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_error ?? 'Failed to add material'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    
    setState(() {
      _error = 'An error occurred: ${e.toString()}';
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_error!),
        backgroundColor: Colors.red,
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Course Materials')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Course Materials')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text('Error', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go Back'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _loadCourseDetails,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    if (_course == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Course Materials')),
        body: const Center(child: Text('Course not found')),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text('${_course!.title} - Materials'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMaterialDialog,
        backgroundColor: const Color(0xFF8852E5),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _course!.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Grade ${_course!.grade}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'Course Materials',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            Expanded(
              child: _materials.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'No materials added yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showAddMaterialDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Your First Material'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8852E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _materials.length,
                    itemBuilder: (ctx, index) => _buildMaterialCard(_materials[index]),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialCard(CourseMaterial material) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (material.type == 'pdf' && material.fileUrl != null) {
            _viewPdf(material.fileUrl!);
          } else if (material.type == 'note' && material.content != null) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(material.title),
                content: SingleChildScrollView(child: Text(material.content!)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          } else if (material.type == 'video' && material.fileUrl != null) {
            _playVideo(material.fileUrl!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getMaterialColor(material.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getMaterialIcon(material.type),
                  color: _getMaterialColor(material.type),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      material.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Added on ${_formatDate(material.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                onPressed: () => _showDeleteMaterialConfirmation(material),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteMaterialConfirmation(CourseMaterial material) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Material'),
        content: Text('Are you sure you want to delete "${material.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => const Center(child: CircularProgressIndicator()),
              );
              
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              final courseProvider = Provider.of<CourseProvider>(context, listen: false);
              
              final success = await courseProvider.deleteCourseMaterial(
                authProvider.token,
                _course!.id,
                material.id,
              );
              
              if (mounted) Navigator.of(context, rootNavigator: true).pop();
              
              if (success) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Material deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadCourseDetails();
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(courseProvider.error ?? 'Failed to delete material'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  IconData _getMaterialIcon(String type) {
    switch (type) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'note': return Icons.note;
      case 'video': return Icons.videocam;
      case 'image': return Icons.image;
      case 'link': return Icons.link;
      default: return Icons.insert_drive_file;
    }
  }

  Color _getMaterialColor(String type) {
    switch (type) {
      case 'pdf': return Colors.red;
      case 'note': return Colors.blue;
      case 'video': return Colors.green;
      case 'image': return Colors.purple;
      case 'link': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Future<void> _playVideo(String fileUrl) async {
    final Uri url = Uri.parse(fileUrl);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }
}