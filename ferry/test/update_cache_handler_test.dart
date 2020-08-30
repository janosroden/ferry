import 'dart:async';
import 'package:async/async.dart';
import 'package:mockito/mockito.dart';
import 'package:gql_link/gql_link.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:ferry/ferry.dart';
import 'package:test/test.dart';

import 'package:ferry_test_graphql/queries/variables/reviews.req.gql.dart';
import 'package:ferry_test_graphql/queries/variables/reviews.data.gql.dart';
import 'package:ferry_test_graphql/mutations/variables/create_review.req.gql.dart';
import 'package:ferry_test_graphql/mutations/variables/create_review.var.gql.dart';
import 'package:ferry_test_graphql/mutations/variables/create_review.data.gql.dart';
import 'package:ferry_test_graphql/schema/schema.schema.gql.dart';

class MockLink extends Mock implements Link {}

final createReviewData = GCreateReviewData(
  (b) => b
    ..createReview.id = '123'
    ..createReview.stars = 5
    ..createReview.episode = GEpisode.NEWHOPE
    ..createReview.commentary = 'Amazing!!!',
);

final reviewsReq = GReviewsReq();

UpdateCacheHandler<GCreateReviewData, GCreateReviewVars> createReviewHandler = (
  proxy,
  response,
) {
  final reviews = proxy.readQuery(reviewsReq) ?? GReviewsData();
  proxy.writeQuery(
    reviewsReq,
    reviews.rebuild((b) => b
      ..reviews.add(
          GReviewsData_reviews.fromJson(response.data.createReview.toJson()))),
  );
};

void main() {
  group('UpdateCacheHandler', () {
    final clientOptions = ClientOptions(updateCacheHandlers: {
      'createReviewHandler': createReviewHandler,
    });

    group('without optimistic response', () {
      final mockLink = MockLink();
      final req = GCreateReviewReq(
        (b) => b
          ..updateCacheHandlerKey = 'createReviewHandler'
          ..vars.episode = GEpisode.NEWHOPE
          ..vars.review.stars = 5
          ..vars.review.commentary = 'Amazing!!!',
      );
      final linkController = StreamController<Response>();
      final client = Client(link: mockLink, options: clientOptions);
      final queue = StreamQueue(client.responseStream(
        req,
        executeOnListen: false,
      ));

      when(mockLink.request(any, any)).thenAnswer((_) => linkController.stream);

      test('runs only on first non-optimistic', () async {
        expect(client.cache.readQuery(reviewsReq), equals(null));

        client.requestController.add(req);
        linkController.add(Response(data: createReviewData.toJson()));
        await queue.next;

        expect(client.cache.readQuery(reviewsReq).reviews.length, equals(1));

        linkController.add(Response(data: createReviewData.toJson()));
        await queue.next;

        expect(client.cache.readQuery(reviewsReq).reviews.length, equals(1));
      });
    });

    group('with optimistic response', () {
      final mockLink = MockLink();
      final req = GCreateReviewReq(
        (b) => b
          ..updateCacheHandlerKey = 'createReviewHandler'
          ..vars.episode = GEpisode.NEWHOPE
          ..vars.review.stars = 5
          ..vars.review.commentary = 'Amazing!!!'
          ..optimisticResponse.createReview.id = '456'
          ..optimisticResponse.createReview.stars = 4
          ..optimisticResponse.createReview.episode = GEpisode.JEDI
          ..optimisticResponse.createReview.commentary = 'hi',
      );
      final linkController = StreamController<Response>();
      final client = Client(link: mockLink, options: clientOptions);
      final queue = StreamQueue(client.responseStream(
        req,
        executeOnListen: false,
      ));

      when(mockLink.request(any, any)).thenAnswer((_) => linkController.stream);

      test('runs on optimistic response and first non-optimistic response',
          () async {
        expect(client.cache.readQuery(reviewsReq), equals(null));

        client.requestController.add(req);
        await queue.next;

        expect(client.cache.readQuery(reviewsReq).reviews.length, equals(1));
        expect(
          client.cache.readQuery(reviewsReq).reviews.first.id,
          equals('456'),
        );

        linkController.add(Response(data: createReviewData.toJson()));
        await queue.next;

        expect(client.cache.readQuery(reviewsReq).reviews.length, equals(1));
        expect(
          client.cache.readQuery(reviewsReq).reviews.first.id,
          equals('123'),
        );

        linkController.add(Response(data: createReviewData.toJson()));
        await queue.next;

        expect(client.cache.readQuery(reviewsReq).reviews.length, equals(1));
        expect(
          client.cache.readQuery(reviewsReq).reviews.first.id,
          equals('123'),
        );
      });
    });
  });
}