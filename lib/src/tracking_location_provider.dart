import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myrun/src/tracking_session.dart';

abstract class TrackingLocationProvider {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<void> openLocationSettings();
  Future<void> openAppSettings();
  Stream<TrackingLocationSample> warmupSamples();
  Stream<TrackingLocationSample> runningSamples();
}

class GeolocatorTrackingLocationProvider implements TrackingLocationProvider {
  const GeolocatorTrackingLocationProvider();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Stream<TrackingLocationSample> runningSamples() {
    return Geolocator.getPositionStream(
      locationSettings: _runningLocationSettings(),
    ).map(_sampleFromPosition);
  }

  @override
  Stream<TrackingLocationSample> warmupSamples() {
    return Geolocator.getPositionStream(
      locationSettings: _warmupLocationSettings(),
    ).map(_sampleFromPosition);
  }

  LocationSettings _warmupLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  LocationSettings _runningLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'RunNow đang tracking',
          notificationText: 'Đang ghi lại route, distance và pace.',
          notificationChannelName: 'RunNow Tracking',
          enableWakeLock: true,
          setOngoing: true,
          color: Color(0xffff3b5f),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );
  }
}

TrackingLocationSample _sampleFromPosition(Position position) {
  return TrackingLocationSample(
    latitude: position.latitude,
    longitude: position.longitude,
    timestamp: position.timestamp,
    altitudeMeters: position.altitude,
    accuracyMeters: position.accuracy,
    speedMetersPerSecond: position.speed,
    headingDegrees: position.heading,
  );
}
