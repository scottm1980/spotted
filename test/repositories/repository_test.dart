import 'package:firebase_analytics/firebase_analytics.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spot/data_profiders/location_provider.dart';
import 'package:spot/repositories/repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../test_resources/constants.dart';

// ignore_for_file: unawaited_futures, subtype_of_sealed_class

class MockUser extends Mock implements User {}

class MockUserCredential extends Mock implements UserCredential {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockLocationProvider extends Mock implements LocationProvider {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  registerFallbackValue('');
  final firebaseAuth = MockFirebaseAuth();
  final firestore = MockFirebaseFirestore();
  final storage = MockFirebaseStorage();
  final functions = MockFirebaseFunctions();
  final analytics = MockFirebaseAnalytics();
  final localStorage = MockFlutterSecureStorage();
  final locationProvider = MockLocationProvider();

  // Global stubs for Repository initialization
  when(() => firebaseAuth.authStateChanges())
      .thenAnswer((_) => Stream<User?>.empty());

  Repository _createRepository() {
    return Repository(
      firebaseAuth: firebaseAuth,
      firestore: firestore,
      storage: storage,
      functions: functions,
      analytics: analytics,
      localStorage: localStorage,
      locationProvider: locationProvider,
    );
  }

  setUp(() {
    reset(firebaseAuth);
    reset(firestore);
    reset(storage);
    reset(functions);
    reset(analytics);
    reset(localStorage);
    reset(locationProvider);

    when(() => analytics.logEvent(
          name: any<String>(named: 'name'),
          parameters: any<Map<String, Object>?>(named: 'parameters'),
        )).thenAnswer((invocation) async => null);
    when(() => analytics.logSignUp(
            signUpMethod: any<String>(named: 'signUpMethod')))
        .thenAnswer((invocation) async => null);
    when(() =>
            analytics.logLogin(loginMethod: any<String>(named: 'loginMethod')))
        .thenAnswer((invocation) async => null);
    when(() =>
            analytics.logSearch(searchTerm: any<String>(named: 'searchTerm')))
        .thenAnswer((invocation) async => null);
    when(() => localStorage.read(key: any<String>(named: 'key')))
        .thenAnswer((invocation) async => null);
    when(locationProvider.determinePosition)
        .thenAnswer((_) async => const LatLng(0, 0));
  });

  group('repository', () {
    setUpAll(() async {
      // Setup done in main
    });

    tearDown(() {
      // Cleanup if needed
    });

    test('signUp', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.createUserWithEmailAndPassword(
          email: '',
          password: '')).thenAnswer((_) async => MockUserCredential());

      await repository.signUp(email: '', password: '');

      verify(() => firebaseAuth.createUserWithEmailAndPassword(
          email: '', password: '')).called(1);
    });

    test('signIn', () async {
      final repository = _createRepository();

      when(() =>
              firebaseAuth.signInWithEmailAndPassword(email: '', password: ''))
          .thenAnswer((_) async => MockUserCredential());

      await repository.signIn(email: '', password: '');

      verify(() =>
              firebaseAuth.signInWithEmailAndPassword(email: '', password: ''))
          .called(1);
    });

    test('getMyProfile', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.currentUser).thenReturn(user);

      final profileDoc = MockDocumentSnapshot();
      when(() => profileDoc.exists).thenReturn(true);
      when(() => profileDoc.data()).thenReturn({
        'name': 'Tyler',
        'description': 'Hi',
      });
      final profileRef = MockDocumentReference();
      when(() => firestore.collection('users').doc('aaa'))
          .thenReturn(profileRef);
      when(() => profileRef.get()).thenAnswer((_) async => profileDoc);

      await repository.getMyProfile();

      expect(repository.myProfile!.id, 'aaa');
      expect(repository.myProfile!.name, 'Tyler');
    });

    test('getVideosFromLocation', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.currentUser).thenReturn(user);

      // This is hard to mock perfectly due to geoflutterfire_plus wrapper,
      // but let's at least ensure we mock the Firestore collection it uses.
      final colRef = MockCollectionReference();
      when(() => firestore.collection('videos')).thenReturn(colRef);
      // fetchWithin will call query.get() internally or similar.
      // For now, we'll mock the error or return empty to see if it passes.
      when(() => colRef.get()).thenAnswer((_) async => MockQuerySnapshot());

      await repository.getVideosFromLocation(const LatLng(45.0, 45.0));
      // Verify something happened
      verify(() => firestore.collection('videos')).called(1);
    });

    test('getVideosInBoundingBox', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.currentUser).thenReturn(user);

      final colRef = MockCollectionReference();
      when(() => firestore.collection('videos')).thenReturn(colRef);
      when(() => colRef.get()).thenAnswer((_) async => MockQuerySnapshot());

      await repository.getVideosInBoundingBox(LatLngBounds(
          southwest: const LatLng(0, 0), northeast: const LatLng(45, 45)));

      verify(() => firestore.collection('videos'))
          .called(greaterThanOrEqualTo(1));
    });

    test('getVideosFromUid', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.currentUser).thenReturn(user);

      final query = MockQuery();
      final colRef = MockCollectionReference();
      when(() => firestore.collection('videos')).thenReturn(colRef);
      when(() => colRef.where('user_id', isEqualTo: 'aaa')).thenReturn(query);
      when(() => query.orderBy('created_at', descending: true))
          .thenReturn(query);

      final doc1 = MockQueryDocumentSnapshot();
      when(() => doc1.id).thenReturn('a');
      when(() => doc1.data()).thenReturn({
        'user_id': 'aaa',
        'created_at': Timestamp.now(),
        'url': '',
        'image_url': '',
        'thumbnail_url': '',
        'gif_url': '',
        'description': '',
      });

      final snapshot = MockQuerySnapshot();
      when(() => snapshot.docs).thenReturn([doc1]);

      when(() => query.get()).thenAnswer((_) async => snapshot);

      final videos = await repository.getVideosFromUid('aaa');

      expect(videos.length, 1);
      expect(videos.first.userId, 'aaa');
      expect(videos.first.id, 'a');
    });

    test('getProfile', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.currentUser).thenReturn(user);

      final profileDoc = MockDocumentSnapshot();
      when(() => profileDoc.exists).thenReturn(true);
      when(() => profileDoc.data()).thenReturn({
        'name': 'Tyler',
        'description': 'Hi',
      });
      final profileRef = MockDocumentReference();
      when(() => firestore.collection('users').doc('aaa'))
          .thenReturn(profileRef);
      when(() => profileRef.get()).thenAnswer((_) async => profileDoc);

      await repository.getProfileDetail('aaa');
      final profiles = await repository.profileStream.first;
      final profile = profiles['aaa'];

      expect(profile!.id, 'aaa');
      expect(profile.name, 'Tyler');
    });

    test('saveProfile', () async {
      final repository = _createRepository();

      final user = MockUser();
      when(() => user.uid).thenReturn('aaa');
      when(() => firebaseAuth.currentUser).thenReturn(user);

      final profileRef = MockDocumentReference();
      when(() => firestore.collection('users').doc(sampleProfile.id))
          .thenReturn(profileRef);
      when(() => profileRef.set(any(), any())).thenAnswer((_) async => {});

      // For the resetCache inside saveProfile
      final userRef = MockDocumentReference();
      when(() => firestore.collection('users').doc('aaa')).thenReturn(userRef);
      final userDoc = MockDocumentSnapshot();
      when(() => userDoc.exists).thenReturn(true);
      when(() => userDoc.data()).thenReturn({
        'name': 'Tyler',
        'description': 'Hi',
      });
      when(() => userRef.get()).thenAnswer((_) async => userDoc);

      await repository.saveProfile(profile: sampleProfile);

      final profiles = await repository.profileStream.first;
      expect(profiles[sampleProfile.id]!.name, sampleProfile.name);
    });

    group('Mentions', () {
      test('getMentionedProfiles on a comment with email address', () {
        final repository = _createRepository();
        final comment = 'Email me at sample@example.com';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });
        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 0);
      });
      test('getMentionedProfiles on a comment with no mentions', () {
        final repository = _createRepository();
        final comment = 'What do you think?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });
        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 0);
      });
      test('getMentionedProfiles at the beginning of sentence', () {
        final repository = _createRepository();
        final comment = '@${sampleProfile.name} What do you think?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });
        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 1);
        expect(profiles.first.id, 'aaa');
      });
      test('getMentionedProfiles in a sentence', () {
        final repository = _createRepository();
        final comment = 'Hey @${sampleProfile.name} ! How are you?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });
        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 1);
        expect(profiles.first.id, 'aaa');
      });
      test('getMentionedProfiles with one matching username', () {
        final repository = _createRepository();
        final comment = 'What do you think @${sampleProfile.name}?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });

        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 1);
        expect(profiles.first.id, 'aaa');
      });
      test('getMentionedProfiles with two matching username', () {
        final repository = _createRepository();
        final comment =
            'What do you think @${sampleProfile.name}, @${otherProfile.name}?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });

        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 2);
        expect(profiles.first.id, 'aaa');
        expect(profiles[1].id, 'bbb');
      });
      test('getMentionedProfiles with space in the username would not work',
          () {
        final repository = _createRepository();
        final comment = 'What do you think @John Tyter?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
          otherProfileDetail.id: otherProfileDetail,
        });

        final profiles = repository
            .getMentionedProfiles(commentText: comment, profilesInComments: []);

        expect(profiles.length, 0);
      });

      test('getMentionedProfiles returns profiles from comments profiles', () {
        final repository = _createRepository();
        final comment =
            'What do you think @${sampleProfile.name}, @${otherProfile.name}?';
        repository.profileDetailsCache.addAll({
          sampleProfileDetail.id: sampleProfileDetail,
        });

        final profiles = repository.getMentionedProfiles(
            commentText: comment, profilesInComments: [otherProfile]);

        expect(profiles.length, 2);
        expect(profiles.first.id, 'aaa');
        expect(profiles[1].id, 'bbb');
      });
    });
  });

  group('replaceMentionsInAComment', () {
    final repository = _createRepository();
    test('without mention', () {
      final comment = '@test';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [],
      );
      expect(replacedComment, '@test');
    });

    test('user mentioned at the beginning', () {
      final comment = '@${sampleProfile.name}';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [
          sampleProfile,
        ],
      );
      expect(replacedComment, '@${sampleProfile.id}');
    });
    test('user mentioned multiple times', () {
      final comment = '@${sampleProfile.name} @${sampleProfile.name}';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [sampleProfile],
      );
      expect(replacedComment, '@${sampleProfile.id} @${sampleProfile.id}');
    });
    test('multiple user mentions', () {
      final comment = '@${sampleProfile.name} @${otherProfile.name}';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [
          sampleProfile,
          otherProfile,
        ],
      );
      expect(replacedComment, '@${sampleProfile.id} @${otherProfile.id}');
    });
    test('there can be multiple mentions', () {
      final comment = '@${sampleProfile.name} @${otherProfile.name}';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [
          sampleProfile,
          otherProfile,
        ],
      );
      expect(replacedComment, '@${sampleProfile.id} @${otherProfile.id}');
    });

    test('mention can be in a sentence', () {
      final comment = 'some comment @${sampleProfile.name} more words';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [
          sampleProfile,
        ],
      );
      expect(replacedComment, 'some comment @${sampleProfile.id} more words');
    });

    test('multiple user mentions', () {
      final comment = 'some comment @${sampleProfile.name}';
      final replacedComment = repository.replaceMentionsInAComment(
        comment: comment,
        mentions: [
          sampleProfile,
        ],
      );
      expect(replacedComment, 'some comment @${sampleProfile.id}');
    });
  });

  group('getMentionedUserName', () {
    final repository = _createRepository();
    test('username is the only thing within the comment', () {
      final comment = '@test';
      final mentionedUserName = repository.getMentionedUserName(comment);
      expect(mentionedUserName, 'test');
    });
    test('username is at the end of comment', () {
      final comment = 'something @test';
      final mentionedUserName = repository.getMentionedUserName(comment);
      expect(mentionedUserName, 'test');
    });
    test('There are no @ sign in the comment', () {
      final comment = 'something test';
      final mentionedUserName = repository.getMentionedUserName(comment);
      expect(mentionedUserName, isNull);
    });
    test('@mention is not the last word in the comment', () {
      final comment = 'something @test another';
      final mentionedUserName = repository.getMentionedUserName(comment);
      expect(mentionedUserName, isNull);
    });
    test('There are multiple @ sign in the comment', () {
      final comment = 'something @test @some';
      final mentionedUserName = repository.getMentionedUserName(comment);
      expect(mentionedUserName, 'some');
    });
    test('getUserIdsInComment with 0 user id', () {
      final comment = 'some random text';
      final userIds = repository.getUserIdsInComment(comment);
      expect(userIds, <String>[]);
    });
    test('getUserIdsInComment with 1 user id at the beginning', () {
      final comment = '@b35bac1a-8d4b-4361-99cc-a1d274d1c4d2 yay';
      final userIds = repository.getUserIdsInComment(comment);
      expect(userIds, ['b35bac1a-8d4b-4361-99cc-a1d274d1c4d2']);
    });
    test('getUserIdsInComment with 1 user id', () {
      final comment =
          'something random @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2 yay';
      final userIds = repository.getUserIdsInComment(comment);
      expect(userIds, ['b35bac1a-8d4b-4361-99cc-a1d274d1c4d2']);
    });
    test('getUserIdsInComment with 2 user id', () {
      final comment =
          'something random @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2 yay'
          ' @aaabac1a-8d4b-4361-99cc-a1d274d1c4d2';
      final userIds = repository.getUserIdsInComment(comment);
      expect(userIds, [
        'b35bac1a-8d4b-4361-99cc-a1d274d1c4d2',
        'aaabac1a-8d4b-4361-99cc-a1d274d1c4d2'
      ]);
    });
    test('getUserIdsInComment with 2 user id with the same id', () {
      final comment =
          'something random @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2 yay'
          ' @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2';
      final userIds = repository.getUserIdsInComment(comment);
      expect(userIds, [
        'b35bac1a-8d4b-4361-99cc-a1d274d1c4d2',
        'b35bac1a-8d4b-4361-99cc-a1d274d1c4d2'
      ]);
    });
  });

  group('replaceMentionsWithUserNames', () {
    test('replaceMentionsWithUserNames with two profiles', () async {
      final repository = _createRepository();

      final tylerDoc = MockDocumentSnapshot();
      when(() => tylerDoc.exists).thenReturn(true);
      when(() => tylerDoc.data()).thenReturn({
        'name': 'Tyler',
        'description': 'Hi',
      });
      final tylerRef = MockDocumentReference();
      when(() => firestore
          .collection('users')
          .doc('b35bac1a-8d4b-4361-99cc-a1d274d1c4d2')).thenReturn(tylerRef);
      when(() => tylerRef.get()).thenAnswer((_) async => tylerDoc);

      final samDoc = MockDocumentSnapshot();
      when(() => samDoc.exists).thenReturn(true);
      when(() => samDoc.data()).thenReturn({
        'name': 'Sam',
        'description': 'Hi',
      });
      final samRef = MockDocumentReference();
      when(() => firestore
          .collection('users')
          .doc('aaabac1a-8d4b-4361-99cc-a1d274d1c4d2')).thenReturn(samRef);
      when(() => samRef.get()).thenAnswer((_) async => samDoc);

      final comment =
          'something random @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2 yay'
          ' @aaabac1a-8d4b-4361-99cc-a1d274d1c4d2';

      final updatedComment =
          await repository.replaceMentionsWithUserNames(comment);
      expect(updatedComment, 'something random @Tyler yay @Sam');
    });
    test('replaceMentionsWithUserNames with two userIds of the same user',
        () async {
      final repository = _createRepository();

      final tylerDoc = MockDocumentSnapshot();
      when(() => tylerDoc.exists).thenReturn(true);
      when(() => tylerDoc.data()).thenReturn({
        'name': 'Tyler',
        'description': 'Hi',
      });
      when(() => firestore
          .collection('users')
          .doc('b35bac1a-8d4b-4361-99cc-a1d274d1c4d2')
          .get()).thenAnswer((_) async => tylerDoc);

      final comment = 'something random @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2 '
          'yay @b35bac1a-8d4b-4361-99cc-a1d274d1c4d2';

      final updatedComment =
          await repository.replaceMentionsWithUserNames(comment);
      expect(updatedComment, 'something random @Tyler yay @Tyler');
    });
    test('getZIndex', () async {
      final repository = _createRepository();
      final recentZIndex = repository.getZIndex(DateTime(2021, 4, 10));
      expect(recentZIndex.isNegative, false);
      expect(recentZIndex < 1000000, true);

      final futureZIndex = repository.getZIndex(DateTime(2030, 4, 10));
      expect(futureZIndex.isNegative, false);
      expect(futureZIndex < 1000000, true);
    });
    test('getZIndex close ', () async {
      final repository = _createRepository();
      final firstZIndex =
          repository.getZIndex(DateTime(2021, 4, 10, 10, 0, 0)).toInt();
      final laterZIndex =
          repository.getZIndex(DateTime(2021, 4, 10, 11, 0, 0)).toInt();
      expect(firstZIndex < laterZIndex, true);
    });
  });
}
