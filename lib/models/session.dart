class LiveSession {
  final String id;
  final String title;
  final String description;
  final String? moduleId;
  final String? course;
  final String date;
  final String time;
  final int duration;
  final String teacher;
  final String? meetingLink;
  final String? recordingLink;
  final List<String>? attendees;

  LiveSession({
    required this.id,
    required this.title,
    required this.description,
    this.moduleId,
    this.course,
    required this.date,
    required this.time,
    required this.duration,
    required this.teacher,
    this.meetingLink,
    this.recordingLink,
    this.attendees,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    return LiveSession(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      moduleId: json['module_id'],
      course: json['course'],
      date: json['date'],
      time: json['time'],
      duration: json['duration'],
      teacher: json['teacher'],
      meetingLink: json['meeting_link'],
      recordingLink: json['recording_link'],
      attendees: json['attendees'] != null
          ? List<String>.from(json['attendees'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'module_id': moduleId,
      'course': course,
      'date': date,
      'time': time,
      'duration': duration,
      'teacher': teacher,
      'meeting_link': meetingLink,
      'recording_link': recordingLink,
      'attendees': attendees,
    };
  }
}

