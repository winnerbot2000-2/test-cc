<?php

declare(strict_types=1);

namespace App\Jobs\Video;

use App\Enums\Notification\Channel;
use App\Enums\Notification\Type;
use App\Jobs\SendNotification;
use App\Models\Media;
use App\Models\Post;
use App\Models\User;
use App\Models\Workspace;
use App\Services\Video\RpsBattleVideoGenerator;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

/**
 * Renders one battle video per targeted platform (distinct seed each) via the
 * RPS CLI and attaches the results to the post as normal media. Runs on the
 * `ai` queue so video export never blocks the request/UI.
 */
class GenerateRpsBattleVideo implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 1;

    public int $timeout = 960;

    /**
     * @param  array<string, mixed>  $settings
     * @param  array<int, string>  $platforms
     */
    public function __construct(
        public string $workspaceId,
        public string $postId,
        public string $userId,
        public array $settings,
        public array $platforms,
    ) {
        $this->onQueue('ai');
    }

    public function handle(RpsBattleVideoGenerator $generator): void
    {
        $post = Post::findOrFail($this->postId);
        $workspace = Workspace::findOrFail($this->workspaceId);

        $attached = [];
        $failed = [];
        $tempFiles = [];

        try {
            foreach ($this->platforms as $platform) {
                $seed = $generator->seedFor($this->postId, $platform);
                $tempPath = $this->tempPath();

                try {
                    $generator->generate($this->settings, $seed, $tempPath);
                } catch (Throwable $e) {
                    $failed[$platform] = $e->getMessage();
                    Log::error('RPS battle video generation failed', [
                        'post_id' => $this->postId,
                        'platform' => $platform,
                        'error' => $e->getMessage(),
                    ]);

                    continue;
                }

                $tempFiles[] = $tempPath;

                try {
                    $media = $workspace->addMediaFromPath(
                        $tempPath,
                        "rps_battle_{$platform}_{$seed}.mp4",
                        'assets',
                    );

                    $attached[] = $this->snapshot($media, $platform, $seed);
                } catch (Throwable $e) {
                    $failed[$platform] = $e->getMessage();
                    Log::error('RPS battle video attach failed', [
                        'post_id' => $this->postId,
                        'platform' => $platform,
                        'error' => $e->getMessage(),
                    ]);
                }
            }
        } finally {
            foreach ($tempFiles as $file) {
                @unlink($file);
            }
        }

        if ($attached === []) {
            $this->notifyFailure($workspace, $post, $failed);

            throw new RuntimeException('Battle video generation failed for every platform.');
        }

        $post->appendMedia($attached);

        if ($failed !== []) {
            $this->notifyPartial($workspace, $post, $failed);
        } else {
            $this->notifySuccess($workspace, $post, count($attached));
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function snapshot(Media $media, string $platform, int $seed): array
    {
        return [
            'id' => $media->id,
            'path' => $media->path,
            'url' => $media->url,
            'type' => $media->type->value,
            'mime_type' => $media->mime_type,
            'original_filename' => $media->original_filename,
            'size' => $media->size,
            'source' => 'rps',
            'meta' => ['platform' => $platform, 'seed' => $seed],
        ];
    }

    private function tempPath(): string
    {
        return sys_get_temp_dir().DIRECTORY_SEPARATOR.'rps_video_'.Str::uuid().'.mp4';
    }

    /**
     * @param  array<string, string>  $failed
     */
    private function notifyFailure(Workspace $workspace, Post $post, array $failed): void
    {
        $this->notify($workspace, Type::PostFailed, 'Battle video generation failed', $this->failedBody($post, $failed));
    }

    /**
     * @param  array<string, string>  $failed
     */
    private function notifyPartial(Workspace $workspace, Post $post, array $failed): void
    {
        $this->notify($workspace, Type::PostReady, 'Some battle videos could not be generated', $this->failedBody($post, $failed));
    }

    private function notifySuccess(Workspace $workspace, Post $post, int $count): void
    {
        $this->notify($workspace, Type::PostReady, 'Battle video ready', sprintf('%d battle video(s) were attached to your post.', $count));
    }

    private function notify(Workspace $workspace, Type $type, string $title, string $body): void
    {
        $user = User::find($this->userId);

        if ($user === null) {
            return;
        }

        SendNotification::dispatch(
            user: $user,
            workspaceId: $workspace->id,
            type: $type,
            channel: Channel::InApp,
            title: $title,
            body: $body,
        );
    }

    /**
     * @param  array<string, string>  $failed
     */
    private function failedBody(Post $post, array $failed): string
    {
        $details = collect($failed)
            ->map(fn (string $message, string $platform): string => ucfirst($platform).': '.$message)
            ->join('; ');

        return sprintf('Battle video generation for post "%s" did not complete for: %s', $post->id, $details);
    }
}
