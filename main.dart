import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String kAdminPhone = '+8801625287338';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp().timeout(Duration(seconds: 5));
  } catch (_) {}
  runApp(const MyAdminApp());
}

class MyAdminApp extends StatelessWidget {
  const MyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Admin Approval Panel',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF15803D),
          primary: const Color(0xFF15803D),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6FBF7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF15803D),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
      ),
home: const AdminLoginPage(),
    );
  }
}

class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF15803D)),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AdminLoginPage();
        }

        final signedInPhone = _normalizePhone(user.phoneNumber ?? '');
        if (signedInPhone != kAdminPhone) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 56, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Unauthorized Number',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Only admin ($kAdminPhone) can access this panel.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF15803D),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const AdminPanel();
      },
    );
  }
}

String _normalizePhone(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (cleaned.startsWith('+880')) return cleaned;
  if (cleaned.startsWith('880')) return '+$cleaned';
  if (cleaned.startsWith('01') && cleaned.length == 11) return '+88$cleaned';
  return cleaned;
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController _phoneController =
      TextEditingController(text: kAdminPhone);
  final TextEditingController _otpController = TextEditingController();

  String? _verificationId;
  int? _resendToken;
  bool _codeSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    final normalized = _normalizePhone(_phoneController.text.trim());
    if (normalized != kAdminPhone) {
      setState(() {
        _errorMessage = 'Only Admin number ($kAdminPhone) is allowed.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: kAdminPhone,
      forceResendingToken: isResend ? _resendToken : null,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(credential);
        } catch (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = e.toString();
            });
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = e.message ?? 'OTP verification failed.';
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _codeSent = true;
          _isLoading = false;
        });
        _startResendTimer();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit OTP code.');
      return;
    }
    if (_verificationId == null) {
      setState(() => _errorMessage = 'Please request an OTP first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message ?? 'Invalid OTP code.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1215803D),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          size: 34,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Admin OTP Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in with Admin Phone (+8801625287338)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _phoneController,
                      enabled: !_codeSent && !_isLoading,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Admin Phone Number',
                        prefixIcon: const Icon(
                          Icons.phone_android_rounded,
                          color: Color(0xFF15803D),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF15803D),
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _otpController,
                        enabled: !_isLoading,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                        ),
                        decoration: InputDecoration(
                          labelText: '6-Digit OTP Code',
                          counterText: '',
                          prefixIcon: const Icon(
                            Icons.password_rounded,
                            color: Color(0xFF15803D),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF15803D),
                              width: 1.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : (_codeSent ? _verifyOtp : () => _sendOtp()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF15803D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _codeSent ? 'Verify & Login' : 'Send OTP',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    _timer?.cancel();
                                    setState(() {
                                      _codeSent = false;
                                      _otpController.clear();
                                      _errorMessage = null;
                                    });
                                  },
                            child: const Text(
                              'Change Number',
                              style: TextStyle(color: Color(0xFF475569)),
                            ),
                          ),
                          TextButton(
                            onPressed: (_resendSeconds > 0 || _isLoading)
                                ? null
                                : () => _sendOtp(isResend: true),
                            child: Text(
                              _resendSeconds > 0
                                  ? 'Resend in ${_resendSeconds}s'
                                  : 'Resend OTP',
                              style: const TextStyle(
                                color: Color(0xFF15803D),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  String tab = 'pending';
  String _searchQuery = '';
  final Set<String> _busyIds = <String>{};
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> approve(String id, {String? userName}) async {
    setState(() => _busyIds.add(id));
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'status': 'approved',
        'isApproved': true,
        'approved': true,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved ${userName ?? id}'),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to approve: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> reject(String id, {String? userName}) async {
    setState(() => _busyIds.add(id));
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'status': 'rejected',
        'isApproved': false,
        'approved': false,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejected ${userName ?? id}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reject: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> createPendingUser(String phone, String name) async {
    final String normalized = _normalizePhone(phone);
    final String docId = normalized.replaceAll('+88', '');
    await FirebaseFirestore.instance.collection('users').doc(docId).set({
      'phone': normalized,
      'name': name.trim(),
      'status': 'pending',
      'isApproved': false,
      'approved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _resolveStatus(Map<String, dynamic> data) {
    final rawStatus = (data['status'] ?? '').toString().trim().toLowerCase();
    if (rawStatus == 'approved' ||
        rawStatus == 'rejected' ||
        rawStatus == 'pending') {
      return rawStatus;
    }
    if (data['isApproved'] == true || data['approved'] == true) {
      return 'approved';
    }
    return 'pending';
  }

  DateTime? _extractDateTime(Map<String, dynamic> data, String status) {
    final dynamic raw = status == 'approved'
        ? (data['approvedAt'] ?? data['createdAt'])
        : status == 'rejected'
            ? (data['rejectedAt'] ?? data['createdAt'])
            : data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Just now';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Panel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '01625-287338',
              style: TextStyle(fontSize: 12, color: Color(0xFFDCFCE7)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Firestore Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot>[];

          int pendingCount = 0;
          int approvedCount = 0;
          int rejectedCount = 0;

          final List<QueryDocumentSnapshot> filteredDocs = [];

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
            final status = _resolveStatus(data);

            if (status == 'pending') pendingCount++;
            if (status == 'approved') approvedCount++;
            if (status == 'rejected') rejectedCount++;

            if (status != tab) continue;

            if (_searchQuery.isNotEmpty) {
              final name = (data['name'] ?? '').toString().toLowerCase();
              final phone = (data['phone'] ?? doc.id).toString().toLowerCase();
              final q = _searchQuery.toLowerCase();
              if (!name.contains(q) && !phone.contains(q)) continue;
            }

            filteredDocs.add(doc);
          }

          filteredDocs.sort((a, b) {
            final da = a.data() as Map<String, dynamic>? ?? <String, dynamic>{};
            final db = b.data() as Map<String, dynamic>? ?? <String, dynamic>{};
            final ta = _extractDateTime(da, tab) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final tb = _extractDateTime(db, tab) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return tb.compareTo(ta);
          });

          return Column(
            children: [
              Container(
                color: const Color(0xFF15803D),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search by name or phone...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF15803D)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF166534),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildTabButton('pending', 'Pending', pendingCount),
                          _buildTabButton('approved', 'Approved', approvedCount),
                          _buildTabButton('rejected', 'Rejected', rejectedCount),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF15803D)),
                      )
                    : filteredDocs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tab == 'pending'
                                      ? Icons.hourglass_empty_rounded
                                      : tab == 'approved'
                                          ? Icons.verified_outlined
                                          : Icons.block_outlined,
                                  size: 48,
                                  color: const Color(0xFF94A3B8),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'কোন ইউজার নাই',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredDocs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final doc = filteredDocs[index];
                              final data = doc.data() as Map<String, dynamic>? ??
                                  <String, dynamic>{};
                              final name = (data['name'] ?? 'Unnamed User')
                                  .toString()
                                  .trim();
                              final phone =
                                  (data['phone'] ?? doc.id).toString().trim();
                              final dt = _extractDateTime(data, tab);
                              final formattedTime = _formatDateTime(dt);
                              final isBusy = _busyIds.contains(doc.id);

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFDCFCE7),
                                    width: 1.2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0A000000),
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: const Color(0xFFDCFCE7),
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : 'U',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isEmpty ? 'Unnamed User' : name,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                phone,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: Color(0xFF334155),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time_rounded,
                                          size: 15,
                                          color: Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          formattedTime,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (tab == 'pending') ...[
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: isBusy
                                                  ? null
                                                  : () => approve(
                                                        doc.id,
                                                        userName: name,
                                                      ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF16A34A),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 12,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.check_rounded,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Approve',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: isBusy
                                                  ? null
                                                  : () => reject(
                                                        doc.id,
                                                        userName: name,
                                                      ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFFDC2626),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 12,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Reject',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else if (tab == 'approved') ...[
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: OutlinedButton.icon(
                                          onPressed: isBusy
                                              ? null
                                              : () => reject(
                                                    doc.id,
                                                    userName: name,
                                                  ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFFDC2626),
                                            side: const BorderSide(
                                              color: Color(0xFFFECACA),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('Revoke / Reject'),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: OutlinedButton.icon(
                                          onPressed: isBusy
                                              ? null
                                              : () => approve(
                                                    doc.id,
                                                    userName: name,
                                                  ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFF15803D),
                                            side: const BorderSide(
                                              color: Color(0xFFBBF7D0),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('Re-Approve'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton(String key, String label, int count) {
    final bool isSelected = tab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => tab = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSelected ? const Color(0xFF15803D) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
