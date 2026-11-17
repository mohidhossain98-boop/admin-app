import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase এর জন্য অপেক্ষা না কইরা অ্যাপ আগেই খুলে দিলাম
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Admin App',
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: true),
      home: const FirebaseGate(),
    );
  }
}

class FirebaseGate extends StatefulWidget {
  const FirebaseGate({super.key});
  @override
  State<FirebaseGate> createState() => _FirebaseGateState();
}

class _FirebaseGateState extends State<FirebaseGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initFirebase();
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Firebase init failed: $e');
      // ফেইল করলেও সামনে যাইতে দিবো
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return const AdminAuthGate();
      },
    );
  }
}

class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    try {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) return const AdminHomePage();
          return const AdminLoginPage();
        },
      );
    } catch (e) {
      return const AdminLoginPage();
    }
  }
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _signInWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Email ar password daw');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'invalid-credential' || e.code == 'user-not-found' || e.code == 'wrong-password') {
          _errorMessage = 'Email ba password vul hoise';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'Email ta thik nai';
        } else {
          _errorMessage = 'Login failed: ${e.message ?? e.code}';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5E7EB))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Admin Login', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('Email ar password diye login koro', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', hintText: 'admin@gmail.com', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
                    const SizedBox(height: 16),
                    TextField(controller: _passwordController, obscureText: _obscurePassword, decoration: InputDecoration(labelText: 'Password', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
                    if (_errorMessage != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))],
                    const SizedBox(height: 20),
                    SizedBox(height: 50, child: ElevatedButton(onPressed: _isLoading ? null : _signInWithEmail, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Login', style: TextStyle(fontSize: 16)))),
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

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Home'), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () async => await FirebaseAuth.instance.signOut())]),
      body: Center(child: Text('Welcome\n${user?.email ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20))),
    );
  }
}
