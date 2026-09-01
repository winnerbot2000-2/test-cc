<?php

declare(strict_types=1);

namespace App\Services\Automation;

use App\Enums\PostPlatform\ContentType;

/**
 * Backend mirror of the Generate node's frontend compliance. AI image
 * generation has been removed, so the node is text-only: it can target any
 * content type that does not itself require media. Content types that need an
 * image/video to publish (pins, reels, stories, carousels, …) are rejected
 * because the node can no longer produce them.
 */
final class GenerateNodeValidator
{
    public const MAX_GENERATED_IMAGES = 10;

    /**
     * First compliance issue for a generate node's config, or null when valid.
     *
     * @param  array<string, mixed>  $config
     */
    public function issueFor(array $config): ?string
    {
        $accounts = data_get($config, 'accounts');

        if (! is_array($accounts) || $accounts === []) {
            return null;
        }

        foreach ($accounts as $entry) {
            $contentType = ContentType::tryFrom((string) data_get($entry, 'content_type'));

            if (! $contentType instanceof ContentType) {
                continue;
            }

            if (! $contentType->supportsImage() || $contentType->requiresMedia()) {
                return __('automations.errors.generate_image_format_required');
            }
        }

        return null;
    }
}
