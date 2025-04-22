class Course {
  final String id;
  final String title;
  final String description;
  final String grade;
  final double price;
  final String? teacherId;
  final String? teacherName;
  final List<String>? students;
  final String? thumbnail;
  final String? videoUrl; // Added for course video

  Course({
    required this.id,
    required this.title,
    required this.description,
    required this.grade,
    required this.price,
    this.teacherId,
    this.teacherName,
    this.students,
    this.thumbnail,
    this.videoUrl, // Added for course video
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      grade: json['grade'],
      price: json['price'].toDouble(),
      teacherId: json['teacher_id'],
      teacherName: json['teacher_name'],
      students: json['students'] != null
          ? List<String>.from(json['students'])
          : null,
      thumbnail: json['thumbnail'],
      videoUrl: json['video_url'], // Added for course video
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'grade': grade,
      'price': price,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'video_url': videoUrl, // Added for course video
    };
  }
}
