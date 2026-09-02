<?php

declare(strict_types=1);

namespace App\Http\Requests\App\Post;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class GenerateBattleVideoRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'settings' => ['sometimes', 'array'],
            'settings.rock_count' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'settings.paper_count' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'settings.scissors_count' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'settings.theme' => ['sometimes', 'string', Rule::in(config('rps.themes'))],
            'settings.speed' => ['sometimes', 'numeric', 'min:0.1', 'max:10'],
            'settings.max_duration_seconds' => ['sometimes', 'integer', 'min:1', 'max:300'],
            'settings.winner_display_style' => ['sometimes', 'string', Rule::in(config('rps.winner_display_styles'))],
            'settings.custom_winner_text' => ['sometimes', 'string', 'max:200'],
            'settings.branding_enabled' => ['sometimes', 'boolean'],
            'settings.branding_text' => ['sometimes', 'string', 'max:200'],
            'settings.sound_enabled' => ['sometimes', 'boolean'],
            'post_platform_ids' => ['sometimes', 'array'],
            'post_platform_ids.*' => ['string', 'uuid'],
        ];
    }
}
