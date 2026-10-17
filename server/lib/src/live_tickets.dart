/// One-time tickets that open a live connection (`GET /v1/live?ticket=…`)
/// for clients that cannot send the bearer token on a WebSocket: browsers.
library;

import 'dart:math';

/// How long a ticket stays valid.
const defaultTicketLifetime = Duration(seconds: 30);

/// Issues and redeems tickets: random, single-use and short-lived, so one
/// that ends up in a log is worthless (unlike the long-lived token, which
/// never goes into a URL).
class LiveTickets {
  LiveTickets({this.lifetime = defaultTicketLifetime, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// How long a ticket is valid after it was issued.
  final Duration lifetime;

  final DateTime Function() _now;
  final Map<String, DateTime> _expiry = {};
  final _random = Random.secure();

  /// Tickets beyond this many outstanding drop the oldest.
  static const maxOutstanding = 1000;

  /// A new ticket.
  String issue() {
    _dropExpired();
    while (_expiry.length >= maxOutstanding) {
      _expiry.remove(_expiry.keys.first);
    }
    final ticket = [
      for (var i = 0; i < 24; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    _expiry[ticket] = _now().add(lifetime);
    return ticket;
  }

  /// Whether [ticket] is valid; it is used up either way.
  bool redeem(String ticket) {
    final expiry = _expiry.remove(ticket);
    return expiry != null && _now().isBefore(expiry);
  }

  void _dropExpired() {
    final now = _now();
    _expiry.removeWhere((_, expiry) => !now.isBefore(expiry));
  }
}
