<?php

declare(strict_types=1);

use App\DataTransferObjects\MediaItem;
use App\Models\Post;
use App\Models\PostPlatform;
use App\Models\SocialAccount;
use App\Models\User;
use App\Models\Workspace;

beforeEach(function () {
    $this->user = User::factory()->create();
    $this->workspace = Workspace::factory()->create(['user_id' => $this->user->id]);

    $this->socialAccount = SocialAccount::factory()->linkedin()->create([
        'workspace_id' => $this->workspace->id,
    ]);

    $this->post = Post::factory()->create([
        'workspace_id' => $this->workspace->id,
        'user_id' => $this->user->id,
    ]);

    $this->postPlatform = PostPlatform::factory()->linkedin()->create([
        'post_id' => $this->post->id,
        'social_account_id' => $this->socialAccount->id,
    ]);
});

test('effective media items fall back to the post media when no override is set', function () {
    $this->post->update([
        'media' => [
            [
                'id' => 'shared-video',
                'path' => 'media/shared.mp4',
                'url' => 'https://example.com/shared.mp4',
                'mime_type' => 'video/mp4',
            ],
        ],
    ]);

    $items = $this->postPlatform->fresh()->effectiveMediaItems();

    expect($items)->toHaveCount(1)
        ->and($items->first())->toBeInstanceOf(MediaItem::class)
        ->and($items->first()->id)->toBe('shared-video');
});

test('effective media items prefer the platform override over the post media', function () {
    $this->post->update([
        'media' => [
            [
                'id' => 'shared-video',
                'path' => 'media/shared.mp4',
                'url' => 'https://example.com/shared.mp4',
                'mime_type' => 'video/mp4',
            ],
        ],
    ]);

    $this->postPlatform->update([
        'media' => [
            [
                'id' => 'platform-video',
                'path' => 'media/platform.mp4',
                'url' => 'https://example.com/platform.mp4',
                'mime_type' => 'video/mp4',
            ],
        ],
    ]);

    $items = $this->postPlatform->fresh()->effectiveMediaItems();

    expect($items)->toHaveCount(1)
        ->and($items->first()->id)->toBe('platform-video');
});

test('effective media items fall back when the override is an empty array', function () {
    $this->post->update([
        'media' => [
            [
                'id' => 'shared-video',
                'path' => 'media/shared.mp4',
                'url' => 'https://example.com/shared.mp4',
                'mime_type' => 'video/mp4',
            ],
        ],
    ]);

    $this->postPlatform->update(['media' => []]);

    $items = $this->postPlatform->fresh()->effectiveMediaItems();

    expect($items)->toHaveCount(1)
        ->and($items->first()->id)->toBe('shared-video');
});
