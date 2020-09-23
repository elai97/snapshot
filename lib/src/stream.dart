import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:snapshot/snapshot.dart';

extension StreamX on Stream<dynamic> {
  /// Transforms this stream to a stream of [Snapshot]s with the specified
  /// [decoder].
  ///
  /// The emitted snapshots share their cache for content parts that did not
  /// change. Only distinct snapshots are emitted.
  Stream<Snapshot> toSnapshots({SnapshotDecoder decoder}) {
    var s = Snapshot.empty(decoder: decoder);
    return map((v) => s = s.set(v)).distinct();
  }
}

extension SnapshotStreamX on Stream<Snapshot> {
  /// Takes the (grand)child defined by [path] of each Snapshot in this stream.
  ///
  /// Only distinct values are emitted.
  ///
  /// When this stream implements [EfficientChild.child], this implementation
  /// will be used instead of the default one. With [EfficientChild], a new
  /// stream can be created that does not require the original stream to be
  /// listened to.
  Stream<Snapshot> child(String path) {
    if (this is EfficientChild) {
      return (this as EfficientChild).child(path)?.distinct();
    }

    return map((s) => s.child(path)).distinct();
  }

  /// Returns a stream where each snapshot is converted to an object of type T.
  Stream<T> as<T>({String format}) => map((s) => s.as<T>(format: format));

  /// Returns a stream where each snapshot is converted to a list of objects of
  /// type T.
  Stream<List<T>> asList<T>({String format}) =>
      map((s) => s.asList<T>(format: format));

  /// Returns a stream where each snapshot is converted to a map with values of
  /// type T.
  Stream<Map<String, T>> asMap<T>({String format}) =>
      map((s) => s.asMap<T>(format: format));

  /// Updates the content at [path] for each snapshot in this stream.
  Stream<Snapshot> setPath(String path, dynamic value) =>
      map((s) => s.setPath(path, value));

  /// Updates the content at [path] for each snapshot in this stream
  /// asynchronously with the values from [childStream]
  Stream<Snapshot> asyncSetPath(String path, Stream<dynamic> childStream) {
    // withLatestFrom could also be used, but handles first and second stream
    // differently
    return CombineLatestStream([this, childStream], (l) {
      var t = l[0] as Snapshot;
      var s = l[1];
      return t.setPath(path, s);
    });
  }

  /// Updates the content at [path] for each snapshot in this stream
  /// asynchronously with the values from the stream returned by the [mapper]
  /// callback.
  ///
  /// The callback is called with the snapshot value of the original child at
  /// [path] whenever this child changes.
  Stream<Snapshot> switchPath(
      String path, Stream<dynamic> Function(Snapshot snapshot) mapper) {
    var controller = StreamController<Snapshot>(sync: true);
    var stream = doOnDone(() {
      controller.close();
    });
    return stream.map((v) {
      controller.add(v);
      return v;
    }).asyncSetPath(path,
        controller.stream.child(path).switchMap((value) => mapper(value)));
  }

  /// Updates the content of each child with the value returned by [mapper]
  Stream<Snapshot> mapChildren(
          dynamic Function(String key, Snapshot value) mapper) =>
      map((s) {
        var keys = s.as<Map<String, dynamic>>().keys;
        return keys.fold(s, (s, k) => s.setPath(k, mapper(k, s.child(k))));
      });

  Stream<Snapshot> mapPath(
          String path, dynamic Function(Snapshot value) mapper) =>
      map((s) {
        return s.setPath(path, mapper(s.child(path)));
      });

  /// Updates the content of each child with the values of the stream returned
  /// by [mapper]
  Stream<Snapshot> switchChildren(
          Stream<dynamic> Function(String key, Snapshot value) mapper) =>
      switchMap((s) {
        var keys = s.as<Map<String, dynamic>>().keys;
        return CombineLatestStream(
            keys.map((k) => mapper(k, s.child(k)).map((v) => MapEntry(k, v))),
            (List<MapEntry<String, dynamic>> l) {
          return l.fold(s, (s, e) => s.setPath(e.key, e.value));
        });
      });
}

mixin EfficientChild on Stream<Snapshot> {
  Stream<Snapshot> child(String path);
}
