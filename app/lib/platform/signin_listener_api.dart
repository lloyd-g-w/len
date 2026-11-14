/// A listener of Len for the sign-in page's redirect (signin_listener.dart).
abstract interface class SigninListener {
  /// The port the page redirects to.
  int get port;

  /// The URLs of the redirects that arrived.
  Stream<String> get callbacks;

  Future<void> close();
}
