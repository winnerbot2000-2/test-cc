<script setup lang="ts">
import { usePage } from '@inertiajs/vue3';
import { trans } from 'laravel-vue-i18n';
import { computed, ref, watch } from 'vue';

import ContentStylePicker from '@/components/ai/ContentStylePicker.vue';
import ChannelConfigurator from '@/components/ChannelConfigurator.vue';
import CodeEditor from '@/components/CodeEditor.vue';
import InputError from '@/components/InputError.vue';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { useExpandedEditor } from '@/composables/useExpandedEditor';
import { getPlatformMetaIssue } from '@/composables/usePostCompliance';
import type { PinterestBoard, PinterestBoardsPayload } from '@/types';
import type { Channel } from '@/types/channel';
import { ContentType } from '@/types/content-type';
import { Platform } from '@/types/platform';

interface SocialAccount {
    id: string;
    platform: string;
    display_name: string;
    username: string;
    display_label: string;
    avatar_url: string | null;
}

interface TikTokCreatorInfo {
    creator_nickname: string | null;
    creator_username: string | null;
    creator_avatar_url: string | null;
    privacy_level_options: string[];
    comment_disabled: boolean;
    duet_disabled: boolean;
    stitch_disabled: boolean;
    max_video_post_duration_sec: number | null;
}

interface GenerateAccount {
    social_account_id: string;
    content_type: string;
    meta: Record<string, any>;
}

interface GenerateConfig {
    accounts: GenerateAccount[];
    prompt_template: string;
    use_brand_voice: boolean;
    style: string;
}

const CONTENT_STYLE_KEYS = ['image_card', 'tweet_card', 'tweet_card_image'] as const;

const CONTENT_STYLE_PREVIEWS: Record<string, string> = {
    image_card: '/images/ai-templates/image-card.png',
    tweet_card: '/images/ai-templates/tweet-card.png',
    tweet_card_image: '/images/ai-templates/tweet-card-image.png',
};

const contentStyles = computed(() =>
    CONTENT_STYLE_KEYS.map((key) => ({
        key,
        preview: CONTENT_STYLE_PREVIEWS[key],
        name: trans(`posts.ai.templates.${key}.name`),
        description: trans(`posts.ai.templates.${key}.description`),
    })),
);

const props = defineProps<{
    data: Record<string, unknown>;
    errors?: Record<string, string>;
}>();
const emit = defineEmits<{ update: [Record<string, unknown>] }>();

const editorExpanded = useExpandedEditor();

const page = usePage();

const socialAccounts = computed<SocialAccount[]>(() => {
    const raw = page.props.socialAccounts as { data?: SocialAccount[] } | SocialAccount[] | undefined;
    if (!raw) return [];
    return Array.isArray(raw) ? (raw as SocialAccount[]) : ((raw as { data: SocialAccount[] }).data ?? []);
});

const platformConfigs = computed<Record<string, any>>(() => {
    const raw = page.props.platformConfigs as Record<string, any> | undefined;
    return raw ?? {};
});

const pinterestBoards = computed<Record<string, PinterestBoardsPayload>>(() => {
    const raw = page.props.pinterestBoards as Record<string, PinterestBoardsPayload> | undefined;
    return raw ?? {};
});

const tiktokCreatorInfos = computed<Record<string, TikTokCreatorInfo>>(() => {
    const raw = page.props.tiktokCreatorInfos as Record<string, TikTokCreatorInfo> | null | undefined;
    return raw ?? {};
});

const defaultContentTypeFor = (platform: string): string => {
    switch (platform) {
        case Platform.Instagram:
        case Platform.InstagramFacebook:
            return ContentType.InstagramFeed;
        case Platform.Facebook:
            return ContentType.FacebookPost;
        case Platform.LinkedIn:
            return ContentType.LinkedInPost;
        case Platform.LinkedInPage:
            return ContentType.LinkedInPagePost;
        case Platform.TikTok:
            return ContentType.TikTokPhoto;
        case Platform.Pinterest:
            return ContentType.PinterestPin;
        case Platform.YouTube:
            return ContentType.YouTubeShort;
        case Platform.X:
            return ContentType.XPost;
        case Platform.Threads:
            return ContentType.ThreadsPost;
        case Platform.Bluesky:
            return ContentType.BlueskyPost;
        case Platform.Mastodon:
            return ContentType.MastodonPost;
        default:
            return '';
    }
};

const accountById = (id: string): SocialAccount | undefined =>
    socialAccounts.value.find((a) => a.id === id);

const normalizeAccountsFromData = (): GenerateAccount[] => {
    const incoming = props.data.accounts;
    if (Array.isArray(incoming)) {
        return (incoming as any[]).map((a) => ({
            social_account_id: String(a.social_account_id ?? ''),
            content_type: typeof a.content_type === 'string' && a.content_type
                ? a.content_type
                : defaultContentTypeFor(accountById(String(a.social_account_id ?? ''))?.platform ?? ''),
            meta: (a.meta as Record<string, any>) ?? {},
        })).filter((a) => a.social_account_id);
    }
    // Backward-compat with the old shape (social_account_ids: string[]).
    const legacyIds = props.data.social_account_ids;
    if (Array.isArray(legacyIds)) {
        return (legacyIds as string[]).map((id) => ({
            social_account_id: id,
            content_type: defaultContentTypeFor(accountById(id)?.platform ?? ''),
            meta: {},
        }));
    }
    return [];
};

const local = ref<GenerateConfig>({
    accounts: normalizeAccountsFromData(),
    prompt_template: (props.data.prompt_template as string) ?? '',
    use_brand_voice: (props.data.use_brand_voice as boolean | undefined) ?? true,
    style: (props.data.style as string) ?? 'image_card',
});

watch(local, (val) => emit('update', val), { deep: true });

const selectedAccountIds = computed(() => local.value.accounts.map((a) => a.social_account_id));

const onToggleAccount = (accountId: string) => {
    const account = accountById(accountId);
    if (account) toggleAccount(account);
};

const toggleAccount = (account: SocialAccount) => {
    if (selectedAccountIds.value.includes(account.id)) {
        local.value.accounts = local.value.accounts.filter((a) => a.social_account_id !== account.id);
        return;
    }
    local.value.accounts = [
        ...local.value.accounts,
        {
            social_account_id: account.id,
            content_type: defaultContentTypeFor(account.platform),
            meta: {},
        },
    ];
};

const updateContentType = (accountId: string, value: string) => {
    const idx = local.value.accounts.findIndex((a) => a.social_account_id === accountId);
    if (idx === -1) return;
    local.value.accounts[idx] = { ...local.value.accounts[idx], content_type: value };
};

const updateMeta = (accountId: string, value: Record<string, any>) => {
    const idx = local.value.accounts.findIndex((a) => a.social_account_id === accountId);
    if (idx === -1) return;
    local.value.accounts[idx] = { ...local.value.accounts[idx], meta: value };
};

const getPublishConfig = (account: SocialAccount): Record<string, any> | null =>
    platformConfigs.value[account.id]?.publishConfig ?? null;

const getCreatorInfo = (account: SocialAccount): TikTokCreatorInfo | null =>
    tiktokCreatorInfos.value[account.id] ?? null;

const getBoards = (account: SocialAccount): PinterestBoard[] =>
    pinterestBoards.value[account.id]?.boards ?? [];

const boardsTruncated = (account: SocialAccount): boolean =>
    pinterestBoards.value[account.id]?.truncated ?? false;

// The Generate node is text-only (AI image generation has been removed), so
// per-account compliance is limited to platform meta rules (TikTok
// privacy/disclosure, Pinterest board required, …). Media-count checks are no
// longer applicable.
const accountIssue = (accountId: string): string | null => {
    const entry = local.value.accounts.find((a) => a.social_account_id === accountId);
    if (!entry) return null;
    const account = accountById(accountId);
    return account ? getPlatformMetaIssue(account.platform, entry.meta) : null;
};

const channels = computed<Channel[]>(() =>
    socialAccounts.value.map((account) => {
        const entry = local.value.accounts.find((a) => a.social_account_id === account.id);
        return {
            id: account.id,
            platform: account.platform,
            displayName: account.display_label,
            username: account.username,
            avatarUrl: account.avatar_url,
            socialAccount: account,
            contentType: entry?.content_type ?? defaultContentTypeFor(account.platform),
            meta: entry?.meta ?? {},
            issue: accountIssue(account.id),
            publishConfig: getPublishConfig(account),
            creatorInfo: getCreatorInfo(account),
            boards: getBoards(account),
            boardsTruncated: boardsTruncated(account),
        };
    }),
);
</script>

<template>
    <div class="space-y-4">
        <div class="space-y-2">
            <Label class="text-sm font-bold">{{ $t('automations.config.generate.social_accounts') }}</Label>
            <InputError :message="errors?.accounts" />
            <p v-if="socialAccounts.length === 0" class="text-xs text-foreground/60">
                {{ $t('automations.config.generate.social_accounts_empty') }}
            </p>
            <ChannelConfigurator
                v-else
                :channels="channels"
                :selected-ids="selectedAccountIds"
                :preview-only="true"
                @toggle="onToggleAccount"
                @update:content-type="updateContentType"
                @update:meta="updateMeta"
            />
        </div>

        <div class="space-y-2">
            <Label class="text-sm font-bold">{{ $t('automations.config.generate.style') }}</Label>
            <ContentStylePicker v-model="local.style" :styles="contentStyles" mini />
        </div>

        <div v-show="!editorExpanded" class="flex items-start justify-between gap-3">
            <div class="space-y-0.5">
                <Label class="text-sm font-bold">{{ $t('automations.config.generate.use_brand_voice') }}</Label>
                <p class="text-xs text-foreground/60">{{ $t('automations.config.generate.use_brand_voice_hint') }}</p>
            </div>
            <Switch v-model="local.use_brand_voice" />
        </div>

        <div v-show="!editorExpanded">
            <Label class="mb-1 block">{{ $t('automations.config.generate.prompt_template') }}</Label>
            <div class="h-40">
                <CodeEditor
                    v-model="local.prompt_template"
                    language="text"
                    expandable
                    :label="$t('automations.config.generate.prompt_template')"
                    placeholder="Write a social media post about {{ trigger.title }}…"
                />
            </div>
            <p class="mt-1 text-xs text-foreground/50">{{ $t('automations.config.generate.prompt_template_hint') }}</p>
            <InputError :message="errors?.prompt_template" class="mt-1" />
        </div>
    </div>
</template>
