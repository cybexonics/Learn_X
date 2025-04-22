import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';
import '../../models/course.dart';

class CoursePaymentScreen extends StatefulWidget {
  const CoursePaymentScreen({Key? key}) : super(key: key);

  @override
  State<CoursePaymentScreen> createState() => _CoursePaymentScreenState();
}

class _CoursePaymentScreenState extends State<CoursePaymentScreen> {
  bool _isLoading = false;
  String? _error;
  Course? _course;

  final _cardNumberController = TextEditingController(text: '4242 4242 4242 4242');
  final _expiryDateController = TextEditingController(text: '12/25');
  final _cvvController = TextEditingController(text: '123');
  final _nameOnCardController = TextEditingController(text: 'Test User');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      setState(() {
        _course = args['course'] as Course;
      });
    });
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryDateController.dispose();
    _cvvController.dispose();
    _nameOnCardController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (_cardNumberController.text.isEmpty ||
        _expiryDateController.text.isEmpty ||
        _cvvController.text.isEmpty ||
        _nameOnCardController.text.isEmpty) {
      setState(() {
        _error = 'Please fill in all payment details';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final courseProvider = Provider.of<CourseProvider>(context, listen: false);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Processing Payment...',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              const SizedBox(height: 8),
              Text(
                'Amount: \$${_course!.price.toStringAsFixed(2)}',
                style: const TextStyle(fontFamily: 'Poppins'),
              ),
            ],
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      final success = await courseProvider.processPayment(
        authProvider.token,
        _course!.id,
        _course!.price,
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        // Ensure enrolled courses are refreshed
        await courseProvider.fetchEnrolledCourses(authProvider.token);

        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Payment Successful', style: TextStyle(fontFamily: 'Poppins')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Your payment was processed successfully!',
                  style: TextStyle(fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 8),
                Text(
                  'You are now enrolled in ${_course!.title}',
                  style: const TextStyle(fontFamily: 'Poppins'),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/student-dashboard',
                    (route) => false,
                  );
                },
                child: const Text('Go to Dashboard', style: TextStyle(fontFamily: 'Poppins')),
              ),
            ],
          ),
        );
      } else {
        setState(() {
          _error = courseProvider.error ?? 'Payment failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_course == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment', style: TextStyle(fontFamily: 'Poppins'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Payment', style: TextStyle(fontFamily: 'Poppins'))),
      body: SingleChildScrollView(
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
                      'Course: ${_course!.title}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Teacher: ${_course!.teacherName ?? 'Unknown Teacher'}',
                      style: const TextStyle(fontSize: 16, fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 8),
                    Text('Grade: ${_course!.grade}', style: const TextStyle(fontSize: 16, fontFamily: 'Poppins')),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount:',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                        ),
                        Text(
                          '\$${_course!.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Payment Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This is a demo payment form. The fields are pre-filled with test data. Just click "Pay Now" to proceed.',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 14, fontFamily: 'Poppins'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                child: Text(_error!, style: TextStyle(color: Colors.red.shade800, fontFamily: 'Poppins')),
              ),
            _buildTextField(_cardNumberController, 'Card Number', '1234 5678 9012 3456', Icons.credit_card),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(_expiryDateController, 'Expiry Date', 'MM/YY', null),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(_cvvController, 'CVV', '123', null, obscure: true),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(_nameOnCardController, 'Name on Card', 'John Doe', Icons.person),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8852E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Pay Now'),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.grey.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your payment information is secure and encrypted.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontFamily: 'Poppins'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData? icon, {
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.text,
      maxLength: obscure ? 3 : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontFamily: 'Poppins'),
        hintStyle: const TextStyle(fontFamily: 'Poppins'),
        border: const OutlineInputBorder(),
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
      style: const TextStyle(fontFamily: 'Poppins'),
    );
  }
}
