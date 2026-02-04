// ignore_for_file: public_member_api_docs

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spot/cubits/notification/notification_cubit.dart';
import 'package:spot/data_profiders/location_provider.dart';
import 'package:spot/pages/tab_page.dart';
import 'package:spot/repositories/repository.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static const FlutterSecureStorage _localStorage = FlutterSecureStorage();
  static final LocationProvider _locationProvider = LocationProvider();

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<Repository>(
          create: (context) => Repository(
            firebaseAuth: _firebaseAuth,
            firestore: _firestore,
            storage: _storage,
            functions: _functions,
            analytics: _analytics,
            localStorage: _localStorage,
            locationProvider: _locationProvider,
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<NotificationCubit>(
            create: (context) => NotificationCubit(
              repository: RepositoryProvider.of<Repository>(context),
            )..loadNotifications(),
          )
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            textSelectionTheme:
                const TextSelectionThemeData(cursorColor: Color(0xFFFFFFFF)),
            primaryColor: const Color(0xFFFFFFFF),
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              titleTextStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w300,
              ),
            ),
            inputDecorationTheme: const InputDecorationTheme(
              labelStyle: TextStyle(color: Color(0xFFFFFFFF)),
              border: OutlineInputBorder(
                borderSide: BorderSide(width: 1, color: Color(0xFFFFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(width: 1, color: Color(0xFFFFFFFF)),
              ),
              focusColor: Color(0xFFFFFFFF),
              isDense: true,
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFFFFF),
                side: const BorderSide(color: Color(0xFFFFFFFF)),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
              elevation: 10,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
          ],
          navigatorObservers: [
            FirebaseAnalyticsObserver(analytics: _analytics),
          ],
          home: TabPage(),
        ),
      ),
    );
  }
}
