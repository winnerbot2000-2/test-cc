<?php

declare(strict_types=1);

use App\Services\Video\RpsBattleVideoGenerator;

test('normalize falls back to configured defaults for missing fields', function () {
    $generator = app(RpsBattleVideoGenerator::class);

    $settings = $generator->normalize([]);

    expect($settings)->toMatchArray([
        'rock_count' => 30,
        'paper_count' => 30,
        'scissors_count' => 30,
        'theme' => 'default',
        'winner_display_style' => 'banner',
        'sound_enabled' => false,
        'branding_enabled' => false,
    ]);
});

test('normalize clamps out-of-range values', function () {
    $generator = app(RpsBattleVideoGenerator::class);

    $settings = $generator->normalize([
        'rock_count' => 99999,
        'speed' => -50,
        'max_duration_seconds' => 0,
    ]);

    expect($settings['rock_count'])->toBe(240)
        ->and($settings['speed'])->toBe(0.1)
        ->and($settings['max_duration_seconds'])->toBe(1);
});

test('normalize rejects unknown theme and winner display style', function () {
    $generator = app(RpsBattleVideoGenerator::class);

    $settings = $generator->normalize([
        'theme' => 'not-a-theme',
        'winner_display_style' => 'not-a-style',
    ]);

    expect($settings['theme'])->toBe('default')
        ->and($settings['winner_display_style'])->toBe('banner');
});

test('simulationJson emits the camelCase SimulationSettings contract', function () {
    $generator = app(RpsBattleVideoGenerator::class);

    $json = $generator->simulationJson([
        'rock_count' => 5,
        'paper_count' => 6,
        'scissors_count' => 7,
        'theme' => 'neon',
        'winner_display_style' => 'center',
        'max_duration_seconds' => 20,
    ], 12345);

    expect($json)->toMatchArray([
        'rockCount' => 5,
        'paperCount' => 6,
        'scissorsCount' => 7,
        'theme' => 'neon',
        'winnerDisplayStyle' => 'center',
        'seed' => 12345,
    ]);

    expect($json['maxDuration'])->toBe(['type' => 'custom', 'seconds' => 20.0]);
});

test('seedFor is deterministic and distinct per target key', function () {
    $generator = app(RpsBattleVideoGenerator::class);

    $seedA = $generator->seedFor('post-1', 'tiktok');
    $seedB = $generator->seedFor('post-1', 'youtube');
    $seedA2 = $generator->seedFor('post-1', 'tiktok');

    expect($seedA)->toBe($seedA2)
        ->and($seedA)->not->toBe($seedB)
        ->and($seedA)->toBeGreaterThanOrEqual(0)
        ->and($seedA)->toBeLessThanOrEqual(4294967295);
});

test('generate fails with a specific error when the configured binary is missing', function () {
    config()->set('rps.binary_path', '/definitely/not/a/real/RPSBattleSimulator');

    $generator = app(RpsBattleVideoGenerator::class);

    expect(fn () => $generator->generate(['rock_count' => 5], 123, '/tmp/should-not-exist.mp4'))
        ->toThrow(RuntimeException::class, 'RPS battle simulator binary not found');
});
