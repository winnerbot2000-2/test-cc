<?php

declare(strict_types=1);

namespace App\Http\Controllers\App;

use App\Http\Requests\App\Asset\StoreAssetRequest;
use App\Http\Requests\App\Asset\StoreChunkedAssetRequest;
use App\Http\Resources\App\MediaResource;
use App\Models\Media;
use App\Services\Media\ChunkedAssetReceiver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Inertia\Inertia;
use Inertia\Response;
use Symfony\Component\HttpFoundation\Response as SymfonyResponse;

class AssetController extends Controller
{
    public function index(Request $request): Response|RedirectResponse
    {
        $workspace = $request->user()->currentWorkspace;

        if (! $workspace) {
            return redirect()->route('app.workspaces.create');
        }

        $this->authorize('createPost', $workspace);

        return Inertia::render('assets/Index');
    }

    public function search(Request $request): AnonymousResourceCollection
    {
        $workspace = $request->user()->currentWorkspace;

        $this->authorize('createPost', $workspace);

        $term = trim((string) $request->input('search', ''));
        $type = $request->input('type');

        $assets = $workspace->getMedia('assets')
            ->when($term !== '', fn ($query) => $query->whereLike('original_filename', '%'.$term.'%'))
            ->when(in_array($type, ['image', 'video'], true), fn ($query) => $query->where('type', $type))
            ->latest()
            ->paginate(config('app.pagination.default'));

        return MediaResource::collection($assets);
    }

    public function store(StoreAssetRequest $request): MediaResource
    {
        $workspace = $request->user()->currentWorkspace;

        $this->authorize('createPost', $workspace);

        $clientMeta = (array) $request->input('meta', []);

        $media = $workspace->addMedia($request->file('media'), 'assets', $clientMeta);

        return new MediaResource($media);
    }

    public function storeChunked(StoreChunkedAssetRequest $request, ChunkedAssetReceiver $receiver): JsonResponse
    {
        $workspace = $request->user()->currentWorkspace;

        $this->authorize('createPost', $workspace);

        return $receiver->receive(
            $workspace,
            $request->user(),
            $request->validated('file_name'),
            $request->getContent(),
            (int) $request->validated('range_start'),
            (int) $request->validated('range_end'),
            (int) $request->validated('total_size'),
            (string) $request->validated('upload_id'),
        )->toResponse();
    }

    public function destroy(Request $request, Media $media): RedirectResponse
    {
        $workspace = $request->user()->currentWorkspace;

        $this->authorize('createPost', $workspace);

        if ($media->mediable_type !== $workspace->getMorphClass() || $media->mediable_id !== $workspace->id) {
            abort(SymfonyResponse::HTTP_FORBIDDEN);
        }

        $media->delete();

        return back();
    }
}
