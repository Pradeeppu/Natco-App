/// The validation queue: sheets waiting on a human decision.
///
/// A Supervisor's working list, scope-filtered exactly like every other list
/// in the app — a cluster-scoped account sees only the sheets in its own
/// clusters.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/presentation/controller/omr_validation_controllers.dart';

final class OmrValidationQueueScreen extends ConsumerStatefulWidget {
  const OmrValidationQueueScreen({super.key});

  @override
  ConsumerState<OmrValidationQueueScreen> createState() =>
      _OmrValidationQueueScreenState();
}

class _OmrValidationQueueScreenState
    extends ConsumerState<OmrValidationQueueScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(omrValidationQueueControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<PagedListState<OmrSubmission>> value = ref.watch(
      omrValidationQueueControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Validation')),
      body: SafeArea(
        child: value.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () => ref
                .read(omrValidationQueueControllerProvider.notifier)
                .refresh(),
          ),
          data: (PagedListState<OmrSubmission> state) {
            final Failure? failure = state.failure;
            if (failure != null) {
              return FailureView(
                failure: failure,
                onRetry: () => ref
                    .read(omrValidationQueueControllerProvider.notifier)
                    .refresh(),
              );
            }
            if (state.items.isEmpty) {
              return const EmptyView(
                title: 'Nothing waiting on you',
                message:
                    'Every sheet in your area has either scored cleanly or '
                    'already has a decision recorded.',
                icon: Icons.rule_folder_outlined,
              );
            }
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nothing here can be scored until it is resolved, '
                          'and a decision is always recorded with who made it '
                          'and why.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }
                      return _QueueTile(submission: state.items[index]);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.submission});

  final OmrSubmission submission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<OmrAnswer>> answers = ref.watch(
      omrAnswersProvider(submission.omrId),
    );
    final int flaggedCount = answers.maybeWhen(
      data: (List<OmrAnswer> list) => list
          .where((OmrAnswer a) => a.needsValidation && a.finalAnswer == null)
          .length,
      orElse: () => 0,
    );

    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: theme.statusColors.warningContainer,
        child: Text(
          '$flaggedCount',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.statusColors.warning,
          ),
        ),
      ),
      title: Text('OMR ${submission.omrId}'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$flaggedCount answer(s) waiting on a decision · captured '
          '${_relativeTime(submission.capturedAt)}',
          style: theme.textTheme.bodySmall,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        RoutePaths.of(RoutePaths.omrValidationDetail, <String, String>{
          'omrId': submission.omrId,
        }),
      ),
    );
  }

  static String _relativeTime(DateTime at) {
    final Duration age = DateTime.now().toUtc().difference(at.toUtc());
    if (age.inMinutes < 60) {
      return '${age.inMinutes.clamp(1, 59)}m ago';
    }
    if (age.inHours < 24) {
      return '${age.inHours}h ago';
    }
    return '${age.inDays}d ago';
  }
}
