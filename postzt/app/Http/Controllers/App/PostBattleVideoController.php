<?php

declare(strict_types=1);

namespace App\Http\Controllers\App;

use App\Enums\Media\Type as MediaType;
use App\Http\Requests\App\Post\GenerateBattleVideoRequest;
use App\Jobs\Video\GenerateRpsBattleVideo;
use App\Models\Post;
use App\Services\Video\RpsBattleVideoGenerator;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\Response;

class PostBattleVideoController extends Controller
{
    /**
     * Queue battle video generation for a post. One distinct video is produced
     * per targeted account (PostPlatform row), then attached to that account's
     * media override.
     */
    public function generate(GenerateBattleVideoRequest $request, Post $post): JsonResponse
    {
        $this->authorize('update', $post);

        $workspace = $request->user()->currentWorkspace;

        $postPlatformIds = $this->resolveTargetIds($post, $request);

        if ($postPlatformIds === []) {
            return response()->json([
                'message' => __('posts.battle_video.errors.no_platforms'),
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        if (! in_array(MediaType::Video, $post->allowedMediaTypes(), true)) {
            return response()->json([
                'message' => __('posts.battle_video.errors.video_not_supported'),
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $generator = app(RpsBattleVideoGenerator::class);

        // Workspace defaults, overridden by whatever this request submitted.
        $settings = array_merge(
            $workspace->rps_battle_settings ?? [],
            $request->input('settings', []),
        );

        GenerateRpsBattleVideo::dispatch(
            workspaceId: $workspace->id,
            postId: $post->id,
            userId: $request->user()->id,
            settings: $generator->normalize($settings),
            postPlatformIds: $postPlatformIds,
        );

        return response()->json([
            'message' => __('posts.battle_video.queued'),
            'post_platform_ids' => $postPlatformIds,
        ], Response::HTTP_ACCEPTED);
    }

    /**
     * Resolve the PostPlatform rows to target. Keyed by PostPlatform id (one row
     * per connected account) rather than platform value, so N accounts on the
     * same network produce N distinct videos instead of collapsing to one.
     *
     * @return array<int, string>
     */
    private function resolveTargetIds(Post $post, GenerateBattleVideoRequest $request): array
    {
        $enabledIds = $post->postPlatforms()
            ->enabled()
            ->pluck('id')
            ->map(fn ($id): string => (string) $id)
            ->all();

        $requested = $request->collect('post_platform_ids')
            ->filter()
            ->map(fn ($id): string => (string) $id)
            ->unique()
            ->values()
            ->all();

        if ($requested === []) {
            return array_values($enabledIds);
        }

        return array_values(array_intersect($requested, $enabledIds));
    }
}
