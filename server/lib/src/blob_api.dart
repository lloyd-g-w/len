/// HTTP routes for content-addressed blobs (`/v1/blobs/<sha256>`).
library;

import 'dart:convert';
import 'dart:io' show HttpStatus;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'blob_store.dart';

/// Default maximum blob size in bytes (200 MiB).
const defaultMaxBlobBytes = 200 * 1024 * 1024;

/// Registers the blob routes on [router]. Auth is applied by the caller.
void addBlobRoutes(Router router, BlobStore blobs, {required int maxBytes}) {
  // HEAD must be registered before GET: shelf_router's implicit HEAD for GET
  // routes would replace Content-Length with 0.
  router
    ..head('/v1/blobs/<sha>', (Request r, String sha) => _get(blobs, sha, withBody: false))
    ..get('/v1/blobs/<sha>', (Request r, String sha) => _get(blobs, sha, withBody: true))
    ..put('/v1/blobs/<sha>', (Request r, String sha) => _put(r, blobs, sha, maxBytes));
}

Response _get(BlobStore blobs, String sha, {required bool withBody}) {
  if (!BlobStore.isValidSha(sha)) return _invalidSha();
  final size = blobs.size(sha);
  if (size == null) {
    return withBody
        ? _json(HttpStatus.notFound, {'error': 'not found'})
        : Response(HttpStatus.notFound);
  }
  return Response.ok(
    withBody ? blobs.openRead(sha) : null,
    headers: {'content-type': 'application/octet-stream', 'content-length': '$size'},
  );
}

Future<Response> _put(Request request, BlobStore blobs, String sha, int maxBytes) async {
  if (!BlobStore.isValidSha(sha)) return _invalidSha();
  final declared = request.contentLength;
  if (declared != null && declared > maxBytes) return _tooLarge(maxBytes);
  try {
    final size = await blobs.put(sha, request.read(), maxBytes: maxBytes);
    return _json(HttpStatus.ok, {'sha256': sha, 'size': size});
  } on BlobTooLargeException {
    return _tooLarge(maxBytes);
  } on BlobHashMismatchException {
    return _json(HttpStatus.badRequest, {'error': 'hash mismatch'});
  }
}

Response _invalidSha() =>
    _json(HttpStatus.badRequest, {'error': 'blob id must be 64 lowercase hex chars (sha256)'});

Response _tooLarge(int maxBytes) =>
    _json(HttpStatus.requestEntityTooLarge, {'error': 'blob exceeds $maxBytes bytes'});

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
