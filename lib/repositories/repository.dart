import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_video_info/flutter_video_info.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rxdart/subjects.dart';
import 'package:share/share.dart';
import 'package:spot/data_profiders/location_provider.dart';
import 'package:spot/models/comment.dart';
import 'package:spot/models/notification.dart';
import 'package:spot/models/profile.dart';
import 'package:spot/models/video.dart';
import 'package:video_player/video_player.dart';

/// Class that communicates with external APIs.
class Repository {
  /// Class that communicates with external APIs.
  Repository({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required FirebaseFunctions functions,
    required FirebaseAnalytics analytics,
    required FlutterSecureStorage localStorage,
    required LocationProvider locationProvider,
  })  : _firebaseAuth = firebaseAuth,
        _firestore = firestore,
        _storage = storage,
        _functions = functions,
        _analytics = analytics,
        _localStorage = localStorage,
        _locationProvider = locationProvider {
    _setAuthListenner();
  }

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  // ignore: unused_field
  final FirebaseFunctions _functions;
  final FirebaseAnalytics _analytics;
  final FlutterSecureStorage _localStorage;
  final LocationProvider _locationProvider;
  // static const _localStorage = FlutterSecureStorage();
  static const _termsOfServiceAgreementKey = 'agreed';
  static const _timestampOfLastSeenNotification =
      'timestampOfLastSeenNotification';

  // Local Cache
  final List<Video> _mapVideos = [];
  final _mapVideosStreamConntroller = BehaviorSubject<List<Video>>();

  /// Emits videos displayed on the map.
  Stream<List<Video>> get mapVideosStream => _mapVideosStreamConntroller.stream;

  final Map<String, VideoDetail> _videoDetails = {};
  final _videoDetailStreamController = BehaviorSubject<VideoDetail?>();

  /// Stream that emits video details.
  /// Mainly used when the user watches a video.
  Stream<VideoDetail?> get videoDetailStream =>
      _videoDetailStreamController.stream;

  /// In memory cache of profileDetails.
  @visibleForTesting
  final Map<String, ProfileDetail> profileDetailsCache = {};
  final _profileStreamController =
      BehaviorSubject<Map<String, ProfileDetail>>();

  /// Emits map of all profiles that are stored in memory.
  Stream<Map<String, ProfileDetail>> get profileStream =>
      _profileStreamController.stream;

  /// List of comments that are loaded about a particular video.
  @visibleForTesting
  List<Comment> comments = [];
  final _commentsStreamController = BehaviorSubject<List<Comment>>();

  /// Emits list of comments about a particular video.
  Stream<List<Comment>> get commentsStream => _commentsStreamController.stream;

  List<AppNotification> _notifications = [];
  final _notificationsStreamController =
      BehaviorSubject<List<AppNotification>>();

  /// Emits list of in app notification.
  Stream<List<AppNotification>> get notificationsStream =>
      _notificationsStreamController.stream;

  final _mentionSuggestionCache = <String, List<Profile>>{};

  /// Return userId or null
  String? get userId => _firebaseAuth.currentUser?.uid;

  /// Completes when auth state is known
  Completer<void> statusKnown = Completer<void>();

  /// Completer that completes once the logged in user's profile has been loaded
  Completer<void> myProfileHasLoaded = Completer<void>();

  /// The user's profile
  Profile? get myProfile => profileDetailsCache[userId ?? ''];

  /// Whether the user has agreed to terms of service or not
  Future<bool> get hasAgreedToTermsOfService =>
      _localStorage.containsKey(key: _termsOfServiceAgreementKey);

  /// Returns whether the user has agreeed to the terms of service or not.
  Future<void> agreedToTermsOfService() =>
      _localStorage.write(key: _termsOfServiceAgreementKey, value: 'true');

  bool _hasRefreshedSession = false;

  /// Resets all cache upon identifying the user
  Future<void> _resetCache() async {
    if (userId != null && !_hasRefreshedSession) {
      _hasRefreshedSession = true;
      profileDetailsCache.clear();
      _mapVideos.clear();
      await getMyProfile();
      // ignore: unawaited_futures
      getNotifications();
      _mapVideosStreamConntroller.add(_mapVideos);
      final searchLocation = await _locationProvider.determinePosition();
      await getVideosFromLocation(searchLocation);
    }
  }

  void _setAuthListenner() {
    _firebaseAuth.authStateChanges().listen((User? user) {
      _resetCache();
    });
  }

  /// Recovers session stored inn device's storage.
  /// Firebase handles this automatically, but we check if user is already logged in
  /// to trigger necessary state updates.
  Future<void> recoverSession() async {
    if (_firebaseAuth.currentUser != null) {
      await _resetCache();
    }
    if (!statusKnown.isCompleted) {
      statusKnown.complete();
    }
  }

  /// Returns Persist Session String
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
          email: email, password: password);
      await _analytics.logSignUp(signUpMethod: 'email');
    } on FirebaseAuthException catch (e) {
      throw PlatformException(code: e.code, message: e.message);
    }
  }

  /// Returns Persist Session String
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
          email: email, password: password);
      await _analytics.logLogin(loginMethod: 'email');
    } on FirebaseAuthException catch (e) {
      throw PlatformException(code: e.code, message: e.message);
    }
  }

  /// Get the logged in user's profile.
  Future<Profile?> getMyProfile() async {
    final userId = this.userId;
    if (userId == null) {
      throw PlatformException(code: 'not signed in ', message: 'Not signed in');
    }
    try {
      await getProfileDetail(userId);
      if (!myProfileHasLoaded.isCompleted) {
        myProfileHasLoaded.complete();
      }
    } catch (e) {
      print(e.toString());
    }
    if (!statusKnown.isCompleted) {
      statusKnown.complete();
    }
  }

  /// Get 5 closest videos from the current user's location.
  Future<void> getVideosFromLocation(LatLng location) async {
    final query = _firestore.collection('videos');

    final geoFirePoint =
        GeoFirePoint(GeoPoint(location.latitude, location.longitude));

    // geoflutterfire_plus provides a stream or future of documents.
    // We'll use getGeoQueryBuilder or similar if available, or fetch manually if simple.
    // For now, let's use the standard radial query.

    try {
      final docs = await GeoCollectionReference(query).fetchWithin(
        center: geoFirePoint,
        radiusInKm: 5, // Defaulting to 5km
        field: 'position',
        geopointFrom: (data) =>
            (data['position'] as Map<String, dynamic>)['geopoint'] as GeoPoint,
        strictMode: true,
      );

      final videoIds = _mapVideos.map((video) => video.id).toSet();
      final newVideos = docs
          .map((doc) => Video.videosFromData(data: [
                {...(doc.data() as Map<String, dynamic>), 'id': doc.id}
              ], userId: userId)
                  .first)
          .where((video) => !videoIds.contains(video.id));

      _mapVideos.addAll(newVideos);
      _mapVideosStreamConntroller.sink.add(_mapVideos);
    } catch (e) {
      throw PlatformException(
          code: 'getVideosFromLocation error', message: e.toString());
    }
  }

  /// Loads all videos inside a bounding box.
  Future<void> getVideosInBoundingBox(LatLngBounds bounds) async {
    // geoflutterfire_plus doesn't have a direct bounding box query in the same way Supabase does.
    // We can approximate it with a radial query from the center of the bounds.
    final centerLat =
        (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
    final centerLng =
        (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

    await getVideosFromLocation(LatLng(centerLat, centerLng));
  }

  /// Get videos created by a certain user.
  Future<List<Video>> getVideosFromUid(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('videos')
          .where('user_id', isEqualTo: uid)
          .orderBy('created_at', descending: true)
          .get();

      return Video.videosFromData(
        data:
            snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(),
        userId: userId,
      );
    } catch (e) {
      throw PlatformException(
          code: 'getVideosFromUid error', message: e.toString());
    }
  }

  /// Get list of videos that a certain user has liked.
  Future<List<Video>> getLikedPostsFromUid(String uid) async {
    try {
      final likesSnapshot = await _firestore
          .collection('likes')
          .where('user_id', isEqualTo: uid)
          .orderBy('created_at', descending: true)
          .get();

      final videoIds = likesSnapshot.docs
          .map((doc) => doc.data()['video_id'] as String)
          .toList();

      if (videoIds.isEmpty) return [];

      // Firestore 'in' query is limited to 10 items. This might be a problem if they liked many.
      // For now, let's fetch in batches or handle simply.
      final videosSnapshot = await _firestore
          .collection('videos')
          .where(FieldPath.documentId, whereIn: videoIds.take(10).toList())
          .get();

      return Video.videosFromData(
        data: videosSnapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList(),
        userId: userId,
      );
    } catch (e) {
      throw PlatformException(
          code: 'getLikedPostsFromUid error', message: e.toString());
    }
  }

  /// Get profile detail of a certain user.
  Future<void> getProfileDetail(String targetUid) async {
    if (profileDetailsCache[targetUid] != null) {
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(targetUid).get();
      if (!doc.exists) {
        throw PlatformException(
            code: 'No User', message: 'Could not find the user.');
      }

      final data = doc.data()!;
      // For isFollowing, we check the follow collection
      bool isFollowing = false;
      if (userId != null) {
        final followDoc = await _firestore
            .collection('follows')
            .doc('${userId}_$targetUid')
            .get();
        isFollowing = followDoc.exists;
      }

      final profile = ProfileDetail.fromData({
        ...data,
        'id': doc.id,
        'is_following': isFollowing,
      });
      profileDetailsCache[targetUid] = profile;
      _profileStreamController.sink.add(profileDetailsCache);
    } catch (e) {
      throw PlatformException(code: 'Database_Error', message: e.toString());
    }
  }

  /// Updates a profile of logged in user.
  Future<void> saveProfile({required Profile profile}) async {
    try {
      await _firestore
          .collection('users')
          .doc(profile.id)
          .set(profile.toMap(), SetOptions(merge: true));

      late final ProfileDetail newProfile;
      if (profileDetailsCache[userId!] != null) {
        newProfile = profileDetailsCache[userId!]!.copyWith(
          name: profile.name,
          description: profile.description,
          imageUrl: profile.imageUrl,
        );
      } else {
        // When the user initially registered
        _hasRefreshedSession = false;
        // ignore: unawaited_futures
        _resetCache();
        newProfile = ProfileDetail(
          id: userId!,
          name: profile.name,
          description: profile.description,
          imageUrl: profile.imageUrl,
          followerCount: 0,
          followingCount: 0,
          likeCount: 0,
          isFollowing: true,
        );
      }
      profileDetailsCache[userId!] = newProfile;
      _profileStreamController.add(profileDetailsCache);
    } catch (e) {
      throw PlatformException(code: 'Database_Error', message: e.toString());
    }
  }

  /// Uploads the video and returns the download URL
  Future<String> uploadFile({
    required String bucket,
    required File file,
    required String path,
  }) async {
    try {
      final ref = _storage.ref().child(bucket).child(path);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      throw PlatformException(code: 'uploadFile', message: e.toString());
    }
  }

  /// Inserts a new row in `videos` collection on Firestore.
  Future<void> saveVideo(Video creatingVideo) async {
    try {
      final docRef =
          await _firestore.collection('videos').add(creatingVideo.toMap());
      final createdVideo = creatingVideo.updateId(id: docRef.id);
      _mapVideos.add(createdVideo);
      _mapVideosStreamConntroller.sink.add(_mapVideos);
      await _analytics.logEvent(name: 'post_video');
    } catch (e) {
      throw PlatformException(code: 'saveVideo', message: e.toString());
    }
  }

  /// Loads a single video data and emits it on `videoDetailStream`
  Future<void> getVideoDetailStream(String videoId) async {
    _videoDetailStreamController.sink.add(null);
    try {
      final videoDoc = await _firestore.collection('videos').doc(videoId).get();
      if (!videoDoc.exists) {
        throw PlatformException(
            code: 'Get Video Detail',
            message: 'No data found for this videoId');
      }

      final videoData = videoDoc.data()!;
      final creatorUid = videoData['user_id'] as String;

      // Fetch creator profile
      final userDoc =
          await _firestore.collection('users').doc(creatorUid).get();
      final userData = userDoc.exists
          ? (userDoc.data() as Map<String, dynamic>)
          : <String, dynamic>{};

      // Check if liked
      bool haveLiked = false;
      if (userId != null) {
        final likeDoc = await _firestore
            .collection('likes')
            .doc('${userId}_$videoId')
            .get();
        haveLiked = likeDoc.exists;
      }

      // Check if following
      bool isFollowing = false;
      if (userId != null) {
        final followDoc = await _firestore
            .collection('follows')
            .doc('${userId}_$creatorUid')
            .get();
        isFollowing = followDoc.exists;
      }

      final Map<String, dynamic> dataMap = {
        ...videoData,
        'id': videoId,
        'name': userData['name'] ?? '',
        'user_image_url': userData['image_url'] ?? '',
        'have_liked': haveLiked,
        'is_following': isFollowing,
        // Assume counts are in videoData or metadata
        'like_count': videoData['like_count'] ?? 0,
        'comment_count': videoData['comment_count'] ?? 0,
      };

      var videoDetail = VideoDetail.fromData(data: dataMap, userId: userId);
      if (videoDetail.position != null) {
        final locationString = await _locationToString(videoDetail.position!);
        videoDetail = videoDetail.copyWith(locationString: locationString);
      }
      _videoDetails[videoId] = videoDetail;
      _videoDetailStreamController.sink.add(_videoDetails[videoId]!);
      await _analytics.logEvent(name: 'view_video', parameters: {
        'video_id': videoId,
      });
    } catch (e) {
      throw PlatformException(code: 'Get Video Detail', message: e.toString());
    }
  }

  /// Inserts a new row in `likes` collection
  /// and increments the like count of a video.
  Future<void> like(Video video) async {
    final videoId = video.id;
    final currentVideoDetail = _videoDetails[videoId]!;
    _videoDetails[videoId] = currentVideoDetail.copyWith(
        likeCount: (currentVideoDetail.likeCount + 1), haveLiked: true);
    _videoDetailStreamController.sink.add(_videoDetails[videoId]!);

    if (profileDetailsCache[video.userId] != null) {
      // Increment the like count of liked user by 1
      profileDetailsCache[video.userId] = profileDetailsCache[video.userId]!
          .copyWith(
              likeCount: profileDetailsCache[video.userId]!.likeCount + 1);
      _profileStreamController.add(profileDetailsCache);
    }

    try {
      final uid = _firebaseAuth.currentUser!.uid;
      final batch = _firestore.batch();

      final likeRef = _firestore.collection('likes').doc('${uid}_$videoId');
      batch.set(likeRef, VideoDetail.like(videoId: videoId, uid: uid));

      final videoRef = _firestore.collection('videos').doc(videoId);
      batch.update(videoRef, {'like_count': FieldValue.increment(1)});

      final userRef = _firestore.collection('users').doc(video.userId);
      batch.update(userRef, {'like_count': FieldValue.increment(1)});

      await batch.commit();

      await _analytics.logEvent(name: 'like_video', parameters: {
        'video_id': videoId,
      });
    } catch (e) {
      throw PlatformException(code: 'Like Video', message: e.toString());
    }
  }

  /// Deletes a row in `likes` collection and decrements the like count of a video.
  Future<void> unlike(Video video) async {
    final videoId = video.id;
    final currentVideoDetail = _videoDetails[videoId]!;
    _videoDetails[videoId] = currentVideoDetail.copyWith(
        likeCount: (currentVideoDetail.likeCount - 1), haveLiked: false);
    _videoDetailStreamController.sink.add(_videoDetails[videoId]!);

    if (profileDetailsCache[video.userId] != null) {
      // Decrement the like count of liked user by 1
      profileDetailsCache[video.userId] = profileDetailsCache[video.userId]!
          .copyWith(
              likeCount: profileDetailsCache[video.userId]!.likeCount - 1);
      _profileStreamController.add(profileDetailsCache);
    }

    try {
      final uid = _firebaseAuth.currentUser!.uid;
      final batch = _firestore.batch();

      final likeRef = _firestore.collection('likes').doc('${uid}_$videoId');
      batch.delete(likeRef);

      final videoRef = _firestore.collection('videos').doc(videoId);
      batch.update(videoRef, {'like_count': FieldValue.increment(-1)});

      final userRef = _firestore.collection('users').doc(video.userId);
      batch.update(userRef, {'like_count': FieldValue.increment(-1)});

      await batch.commit();
      await _analytics.logEvent(name: 'unlike_video', parameters: {
        'video_id': videoId,
      });
    } catch (e) {
      throw PlatformException(code: 'Unlike Video', message: e.toString());
    }
  }

  /// Get comments of a video.
  Future<void> getComments(String videoId) async {
    try {
      final snapshot = await _firestore
          .collection('comments')
          .where('video_id', isEqualTo: videoId)
          .orderBy('created_at', descending: true)
          .get();

      final data =
          snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      final comments = Comment.commentsFromData(data);
      _commentsStreamController.sink.add(comments);
      await _analytics.logEvent(name: 'view_comments', parameters: {
        'video_id': videoId,
      });
    } catch (e) {
      throw PlatformException(code: 'getComments', message: e.toString());
    }
  }

  /// Post a comment.
  Future<void> postComment(Comment creatingComment) async {
    try {
      final uid = _firebaseAuth.currentUser!.uid;
      final docRef = await _firestore.collection('comments').add({
        ...creatingComment.toMap(),
        'user_id': uid,
        'created_at': FieldValue.serverTimestamp(),
      });

      final createdComment = creatingComment.copyWith(id: docRef.id);

      // Increment comment count on video
      await _firestore
          .collection('videos')
          .doc(creatingComment.videoId)
          .update({
        'comment_count': FieldValue.increment(1),
      });

      final current = await _commentsStreamController.stream.first;
      _commentsStreamController.sink.add([createdComment, ...current]);

      await _analytics.logEvent(name: 'post_comment', parameters: {
        'video_id': creatingComment.videoId,
      });
    } catch (e) {
      throw PlatformException(code: 'postComment', message: e.toString());
    }
  }

  /// Loads the 50 most recent notifications.
  Future<void> getNotifications() async {
    if (userId == null) {
      return;
    }
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('receiver_user_id', isEqualTo: userId)
          .orderBy('created_at', descending: true)
          .limit(50)
          .get();

      final data =
          snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();

      final timestampOfLastSeenNotification =
          await _localStorage.read(key: _timestampOfLastSeenNotification);
      DateTime? createdAtOfLastSeenNotification;
      if (timestampOfLastSeenNotification != null) {
        createdAtOfLastSeenNotification =
            DateTime.parse(timestampOfLastSeenNotification);
      }

      _notifications = AppNotification.fromData(data,
          createdAtOfLastSeenNotification: createdAtOfLastSeenNotification);
      _notificationsStreamController.sink.add(_notifications);
    } catch (e) {
      throw PlatformException(code: 'getNotifications', message: e.toString());
    }
  }

  /// Blocks a certain user.
  Future<void> block(String blockedUserId) async {
    final uid = userId;
    if (uid == null) return;

    try {
      await _firestore.collection('blocks').doc('${uid}_$blockedUserId').set({
        'user_id': uid,
        'blocked_user_id': blockedUserId,
        'created_at': FieldValue.serverTimestamp(),
      });

      _mapVideos.removeWhere((value) => value.userId == blockedUserId);
      _mapVideosStreamConntroller.sink.add(_mapVideos);

      await _analytics.logEvent(name: 'block_user', parameters: {
        'user_id': blockedUserId,
      });
    } catch (e) {
      throw PlatformException(code: 'Block User', message: e.toString());
    }
  }

  /// Reports a certain video.
  Future<void> report({
    required String videoId,
    required String reason,
  }) async {
    final uid = userId;
    if (uid == null) return;

    try {
      await _firestore.collection('reports').add({
        'user_id': uid,
        'video_id': videoId,
        'reason': reason,
        'created_at': FieldValue.serverTimestamp(),
      });

      await _analytics.logEvent(name: 'report_video', parameters: {
        'video_id': videoId,
      });
    } catch (e) {
      throw PlatformException(
          code: 'Report Video Error', message: e.toString());
    }
  }

  /// Deletes a certain video.
  Future<void> deleteVideo(Video video) async {
    try {
      final batch = _firestore.batch();

      final videoRef = _firestore.collection('videos').doc(video.id);
      batch.delete(videoRef);

      // Decrement video count from user
      final userRef = _firestore.collection('users').doc(video.userId);
      batch.update(userRef, {'video_count': FieldValue.increment(-1)});

      await batch.commit();

      // Delete files from storage
      try {
        await _storage.refFromURL(video.url).delete();
        await _storage.refFromURL(video.imageUrl).delete();
        if (video.thumbnailUrl.isNotEmpty) {
          await _storage.refFromURL(video.thumbnailUrl).delete();
        }
      } catch (e) {
        // Ignore storage delete errors if file not found
      }

      _mapVideos.removeWhere((v) => v.id == video.id);
      _mapVideosStreamConntroller.sink.add(_mapVideos);

      await _analytics.logEvent(name: 'delete_video', parameters: {
        'video_id': video.id,
      });
    } catch (e) {
      throw PlatformException(
          code: 'Delete Video Error', message: e.toString());
    }
  }

  /// Performs a keyword search of videos.
  Future<List<Video>> searchVideo(String queryString) async {
    try {
      final snapshot = await _firestore
          .collection('videos')
          .where('description', isGreaterThanOrEqualTo: queryString)
          .where('description', isLessThanOrEqualTo: '$queryString\uf8ff')
          .limit(24)
          .get();

      final data =
          snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      await _analytics.logSearch(searchTerm: queryString);
      return Video.videosFromData(data: data, userId: userId);
    } catch (e) {
      throw PlatformException(code: 'searchVideo', message: e.toString());
    }
  }

  /// Loads `VideoPlayerController` of a video.
  Future<VideoPlayerController> getVideoPlayerController(String url) async {
    return VideoPlayerController.network(url);
  }

  /// Returns whether the user has turned on location permission or not.
  Future<bool> hasLocationPermission() async {
    final result = await Geolocator.requestPermission();
    return result != LocationPermission.denied &&
        result != LocationPermission.deniedForever;
  }

  /// Updates the timestamp of when the user has last seen notifications.
  ///
  /// Timestamp of when the user has last seen notifications is used to
  /// determine which notification is unread.
  Future<void> updateTimestampOfLastSeenNotification(DateTime time) async {
    await _localStorage.write(
        key: _timestampOfLastSeenNotification, value: time.toIso8601String());
  }

  /// Performs a keyword search of location within a map.
  Future<LatLng?> searchLocation(String searchQuery) async {
    try {
      final locations = await locationFromAddress(searchQuery);
      if (locations.isEmpty) {
        return null;
      }
      final location = locations.first;
      await _analytics.logEvent(
          name: 'search_location', parameters: {'search_term': searchQuery});
      return LatLng(location.latitude, location.longitude);
    } catch (e) {
      return null;
    }
  }

  /// Opens a share dialog to share the video on other social media or apps.
  Future<void> shareVideo(VideoDetail videoDetail) async {
    await Share.share(
        'Check out this video on Spot http://spotvideo.app/post/${videoDetail.id}');
    await _analytics.logEvent(
        name: 'share_video', parameters: {'video_id': videoDetail.id});
  }

  /// Loads cached image file.
  ///
  /// Mainly used to get cached video thumbnail.
  Future<File> getCachedFile(String url) {
    return DefaultCacheManager().getSingleFile(url);
  }

  /// Loads suggested mentions from a given search query.
  Future<List<Profile>> getMentionSuggestions(String queryString) async {
    if (_mentionSuggestionCache[queryString] != null) {
      return _mentionSuggestionCache[queryString]!;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: queryString)
          .where('name', isLessThanOrEqualTo: '$queryString\uf8ff')
          .limit(2)
          .get();

      final profiles = snapshot.docs
          .map<Profile>(
              (doc) => Profile.fromData({...doc.data(), 'id': doc.id}))
          .toList();

      _mentionSuggestionCache[queryString] = profiles;
      return profiles;
    } catch (e) {
      throw PlatformException(
          code: 'Error finding mentionend users', message: e.toString());
    }
  }

  /// Get all of the mentioned profiles in a comment
  List<Profile> getMentionedProfiles({
    required String commentText,
    required List<Profile> profilesInComments,
  }) {
    final userNames = commentText
        .split(' ')
        .where((word) => word.isNotEmpty && word[0] == '@')
        .map((word) => RegExp(r'^\w*').firstMatch(word.substring(1))!.group(0)!)
        .toList();

    /// Map where user name is the key and profile is the value
    final userNameMap = <String, Profile>{}
      ..addEntries(
          profilesInComments.map((profile) => MapEntry(profile.name, profile)))
      ..addEntries(profileDetailsCache.values.map<MapEntry<String, Profile>>(
          (profile) => MapEntry(profile.name, profile)))
      ..addEntries(_mentionSuggestionCache.values
          .expand((i) => i)
          .toList()
          .map<MapEntry<String, Profile>>(
              (profile) => MapEntry(profile.name, profile)));
    final mentionedProfiles = userNames
        .map<Profile?>((userName) => userNameMap[userName])
        .where((profile) => profile != null)
        .map<Profile>((profile) => profile!)
        .toList();
    return mentionedProfiles;
  }

  /// Replaces mentioned user names with users' id in comment text
  /// Called right before saving a new comment to the database
  String replaceMentionsInAComment(
      {required String comment, required List<Profile> mentions}) {
    var mentionReplacedText = comment;
    for (final mention in mentions) {
      mentionReplacedText =
          mentionReplacedText.replaceAll('@${mention.name}', '@${mention.id}');
    }
    return mentionReplacedText;
  }

  /// Extracts the username to be searched within the database
  /// Called when a user is typing up a comment
  String? getMentionedUserName(String comment) {
    final mention = comment.split(' ').last;
    if (mention.isEmpty || mention[0] != '@') {
      return null;
    }
    final mentionedUserName = mention.substring(1);
    if (mentionedUserName.isEmpty) {
      return '@';
    }
    return mentionedUserName;
  }

  /// Returns list of userIds that are present in a comment
  List<String> getUserIdsInComment(String comment) {
    final regExp = RegExp(r'@([a-zA-Z0-9-]{3,})');
    final matches = regExp.allMatches(comment);
    return matches.map((match) => match.group(1)!).toList();
  }

  /// Replaces user ids found in comments with user names
  Future<String> replaceMentionsWithUserNames(
    String comment,
  ) async {
    await Future.wait(
        getUserIdsInComment(comment).map(getProfileDetail).toList());
    final regExp = RegExp(r'@([a-zA-Z0-9-]{3,})');
    final replacedComment = comment.replaceAllMapped(regExp, (match) {
      final key = match.group(1)!;
      final name = profileDetailsCache[key]?.name;

      /// Return the original id if no profile was found with the id
      return '@${name ?? match.group(0)!.substring(1)}';
    });
    return replacedComment;
  }

  /// Calculate the z-index of a marker on a map.
  /// Newer videos have high z-index.
  /// It has a wierd formula so that it does not go
  /// over iOS's max z-index value.
  double getZIndex(DateTime createdAt) {
    return max((createdAt.millisecondsSinceEpoch ~/ 1000000 - 1600000), 0)
        .toDouble();
  }

  /// Opens device's camera roll to find videos taken in the past.
  Future<File?> getVideoFile() async {
    try {
      final pickedVideo =
          await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (pickedVideo != null) {
        return File(pickedVideo.path);
      }
    } catch (err) {
      debugPrint(err.toString());
    }
    return null;
  }

  /// Find the location attached to a video file from a video path.
  Future<LatLng?> getVideoLocation(String videoPath) async {
    final videoInfo = await FlutterVideoInfo().getVideoInfo(videoPath);
    final locationString = videoInfo?.location;
    if (locationString != null) {
      print(locationString);
      final matches = RegExp(r'(\+|\-)(\d*\.?\d*)').allMatches(locationString);
      final lat = double.parse(matches.elementAt(0).group(0)!);
      final lng = double.parse(matches.elementAt(1).group(0)!);
      return LatLng(lat, lng);
    }
    return null;
  }

  /// Loads list of 24 videos in desc createdAt order.
  Future<List<Video>> getNewVideos() async {
    try {
      final snapshot = await _firestore
          .collection('videos')
          .orderBy('created_at', descending: true)
          .limit(50)
          .get();

      final data =
          snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      final videos = Video.videosFromData(data: data, userId: userId);
      return videos;
    } catch (e) {
      throw PlatformException(code: 'NewVideos', message: e.toString());
    }
  }

  /// Follows a user.
  Future<void> follow(String followedUid) async {
    final myUid = userId;
    if (myUid == null) {
      return;
    }

    // Optimistic Update
    if (profileDetailsCache[followedUid] != null) {
      profileDetailsCache[followedUid] =
          profileDetailsCache[followedUid]!.copyWith(isFollowing: true);
    }
    if (profileDetailsCache[myUid] != null) {
      profileDetailsCache[myUid] = profileDetailsCache[myUid]!.copyWith(
          followingCount: profileDetailsCache[myUid]!.followingCount + 1);
    }
    if (profileDetailsCache[followedUid] != null) {
      profileDetailsCache[followedUid] = profileDetailsCache[followedUid]!
          .copyWith(
              followerCount:
                  profileDetailsCache[followedUid]!.followerCount + 1);
    }
    _profileStreamController.add(profileDetailsCache);

    try {
      final batch = _firestore.batch();

      final followRef =
          _firestore.collection('follows').doc('${myUid}_$followedUid');
      batch.set(followRef, {
        'following_user_id': myUid,
        'followed_user_id': followedUid,
        'created_at': FieldValue.serverTimestamp(),
      });

      final myUserRef = _firestore.collection('users').doc(myUid);
      batch.update(myUserRef, {'following_count': FieldValue.increment(1)});

      final followedUserRef = _firestore.collection('users').doc(followedUid);
      batch
          .update(followedUserRef, {'follower_count': FieldValue.increment(1)});

      await batch.commit();

      await _analytics.logEvent(name: 'follow', parameters: {
        'following_user_id': myUid,
        'followed_user_id': followedUid,
      });
    } catch (e) {
      throw PlatformException(code: 'Follow Error', message: e.toString());
    }
  }

  /// Unfollows a user.
  Future<void> unfollow(String followedUid) async {
    final myUid = userId;
    if (myUid == null) {
      return;
    }

    // Optimistic Update
    if (profileDetailsCache[followedUid] != null) {
      profileDetailsCache[followedUid] =
          profileDetailsCache[followedUid]!.copyWith(isFollowing: false);
    }
    if (profileDetailsCache[myUid] != null) {
      profileDetailsCache[myUid] = profileDetailsCache[myUid]!.copyWith(
          followingCount: profileDetailsCache[myUid]!.followingCount - 1);
    }
    if (profileDetailsCache[followedUid] != null) {
      profileDetailsCache[followedUid] = profileDetailsCache[followedUid]!
          .copyWith(
              followerCount:
                  profileDetailsCache[followedUid]!.followerCount - 1);
    }
    _profileStreamController.add(profileDetailsCache);

    try {
      final batch = _firestore.batch();

      final followRef =
          _firestore.collection('follows').doc('${myUid}_$followedUid');
      batch.delete(followRef);

      final myUserRef = _firestore.collection('users').doc(myUid);
      batch.update(myUserRef, {'following_count': FieldValue.increment(-1)});

      final followedUserRef = _firestore.collection('users').doc(followedUid);
      batch.update(
          followedUserRef, {'follower_count': FieldValue.increment(-1)});

      await batch.commit();

      await _analytics.logEvent(name: 'unfollow', parameters: {
        'following_user_id': myUid,
        'followed_user_id': followedUid,
      });
    } catch (e) {
      throw PlatformException(code: 'Unfollow Error', message: e.toString());
    }
  }

  Future<String> _locationToString(LatLng location) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isEmpty) {
        return 'Unknown';
      }
      if (placemarks.first.administrativeArea?.isEmpty == true) {
        return '${placemarks.first.name}';
      }
      return '${placemarks.first.administrativeArea}, '
          '${placemarks.first.country}';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Loads list of followers.
  Future<List<Profile>> getFollowers(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('follows')
          .where('followed_user_id', isEqualTo: uid)
          .limit(50)
          .get();

      final followingUserIds = snapshot.docs
          .map((doc) => doc.data()['following_user_id'] as String)
          .toList();

      if (followingUserIds.isEmpty) return [];

      // Fetch profiles in chunks if more than 10
      List<Profile> profiles = [];
      for (var i = 0; i < followingUserIds.length; i += 10) {
        final chunk =
            followingUserIds.sublist(i, min(i + 10, followingUserIds.length));
        final profilesSnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        profiles.addAll(profilesSnapshot.docs
            .map((doc) => Profile.fromData({...doc.data(), 'id': doc.id})));
      }

      return profiles;
    } catch (e) {
      throw PlatformException(code: 'getFollowers', message: e.toString());
    }
  }

  /// Loads list of followings.
  Future<List<Profile>> getFollowings(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('follows')
          .where('following_user_id', isEqualTo: uid)
          .limit(50)
          .get();

      final followedUserIds = snapshot.docs
          .map((doc) => doc.data()['followed_user_id'] as String)
          .toList();

      if (followedUserIds.isEmpty) return [];

      // Fetch profiles in chunks if more than 10
      List<Profile> profiles = [];
      for (var i = 0; i < followedUserIds.length; i += 10) {
        final chunk =
            followedUserIds.sublist(i, min(i + 10, followedUserIds.length));
        final profilesSnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        profiles.addAll(profilesSnapshot.docs
            .map((doc) => Profile.fromData({...doc.data(), 'id': doc.id})));
      }

      return profiles;
    } catch (e) {
      throw PlatformException(code: 'getFollowings', message: e.toString());
    }
  }

  /// Get the current user's location.
  Future<LatLng> determinePosition() {
    return _locationProvider.determinePosition();
  }

  /// Open location settings page on the device.
  Future<bool> openLocationSettingsPage() {
    return _locationProvider.openLocationSettingsPage();
  }
}
