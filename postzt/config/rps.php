<?php

declare(strict_types=1);

return [

    /*
    |--------------------------------------------------------------------------
    | RPS Battle Simulator CLI
    |--------------------------------------------------------------------------
    |
    | Path to the RPSBattleSimulator binary used to render battle videos.
    | TryPost invokes it headlessly (no GUI) as a subprocess, passing a
    | SimulationSettings JSON file and an output path. See the RPS repo's
    | HeadlessRunner for the exact contract.
    |
    */

    'binary_path' => env('RPS_BINARY_PATH', 'RPSBattleSimulator'),

    /*
    |--------------------------------------------------------------------------
    | Generation timeout
    |--------------------------------------------------------------------------
    |
    | Seconds to wait for a single video render before giving up. Longer
    | durations render more frames, so this is generous rather than tight.
    |
    */

    'timeout_seconds' => (int) env('RPS_TIMEOUT_SECONDS', 900),

    /*
    |--------------------------------------------------------------------------
    | Exposed generation settings
    |--------------------------------------------------------------------------
    |
    | The subset of SimulationSettings surfaced in TryPost's UI. Values here
    | are the defaults; the rest of the SimulationSettings struct keeps its
    | own built-in defaults (the CLI merges the payload over them). The seed
    | is intentionally absent — it is derived per platform at generation time,
    | never set by hand.
    |
    */

    'settings' => [
        'rock_count' => 30,
        'paper_count' => 30,
        'scissors_count' => 30,
        'theme' => 'default',
        'speed' => 1.2,
        'max_duration_seconds' => 15,
        'winner_display_style' => 'banner',
        'custom_winner_text' => '',
        'branding_enabled' => false,
        'branding_text' => '',
        'sound_enabled' => false,
    ],

    /*
    |--------------------------------------------------------------------------
    | Allowed values
    |--------------------------------------------------------------------------
    |
    | Enum-like fields mirror the Swift enums. Kept in one place so validation
    | and the UI share a single source of truth.
    |
    */

    'themes' => ['default', 'pastel', 'neon', 'dark'],

    'winner_display_styles' => ['banner', 'center', 'neon_rainbow'],
];
