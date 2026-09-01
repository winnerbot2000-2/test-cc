<?php

declare(strict_types=1);

namespace App\Support;

use Illuminate\Support\Facades\File;

/**
 * Persists user-supplied secrets (social platform OAuth credentials, AI keys,
 * Stripe keys, media APIs) in the app's local data directory instead of baking
 * them into the bundled `.env` (which ships with the app and is readable by
 * anyone who unpacks it).
 *
 * Values are stored as a flat JSON object keyed by env name and merged into
 * Laravel's runtime config at boot so the rest of the app keeps reading
 * `config('services.x.client_id')`, `config('ai.providers.openai.key')`, etc.
 */
final class NativeSecrets
{
    /**
     * Where the file lives inside the app-data storage directory.
     */
    public static function path(): string
    {
        return storage_path('native-secrets.json');
    }

    /**
     * @return array<string, string>
     */
    public static function all(): array
    {
        if (! File::exists(self::path())) {
            return [];
        }

        $decoded = json_decode(File::get(self::path()), true);

        return is_array($decoded) ? $decoded : [];
    }

    public static function set(string $key, ?string $value): void
    {
        $secrets = self::all();

        if ($value === null || $value === '') {
            unset($secrets[$key]);
        } else {
            $secrets[$key] = $value;
        }

        File::put(self::path(), json_encode($secrets, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    }

    /**
     * Merge stored secrets into the running configuration.
     */
    public static function load(): void
    {
        foreach (self::all() as $key => $value) {
            $path = self::configPathForKey($key);

            if ($path !== null && $value !== null && $value !== '') {
                config([$path => $value]);
            }
        }
    }

    /**
     * Map an env-style key to the config path the app reads at runtime.
     */
    protected static function configPathForKey(string $key): ?string
    {
        $services = [
            'LINKEDIN_CLIENT_ID' => 'services.linkedin.client_id',
            'LINKEDIN_CLIENT_SECRET' => 'services.linkedin.client_secret',
            'LINKEDIN_CLIENT_REDIRECT' => 'services.linkedin.redirect',
            'LINKEDIN_PAGE_CLIENT_REDIRECT' => 'services.linkedin-page.redirect',
            'X_CLIENT_ID' => 'services.x.client_id',
            'X_CLIENT_SECRET' => 'services.x.client_secret',
            'X_CLIENT_REDIRECT' => 'services.x.redirect',
            'TIKTOK_CLIENT_ID' => 'services.tiktok.client_id',
            'TIKTOK_CLIENT_SECRET' => 'services.tiktok.client_secret',
            'TIKTOK_CLIENT_REDIRECT' => 'services.tiktok.redirect',
            'FACEBOOK_CLIENT_ID' => 'services.facebook.client_id',
            'FACEBOOK_CLIENT_SECRET' => 'services.facebook.client_secret',
            'FACEBOOK_CLIENT_REDIRECT' => 'services.facebook.redirect',
            'INSTAGRAM_CLIENT_ID' => 'services.instagram.client_id',
            'INSTAGRAM_CLIENT_SECRET' => 'services.instagram.client_secret',
            'INSTAGRAM_CLIENT_REDIRECT' => 'services.instagram.redirect',
            'THREADS_CLIENT_ID' => 'services.threads.client_id',
            'THREADS_CLIENT_SECRET' => 'services.threads.client_secret',
            'THREADS_CLIENT_REDIRECT' => 'services.threads.redirect',
            'GOOGLE_CLIENT_ID' => 'services.google.client_id',
            'GOOGLE_CLIENT_SECRET' => 'services.google.client_secret',
            'GOOGLE_CLIENT_REDIRECT' => 'services.google.redirect',
            'GOOGLE_AUTH_CALLBACK' => 'services.google-auth.redirect',
            'GITHUB_CLIENT_ID' => 'services.github.client_id',
            'GITHUB_CLIENT_SECRET' => 'services.github.client_secret',
            'GITHUB_AUTH_CALLBACK' => 'services.github.redirect',
            'PINTEREST_CLIENT_ID' => 'services.pinterest.client_id',
            'PINTEREST_CLIENT_SECRET' => 'services.pinterest.client_secret',
            'PINTEREST_CLIENT_REDIRECT' => 'services.pinterest.redirect',
            'DISCORD_CLIENT_ID' => 'services.discord.client_id',
            'DISCORD_CLIENT_SECRET' => 'services.discord.client_secret',
            'DISCORD_CLIENT_REDIRECT' => 'services.discord.redirect',
        ];

        if (array_key_exists($key, $services)) {
            return $services[$key];
        }

        $aiProviders = [
            'OPENAI_API_KEY' => 'openai',
            'ANTHROPIC_API_KEY' => 'anthropic',
            'GEMINI_API_KEY' => 'gemini',
            'OPENROUTER_API_KEY' => 'openrouter',
            'ELEVENLABS_API_KEY' => 'eleven',
            'XAI_API_KEY' => 'xai',
            'GROQ_API_KEY' => 'groq',
            'MISTRAL_API_KEY' => 'mistral',
            'DEEPSEEK_API_KEY' => 'deepseek',
            'COHERE_API_KEY' => 'cohere',
        ];

        if (array_key_exists($key, $aiProviders)) {
            return "ai.providers.{$aiProviders[$key]}.key";
        }

        $stripe = [
            'STRIPE_KEY' => 'cashier.key',
            'STRIPE_SECRET' => 'cashier.secret',
            'STRIPE_WEBHOOK_SECRET' => 'cashier.webhook.secret',
        ];

        return $stripe[$key] ?? null;
    }
}
