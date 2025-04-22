class Module {
  final String id;
  final String title;
  final String description;
  final String courseId;
  final List<String>? sessions;
  final int order;

  Module({
    required this.id,
    required this.title,
    required this.description,
    required this.courseId,
    this.sessions,
    required this.order,
  });

  factory Module.fromJson(Map<String, dynamic> json) {
    return Module(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      courseId: json['course_id'],
      sessions: json['sessions'] != null
          ? List<String>.from(json['sessions'])
          : null,
      order: json['order'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'course_id': courseId,
      'sessions': sessions,
      'order': order,
    };
  }
}

