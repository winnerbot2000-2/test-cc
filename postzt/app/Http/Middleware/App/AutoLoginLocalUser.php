<?php

declare(strict_types=1);

namespace App\Http\Middleware\App;

use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * In the NativePHP desktop build there is exactly one local account (seeded by
 * UserSeeder on first run), so the login screen is removed and the single user
 * is authenticated automatically on every web request. Runs after the session
 * middleware but before Inertia/Hash shared-props and the route-level `auth`
 * middleware, so `auth()->user()` is always populated.
 *
 * Gated on `nativephp-internal.running` so the shared Docker/Cloud code path
 * (multi-user, real login) is untouched.
 */
class AutoLoginLocalUser
{
    public function handle(Request $request, Closure $next): Response
    {
        if (config('nativephp-internal.running') && Auth::guard('web')->guest()) {
            $userId = User::query()->value('id');

            if ($userId !== null) {
                Auth::guard('web')->loginUsingId($userId);
            }
        }

        return $next($request);
    }
}
