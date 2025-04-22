class CourseMaterial {
  final String id;
  final String courseId;
  final String title;
  final String description;
  final String type; // 'note', 'pdf', 'document', 'image', 'video', 'file', etc.
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? content; // For text-based notes
  final String? externalUrl;
  final DateTime createdAt;
  final String? createdBy;

  CourseMaterial({
    required this.id,
    required this.courseId,
    required this.title,
    required this.description,
    required this.type,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.content,
    this.externalUrl,
    required this.createdAt,
    this.createdBy,
  });

  factory CourseMaterial.fromJson(Map<String, dynamic> json) {
    return CourseMaterial(
      id: json['id'],
      courseId: json['course_id'],
      title: json['title'],
      description: json['description'],
      type: json['type'],
      fileUrl: json['file_url'],
      fileName: json['file_name'],
      fileSize: json['file_size'],
      content: json['content'],
      externalUrl: json['external_url'],
      createdAt: DateTime.parse(json['created_at']),
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_id': courseId,
      'title': title,
      'description': description,
      'type': type,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'content': content,
      'external_url': externalUrl,
      'created_by': createdBy,
    };
  }

  // Helper method to format file size
  String? getFormattedFileSize() {
    if (fileSize == null) return null;
    
    if (fileSize! < 1024) {
      return '$fileSize B';
    } else if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
