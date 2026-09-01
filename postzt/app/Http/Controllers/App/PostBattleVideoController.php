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
     * per targeted platform, then attached to the post as media.
     */
    public function generate(GenerateBattleVideoRequest $request, Post $post): JsonResponse
    {
        $this->authorize('update', $post);

        $workspace = $request->user()->currentWorkspace;

        $platforms = $request->collect('platforms')->filter()->map(fn ($p) => (string) $p)->unique()->values()->all();

        if ($platforms === []) {
            $platforms = $post->postPlatforms()
                ->enabled()
                ->get()
                ->map(fn ($postPlatform) => $postPlatform->platform->value)
                ->unique()
                ->values()
                ->all();
        }

        if ($platforms === []) {
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
            platforms: $platforms,
        );

        return response()->json([
            'message' => __('posts.battle_video.queued'),
            'platforms' => $platforms,
        ], Response::HTTP_ACCEPTED);
    }
}
