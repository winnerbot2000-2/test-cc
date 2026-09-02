<?php

declare(strict_types=1);

namespace App\Services\Video;

use Illuminate\Support\Facades\Process;
use RuntimeException;
use Throwable;

/**
 * Renders a Rock-Paper-Scissors battle video by shelling out to the
 * RPSBattleSimulator CLI (headless mode). This is the single place that knows
 * the CLI's JSON + argument contract; everything else in TryPost goes through
 * here.
 */
class RpsBattleVideoGenerator
{
    /**
     * Render a battle video at the given output path.
     *
     * @param  array<string, mixed>  $settings
     * @return string the output path on success
     *
     * @throws RuntimeException
     */
    public function generate(array $settings, int $seed, string $outputPath): string
    {
        $binary = $this->resolveBinary();
        $timeout = (int) config('rps.timeout_seconds');

        $settingsJson = $this->simulationJson($settings, $seed);
        $settingsFile = $this->writeSettingsFile($settingsJson);

        try {
            $result = Process::timeout($timeout)
                ->run([$binary, '--headless', '--settings', $settingsFile, '--output', $outputPath]);
        } catch (Throwable $e) {
            throw new RuntimeException(
                sprintf('Could not run the RPS battle simulator binary "%s": %s', $binary, $e->getMessage()),
            );
        } finally {
            @unlink($settingsFile);
        }

        if (! $result->successful()) {
            throw new RuntimeException(
                'Battle video generation failed: '.trim($result->errorOutput() ?: $result->output()),
            );
        }

        if (! is_file($outputPath) || filesize($outputPath) === 0) {
            throw new RuntimeException('Battle video generation reported success but produced no file.');
        }

        return $outputPath;
    }

    /**
     * Resolve the simulator binary, failing with a specific message when an
     * explicit path is configured but the file is missing or not executable.
     */
    private function resolveBinary(): string
    {
        $binary = (string) config('rps.binary_path');

        if (str_contains($binary, '/') || str_contains($binary, DIRECTORY_SEPARATOR)) {
            if (! is_file($binary)) {
                throw new RuntimeException(
                    sprintf('RPS battle simulator binary not found at "%s". Set RPS_BINARY_PATH to the RPSBattleSimulator executable.', $binary),
                );
            }

            if (! is_executable($binary)) {
                throw new RuntimeException(
                    sprintf('RPS battle simulator binary is not executable: "%s".', $binary),
                );
            }
        }

        return $binary;
    }

    /**
     * Build the SimulationSettings-shaped JSON payload the CLI expects. Only the
     * user-facing fields are sent — the CLI merges them over its own defaults,
     * so unexposed fields never need mirroring here.
     *
     * @param  array<string, mixed>  $settings
     * @return array<string, mixed>
     */
    public function simulationJson(array $settings, int $seed): array
    {
        $normalized = $this->normalize($settings);

        return [
            'rockCount' => $normalized['rock_count'],
            'paperCount' => $normalized['paper_count'],
            'scissorsCount' => $normalized['scissors_count'],
            'theme' => $normalized['theme'],
            'speed' => $normalized['speed'],
            'maxDuration' => ['type' => 'custom', 'seconds' => (float) $normalized['max_duration_seconds']],
            'winnerDisplayStyle' => $normalized['winner_display_style'],
            'customWinnerText' => $normalized['custom_winner_text'],
            'brandingEnabled' => $normalized['branding_enabled'],
            'brandingText' => $normalized['branding_text'],
            'soundEnabled' => $normalized['sound_enabled'],
            'seed' => $seed,
            'filenamePrefix' => 'RPS_Battle',
        ];
    }

    /**
     * Deterministic, distinct seed per post + target. The target is a PostPlatform
     * id (one per connected account), so two accounts on the same network never
     * share a video. 32-bit to match the Swift UInt32 seed.
     */
    public function seedFor(string $postId, string $key): int
    {
        return (int) hexdec(substr(sha1($postId.'|'.$key), 0, 8));
    }

    /**
     * Normalize + clamp a settings payload against the exposed contract,
     * falling back to the configured defaults for anything missing or invalid.
     *
     * @param  array<string, mixed>  $settings
     * @return array<string, mixed>
     */
    public function normalize(array $settings): array
    {
        $defaults = (array) config('rps.settings', []);
        $themes = (array) config('rps.themes', []);
        $styles = (array) config('rps.winner_display_styles', []);

        $theme = (string) ($settings['theme'] ?? $defaults['theme'] ?? 'default');
        if (! in_array($theme, $themes, true)) {
            $theme = (string) ($defaults['theme'] ?? 'default');
        }

        $style = (string) ($settings['winner_display_style'] ?? $defaults['winner_display_style'] ?? 'banner');
        if (! in_array($style, $styles, true)) {
            $style = (string) ($defaults['winner_display_style'] ?? 'banner');
        }

        return [
            'rock_count' => $this->clampInt($settings['rock_count'] ?? null, (int) ($defaults['rock_count'] ?? 30), 0, 240),
            'paper_count' => $this->clampInt($settings['paper_count'] ?? null, (int) ($defaults['paper_count'] ?? 30), 0, 240),
            'scissors_count' => $this->clampInt($settings['scissors_count'] ?? null, (int) ($defaults['scissors_count'] ?? 30), 0, 240),
            'theme' => $theme,
            'speed' => $this->clampFloat($settings['speed'] ?? null, (float) ($defaults['speed'] ?? 1.2), 0.1, 10.0),
            'max_duration_seconds' => $this->clampInt($settings['max_duration_seconds'] ?? null, (int) ($defaults['max_duration_seconds'] ?? 15), 1, 300),
            'winner_display_style' => $style,
            'custom_winner_text' => (string) ($settings['custom_winner_text'] ?? $defaults['custom_winner_text'] ?? ''),
            'branding_enabled' => (bool) ($settings['branding_enabled'] ?? $defaults['branding_enabled'] ?? false),
            'branding_text' => (string) ($settings['branding_text'] ?? $defaults['branding_text'] ?? ''),
            'sound_enabled' => (bool) ($settings['sound_enabled'] ?? $defaults['sound_enabled'] ?? false),
        ];
    }

    private function clampInt(mixed $value, int $default, int $min, int $max): int
    {
        if (! is_numeric($value)) {
            return $default;
        }

        return max($min, min($max, (int) $value));
    }

    private function clampFloat(mixed $value, float $default, float $min, float $max): float
    {
        if (! is_numeric($value)) {
            return $default;
        }

        return max($min, min($max, (float) $value));
    }

    /**
     * @param  array<string, mixed>  $json
     */
    private function writeSettingsFile(array $json): string
    {
        $path = tempnam(sys_get_temp_dir(), 'rps_settings_');

        if ($path === false) {
            throw new RuntimeException('Could not create a temp file for battle video settings.');
        }

        $encoded = json_encode($json, JSON_UNESCAPED_UNICODE);

        if ($encoded === false || file_put_contents($path, $encoded) === false) {
            @unlink($path);

            throw new RuntimeException('Could not write battle video settings.');
        }

        return $path;
    }
}
