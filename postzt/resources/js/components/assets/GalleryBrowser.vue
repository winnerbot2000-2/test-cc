<script setup lang="ts">
import { router } from '@inertiajs/vue3';
import { IconCloudUpload, IconFileTypePdf, IconLoader2, IconPencilPlus, IconPhoto, IconSearch, IconTrash } from '@tabler/icons-vue';
import { trans } from 'laravel-vue-i18n';
import { computed, nextTick, onMounted, onUnmounted, ref, useTemplateRef, watch } from 'vue';
import { toast } from 'vue-sonner';

import ConfirmDeleteModal from '@/components/ConfirmDeleteModal.vue';
import EmptyState from '@/components/EmptyState.vue';
import ImagePreviewDialog from '@/components/ImagePreviewDialog.vue';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import debounce from '@/debounce';
import { acceptAttribute, classify, isDocument, isVideo, MediaType } from '@/lib/mediaType';
import { destroy as assetsDestroy, search as assetsSearch, storeChunked as assetsStoreChunked } from '@/routes/app/assets';
import { store as storePost } from '@/routes/app/posts';
import { uploadChunked } from '@/utils/chunkedUpload';

interface AssetMedia {
    id: string;
    path: string;
    url: string;
    type: MediaType;
    mime_type: string;
    original_filename: string;
    size: number;
    meta: { width?: number; height?: number; duration?: number } | null;
    created_at: string;
}

interface SavedMedia {
    id: string;
    path: string;
    url: string;
    type: MediaType;
    mime_type: string;
}

interface PickedMedia {
    id: string;
    path: string;
    url: string;
    type: MediaType;
    mime_type: string;
    original_filename?: string;
    size?: number;
    meta?: { width?: number; height?: number; duration?: number };
}

const props = defineProps<{
    mode: 'standalone' | 'picker';
}>();

const selected = defineModel<PickedMedia[]>('selected', { default: () => [] });

const isPicker = computed(() => props.mode === 'picker');

// The upload file picker accepts everything the backend's Media\Type allow-list does.
const acceptedUploadTypes = acceptAttribute();

const lightbox = ref<InstanceType<typeof ImagePreviewDialog> | null>(null);

const handleAssetClick = (asset: AssetMedia) => {
    if (isPicker.value) {
        toggleSelect(asset);
        return;
    }
    const items = uploads.value.map((a) => ({
        url: a.url,
        type: classify(a) ?? MediaType.Image,
    }));
    const idx = uploads.value.findIndex((a) => a.id === asset.id);
    lightbox.value?.openCollection(items, idx);
};

const selectedIds = computed(() => new Set(selected.value.map((m) => m.id)));
const isSelected = (id: string) => selectedIds.value.has(id);
const selectionIndex = (id: string) => selected.value.findIndex((m) => m.id === id) + 1;

const toggleSelect = (asset: AssetMedia | SavedMedia, extra?: Partial<PickedMedia>) => {
    if (!isPicker.value) return;
    if (isSelected(asset.id)) {
        selected.value = selected.value.filter((m) => m.id !== asset.id);
    } else {
        selected.value = [
            ...selected.value,
            {
                id: asset.id,
                path: asset.path,
                url: asset.url,
                type: asset.type,
                mime_type: asset.mime_type,
                original_filename: 'original_filename' in asset ? asset.original_filename : undefined,
                size: 'size' in asset ? asset.size : undefined,
                meta: 'meta' in asset ? (asset.meta ?? undefined) : undefined,
                ...extra,
            },
        ];
    }
};

// ─── Uploads tab ────────────────────────────────────────────────
const uploads = ref<AssetMedia[]>([]);
const uploadsSearch = ref('');
const uploadsPage = ref(1);
const uploadsLastPage = ref(1);
const uploadsLoading = ref(false);
const uploadsLoadingMore = ref(false);
const uploadsHasMore = computed(() => uploadsPage.value < uploadsLastPage.value);

const fileInput = ref<HTMLInputElement | null>(null);
const uploadsSentinel = useTemplateRef<HTMLDivElement>('uploadsSentinel');
const isDragging = ref(false);
const uploading = ref(false);
let uploadsObserver: IntersectionObserver | null = null;
let uploadAbortController: AbortController | null = null;

const fetchUploads = async (page: number, term: string) => {
    const response = await fetch(
        assetsSearch.url({ query: { search: term, page: String(page) } }),
        { headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' }, credentials: 'same-origin' },
    );
    if (!response.ok) throw new Error('Failed to load uploads');
    return (await response.json()) as { data: AssetMedia[]; meta: { current_page: number; last_page: number } };
};

const loadUploadsFirstPage = async () => {
    uploadsLoading.value = true;
    try {
        const response = await fetchUploads(1, uploadsSearch.value.trim());
        uploads.value = response.data;
        uploadsPage.value = response.meta.current_page;
        uploadsLastPage.value = response.meta.last_page;
    } catch {
        uploads.value = [];
    } finally {
        uploadsLoading.value = false;
    }
};

const loadMoreUploads = async () => {
    if (uploadsLoadingMore.value || !uploadsHasMore.value) return;
    uploadsLoadingMore.value = true;
    try {
        const response = await fetchUploads(uploadsPage.value + 1, uploadsSearch.value.trim());
        uploads.value.push(...response.data);
        uploadsPage.value = response.meta.current_page;
        uploadsLastPage.value = response.meta.last_page;
    } catch {
        // ignore
    } finally {
        uploadsLoadingMore.value = false;
    }
};

const debouncedUploadsSearch = debounce(() => {
    void loadUploadsFirstPage();
}, 300);

watch(uploadsSearch, () => debouncedUploadsSearch());

const setupUploadsObserver = () => {
    uploadsObserver?.disconnect();
    uploadsObserver = new IntersectionObserver(
        (entries) => {
            if (entries[0]?.isIntersecting && uploadsHasMore.value && !uploadsLoadingMore.value) {
                void loadMoreUploads();
            }
        },
        { rootMargin: '200px' },
    );
    if (uploadsSentinel.value) uploadsObserver.observe(uploadsSentinel.value);
};

watch(uploadsSentinel, async () => {
    await nextTick();
    setupUploadsObserver();
});

const triggerFileInput = () => fileInput.value?.click();
const handleFileSelect = (event: Event) => {
    const target = event.target as HTMLInputElement;
    if (target.files) {
        void uploadFiles(Array.from(target.files));
        target.value = '';
    }
};
const handleDrop = (event: DragEvent) => {
    isDragging.value = false;
    if (event.dataTransfer?.files) {
        void uploadFiles(Array.from(event.dataTransfer.files));
    }
};

const uploadFiles = async (files: File[]) => {
    if (uploading.value) return;
    uploading.value = true;
    uploadAbortController = new AbortController();
    for (const file of files) {
        try {
            await uploadChunked({
                file,
                url: assetsStoreChunked.url(),
                collection: 'assets',
                signal: uploadAbortController.signal,
            });
        } catch (error) {
            if (error instanceof DOMException && error.name === 'AbortError') {
                toast.info(trans('assets.upload.cancelled'));
                break;
            }
            toast.error(trans('assets.upload.failed', { file: file.name }));
        }
    }
    uploading.value = false;
    await loadUploadsFirstPage();
};

const deleteModal = ref<InstanceType<typeof ConfirmDeleteModal> | null>(null);
const handleDelete = (assetId: string) => {
    deleteModal.value?.open({
        url: assetsDestroy.url(assetId),
        confirmText: trans('common.confirm_modal.delete_keyword'),
    });
};

const onAssetDeleted = async () => {
    await loadUploadsFirstPage();
};

const createPostFromAsset = (asset: AssetMedia) => {
    router.post(storePost.url(), {
        media: [{ id: asset.id, path: asset.path, url: asset.url, type: asset.type, mime_type: asset.mime_type }],
    });
};

// ─── Lifecycle ─────────────────────────────────────────────────
const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1048576).toFixed(1)} MB`;
};

const initialize = async () => {
    await loadUploadsFirstPage();
};

defineExpose({ initialize, refreshUploads: loadUploadsFirstPage });

onMounted(() => {
    void initialize();
});

onUnmounted(() => {
    uploadsObserver?.disconnect();
    uploadAbortController?.abort();
});
</script>

<template>
    <div>
        <!-- ───── My Uploads ───── -->
        <div class="mt-6">
                <div
                    class="relative mb-4 flex cursor-pointer flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed p-8 text-center transition-colors"
                    :class="[
                        isDragging ? 'border-foreground bg-violet-100' : 'border-foreground/25 bg-card hover:bg-foreground/5',
                        uploading ? 'pointer-events-none' : '',
                    ]"
                    @click="triggerFileInput"
                    @dragover.prevent="isDragging = true"
                    @dragleave.prevent="isDragging = false"
                    @drop.prevent="handleDrop"
                >
                    <div class="inline-flex size-12 -rotate-3 items-center justify-center rounded-2xl border-2 border-foreground bg-violet-200 shadow-2xs">
                        <IconCloudUpload class="size-6 text-foreground" stroke-width="2" />
                    </div>
                    <p class="text-sm font-semibold text-foreground">{{ trans('assets.upload.drag_drop') }}</p>
                    <p class="text-xs text-foreground/60">{{ trans('assets.upload.formats') }}</p>
                    <input
                        ref="fileInput"
                        type="file"
                        class="hidden"
                        multiple
                        :accept="acceptedUploadTypes"
                        @change="handleFileSelect"
                    />
                    <div v-if="uploading" class="absolute inset-0 flex items-center justify-center rounded-2xl bg-card/85">
                        <div class="flex items-center gap-2 text-sm font-semibold text-foreground">
                            <IconLoader2 class="size-4 animate-spin" />
                            {{ trans('assets.upload.uploading') }}
                        </div>
                    </div>
                </div>

                <div class="relative mb-4">
                    <IconSearch class="pointer-events-none absolute left-3.5 top-1/2 size-5 -translate-y-1/2 text-foreground/60" />
                    <Input
                        v-model="uploadsSearch"
                        type="search"
                        :placeholder="trans('assets.search_placeholder')"
                        class="h-12 pl-11 text-base"
                    />
                </div>

                <div v-if="uploadsLoading" class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                    <Skeleton v-for="i in 8" :key="i" class="aspect-square rounded-xl" />
                </div>

                <EmptyState
                    v-else-if="uploads.length === 0"
                    :icon="IconPhoto"
                    :title="trans('assets.empty.title')"
                    :description="trans('assets.empty.description')"
                />

                <div v-else class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                    <div
                        v-for="asset in uploads"
                        :key="asset.id"
                        class="group relative overflow-hidden rounded-xl border-2 border-foreground bg-muted shadow-2xs transition-all hover:-translate-y-0.5 hover:shadow-md"
                        :class="[
                            'cursor-pointer',
                            isPicker && isSelected(asset.id) ? 'ring-2 ring-primary ring-offset-2 ring-offset-background' : '',
                        ]"
                        @click="handleAssetClick(asset)"
                    >
                        <div class="aspect-square">
                            <video
                                v-if="isVideo(asset)"
                                :src="asset.url"
                                class="size-full object-cover"
                                muted
                                preload="metadata"
                            />
                            <div
                                v-else-if="isDocument(asset)"
                                class="flex size-full flex-col items-center justify-center gap-1.5 bg-rose-50 p-3 text-center"
                            >
                                <IconFileTypePdf class="size-9 text-rose-600" />
                                <span class="line-clamp-2 break-all text-[11px] font-medium text-foreground/70">{{ asset.original_filename }}</span>
                            </div>
                            <img
                                v-else
                                :src="asset.url"
                                :alt="asset.original_filename"
                                class="size-full object-cover"
                                loading="lazy"
                            />
                        </div>

                        <div
                            v-if="isPicker && isSelected(asset.id)"
                            class="absolute right-2 top-2 inline-flex size-6 items-center justify-center rounded-full border-2 border-foreground bg-primary text-xs font-bold text-primary-foreground shadow-2xs"
                        >
                            {{ selectionIndex(asset.id) }}
                        </div>

                        <div
                            v-if="!isPicker"
                            class="absolute inset-0 flex flex-col justify-between bg-transparent p-2 opacity-100 transition-opacity lg:bg-foreground/60 lg:opacity-0 lg:group-hover:opacity-100"
                        >
                            <div class="flex justify-end gap-1.5">
                                <TooltipProvider>
                                    <Tooltip>
                                        <TooltipTrigger as-child>
                                            <Button variant="outline" size="icon" class="size-8" @click.stop="createPostFromAsset(asset)">
                                                <IconPencilPlus class="size-4" />
                                            </Button>
                                        </TooltipTrigger>
                                        <TooltipContent>{{ trans('assets.create_post') }}</TooltipContent>
                                    </Tooltip>
                                </TooltipProvider>
                                <Button
                                    variant="outline"
                                    size="icon"
                                    class="size-8 bg-rose-100 hover:bg-rose-200"
                                    data-testid="gallery-asset-delete"
                                    @click.stop="handleDelete(asset.id)"
                                >
                                    <IconTrash class="size-4 text-rose-700" />
                                </Button>
                            </div>
                            <div class="space-y-0.5">
                                <p class="truncate text-xs font-semibold text-white">{{ asset.original_filename }}</p>
                                <p class="text-xs text-white/70">{{ formatFileSize(asset.size) }}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <div v-if="uploadsHasMore" ref="uploadsSentinel" class="mt-4 flex justify-center">
                    <IconLoader2 v-if="uploadsLoadingMore" class="size-5 animate-spin text-foreground/60" />
                </div>
            </div>

        <ConfirmDeleteModal
            ref="deleteModal"
            :title="trans('assets.delete.title')"
            :description="trans('assets.delete.description')"
            :action="trans('assets.delete.confirm')"
            :cancel="trans('assets.delete.cancel')"
            @deleted="onAssetDeleted"
        />

        <ImagePreviewDialog ref="lightbox" />
    </div>
</template>
