<?php

declare(strict_types=1);

namespace App\Jobs\Video;

use App\Enums\Notification\Channel;
use App\Enums\Notification\Type;
use App\Jobs\SendNotification;
use App\Models\Media;
use App\Models\Post;
use App\Models\PostPlatform;
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
 * Renders one battle video per targeted account (PostPlatform row, distinct seed
 * each) via the RPS CLI. Each video is attached to its account's PostPlatform
 * override (so every publisher sends only its own video) and, for composer
 * review, to the post's shared media. Runs on the `ai` queue so export never
 * blocks the UI.
 */
class GenerateRpsBattleVideo implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 1;

    public int $timeout = 960;

    /**
     * @param  array<string, mixed>  $settings
     * @param  array<int, string>  $postPlatformIds
     */
    public function __construct(
        public string $workspaceId,
        public string $postId,
        public string $userId,
        public array $settings,
        public array $postPlatformIds,
    ) {
        $this->onQueue('ai');
    }

    public function handle(RpsBattleVideoGenerator $generator): void
    {
        $post = Post::findOrFail($this->postId);
        $workspace = Workspace::findOrFail($this->workspaceId);

        $postPlatforms = $post->postPlatforms()
            ->enabled()
            ->whereIn('id', $this->postPlatformIds)
            ->get()
            ->keyBy(fn (PostPlatform $postPlatform): string => $postPlatform->id);

        $attached = [];
        $failed = [];
        $tempFiles = [];

        try {
            foreach ($this->postPlatformIds as $postPlatformId) {
                $postPlatform = $postPlatforms->get($postPlatformId);

                if ($postPlatform === null) {
                    continue;
                }

                $platform = $postPlatform->platform->value;
                $seed = $generator->seedFor($this->postId, $postPlatform->id);
                $tempPath = $this->tempPath();

                try {
                    $generator->generate($this->settings, $seed, $tempPath);
                } catch (Throwable $e) {
                    $failed[$postPlatformId] = $e->getMessage();
                    Log::error('RPS battle video generation failed', [
                        'post_id' => $this->postId,
                        'post_platform_id' => $postPlatformId,
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

                    $attached[$postPlatformId] = $this->snapshot($media, $platform, $seed, $postPlatform->social_account_id);
                } catch (Throwable $e) {
                    $failed[$postPlatformId] = $e->getMessage();
                    Log::error('RPS battle video attach failed', [
                        'post_id' => $this->postId,
                        'post_platform_id' => $postPlatformId,
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

        // Keep the full set on the post (composer grid + compliance review),
        // and write each account's own video to its per-account override so
        // publishers send one distinct video per account.
        $post->appendMedia(array_values($attached));
        $this->attachPlatformMedia($post, $attached);

        if ($failed !== []) {
            $this->notifyPartial($workspace, $post, $failed);
        } else {
            $this->notifySuccess($workspace, $post, count($attached));
        }
    }

    /**
     * Attach each account's generated video to that account's PostPlatform
     * override. Keyed by PostPlatform id (not platform value) so a post
     * targeting several accounts of the same network publishes one distinct
     * video per account instead of every account's video to every account.
     *
     * @param  array<string, array<string, mixed>>  $mediaByPostPlatform
     */
    private function attachPlatformMedia(Post $post, array $mediaByPostPlatform): void
    {
        foreach ($post->postPlatforms()->enabled()->get() as $postPlatform) {
            /** @var PostPlatform $postPlatform */
            if (! isset($mediaByPostPlatform[$postPlatform->id])) {
                continue;
            }

            $postPlatform->update(['media' => [$mediaByPostPlatform[$postPlatform->id]]]);
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function snapshot(Media $media, string $platform, int $seed, ?string $socialAccountId): array
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
            'meta' => [
                'platform' => $platform,
                'seed' => $seed,
                'social_account_id' => $socialAccountId,
            ],
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
        $labels = $post->postPlatforms()
            ->whereIn('id', array_keys($failed))
            ->get()
            ->mapWithKeys(fn (PostPlatform $postPlatform): array => [
                $postPlatform->id => $this->targetLabel($postPlatform),
            ]);

        $details = collect($failed)
            ->map(fn (string $message, string $id): string => ($labels[$id] ?? $id).': '.$message)
            ->join('; ');

        return sprintf('Battle video generation for post "%s" did not complete for: %s', $post->id, $details);
    }

    /**
     * Human-readable target label: platform + connected account display name, so
     * two accounts on the same network are told apart in notifications.
     */
    private function targetLabel(PostPlatform $postPlatform): string
    {
        $name = $postPlatform->socialAccount?->accountDisplayName()
            ?? $postPlatform->platform_name
            ?? $postPlatform->platform_username
            ?? null;

        return $name === null
            ? $postPlatform->platform->label()
            : $postPlatform->platform->label().' ('.$name.')';
    }
}
