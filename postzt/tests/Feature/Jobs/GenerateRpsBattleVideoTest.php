<?php

declare(strict_types=1);

use App\Jobs\Video\GenerateRpsBattleVideo;
use App\Models\Post;
use App\Models\PostPlatform;
use App\Models\SocialAccount;
use App\Models\User;
use App\Models\Workspace;
use App\Services\Video\RpsBattleVideoGenerator;
use Illuminate\Support\Facades\Storage;
use Mockery;

test('battle video generation attaches each video to its own account override', function () {
    Storage::fake();

    $user = User::factory()->create();
    $workspace = Workspace::factory()->create(['user_id' => $user->id]);

    $tiktokAccount = SocialAccount::factory()->tiktok()->create(['workspace_id' => $workspace->id]);
    $youtubeAccount = SocialAccount::factory()->youtube()->create(['workspace_id' => $workspace->id]);

    $post = Post::factory()->create([
        'workspace_id' => $workspace->id,
        'user_id' => $user->id,
    ]);

    $tiktok = PostPlatform::factory()->tiktok()->create([
        'post_id' => $post->id,
        'social_account_id' => $tiktokAccount->id,
    ]);

    $youtube = PostPlatform::factory()->youtube()->create([
        'post_id' => $post->id,
        'social_account_id' => $youtubeAccount->id,
    ]);

    $generator = Mockery::mock(RpsBattleVideoGenerator::class);
    $generator->shouldReceive('seedFor')
        ->andReturnUsing(fn (string $postId, string $key): int => crc32($postId.'|'.$key));
    $generator->shouldReceive('generate')
        ->andReturnUsing(function (array $settings, int $seed, string $outputPath): string {
            file_put_contents($outputPath, "\x00\x00\x00\x20ftypisom\x00\x00\x00\x00isomiso2mp41");

            return $outputPath;
        });

    $job = new GenerateRpsBattleVideo(
        workspaceId: $workspace->id,
        postId: $post->id,
        userId: $user->id,
        settings: [],
        postPlatformIds: [$tiktok->id, $youtube->id],
    );

    $job->handle($generator);

    $tiktok->refresh();
    $youtube->refresh();

    expect($tiktok->media)->toHaveCount(1)
        ->and($youtube->media)->toHaveCount(1)
        ->and($tiktok->media[0]['meta']['platform'])->toBe('tiktok')
        ->and($youtube->media[0]['meta']['platform'])->toBe('youtube')
        ->and($tiktok->media[0]['meta']['social_account_id'])->toBe($tiktokAccount->id)
        ->and($youtube->media[0]['meta']['social_account_id'])->toBe($youtubeAccount->id)
        ->and($tiktok->media[0]['url'])->not->toBe($youtube->media[0]['url']);

    $post->refresh();

    expect($post->media)->toHaveCount(2);
});

test('two accounts on the same platform get distinct seeds and videos', function () {
    config()->set('trypost.allow_multiple_social_accounts', true);

    Storage::fake();

    $user = User::factory()->create();
    $workspace = Workspace::factory()->create(['user_id' => $user->id]);

    $accountA = SocialAccount::factory()->tiktok()->create(['workspace_id' => $workspace->id]);
    $accountB = SocialAccount::factory()->tiktok()->create(['workspace_id' => $workspace->id]);

    $post = Post::factory()->create([
        'workspace_id' => $workspace->id,
        'user_id' => $user->id,
    ]);

    $slotA = PostPlatform::factory()->tiktok()->create([
        'post_id' => $post->id,
        'social_account_id' => $accountA->id,
    ]);

    $slotB = PostPlatform::factory()->tiktok()->create([
        'post_id' => $post->id,
        'social_account_id' => $accountB->id,
    ]);

    $seeds = [];

    $generator = Mockery::mock(RpsBattleVideoGenerator::class);
    $generator->shouldReceive('seedFor')
        ->andReturnUsing(function (string $postId, string $key) use (&$seeds): int {
            $seed = crc32($postId.'|'.$key);
            $seeds[$key] = $seed;

            return $seed;
        });
    $generator->shouldReceive('generate')
        ->andReturnUsing(function (array $settings, int $seed, string $outputPath): string {
            file_put_contents($outputPath, "\x00\x00\x00\x20ftypisom\x00\x00\x00\x00isomiso2mp41");

            return $outputPath;
        });

    $job = new GenerateRpsBattleVideo(
        workspaceId: $workspace->id,
        postId: $post->id,
        userId: $user->id,
        settings: [],
        postPlatformIds: [$slotA->id, $slotB->id],
    );

    $job->handle($generator);

    $slotA->refresh();
    $slotB->refresh();

    expect($slotA->media)->toHaveCount(1)
        ->and($slotB->media)->toHaveCount(1)
        ->and($slotA->media[0]['meta']['social_account_id'])->toBe($accountA->id)
        ->and($slotB->media[0]['meta']['social_account_id'])->toBe($accountB->id)
        ->and($slotA->media[0]['meta']['seed'])->not->toBe($slotB->media[0]['meta']['seed'])
        ->and($slotA->media[0]['url'])->not->toBe($slotB->media[0]['url']);
});
