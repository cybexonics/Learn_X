class Payment {
  final String id;
  final String userId;
  final String courseId;
  final double amount;
  final String status; // 'pending', 'completed', 'failed'
  final String? transactionId;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.userId,
    required this.courseId,
    required this.amount,
    required this.status,
    this.transactionId,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'],
      userId: json['user_id'],
      courseId: json['course_id'],
      amount: json['amount'].toDouble(),
      status: json['status'],
      transactionId: json['transaction_id'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'course_id': courseId,
      'amount': amount,
      'status': status,
      'transaction_id': transactionId,
    };
  }
}

