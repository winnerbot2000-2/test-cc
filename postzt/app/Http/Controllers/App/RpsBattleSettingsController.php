<?php

declare(strict_types=1);

namespace App\Http\Controllers\App;

use App\Http\Requests\App\Post\GenerateBattleVideoRequest;
use App\Services\Video\RpsBattleVideoGenerator;
use Illuminate\Http\JsonResponse;

class RpsBattleSettingsController extends Controller
{
    /**
     * Persist the workspace's default battle video generation settings.
     */
    public function update(GenerateBattleVideoRequest $request): JsonResponse
    {
        $workspace = $request->user()->currentWorkspace;

        $settings = app(RpsBattleVideoGenerator::class)->normalize($request->input('settings', []));

        $workspace->update(['rps_battle_settings' => $settings]);

        return response()->json([
            'message' => __('posts.battle_video.settings_saved'),
            'settings' => $settings,
        ]);
    }
}
