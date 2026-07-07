import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/services/typing_service.dart';

void main() {
  // TypingService is a singleton whose stream controllers cannot be reopened
  // after dispose(), so tests share one instance and use distinct sender ids.
  final service = TypingService.instance;

  test('emits typing-started for an incoming typing indicator', () async {
    final started = <String>[];
    final sub = service.onTypingStarted.listen(started.add);

    service.handleTypingIndicator(Message.createTypingIndicator(
      senderId: 'peer-a',
      receiverId: 'me',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(started, contains('peer-a'));
    expect(service.isPeerTyping('peer-a'), isTrue);

    await sub.cancel();
    service.clearTyping('peer-a');
  });

  test('ignores non-typing messages', () {
    service.handleTypingIndicator(Message.createTextMessage(
      senderId: 'peer-b',
      receiverId: 'me',
      text: 'hello',
    ));
    expect(service.isPeerTyping('peer-b'), isFalse);
  });

  test('clearTyping stops immediately and emits stopped', () async {
    final stopped = <String>[];
    final sub = service.onTypingStopped.listen(stopped.add);

    service.handleTypingIndicator(Message.createTypingIndicator(
      senderId: 'peer-c',
      receiverId: 'me',
    ));
    service.clearTyping('peer-c');
    await Future<void>.delayed(Duration.zero);

    expect(stopped, contains('peer-c'));
    expect(service.isPeerTyping('peer-c'), isFalse);

    await sub.cancel();
  });

  test('auto-clears after the typing timeout', () {
    fakeAsync((async) {
      final stopped = <String>[];
      final sub = service.onTypingStopped.listen(stopped.add);

      service.handleTypingIndicator(Message.createTypingIndicator(
        senderId: 'peer-d',
        receiverId: 'me',
      ));
      expect(service.isPeerTyping('peer-d'), isTrue);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      expect(stopped, contains('peer-d'));
      expect(service.isPeerTyping('peer-d'), isFalse);

      sub.cancel();
    });
  });

  test('a fresh indicator resets the auto-clear timer', () {
    fakeAsync((async) {
      final stopped = <String>[];
      final sub = service.onTypingStopped.listen(stopped.add);

      service.handleTypingIndicator(Message.createTypingIndicator(
        senderId: 'peer-e',
        receiverId: 'me',
      ));
      async.elapse(const Duration(seconds: 3));
      // Second indicator before the 4s timeout should keep it alive.
      service.handleTypingIndicator(Message.createTypingIndicator(
        senderId: 'peer-e',
        receiverId: 'me',
      ));
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      // 6s total elapsed, but only 3s since the last indicator: still typing.
      expect(service.isPeerTyping('peer-e'), isTrue);
      expect(stopped, isNot(contains('peer-e')));

      service.clearTyping('peer-e');
      sub.cancel();
    });
  });
}
